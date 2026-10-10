import CoreGraphics
import CoreMedia
import CoreVideo
import Metal
import simd

struct CapturedFrame {
    let texture: MTLTexture
    let timestamp: CMTime
    let contentRect: CGRect
    // The physical screen coordinates where this frame should be displayed
    let targetRect: CGRect
    // Estimated global motion from previous frame to current frame, in source pixels.
    let motionHint: SIMD2<Float>

    // Keep this reference alive for frames that come from CVMetalTexture wrappers.
    let backingTexture: CVMetalTexture?
}
