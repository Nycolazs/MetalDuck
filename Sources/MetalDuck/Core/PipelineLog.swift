import Foundation
import Darwin
import os
import QuartzCore

/// Per-second numbers from the pipeline summary, for the in-app monitor.
struct PipelineLiveStats: Sendable {
    var date: Date
    var captureFPS: Double
    var outputFPS: Double
    var generatedFPS: Double
    var captureDrops: Int
    var flowLag: Int
    var flowFrames: Int
    var blendFrames: Int
    var passthroughFrames: Int
    var repeatedFrames: Int
    var visionBusySkipped: Int
    var flowComputeMilliseconds: Double
    var drawAverageMilliseconds: Double
    var drawMaxMilliseconds: Double
    var load: PipelineLoad
    var verdict: String
}

struct PipelineLoad: Sendable {
    var processCPU: Double
    var systemCPU: Double
    var residentMB: Double
}

struct PipelineLogLine: Sendable {
    var date: Date
    var category: String
    var message: String
}

extension Notification.Name {
    /// Posted on the main queue; `object` is a `PipelineLiveStats`.
    static let pipelineLiveStats = Notification.Name("com.metalduck.pipeline.liveStats")
    /// Posted on the main queue; `object` is a `PipelineLogLine`.
    static let pipelineLogLine = Notification.Name("com.metalduck.pipeline.logLine")
}

/// Session log for the capture → interpolate → present pipeline.
///
/// Lifecycle changes are written immediately. Counters are folded into one
/// summary per second so a later read can tell whether frames were really
/// generated or only blended.
final class PipelineLog: @unchecked Sendable {
    static let shared = PipelineLog()
    static let saveFilesKey = "com.metalduck.saveLogFiles"
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/MetalDuck", isDirectory: true)

    enum PresentKind: Equatable {
        case noFrame
        case passthrough
        case flow(t: Float, flowWidth: Int, flowHeight: Int, flowFrameID: UInt64, latestCaptureID: UInt64)
        case blend(t: Float, reason: String)
        case repeated
    }

    private let writeQueue = DispatchQueue(label: "com.metalduck.pipeline-log")
    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.metalduck", category: "pipeline")
    /// Only touched on `writeQueue`.
    private var handle: FileHandle?
    private var currentFileURL: URL?

    private var recent: [PipelineLogLine] = []
    private let recentLimit = 400
    private var statsHistory: [PipelineLiveStats] = []
    private let statsHistoryLimit = 180

    private var windowStart = CACurrentMediaTime()
    private var captureCount = 0
    private var captureDropCount = 0
    private var captureIntervalSum = 0.0
    private var captureIntervalMax = 0.0
    private var captureIntervalSamples = 0
    private var lastCaptureWidth = 0
    private var lastCaptureHeight = 0
    private var lastDropReason = ""

    private var presentNoFrame = 0
    private var presentPassthrough = 0
    private var presentFlow = 0
    private var presentBlend = 0
    private var presentRepeated = 0
    private var blendReasonCounts: [String: Int] = [:]
    private var lastBlendT = 0.0
    private var lastFlowT = 0.0
    private var lastFlowWidth = 0
    private var lastFlowHeight = 0
    private var lastFlowLag = 0
    private var maxFlowLag = 0

    private var flowStarted = 0
    private var announcedFirstFlow = false
    private var flowFinished = 0
    private var flowSkippedBusy = 0
    private var flowFailed = 0
    private var flowFailReasons: [String: Int] = [:]
    private var flowMillisecondsSum = 0.0
    private var lastFlowComputeMilliseconds = 0.0

    private var captureCadence: [Int: Int] = [:]
    private var lastCaptureTimestamp: Double = 0

    private var screenCount = 0
    private var screenDropped = 0
    private var screenIntervalSum = 0.0
    private var screenIntervalMax = 0.0
    private var screenLate = 0
    private var motionErrorSum = 0.0
    private var motionErrorMax = 0.0
    private var motionSamples = 0
    private var lastScreenTime: Double = 0
    private var lastScreenContentTime: Double = 0

    private var drawCount = 0
    private var drawMillisecondsSum = 0.0
    private var drawMillisecondsMax = 0.0
    private var upscaleFallbacks = 0
    private var upscaleDescription = "not used yet"

    private var lastMeaningfulPresent = ""
    private var sawCapture = false
    private var previousProcessCPU: CPUSample?
    private var previousSystemTicks: [UInt32]?

