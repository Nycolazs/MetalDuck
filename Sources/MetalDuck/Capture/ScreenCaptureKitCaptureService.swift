import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Metal
@preconcurrency import ScreenCaptureKit

enum CaptureStaleError: LocalizedError {
    case framesStalled

    var errorDescription: String? {
        switch self {
        case .framesStalled:
            return "Source stopped delivering frames. The window may have changed (e.g. fullscreen). Try refreshing sources or switching to Display capture."
        }
    }
}

@available(macOS 12.3, *)
enum ScreenCaptureServiceError: Error {
    case noShareableDisplay
    case noShareableWindow
    case streamOutputRegistrationFailed
}

@available(macOS 12.3, *)
final class ScreenCaptureKitCaptureService: NSObject, FrameCaptureService, @unchecked Sendable {
    var onFrame: ((CapturedFrame) -> Void)?
    var onError: ((Error) -> Void)?

    private let context: MetalContext
    private var captureConfiguration: CaptureConfiguration
    private var target: CaptureTarget

    private let sampleQueue = DispatchQueue(label: "metaldck.capture.sckit.sample")
    private var stream: SCStream?
    private var trackedWindowID: CGWindowID?
    private var trackedBundleID: String?
    private var trackedDisplayID: CGDirectDisplayID?
    private var trackedPID: pid_t?

    /// Checks once a second whether the app moved its picture into another window.
    private var followTimer: DispatchSourceTimer?
    private var isRetargeting = false
    /// A window has to look like the app's full-screen window on two checks in a row:
    /// some apps show a full-screen snapshot window for half a second while switching.
    private var followCandidate: CGWindowID?
    private var streamConfiguration: SCStreamConfiguration?
    private var configuredAspect: CGFloat = 0
    private var lastResizeUptime: TimeInterval = 0
    private var lastSampleUptime: TimeInterval = 0
    private var lastAcceptedTimestamp: Double = 0
    /// Frames the cap still allows, refilled at the capture rate (see `handleSampleBuffer`).
    private var rateTokens: Double = 1
    /// A sparse grid of the last frame passed on, to recognise repaints of the same picture.
    private var lastPictureSamples: [UInt32] = []
    /// How much the picture changed between recent frames, to tell a cut from fast motion.
    private var recentPictureChange: [Double] = []

    init(context: MetalContext, target: CaptureTarget, configuration: CaptureConfiguration) {
        self.context = context
        self.target = target
        self.captureConfiguration = configuration
    }

    func start() async throws {
        if stream != nil {
            await stop()
        }
        let shareableContent = try await SCShareableContent.current
        let selection = try resolveSelection(in: shareableContent)
        let filter = makeFilter(for: selection, shareableContent: shareableContent)
        let captureSize = resolveCaptureSize(for: selection, filter: filter)

        switch selection {
        case .window(let window):
            self.trackedWindowID = window.windowID
            self.trackedBundleID = window.owningApplication?.bundleIdentifier
            self.trackedPID = window.owningApplication?.processID
            self.trackedDisplayID = nil
        case .display(let display):
            self.trackedDisplayID = display.displayID
            self.trackedWindowID = nil
            self.trackedBundleID = nil
            self.trackedPID = nil
        }

        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = captureSize.width
        streamConfiguration.height = captureSize.height
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.scalesToFit = true
        streamConfiguration.showsCursor = captureConfiguration.showsCursor
        // ScreenCaptureKit rejects fewer than three surfaces.
        streamConfiguration.queueDepth = min(max(captureConfiguration.queueDepth, 3), 8)
        // Sample at the display's own rate so each frame carries the time its content really
        // changed. A 30 fps cap here snaps 24 fps video onto a 33 ms grid (33, 33, 33, 67 ms),
        // which frame generation turns into uneven motion. The configured rate is applied
        // below by timestamp instead.
        streamConfiguration.minimumFrameInterval = .zero
        
        if #available(macOS 15.0, *) {
            streamConfiguration.captureDynamicRange = .SDR
        }

