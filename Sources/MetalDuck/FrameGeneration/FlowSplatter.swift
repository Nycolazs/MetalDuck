import Foundation
import Metal

/// Carries the motion of both captures to the moment being built (see `splatFlow` in
/// Present.metal), so each spot of an in-between frame knows its motion and which capture can
/// see it. Without it, the motion was read at the spot in the older capture, which around a
/// moving person belongs to the person on one side and the background on the other: the halo
/// and see-through edge around anything large that moves.
///
/// The motion splatted is Vision's, except where blocks move on their own: there each flow
/// pixel takes the nearby block vector that lines it up clearly better (see `fuseFlow`).
/// Works at the flow's size (about 800 px wide). On an M1 Pro at 1818x1141 it costs about
/// 0.3 ms of GPU per pair (the fused motion) and 0.4 ms per in-between frame (the splat).
/// Not thread-safe: the renderer calls it under its render lock.
final class FlowSplatter {
    // Must match Present.metal.
    private struct FuseParams {
        var gain: Float
        var blockToFlow: Float
    }

    // Must match Present.metal.
    private struct SplatParams {
        var t: Float
        var gain: Float
        var colourWeight: Float
        var roundTripWeight: Float
        var calmFrom: Float
        var calmFull: Float
        var difficultyScale: Float
        var previousDifficultyScale: Float
    }

    /// How quickly a pixel's weight falls with its colour mismatch (0-1) and with its round
    /// trip through the other flow (flow pixels): a pixel about to be covered matches the
    /// thing covering it, not itself, and must lose to it.
    private static let colourWeight: Float = 25
    private static let roundTripWeight: Float = 0.7

    private let device: MTLDevice
    private let fuse: MTLComputePipelineState
    private let splat: MTLComputePipelineState
    private let resolve: MTLComputePipelineState
    private var sums: MTLBuffer?
    private var motion: MTLTexture?
    private var fusedForward: MTLTexture?
    private var fusedBackward: MTLTexture?
    private var fusedPair: (UInt64, UInt64)?

    init?(device: MTLDevice, library: MTLLibrary) {
        guard let fuseFunction = library.makeFunction(name: "fuseFlow"),
              let splatFunction = library.makeFunction(name: "splatFlow"),
              let resolveFunction = library.makeFunction(name: "resolveSplatFlow"),
              let fuse = try? device.makeComputePipelineState(function: fuseFunction),
              let splat = try? device.makeComputePipelineState(function: splatFunction),
              let resolve = try? device.makeComputePipelineState(function: resolveFunction) else {
            return nil
        }
        self.device = device
        self.fuse = fuse
        self.splat = splat
        self.resolve = resolve
    }

    /// Each flow pixel's motion for a pair, in flow pixels: Vision's, or a block vector where
    /// blocks move on their own and one fits clearly better. Built once per pair (`pair` names
    /// it), then reused for each of its in-between frames.
    func fusedFlow(
        pair: (UInt64, UInt64),
        prev: MTLTexture,
        next: MTLTexture,
        visionForward: MTLTexture,
        visionBackward: MTLTexture,
        gain: Float,
        gated: BlockMotionEstimator.GatedFields,
        captureWidth: Int,
        commandBuffer: MTLCommandBuffer
    ) -> (forward: MTLTexture, backward: MTLTexture)? {
        let width = visionForward.width
        let height = visionForward.height
        if let fusedPair, fusedPair == pair, let fusedForward, let fusedBackward,
           fusedForward.width == width, fusedForward.height == height {
            return (fusedForward, fusedBackward)
        }
        if fusedForward == nil || fusedForward!.width != width || fusedForward!.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            fusedForward = device.makeTexture(descriptor: descriptor)
            fusedBackward = device.makeTexture(descriptor: descriptor)
        }
        guard let fusedForward, let fusedBackward,
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        let quarterWidth = (captureWidth + 3) / 4
        var params = FuseParams(gain: gain, blockToFlow: Float(width) / Float(max(quarterWidth, 1)))
        encoder.setComputePipelineState(fuse)
        encoder.setTexture(prev, index: 0)
        encoder.setTexture(next, index: 1)
        encoder.setTexture(visionForward, index: 2)
        encoder.setTexture(visionBackward, index: 3)
        encoder.setTexture(gated.forward, index: 4)
        encoder.setTexture(gated.backward, index: 5)
        encoder.setTexture(gated.mask, index: 6)
        encoder.setTexture(fusedForward, index: 7)
        encoder.setTexture(fusedBackward, index: 8)
        encoder.setBytes(&params, length: MemoryLayout<FuseParams>.stride, index: 0)
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 2),
            threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1)
        )
        encoder.endEncoding()
        fusedPair = pair
        return (fusedForward, fusedBackward)
    }

    /// Encodes the motion at `t` (after the artifact guard's calming, which the shader
    /// applies from the difficulty buffers) and returns it: rgba16Float at the flow's size,
    /// (x, y) older → newer in flow pixels, z and w the older and newer capture's sight.
    func motionAtT(
        prev: MTLTexture,
        next: MTLTexture,
        forward: MTLTexture,
        backward: MTLTexture,
        gain: Float,
        t: Float,
        calm: (from: Float, full: Float)?,
        difficulty: MTLBuffer,
        difficultyScale: Float,
        previousDifficulty: MTLBuffer,
        previousDifficultyScale: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        let width = forward.width
        let height = forward.height
        let length = width * height * 2 * MemoryLayout<UInt32>.stride
        if sums == nil || sums!.length != length {
            sums = device.makeBuffer(length: length, options: .storageModePrivate)
        }
        if motion == nil || motion!.width != width || motion!.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            motion = device.makeTexture(descriptor: descriptor)
        }
        guard let sums, let motion,
              let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.fill(buffer: sums, range: 0..<length, value: 0)
        blit.endEncoding()

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        var params = SplatParams(
            t: t,
            gain: gain,
            colourWeight: Self.colourWeight,
            roundTripWeight: Self.roundTripWeight,
            calmFrom: calm?.from ?? 0,
            calmFull: calm?.full ?? 0,
            difficultyScale: difficultyScale,
            previousDifficultyScale: previousDifficultyScale
        )
        encoder.setComputePipelineState(splat)
        encoder.setTexture(prev, index: 0)
        encoder.setTexture(next, index: 1)
        encoder.setTexture(forward, index: 2)
        encoder.setTexture(backward, index: 3)
        encoder.setBuffer(sums, offset: 0, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<SplatParams>.stride, index: 1)
        encoder.setBuffer(difficulty, offset: 0, index: 2)
        encoder.setBuffer(previousDifficulty, offset: 0, index: 3)
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 2),
            threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1)
        )
        var flowGain = gain
        encoder.setComputePipelineState(resolve)
        encoder.setBuffer(sums, offset: 0, index: 0)
        encoder.setBytes(&flowGain, length: MemoryLayout<Float>.stride, index: 1)
        encoder.setTexture(motion, index: 0)
        encoder.setTexture(forward, index: 1)
        encoder.setTexture(backward, index: 2)
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1)
        )
        encoder.endEncoding()
        return motion
    }
}
