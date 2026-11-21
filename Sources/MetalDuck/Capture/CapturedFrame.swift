import CoreGraphics
import CoreMedia
import CoreVideo
import Metal

struct CapturedFrame {
    let subtitleImage: SubtitleImage
    let texture: MTLTexture
    let timestamp: CMTime
    let contentRect: CGRect
    // The physical screen coordinates where this frame should be displayed
    let targetRect: CGRect?

    // Keep this reference alive for frames that come from CVMetalTexture wrappers.
    let backingTexture: CVMetalTexture

    init?(pixelBuffer: CVPixelBuffer, timestamp: CMTime, targetRect: CGRect?, context: MetalContext) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var backing: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, context.textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &backing
        )
        guard status == kCVReturnSuccess, let backing, let texture = CVMetalTextureGetTexture(backing) else {
            PipelineLog.shared.noteCaptureDrop("could not wrap pixel buffer as a Metal texture (status \(status))")
            return nil
        }
        self.subtitleImage = SubtitleImage(pixelBuffer: pixelBuffer)
        self.texture = texture
        self.timestamp = timestamp
        self.contentRect = CGRect(x: 0, y: 0, width: width, height: height)
        self.targetRect = targetRect
        self.backingTexture = backing
    }
}
