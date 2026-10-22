import Foundation

enum FrameCaptureFactory {
    static func make(
        context: MetalContext,
        target: CaptureTarget,
        configuration: CaptureConfiguration
    ) -> FrameCaptureService {
        ScreenCaptureKitCaptureService(
            context: context,
            target: target,
            configuration: configuration
        )
    }
}