    private struct CPUSample {
        var user: Double
        var system: Double
        var wall: CFTimeInterval
    }

    private struct Snapshot {
        var reason: String
        var elapsed: Double
        var captureCount: Int
        var captureDropCount: Int
        var captureIntervalSum: Double
        var captureIntervalMax: Double
        var captureIntervalSamples: Int
        var captureWidth: Int
        var captureHeight: Int
        var lastDropReason: String
        var presentNoFrame: Int
        var presentPassthrough: Int
        var presentFlow: Int
        var presentBlend: Int
        var presentRepeated: Int
        var blendReasonCounts: [String: Int]
        var lastBlendT: Double
        var lastFlowT: Double
        var lastFlowWidth: Int
        var lastFlowHeight: Int
        var lastFlowLag: Int
        var maxFlowLag: Int
        var flowStarted: Int
        var flowFinished: Int
        var flowSkippedBusy: Int
        var flowFailed: Int
        var flowFailReasons: [String: Int]
        var flowMillisecondsSum: Double
        var lastFlowComputeMilliseconds: Double
        var captureCadence: [Int: Int]
        var screenCount: Int
        var screenDropped: Int
        var screenIntervalSum: Double
        var screenIntervalMax: Double
        var screenLate: Int
        var motionErrorSum: Double
        var motionErrorMax: Double
        var motionSamples: Int
        var drawCount: Int
        var drawMillisecondsSum: Double
        var drawMillisecondsMax: Double
        var upscaleFallbacks: Int
        var upscaleDescription: String
        var settingsLine: String
        var generationLine: String
        var processCPU: Double
        var systemCPU: Double
        var residentMB: Double
    }

    private var savesToFile: Bool

    private init() {
        savesToFile = UserDefaults.standard.object(forKey: Self.saveFilesKey) as? Bool ?? true
        if savesToFile {
            openFile(backfill: [])
        }
        _ = processCPUPercent()
        _ = systemCPUPercent()
        event("session", "log opened\(savesToFile ? "" : " (memory only, file saving is off)")")
    }

    // MARK: - File output

    /// The file this session writes to, or nil while file saving is off.
    var fileURL: URL? {
        writeQueue.sync { currentFileURL }
    }

    var isSavingToFile: Bool {
        get { lock.sync { savesToFile } }
        set {
            let changed: Bool = lock.sync {
                let changed = savesToFile != newValue
                savesToFile = newValue
                return changed
            }
            UserDefaults.standard.set(newValue, forKey: Self.saveFilesKey)
            guard changed else { return }
            if newValue {
                openFile(backfill: recentLines())
                event("session", "file saving turned on")
            } else {
                event("session", "file saving turned off")
                writeQueue.async {
                    try? self.handle?.close()
                    self.handle = nil
                    self.currentFileURL = nil
                }
            }
        }
    }

    /// Total size of saved logs, in bytes.
    func savedLogsSize() -> Int64 {
        savedLogFiles().reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// Deletes saved logs except the one currently being written.
    func deleteSavedLogs() {
        let current = fileURL
        for url in savedLogFiles() where url != current {
            try? FileManager.default.removeItem(at: url)
        }
        event("session", "old log files deleted")
    }

    private func savedLogFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return urls.filter { $0.pathExtension == "log" }
    }

    private func openFile(backfill: [PipelineLogLine]) {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let name = "metalduck-\(stamp.string(from: Date()).replacingOccurrences(of: ":", with: "-")).log"
        let url = Self.directory.appendingPathComponent(name)
        let header = Self.header(for: url)
        let earlier = backfill.map { Self.stamped("\($0.category): \($0.message)", at: $0.date) }.joined()

        writeQueue.sync {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try? FileHandle(forWritingTo: url)
            currentFileURL = handle == nil ? nil : url
            if let data = (header + earlier).data(using: .utf8) {
                handle?.write(data)
            }
        }
    }

