import CoreVideo
import Metal

enum MetalContextError: Error {
    case noDevice
    case noCommandQueue
    case textureCacheCreationFailed
}

final class MetalContext {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let textureCache: CVMetalTextureCache

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalContextError.noDevice
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalContextError.noCommandQueue
        }

        var cache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )

        guard cacheStatus == kCVReturnSuccess, let cache else {
            throw MetalContextError.textureCacheCreationFailed
        }

        self.device = device
        self.commandQueue = commandQueue
        self.textureCache = cache
    }
}
