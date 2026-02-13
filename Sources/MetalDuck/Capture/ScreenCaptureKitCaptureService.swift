import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Metal
import ScreenCaptureKit

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
        let filter = makeFilter(for: selection)
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
            let candidates = shareableContent.windows.filter { $0.isOnScreen }
            if let requestedWindowID,
               let window = candidates.first(where: { $0.windowID == requestedWindowID }) {
                return .window(window)
            }
            guard let window = candidates.first(where: { $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier })
                ?? candidates.first else {
                throw ScreenCaptureServiceError.noShareableWindow
            }
            return .window(window)

        case .automatic:
            let windows = shareableContent.windows.filter { $0.isOnScreen && $0.windowLayer == 0 }
            if let window = windows.first(where: { $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier }) {
                return .window(window)
            }
            guard let display = shareableContent.displays.first else {
                throw ScreenCaptureServiceError.noShareableDisplay
            }
            return .display(display)
        }
    }

    private func makeFilter(for selection: Selection) -> SCContentFilter {
        switch selection {
        case .display(let display):
            let filter = SCContentFilter(display: display, excludingWindows: [])
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
            return (
                width: max(1, Int(preferredPixelSize.width)),
                height: max(1, Int(preferredPixelSize.height))
            )
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

    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        if let status = frameStatus(from: sampleBuffer) {
            switch status {
            case .complete, .started:
                break
            default:
                return
            }
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
            backingTexture: wrappedTexture
        )

        onFrame?(frame)
    }

    private func frameStatus(from sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[AnyHashable: Any]],
              let firstAttachment = attachments.first,
              let statusValue = firstAttachment[SCStreamFrameInfo.status] as? NSNumber else {
            return nil
        }

        return SCFrameStatus(rawValue: statusValue.intValue)
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
