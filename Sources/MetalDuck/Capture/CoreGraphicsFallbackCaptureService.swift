import Foundation

enum CoreGraphicsFallbackCaptureError: Error {
    case unsupportedOnThisOS
}

// On modern macOS versions, CoreGraphics image capture APIs are unavailable.
// Keep a lightweight fallback implementation that reports unsupported.
final class CoreGraphicsFallbackCaptureService: FrameCaptureService, @unchecked Sendable {
    var onFrame: ((CapturedFrame) -> Void)?
    var onError: ((Error) -> Void)?

    private var target: CaptureTarget
    private var captureConfiguration: CaptureConfiguration

    init(context: MetalContext, target: CaptureTarget, configuration: CaptureConfiguration) {
        _ = context
        self.target = target
        self.captureConfiguration = configuration
    }

    func start() async throws {
        throw CoreGraphicsFallbackCaptureError.unsupportedOnThisOS
    }

    func stop() async {
        // no-op
    }

    func reconfigure(target: CaptureTarget) async throws {
        self.target = target
    }

    func reconfigure(configuration: CaptureConfiguration) async throws {
        self.captureConfiguration = configuration
    }
}
