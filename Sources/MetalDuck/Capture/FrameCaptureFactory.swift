import Foundation

enum FrameCaptureFactory {
    static func make(
        context: MetalContext,
        target: CaptureTarget,
        configuration: CaptureConfiguration
    ) -> FrameCaptureService {
        if #available(macOS 12.3, *) {
            return ScreenCaptureKitCaptureService(
                context: context,
                target: target,
                configuration: configuration
            )
        }

        return CoreGraphicsFallbackCaptureService(
            context: context,
            target: target,
            configuration: configuration
        )
    }
}
