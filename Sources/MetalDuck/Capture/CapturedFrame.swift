import CoreGraphics
import CoreMedia
import CoreVideo
import Metal

struct CapturedFrame {
    let texture: MTLTexture
    let timestamp: CMTime
    let contentRect: CGRect
    // The physical screen coordinates where this frame should be displayed
    let targetRect: CGRect

    // Keep this reference alive for frames that come from CVMetalTexture wrappers.
    let backingTexture: CVMetalTexture?
}
