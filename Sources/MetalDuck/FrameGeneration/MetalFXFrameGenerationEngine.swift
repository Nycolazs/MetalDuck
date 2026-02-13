import Foundation
import Metal

struct FrameGenerationAuxiliary {
    let depthTexture: MTLTexture
    let motionTexture: MTLTexture
    let uiTexture: MTLTexture?

    init(depthTexture: MTLTexture, motionTexture: MTLTexture, uiTexture: MTLTexture? = nil) {
        self.depthTexture = depthTexture
        self.motionTexture = motionTexture
        self.uiTexture = uiTexture
    }
}

enum FrameGenerationError: Error {
    case unsupportedDevice
}

final class MetalFXFrameGenerationEngine {
    private let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }

    // On SDKs where Frame Interpolator APIs are unavailable, keep a safe stub.
    // The renderer already falls back to normal frame presentation when this returns unsupported.
    var isSupported: Bool {
        _ = device
        return false
    }

    func interpolate(
        commandBuffer: MTLCommandBuffer,
        previousTexture: MTLTexture,
        currentTexture: MTLTexture,
        auxiliary: FrameGenerationAuxiliary,
        deltaTime: Float
    ) throws -> MTLTexture {
        _ = commandBuffer
        _ = previousTexture
        _ = currentTexture
        _ = auxiliary
        _ = deltaTime
        throw FrameGenerationError.unsupportedDevice
    }
}