    private static func header(for url: URL) -> String {
        """
        MetalDuck pipeline log
        File: \(url.path)

        How to read a one-second summary
          capture      Real frames delivered by ScreenCaptureKit.
          passthrough  A captured frame shown as is: frame generation is off, too few captures are buffered, or t landed on a capture.
          flow         A new frame built at time t by warping both captures along Vision optical flow (VNGenerateOpticalFlowRequest).
          blend        Frame generation is on, but flow was not usable. The two captured frames are mixed linearly at time t. This is not motion-compensated generation.
          repeated     The same captured frame was shown again because no newer capture had arrived.
          no-frame     The render loop ran, but no captured frame was available.
          vision busy  A waiting flow request was replaced by a newer pair because Vision was already busy.
          flow lag     Captures between the pair being shown and the pair the flow came from. 0 means exact.
          2x / 3x / 4x These do not enqueue that many frames. They only raise the output refresh target to captureFPS × multiplier, capped by the target FPS. Output runs slightly behind capture, and each output frame samples time t between the two buffered captures around that moment.

        The on-screen SOURCE and CAP counters are the same number. This log reports measured capture fps and output fps separately.


        """
    }

    private static func stamped(_ message: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return "[\(formatter.string(from: date))] \(message)\n"
    }

    // MARK: - Events

    func event(_ category: String, _ message: String) {
        write("\(category): \(message)")
        publish(PipelineLogLine(date: Date(), category: category, message: message))
    }

    /// Newest last.
    func recentLines() -> [PipelineLogLine] {
        lock.sync { recent }
    }

    /// Per-second stats of the current session, newest last.
    func recentStats() -> [PipelineLiveStats] {
        lock.sync { statsHistory }
    }

    /// Samples CPU and memory outside a running session so the panel is never blank.
    func currentLoad() -> PipelineLoad {
        lock.sync {
            PipelineLoad(processCPU: processCPUPercent(), systemCPU: systemCPUPercent(), residentMB: residentMemoryMB())
        }
    }

