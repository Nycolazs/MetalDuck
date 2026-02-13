import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Metal
import ScreenCaptureKit
import simd

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
    private let motionEstimator = GlobalMotionEstimator()

    init(context: MetalContext, target: CaptureTarget, configuration: CaptureConfiguration) {
        self.context = context
        self.target = target
        self.captureConfiguration = configuration
    }

    func start() async throws {
        if stream != nil {
            await stop()
        }
        motionEstimator.reset()

        let shareableContent = try await SCShareableContent.current
        let selection = try resolveSelection(in: shareableContent)
        let filter = makeFilter(for: selection, shareableContent: shareableContent)
        let captureSize = resolveCaptureSize(for: selection, filter: filter)

        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = captureSize.width
        streamConfiguration.height = captureSize.height
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.scalesToFit = true
        streamConfiguration.showsCursor = captureConfiguration.showsCursor
        streamConfiguration.queueDepth = max(1, min(captureConfiguration.queueDepth, 8))
        streamConfiguration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(max(captureConfiguration.framesPerSecond, 1))
        )
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
    }

    func stop() async {
        guard let stream else {
            return
        }

        await withCheckedContinuation { continuation in
            stream.stopCapture { _ in
                continuation.resume()
            }
        }

        self.stream = nil
        motionEstimator.reset()
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
            if let requestedDisplayID,
               let display = shareableContent.displays.first(where: { $0.displayID == requestedDisplayID }) {
                return .display(display)
            }
            guard let display = shareableContent.displays.first else {
                throw ScreenCaptureServiceError.noShareableDisplay
            }
            return .display(display)

        case .window(let requestedWindowID):
            let candidates = shareableContent.windows.filter {
                $0.isOnScreen &&
                    $0.windowLayer == 0 &&
                    $0.owningApplication?.processID != currentPID
            }
            if let requestedWindowID,
               let window = candidates.first(where: { $0.windowID == requestedWindowID }) {
                return .window(window)
            }
            guard let window = candidates.first else {
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
            return SCContentFilter(desktopIndependentWindow: window)
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
        guard CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
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
            return
        }

        let frame = CapturedFrame(
            texture: metalTexture,
            timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            contentRect: CGRect(x: 0, y: 0, width: width, height: height),
            motionHint: motionEstimator.estimate(for: pixelBuffer),
            backingTexture: wrappedTexture
        )

        onFrame?(frame)
    }

}

private final class GlobalMotionEstimator {
    private static let sampleWidth = 32
    private static let sampleHeight = 18
    private static let maxShift = 2

    private var previousGrid: [UInt8]?
    private var smoothedMotion: SIMD2<Float> = .zero
    private var frameCounter: UInt64 = 0

    func reset() {
        previousGrid = nil
        smoothedMotion = .zero
        frameCounter = 0
    }

    func estimate(for pixelBuffer: CVPixelBuffer) -> SIMD2<Float> {
        frameCounter &+= 1

        let width = max(1, CVPixelBufferGetWidth(pixelBuffer))
        let height = max(1, CVPixelBufferGetHeight(pixelBuffer))

        guard let currentGrid = makeLumaGrid(from: pixelBuffer) else {
            return .zero
        }

        defer {
            previousGrid = currentGrid
        }

        guard let previousGrid else {
            return .zero
        }

        // Re-estimate every third frame to keep capture callback lightweight.
        if frameCounter % 3 != 0 {
            return smoothedMotion
        }

        let bestShift = bestShiftBetween(previous: previousGrid, current: currentGrid)
        let scaleX = Float(width) / Float(Self.sampleWidth)
        let scaleY = Float(height) / Float(Self.sampleHeight)

        let rawMotion = SIMD2<Float>(Float(bestShift.dx) * scaleX, Float(bestShift.dy) * scaleY)
        smoothedMotion = (smoothedMotion * 0.7) + (rawMotion * 0.3)
        return smoothedMotion
    }

    private func makeLumaGrid(from pixelBuffer: CVPixelBuffer) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let width = max(1, CVPixelBufferGetWidth(pixelBuffer))
        let height = max(1, CVPixelBufferGetHeight(pixelBuffer))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let sampleWidth = Self.sampleWidth
        let sampleHeight = Self.sampleHeight
        var grid = [UInt8](repeating: 0, count: sampleWidth * sampleHeight)

        for sy in 0..<sampleHeight {
            let y = min(height - 1, (sy * height) / sampleHeight)
            let rowPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)

            for sx in 0..<sampleWidth {
                let x = min(width - 1, (sx * width) / sampleWidth)
                let pixel = rowPtr.advanced(by: x * 4)

                // BGRA to luma approximation.
                let b = Int(pixel[0])
                let g = Int(pixel[1])
                let r = Int(pixel[2])
                let luma = (29 * b + 150 * g + 77 * r) >> 8
                grid[(sy * sampleWidth) + sx] = UInt8(clamping: luma)
            }
        }

        return grid
    }

    private func bestShiftBetween(previous: [UInt8], current: [UInt8]) -> (dx: Int, dy: Int) {
        let sampleWidth = Self.sampleWidth
        let sampleHeight = Self.sampleHeight
        let maxShift = Self.maxShift

        var bestDX = 0
        var bestDY = 0
        var bestError: UInt64 = .max

        for dy in (-maxShift)...maxShift {
            for dx in (-maxShift)...maxShift {
                let xStart = max(0, -dx)
                let xEnd = min(sampleWidth, sampleWidth - dx)
                let yStart = max(0, -dy)
                let yEnd = min(sampleHeight, sampleHeight - dy)

                guard xStart < xEnd, yStart < yEnd else {
                    continue
                }

                var error: UInt64 = 0

                for y in yStart..<yEnd {
                    let prevBase = y * sampleWidth
                    let currBase = (y + dy) * sampleWidth

                    for x in xStart..<xEnd {
                        let prevValue = Int(previous[prevBase + x])
                        let currValue = Int(current[currBase + x + dx])
                        error &+= UInt64(abs(prevValue - currValue))
                    }
                }

                if error < bestError {
                    bestError = error
                    bestDX = dx
                    bestDY = dy
                }
            }
        }

        return (bestDX, bestDY)
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