        if #available(macOS 13.0, *) {
            streamConfiguration.capturesAudio = false
        }

        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: self)

        do {
            try stream.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: sampleQueue
            )
        } catch {
            throw ScreenCaptureServiceError.streamOutputRegistrationFailed
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }

        self.stream = stream
        self.streamConfiguration = streamConfiguration
        configuredAspect = CGFloat(captureSize.width) / CGFloat(max(captureSize.height, 1))
        lastSampleUptime = 0
        lastAcceptedTimestamp = 0
        rateTokens = 1
        lastPictureSamples = []
        recentPictureChange = []
        startFollowingWindow()
        PipelineLog.shared.logCaptureStarted(
            target: Self.describe(selection),
            pixelWidth: captureSize.width,
            pixelHeight: captureSize.height,
            configuredFPS: captureConfiguration.framesPerSecond,
            configuredQueueDepth: captureConfiguration.queueDepth
        )
    }

    func stop() async {
        guard let stream else {
            return
        }

        let streamToStop = stream
        self.stream = nil
        followTimer?.cancel()
        followTimer = nil

        await withCheckedContinuation { continuation in
            streamToStop.stopCapture { _ in
                continuation.resume()
            }
        }

        lastSampleUptime = 0
        PipelineLog.shared.event("capture", "stream stopped")
    }

    func reconfigure(target: CaptureTarget) async throws {
        self.target = target
        let isRunning = stream != nil
        if isRunning {
            await stop()
            try await start()
        }
    }

    func reconfigure(configuration: CaptureConfiguration) async throws {
        self.captureConfiguration = configuration
        let isRunning = stream != nil
        if isRunning {
            await stop()
            try await start()
        }
    }

    private enum Selection {
        case display(SCDisplay)
        case window(SCWindow)
    }

    private func resolveSelection(in shareableContent: SCShareableContent) throws -> Selection {
        let currentPID = ProcessInfo.processInfo.processIdentifier

        switch target {
        case .display(let requestedDisplayID):
            if let display = shareableContent.displays.first(where: { $0.displayID == requestedDisplayID }) {
                return .display(display)
            }
            guard let display = shareableContent.displays.first else {
                throw ScreenCaptureServiceError.noShareableDisplay
            }
            return .display(display)

        case .window(let requestedWindowID):
            let candidates = shareableContent.windows.filter {
                $0.owningApplication?.processID != currentPID &&
                ($0.windowLayer == 0 || $0.isOnScreen)
            }
            
            // 1. Try exact match
            if let requestedWindowID,
               let window = candidates.first(where: { $0.windowID == requestedWindowID }) {
                return .window(window)
            }
            
            // 2. Aggressive Re-discovery: If precise window is gone, find the "best" window from the same app
            let bundleID = shareableContent.windows.first(where: { $0.windowID == requestedWindowID })?.owningApplication?.bundleIdentifier ?? self.trackedBundleID
            
            if let bundleID {
                
                // Prefer windows that are "on screen" and have a reasonable video size
                let appWindows = candidates.filter { $0.owningApplication?.bundleIdentifier == bundleID }
                let videoCandidates = appWindows.filter { 
                    $0.isOnScreen && 
                    $0.frame.width >= 640 && 
                    $0.frame.height >= 360 
                }
                
                if let bestVideo = videoCandidates.sorted(by: { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }).first {
                    return .window(bestVideo)
                }
                
                // Fallback to any on-screen window from the app
                if let anyOnScreen = appWindows.first(where: { $0.isOnScreen }) {
                    return .window(anyOnScreen)
                }
            }

            // 3. Global Fallback: Prefer on-screen windows
            let onScreen = candidates.filter { $0.isOnScreen }
            guard let window = onScreen.first ?? candidates.first else {
                throw ScreenCaptureServiceError.noShareableWindow
            }
            return .window(window)

        case .automatic:
            let windows = shareableContent.windows.filter { $0.isOnScreen && $0.windowLayer == 0 }
            if let window = windows.first(where: { $0.owningApplication?.processID != currentPID }) {
                return .window(window)
            }
            guard let display = shareableContent.displays.first else {
                throw ScreenCaptureServiceError.noShareableDisplay
            }
            return .display(display)
        }
    }

    private func makeFilter(for selection: Selection, shareableContent: SCShareableContent) -> SCContentFilter {
        switch selection {
        case .display(let display):
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let ownWindows = shareableContent.windows.filter { $0.owningApplication?.processID == currentPID }
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            if #available(macOS 14.2, *) {
                filter.includeMenuBar = false
            }
            return filter

        case .window(let window):
            if #available(macOS 13.0, *) {
                return SCContentFilter(desktopIndependentWindow: window)
            } else {
                // macOS 12.3: desktopIndependentWindow is not available.
                // Fallback to display-based filter.
                if let display = shareableContent.displays.first {
                    return SCContentFilter(display: display, excludingWindows: [])
                } else {
                    // This should theoretically not happen if ScreenCaptureKit is working,
                    // but we must return something.
                    fatalError("No shareable displays found during filter creation on macOS 12")
                }
            }
        }
    }

    private func resolveCaptureSize(for selection: Selection, filter: SCContentFilter) -> (width: Int, height: Int) {
        if let preferredPixelSize = captureConfiguration.preferredPixelSize {
            let preferredArea = max(1.0, preferredPixelSize.width * preferredPixelSize.height)
            let aspect = max(0.1, captureAspect(for: selection))
            let width = max(1, Int((preferredArea * aspect).squareRoot().rounded()))
            let height = max(1, Int((Double(width) / Double(aspect)).rounded()))
            return (width: width, height: height)
        }

        if #available(macOS 14.0, *) {
            let info = SCShareableContent.info(for: filter)
            let width = max(1, Int(info.contentRect.width * CGFloat(info.pointPixelScale)))
            let height = max(1, Int(info.contentRect.height * CGFloat(info.pointPixelScale)))
            return (width, height)
        }

        switch selection {
        case .display(let display):
            return (max(1, display.width * 2), max(1, display.height * 2))
        case .window(let window):
            return (max(1, Int(window.frame.width * 2)), max(1, Int(window.frame.height * 2)))
        }
    }

    private func captureAspect(for selection: Selection) -> CGFloat {
        switch selection {
        case .display(let display):
            return CGFloat(max(1, display.width)) / CGFloat(max(1, display.height))
        case .window(let window):
            let width = max(1.0, window.frame.width)
            let height = max(1.0, window.frame.height)
            return width / height
        }
    }

    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferIsValid(sampleBuffer) else {
            PipelineLog.shared.noteCaptureDrop("invalid sample buffer")
            return
        }
        // Idle and blank samples only say the content has not changed.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Keep to the configured rate on average. Each frame spends one token and tokens refill
        // at the capture rate, so a 60 fps source under a 30 cap keeps every other frame. A
        // 24 fps video under the cap keeps all of them, even the ones a browser shows early:
        // Firefox put some 26 ms apart, which the old rule (no closer than 25 ms) sat right on.
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

        // Browsers repaint a playing video's window more often than the video changes:
        // Firefox sent 60 or more frames a second for a 24 fps trailer, most of them copies.
        // Kept, a copy froze the motion between it and the real frame before, and the next
        // step jumped to catch up, which looked like 10 fps. Pass on only changed pictures.
        let samples = Self.pictureSamples(of: pixelBuffer)
        if let samples, !lastPictureSamples.isEmpty {
            let changed = Self.changedSamples(samples, lastPictureSamples)
            PipelineLog.shared.noteTiming("repaint changed %", milliseconds: Double(changed) * 100 / Double(samples.count))
            let sinceLast = timestamp.isFinite ? timestamp - lastAcceptedTimestamp : 0
            // Four points or fewer of the grid is the same picture, perhaps with a progress
            // bar moved. Small changes still go through four times a second, so a paused page
            // updates.
            if changed <= 4, !(changed > 0 && sinceLast > 0.25) {
                PipelineLog.shared.noteRepeatSkipped()
                return
            }
        }

        let capRate = Double(max(captureConfiguration.framesPerSecond, 1))
        if timestamp.isFinite, lastAcceptedTimestamp > 0, timestamp > lastAcceptedTimestamp {
            let refilled = min(rateTokens + (timestamp - lastAcceptedTimestamp) * capRate, 2)
            if refilled < 0.95 {
                return
            }
            rateTokens = refilled - 1
        } else {
            rateTokens = 0.5
        }
        lastAcceptedTimestamp = timestamp
        var startsNewShot = false
        if let samples {
            if !lastPictureSamples.isEmpty {
                startsNewShot = isShotChange(from: lastPictureSamples, to: samples)
            }
            lastPictureSamples = samples
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var wrappedTexture: CVMetalTexture?
        let cacheStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            context.textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &wrappedTexture
        )

        guard cacheStatus == kCVReturnSuccess,
              let wrappedTexture,
              let metalTexture = CVMetalTextureGetTexture(wrappedTexture) else {
            PipelineLog.shared.noteCaptureDrop("could not wrap pixel buffer as a Metal texture (status \(cacheStatus))")
            return
        }

        var targetRect = CGRect(x: 0, y: 0, width: width, height: height)
        if let trackedWindowID = self.trackedWindowID {
            // Where the window is on screen comes with the frame. Asking the window server
            // (CGWindowListCopyWindowInfo) took 2 ms, up to 6, on every frame, on a window
            // server already busy compositing the overlay at 120 Hz.
            if let screenRect = Self.screenRect(of: sampleBuffer) {
                targetRect = screenRect
            } else if let bounds = Self.windowBounds(trackedWindowID) {
                targetRect = bounds
            }
            resizeStreamIfNeeded(for: targetRect.size)
        } else if let trackedDisplayID = self.trackedDisplayID {
            targetRect = CGDisplayBounds(trackedDisplayID)
        }

        let frame = CapturedFrame(
            texture: metalTexture,
            timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            contentRect: CGRect(x: 0, y: 0, width: width, height: height),
            targetRect: targetRect,
            backingTexture: wrappedTexture,
            startsNewShot: startsNewShot
        )

        let now = ProcessInfo.processInfo.systemUptime
        let interval = lastSampleUptime > 0 ? now - lastSampleUptime : 0
        lastSampleUptime = now
        PipelineLog.shared.noteCapture(
            width: width,
            height: height,
            interval: interval,
            timestamp: CMTimeGetSeconds(frame.timestamp)
        )

        onFrame?(frame)
    }

    /// 128 x 72 pixels spread evenly over the frame, read straight from its surface. Points
    /// about 14 px apart on a 1821 px capture, so a small moving object still shows.
    private static func pictureSamples(of pixelBuffer: CVPixelBuffer) -> [UInt32]? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer), width >= 128, height >= 72 else {
            return nil
        }
        var samples = [UInt32](repeating: 0, count: 128 * 72)
        for row in 0..<72 {
            let line = base.advanced(by: ((row * 2 + 1) * height / 144) * rowBytes)
                .assumingMemoryBound(to: UInt32.self)
            for column in 0..<128 {
                samples[row * 128 + column] = line[(column * 2 + 1) * width / 256]
            }
        }
        return samples
    }

    /// A hard cut between shots. Building frames across one warps two unrelated pictures
    /// into each other. The brightness histogram of a cut jumps (0.20 to 0.54 of it moved in
    /// tests), and the picture changes far more than in the frames before it. A fast pan
    /// moves the histogram by 0.01 to 0.03 and a cross-fade by 0.08 to 0.16, and neither
    /// counted as a cut; over 3,400 frames of animated promo video, nothing did.
    private func isShotChange(from old: [UInt32], to new: [UInt32]) -> Bool {
        guard old.count == new.count, !new.isEmpty else { return false }
        var oldHistogram = [Int](repeating: 0, count: 32)
        var newHistogram = [Int](repeating: 0, count: 32)
        var difference = 0
        for index in new.indices {
            let before = Self.luma(old[index])
            let after = Self.luma(new[index])
            difference += abs(after - before)
            oldHistogram[before >> 3] += 1
            newHistogram[after >> 3] += 1
        }
        var moved = 0
        for bin in 0..<32 {
            moved += abs(oldHistogram[bin] - newHistogram[bin])
        }
        let histogramChange = Double(moved) / 2 / Double(new.count)
        let pictureChange = Double(difference) / Double(new.count)
        let typical = recentPictureChange.isEmpty
            ? pictureChange
            : recentPictureChange.sorted()[recentPictureChange.count / 2]
        let isCut = histogramChange > 0.35 ||
            (histogramChange > 0.18 && pictureChange > max(8, typical * 2.5))
        if !isCut {
            recentPictureChange.append(pictureChange)
            if recentPictureChange.count > 12 {
                recentPictureChange.removeFirst(recentPictureChange.count - 12)
            }
        }
        return isCut
    }

    private static func luma(_ pixel: UInt32) -> Int {
        let blue = Int(pixel & 0xFF)
        let green = Int((pixel >> 8) & 0xFF)
        let red = Int((pixel >> 16) & 0xFF)
        return (red * 77 + green * 150 + blue * 29) >> 8
    }

    /// Sample points where any colour channel moved by more than 3 of 255.
    private static func changedSamples(_ new: [UInt32], _ old: [UInt32]) -> Int {
        guard new.count == old.count else { return new.count }
        var changed = 0
        for index in new.indices where new[index] != old[index] {
            let a = new[index]
            let b = old[index]
            let blue = abs(Int(a & 0xFF) - Int(b & 0xFF))
            let green = abs(Int((a >> 8) & 0xFF) - Int((b >> 8) & 0xFF))
            let red = abs(Int((a >> 16) & 0xFF) - Int((b >> 16) & 0xFF))
            if max(blue, green, red) > 3 {
                changed += 1
            }
        }
        return changed
    }

    /// The captured window's place on screen, in global points with the origin top left.
    private static func screenRect(of sampleBuffer: CMSampleBuffer) -> CGRect? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let value = attachments.first?[.screenRect] else {
            return nil
        }
        let dictionary = value as CFTypeRef
        guard CFGetTypeID(dictionary) == CFDictionaryGetTypeID(),
              let rect = CGRect(dictionaryRepresentation: dictionary as! CFDictionary),
              rect.width > 0, rect.height > 0 else {
            return nil
        }
        return rect
    }

    private static func windowBounds(_ windowID: CGWindowID) -> CGRect? {
        guard let infos = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              let info = infos.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }),
              let boundsDict = info[kCGWindowBounds as String] as? [String: Any] else {
            return nil
        }
        return CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
    }

    // MARK: - Following full screen

    /// Browsers and players often play full-screen video in a new window on its own Space,
    /// and close it again on exit. The stream would keep showing the old window, which no
    /// longer changes. Follow the app's picture instead.
    private func startFollowingWindow() {
        followTimer?.cancel()
        followTimer = nil
        guard trackedWindowID != nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.checkWindowFollow() }
        timer.resume()
        followTimer = timer
    }

    private struct WindowInfo {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect
        let onScreen: Bool
    }

    private static func windowInfos(_ options: CGWindowListOption) -> [WindowInfo] {
        let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.compactMap { info in
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { return nil }
            let onScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            return WindowInfo(id: id, pid: pid, bounds: bounds, onScreen: onScreen)
        }
    }

    /// True when `bounds` (global, top-left origin) fills one of the displays: full width,
    /// down to the bottom, and up to the top or to just below a MacBook's notch, which is
    /// where full-screen apps stop.
    static func fillsDisplay(_ bounds: CGRect) -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { id in
            let d = CGDisplayBounds(id)
            let topInset = bounds.minY - d.minY
            return abs(bounds.minX - d.minX) <= 2 && abs(bounds.width - d.width) <= 4 &&
                abs(bounds.maxY - d.maxY) <= 2 && topInset >= -2 && topInset <= 60
        }
    }

    private func checkWindowFollow() {
        guard stream != nil, !isRetargeting, let tracked = trackedWindowID, let pid = trackedPID else { return }
        let all = Self.windowInfos(.optionAll)
        let appOnScreen = all.filter { $0.pid == pid && $0.onScreen && $0.bounds.width >= 200 && $0.bounds.height >= 150 }

        // 1. The app put its picture into another window that fills a display: it went full screen.
        if let fullScreen = appOnScreen.first(where: { $0.id != tracked && Self.fillsDisplay($0.bounds) }) {
            if followCandidate == fullScreen.id {
                followCandidate = nil
                retarget(to: fullScreen.id, reason: "the app went full screen in a new window")
            } else {
                followCandidate = fullScreen.id
            }
            return
        }
        followCandidate = nil
        // 2. The window being captured is gone, for example the full-screen window closed on exit.
        if !all.contains(where: { $0.id == tracked }),
           let largest = appOnScreen.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) {
            retarget(to: largest.id, reason: "the captured window closed")
        }
    }

    private func retarget(to windowID: CGWindowID, reason: String) {
        isRetargeting = true
        PipelineLog.shared.event("capture", "following window \(windowID): \(reason)")
        target = .window(windowID)
        Task {
            await self.stop()
            do {
                try await self.start()
            } catch {
                PipelineLog.shared.event("capture", "could not follow window \(windowID): \(error.localizedDescription)")
                self.onError?(error)
            }
            self.sampleQueue.async { self.isRetargeting = false }
        }
    }

    /// Keeps the stream's shape matching the window's, so a window that changes shape
    /// (entering full screen in the same window, say) is not letterboxed inside the frame.
    private func resizeStreamIfNeeded(for size: CGSize) {
        guard size.width > 1, size.height > 1, let stream, let configuration = streamConfiguration else { return }
        let aspect = size.width / size.height
        guard configuredAspect > 0, abs(aspect - configuredAspect) / configuredAspect > 0.02 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastResizeUptime > 0.5 else { return }
        lastResizeUptime = now

        let area = captureConfiguration.preferredPixelSize.map { max(1, $0.width * $0.height) }
            ?? Double(configuration.width * configuration.height)
        let width = max(2, Int((area * aspect).squareRoot().rounded()))
        let height = max(2, Int((Double(width) / aspect).rounded()))
        configuration.width = width
        configuration.height = height
        configuredAspect = CGFloat(width) / CGFloat(height)
        PipelineLog.shared.event("capture", "window changed shape: stream now \(width)x\(height)")
        stream.updateConfiguration(configuration) { error in
            if let error {
                PipelineLog.shared.event("capture", "could not resize the stream: \(error.localizedDescription)")
            }
        }
    }

    private static func describe(_ selection: Selection) -> String {
        switch selection {
        case .display(let display):
            return "display \(display.displayID) \(display.width)x\(display.height)"
        case .window(let window):
            let owner = window.owningApplication?.applicationName ?? "unknown app"
            let title = window.title ?? ""
            return "window \(window.windowID) \(owner) \"\(title)\" \(Int(window.frame.width))x\(Int(window.frame.height))"
        }
    }
}

@available(macOS 12.3, *)
extension ScreenCaptureKitCaptureService: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen else {
            return
        }

        handleSampleBuffer(sampleBuffer)
    }
}

@available(macOS 12.3, *)
extension ScreenCaptureKitCaptureService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onError?(error)
    }
}