    private func publish(_ line: PipelineLogLine) {
        lock.sync {
            recent.append(line)
            if recent.count > recentLimit {
                recent.removeFirst(recent.count - recentLimit)
            }
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pipelineLogLine, object: line)
        }
    }

    func logCaptureStarted(
        target: String,
        pixelWidth: Int,
        pixelHeight: Int,
        configuredFPS: Int,
        configuredQueueDepth: Int
    ) {
        event(
            "capture",
            "stream started \(pixelWidth)x\(pixelHeight) target=\(target) configuredFPS=\(configuredFPS) configuredQueueDepth=\(configuredQueueDepth). ScreenCaptureKit delivers at most the configured rate, and only when the content changes."
        )
    }

    func logSessionRunning(settings: RenderSettings, capture: CaptureConfiguration, target: CaptureTarget) {
        lock.lock()
        announcedFirstFlow = false
        lock.unlock()
        event(
            "session",
            "running target=\(Self.describe(target)) \(Self.describe(settings: settings, captureFPS: capture.framesPerSecond))"
        )
    }

    func noteCapture(width: Int, height: Int, interval: TimeInterval, timestamp: Double) {
        var firstSize: String?
        lock.lock()
        captureCount += 1
        if lastCaptureTimestamp > 0, timestamp > lastCaptureTimestamp, timestamp - lastCaptureTimestamp < 0.5 {
            captureCadence[Int(((timestamp - lastCaptureTimestamp) * 1000).rounded()), default: 0] += 1
        }
        lastCaptureTimestamp = timestamp
        if interval > 0 {
            captureIntervalSum += interval
            captureIntervalMax = max(captureIntervalMax, interval)
            captureIntervalSamples += 1
        }
        if width != lastCaptureWidth || height != lastCaptureHeight || !sawCapture {
            firstSize = "\(width)x\(height)"
            lastCaptureWidth = width
            lastCaptureHeight = height
        }
        sawCapture = true
        lock.unlock()

        if let firstSize {
            event("capture", "frame size \(firstSize)")
        }
    }

    func noteCaptureDrop(_ reason: String) {
        var shouldLog = false
        lock.lock()
        captureDropCount += 1
        if reason != lastDropReason {
            lastDropReason = reason
            shouldLog = true
        }
        lock.unlock()
        if shouldLog {
            event("capture", "dropped sample: \(reason)")
        }
    }

    func noteFlowStarted() {
        lock.lock()
        flowStarted += 1
        lock.unlock()
    }

    func noteFlowSkippedBusy() {
        lock.lock()
        flowSkippedBusy += 1
        lock.unlock()
    }

    func noteFlowFinished(milliseconds: Double, width: Int, height: Int) {
        var isFirst = false
        lock.lock()
        isFirst = !announcedFirstFlow
        announcedFirstFlow = true
        flowFinished += 1
        flowMillisecondsSum += milliseconds
        lastFlowComputeMilliseconds = milliseconds
        lastFlowWidth = width
        lastFlowHeight = height
        lock.unlock()
        if isFirst {
            event(
                "generate",
                "first optical flow ready in \(Self.milliseconds(milliseconds)) at \(width)x\(height). Later frames can use motion-compensated warping."
            )
        }
    }

    func noteFlowFailed(milliseconds: Double, reason: String) {
        var shouldLog = false
        lock.lock()
        flowFailed += 1
        flowMillisecondsSum += milliseconds
        let count = (flowFailReasons[reason] ?? 0) + 1
        flowFailReasons[reason] = count
        shouldLog = count == 1
        lock.unlock()
        if shouldLog {
            event("generate", "optical flow failed: \(reason)")
        }
    }

    func notePresent(_ kind: PresentKind) {
        var transition: String?
        lock.lock()
        let label = Self.meaningfulLabel(kind)
        switch kind {
        case .noFrame:
            presentNoFrame += 1
        case .passthrough:
            presentPassthrough += 1
        case .flow(let t, let flowWidth, let flowHeight, let flowFrameID, let latestCaptureID):
            presentFlow += 1
            lastFlowT = Double(t)
            lastFlowWidth = flowWidth
            lastFlowHeight = flowHeight
            let lag = Int(latestCaptureID >= flowFrameID ? latestCaptureID - flowFrameID : 0)
            lastFlowLag = lag
            maxFlowLag = max(maxFlowLag, lag)
        case .blend(let t, let reason):
            presentBlend += 1
            lastBlendT = Double(t)
            blendReasonCounts[reason, default: 0] += 1
        case .repeated:
            presentRepeated += 1
        }
        if let label, label != lastMeaningfulPresent {
            let previous = lastMeaningfulPresent.isEmpty ? "none" : lastMeaningfulPresent
            lastMeaningfulPresent = label
            transition = "\(previous) → \(label). \(Self.meaning(of: label))"
        }
        lock.unlock()

        if let transition {
            event("generate", "presentation changed \(transition)")
        }
    }

    /// One drawable reaching the screen. `presentedTime` is zero when the system dropped it.
    /// `contentTime` is the moment of the source the frame depicts; on a smooth output it
    /// advances exactly as fast as the screen does.
    func notePresented(presentedTime: Double, contentTime: Double, expectedInterval: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard presentedTime > 0 else {
            screenDropped += 1
            return
        }
        screenCount += 1
        if lastScreenTime > 0 {
            let interval = presentedTime - lastScreenTime
            if interval > 0, interval < 0.25 {
                screenIntervalSum += interval
                screenIntervalMax = max(screenIntervalMax, interval)
                if interval > expectedInterval * 1.5 {
                    screenLate += 1
                }
                let step = contentTime - lastScreenContentTime
                if step >= 0, step < 0.25 {
                    let error = abs(step - interval)
                    motionErrorSum += error
                    motionErrorMax = max(motionErrorMax, error)
                    motionSamples += 1
                }
            }
        }
        lastScreenTime = presentedTime
        lastScreenContentTime = contentTime
    }

    func noteUpscale(
        algorithm: String,
        inputWidth: Int,
        inputHeight: Int,
        outputWidth: Int,
        outputHeight: Int,
        fellBack: Bool
    ) {
        lock.lock()
        upscaleDescription = "\(algorithm) \(inputWidth)x\(inputHeight) → \(outputWidth)x\(outputHeight)"
        if fellBack {
            upscaleFallbacks += 1
        }
        lock.unlock()
    }

    func finishFrame(
        drawMilliseconds: Double,
        settings: RenderSettings,
        configuredCaptureFPS: Int,
        targetPresentFPS: Int
    ) {
        let snapshot: Snapshot? = lock.sync {
            drawCount += 1
            drawMillisecondsSum += drawMilliseconds
            drawMillisecondsMax = max(drawMillisecondsMax, drawMilliseconds)
            let elapsed = CACurrentMediaTime() - windowStart
            guard elapsed >= 1.0 else { return nil }
            return takeSnapshotLocked(
                reason: "1s",
                elapsed: elapsed,
                settings: settings,
                configuredCaptureFPS: configuredCaptureFPS,
                targetPresentFPS: targetPresentFPS
            )
        }
        if let snapshot {
            writeSummary(snapshot)
        }
    }

    func flush(
        reason: String,
        settings: RenderSettings,
        configuredCaptureFPS: Int,
        targetPresentFPS: Int
    ) {
        let snapshot: Snapshot = lock.sync {
            let elapsed = max(0.001, CACurrentMediaTime() - windowStart)
            return takeSnapshotLocked(
                reason: reason,
                elapsed: elapsed,
                settings: settings,
                configuredCaptureFPS: configuredCaptureFPS,
                targetPresentFPS: targetPresentFPS
            )
        }
        writeSummary(snapshot)
    }

    private func takeSnapshotLocked(
        reason: String,
        elapsed: Double,
        settings: RenderSettings,
        configuredCaptureFPS: Int,
        targetPresentFPS: Int
    ) -> Snapshot {
        let snapshot = Snapshot(
            reason: reason,
            elapsed: elapsed,
            captureCount: captureCount,
            captureDropCount: captureDropCount,
            captureIntervalSum: captureIntervalSum,
            captureIntervalMax: captureIntervalMax,
            captureIntervalSamples: captureIntervalSamples,
            captureWidth: lastCaptureWidth,
            captureHeight: lastCaptureHeight,
            lastDropReason: lastDropReason,
            presentNoFrame: presentNoFrame,
            presentPassthrough: presentPassthrough,
            presentFlow: presentFlow,
            presentBlend: presentBlend,
            presentRepeated: presentRepeated,
            blendReasonCounts: blendReasonCounts,
            lastBlendT: lastBlendT,
            lastFlowT: lastFlowT,
            lastFlowWidth: lastFlowWidth,
            lastFlowHeight: lastFlowHeight,
            lastFlowLag: lastFlowLag,
            maxFlowLag: maxFlowLag,
            flowStarted: flowStarted,
            flowFinished: flowFinished,
            flowSkippedBusy: flowSkippedBusy,
            flowFailed: flowFailed,
            flowFailReasons: flowFailReasons,
            flowMillisecondsSum: flowMillisecondsSum,
            lastFlowComputeMilliseconds: lastFlowComputeMilliseconds,
            captureCadence: captureCadence,
            screenCount: screenCount,
            screenDropped: screenDropped,
            screenIntervalSum: screenIntervalSum,
            screenIntervalMax: screenIntervalMax,
            screenLate: screenLate,
            motionErrorSum: motionErrorSum,
            motionErrorMax: motionErrorMax,
            motionSamples: motionSamples,
            drawCount: drawCount,
            drawMillisecondsSum: drawMillisecondsSum,
            drawMillisecondsMax: drawMillisecondsMax,
            upscaleFallbacks: upscaleFallbacks,
            upscaleDescription: upscaleDescription,
            settingsLine: Self.describe(settings: settings, captureFPS: configuredCaptureFPS)
                + " outputTarget=\(targetPresentFPS)fps",
            generationLine: Self.generationExplanation(settings: settings, captureFPS: configuredCaptureFPS),
            processCPU: processCPUPercent(),
            systemCPU: systemCPUPercent(),
            residentMB: residentMemoryMB()
        )

        windowStart = CACurrentMediaTime()
        captureCount = 0
        captureDropCount = 0
        captureIntervalSum = 0
        captureIntervalMax = 0
        captureIntervalSamples = 0
        presentNoFrame = 0
        presentPassthrough = 0
        presentFlow = 0
        presentBlend = 0
        presentRepeated = 0
        blendReasonCounts = [:]
        flowStarted = 0
        flowFinished = 0
        flowSkippedBusy = 0
        flowFailed = 0
        flowFailReasons = [:]
        flowMillisecondsSum = 0
        captureCadence = [:]
        screenCount = 0
        screenDropped = 0
        screenIntervalSum = 0
        screenIntervalMax = 0
        screenLate = 0
        motionErrorSum = 0
        motionErrorMax = 0
        motionSamples = 0
        drawCount = 0
        drawMillisecondsSum = 0
        drawMillisecondsMax = 0
        upscaleFallbacks = 0
        maxFlowLag = 0
        return snapshot
    }

    private func writeSummary(_ snapshot: Snapshot) {
        let elapsed = snapshot.elapsed
        let captureFPS = Double(snapshot.captureCount) / elapsed
        let outputCount = snapshot.presentPassthrough + snapshot.presentFlow + snapshot.presentBlend + snapshot.presentRepeated
        let outputFPS = Double(outputCount) / elapsed
        let captureIntervalAvg = snapshot.captureIntervalSamples > 0
            ? (snapshot.captureIntervalSum / Double(snapshot.captureIntervalSamples)) * 1000
            : 0
        let drawAvg = snapshot.drawCount > 0 ? snapshot.drawMillisecondsSum / Double(snapshot.drawCount) : 0
        let flowAvg = (snapshot.flowFinished + snapshot.flowFailed) > 0
            ? snapshot.flowMillisecondsSum / Double(snapshot.flowFinished + snapshot.flowFailed)
            : 0
        let blendReasons = snapshot.blendReasonCounts
            .sorted { $0.value > $1.value }
            .map { "\($0.key) ×\($0.value)" }
            .joined(separator: ", ")
        let flowFailures = snapshot.flowFailReasons
            .sorted { $0.value > $1.value }
            .map { "\($0.key) ×\($0.value)" }
            .joined(separator: ", ")

        var lines: [String] = []
        lines.append("---- pipeline \(snapshot.reason) \(String(format: "%.2f", elapsed))s ----")
        lines.append(snapshot.settingsLine)
        lines.append(snapshot.generationLine)
        lines.append(
            "capture: \(Self.fps(captureFPS)) fps  \(snapshot.captureWidth)x\(snapshot.captureHeight)  interval avg \(Self.milliseconds(captureIntervalAvg)) max \(Self.milliseconds(snapshot.captureIntervalMax * 1000))  drops \(snapshot.captureDropCount)\(snapshot.lastDropReason.isEmpty ? "" : " (\(snapshot.lastDropReason))")"
        )
        lines.append(
            "output: \(Self.fps(outputFPS)) fps  flow \(snapshot.presentFlow)  blend \(snapshot.presentBlend)  passthrough \(snapshot.presentPassthrough)  repeated \(snapshot.presentRepeated)  no-frame \(snapshot.presentNoFrame)"
        )
        let cadence = snapshot.captureCadence
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { "\($0.key)ms×\($0.value)" }
            .joined(separator: " ")
        if !cadence.isEmpty {
            lines.append("  capture cadence (timestamps): \(cadence)")
        }
        if snapshot.screenCount > 0 {
            let screenIntervals = max(1, snapshot.motionSamples)
            let screenAvg = snapshot.screenIntervalSum / Double(max(1, snapshot.screenCount - 1)) * 1000
            lines.append(
                "screen: \(Self.fps(Double(snapshot.screenCount) / elapsed)) fps on glass  interval avg \(Self.milliseconds(screenAvg)) max \(Self.milliseconds(snapshot.screenIntervalMax * 1000))  late \(snapshot.screenLate)  dropped \(snapshot.screenDropped)  motion error avg \(Self.milliseconds(snapshot.motionErrorSum / Double(screenIntervals) * 1000)) max \(Self.milliseconds(snapshot.motionErrorMax * 1000))"
            )
        }
        if snapshot.presentFlow > 0 {
            lines.append(
                "  flow sample: t=\(String(format: "%.2f", snapshot.lastFlowT)) vectors \(snapshot.lastFlowWidth)x\(snapshot.lastFlowHeight) lag \(snapshot.lastFlowLag) captures (max \(snapshot.maxFlowLag))"
            )
        }
        if snapshot.presentBlend > 0 {
            lines.append(
                "  blend sample: t=\(String(format: "%.2f", snapshot.lastBlendT)) reasons: \(blendReasons.isEmpty ? "unspecified" : blendReasons)"
            )
        }
        let flowAttempts = snapshot.flowStarted + snapshot.flowSkippedBusy
        if flowAttempts == 0 && snapshot.flowFinished == 0 && snapshot.flowFailed == 0 {
            lines.append("vision flow: idle")
        } else {
            lines.append(
                "vision flow: started \(snapshot.flowStarted)  finished \(snapshot.flowFinished)  busy-skipped \(snapshot.flowSkippedBusy)  failed \(snapshot.flowFailed)  compute avg \(Self.milliseconds(flowAvg)) last \(Self.milliseconds(snapshot.lastFlowComputeMilliseconds))\(flowFailures.isEmpty ? "" : "  failures: \(flowFailures)")"
            )
        }
        lines.append("upscale: \(snapshot.upscaleDescription)  metalFX fallbacks \(snapshot.upscaleFallbacks)")
        lines.append(
            "load: process CPU \(Self.percent(snapshot.processCPU))  system CPU \(Self.percent(snapshot.systemCPU))  RSS \(String(format: "%.0f", snapshot.residentMB)) MB  draw avg \(Self.milliseconds(drawAvg)) max \(Self.milliseconds(snapshot.drawMillisecondsMax)) over \(snapshot.drawCount) draws"
        )
        let verdictText = verdict(snapshot)
        lines.append("verdict: \(verdictText)")
        write(lines.joined(separator: "\n"))

        let live = PipelineLiveStats(
            date: Date(),
            captureFPS: captureFPS,
            outputFPS: outputFPS,
            generatedFPS: Double(snapshot.presentFlow + snapshot.presentBlend) / elapsed,
            captureDrops: snapshot.captureDropCount,
            flowLag: snapshot.lastFlowLag,
            flowFrames: snapshot.presentFlow,
            blendFrames: snapshot.presentBlend,
            passthroughFrames: snapshot.presentPassthrough,
            repeatedFrames: snapshot.presentRepeated,
            visionBusySkipped: snapshot.flowSkippedBusy,
            flowComputeMilliseconds: flowAvg,
            drawAverageMilliseconds: drawAvg,
            drawMaxMilliseconds: snapshot.drawMillisecondsMax,
            load: PipelineLoad(processCPU: snapshot.processCPU, systemCPU: snapshot.systemCPU, residentMB: snapshot.residentMB),
            verdict: verdictText
        )
        lock.sync {
            statsHistory.append(live)
            if statsHistory.count > statsHistoryLimit {
                statsHistory.removeFirst(statsHistory.count - statsHistoryLimit)
            }
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pipelineLiveStats, object: live)
        }
        publish(PipelineLogLine(
            date: Date(),
            category: "summary",
            message: "\(Self.fps(captureFPS)) → \(Self.fps(outputFPS)) fps · flow \(snapshot.presentFlow) · blend \(snapshot.presentBlend) · \(verdictText)"
        ))
    }

    private func verdict(_ snapshot: Snapshot) -> String {
        if snapshot.captureCount == 0 && snapshot.presentPassthrough + snapshot.presentFlow + snapshot.presentBlend == 0 {
            if snapshot.presentNoFrame > 0 || snapshot.drawCount > 0 {
                return "NOT WORKING — the render loop is running, but ScreenCaptureKit delivered no frames."
            }
            return "IDLE — no capture and no output in this window."
        }

        let newFrames = snapshot.presentFlow + snapshot.presentBlend + snapshot.presentPassthrough
        if snapshot.captureCount > 0 && newFrames == 0 && snapshot.presentRepeated == 0 {
            return "NOT WORKING — frames are captured, but none of them were presented."
        }

        guard snapshot.generationLine.contains("frame generation ON") else {
            if snapshot.presentPassthrough == 0 && snapshot.presentRepeated > 0 {
                return "DEGRADED — frame generation is off and the output is only repeating an old frame."
            }
            return "WORKING — frame generation is off. Output is the captured frame, possibly upscaled."
        }

        if snapshot.presentFlow == 0 && snapshot.presentBlend > 0 {
            let reason = snapshot.blendReasonCounts.max { $0.value < $1.value }?.key ?? "no flow"
            return "PARTIAL — frame generation is on, but every new frame was a linear blend (\(reason)). Optical-flow warping did not produce a frame in this window."
        }

        if snapshot.presentFlow == 0 && snapshot.presentRepeated > 0 {
            return "WAITING — output is repeating the last frame. No new interpolation was built in this window."
        }

        if snapshot.flowStarted > 0 && snapshot.flowSkippedBusy >= snapshot.flowStarted {
            return "WORKING, BUT SLOW — optical-flow frames are on screen, and Vision is dropping most new requests because the previous flow is still computing (lag \(snapshot.lastFlowLag) captures)."
        }

        if snapshot.presentBlend > snapshot.presentFlow {
            return "PARTIAL — some frames are optical-flow warps, but most new frames still fall back to linear blending."
        }

        return "WORKING — optical-flow warping is producing frames (\(snapshot.presentFlow) flow, \(snapshot.presentBlend) blend, \(snapshot.presentRepeated) repeated)."
    }

    private func write(_ message: String, stamped: Bool = true) {
        let date = Date()
        let logger = self.logger
        writeQueue.async {
            logger.info("\(message, privacy: .public)")
            guard let handle = self.handle else { return }
            let text = stamped
                ? Self.stamped(message, at: date)
                : (message.hasSuffix("\n") ? message : message + "\n")
            if let data = text.data(using: .utf8) {
                handle.write(data)
            }
        }
    }

    private func processCPUPercent() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return -1 }
        let sample = CPUSample(
            user: Self.timevalSeconds(usage.ru_utime),
            system: Self.timevalSeconds(usage.ru_stime),
            wall: CACurrentMediaTime()
        )
        defer { previousProcessCPU = sample }
        guard let previous = previousProcessCPU else { return -1 }
        let cpu = (sample.user - previous.user) + (sample.system - previous.system)
        let wall = sample.wall - previous.wall
        guard wall > 0 else { return -1 }
        return cpu / wall * 100
    }

    private func systemCPUPercent() -> Double {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { previousSystemTicks = ticks }
        guard let previous = previousSystemTicks, previous.count == 4 else { return -1 }
        let deltas = zip(ticks, previous).map { current, prior in current &- prior }
        let idle = Double(deltas[2])
        let total = deltas.reduce(0, +)
        guard total > 0 else { return -1 }
        return (1 - idle / Double(total)) * 100
    }

    private func residentMemoryMB() -> Double {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.resident_size) / (1024 * 1024)
    }

    private static func describe(settings: RenderSettings, captureFPS: Int) -> String {
        let fg = settings.frameGenerationEnabled
            ? "frame generation ON \(settings.frameGenerationMode.rawValue)"
            : "frame generation OFF"
        return "\(fg)  upscale=\(settings.upscalingAlgorithm.rawValue)  scale=\(String(format: "%.2f", settings.outputScale))  matchOutput=\(settings.matchOutputResolution)  sharpness=\(String(format: "%.2f", settings.sharpness))  drs=\(settings.dynamicResolutionEnabled)  configuredCapture=\(captureFPS)fps  target=\(settings.targetPresentationFPS)fps"
    }

    private static func generationExplanation(settings: RenderSettings, captureFPS: Int) -> String {
        guard settings.frameGenerationEnabled else {
            return "frame generation OFF — each output frame is a captured frame. Nothing is interpolated."
        }
        let multiplier: Int
        let inserted: Int
        switch settings.frameGenerationMode {
        case .x2:
            multiplier = 2
            inserted = 1
        case .x3:
            multiplier = 3
            inserted = 2
        case .x4:
            multiplier = 4
            inserted = 3
        }
        let ceiling = captureFPS * multiplier
        return "frame generation ON — mode \(settings.frameGenerationMode.rawValue) means about \(inserted) extra sample(s) between captures, output ceiling \(ceiling) fps. Output trails capture by about one capture interval plus the flow time. For each output tick, t places that moment between the two captures around it; flow warps both captures to t, and blend mixes them when flow is missing."
    }

    private static func describe(_ target: CaptureTarget) -> String {
        switch target {
        case .automatic:
            return "automatic"
        case .display(let id):
            return "display \(id)"
        case .window(let id):
            return "window \(id.map(String.init) ?? "unspecified")"
        }
    }

    private static func meaningfulLabel(_ kind: PresentKind) -> String? {
        switch kind {
        case .noFrame, .repeated:
            return nil
        case .passthrough:
            return "passthrough"
        case .flow:
            return "flow"
        case .blend:
            return "blend"
        }
    }

    private static func meaning(of label: String) -> String {
        switch label {
        case "flow":
            return "New frames are motion-compensated warps."
        case "blend":
            return "New frames are linear mixes, not optical-flow warps."
        case "passthrough":
            return "New frames are the captured image itself."
        default:
            return ""
        }
    }

    private static func fps(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func percent(_ value: Double) -> String {
        guard value >= 0 else { return "n/a" }
        return String(format: "%.0f%%", value)
    }

    private static func milliseconds(_ value: Double) -> String {
        String(format: "%.1f ms", value)
    }

    private static func timevalSeconds(_ value: timeval) -> Double {
        Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
    }
}

private extension NSLock {
    func sync<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
