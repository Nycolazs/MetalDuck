import CoreVideo
import Foundation
import Metal

enum FrameInterpolationAttempt {
    case produced(
        texture: MTLTexture,
        flowWidth: Int,
        flowHeight: Int,
        flowFrameID: UInt64,
        latestCaptureID: UInt64
    )
    case failed(String)
}

/// A buffered capture as the engine sees it.
struct GenerationFrame {
    let texture: MTLTexture
    let id: UInt64
}

// Must match Present.metal.
private struct FlowInterpolateParams {
    var t: Float
    var flowGain: Float
    var consistency: Float
    var colorTolerance: Float
}

// Must match Present.metal.
private struct BlockInterpolateParams {
    var t: Float
    var visionGain: Float
    var blockToCapture: Float
    var matchLimit: Float
    var calmFrom: Float
    var calmFull: Float
    var difficultyScale: Float
    var previousDifficultyScale: Float
    var splatOn: Float
}

/// Builds in-between frames by warping two captures along Vision optical flow.
final class MetalFXFrameGenerationEngine {
    private let device: MTLDevice
    private let interpolatePipeline: MTLComputePipelineState?
    /// Fast and independent motion: a block search next to Vision (see BlockMotionEstimator).
    private let blockMotion: BlockMotionEstimator?
    private let blockInterpolatePipeline: MTLComputePipelineState?
    /// The motion at each in-between moment, with which capture sees each spot (FlowSplatter).
    private let splatter: FlowSplatter?
    private var outputTexture: MTLTexture?

    /// Round-trip error, in flow pixels, still treated as a reliable vector.
    private let consistency: Float = 1.0
    /// Flow from a neighbouring pair may only be used where both warps agree this closely.
    private let borrowedFlowColorTolerance: Float = 0.08
    /// How many captures away a borrowed flow may be.
    private let maxBorrowDistance: UInt64 = 2

    let visionFlowProvider: VisionFlowProvider

    init(device: MTLDevice, commandQueue: MTLCommandQueue, library: MTLLibrary?) {
        self.device = device
        self.visionFlowProvider = VisionFlowProvider(device: device, commandQueue: commandQueue)

        guard let library else {
            PipelineLog.shared.event("generate", "no shader library — optical-flow warping disabled")
            self.interpolatePipeline = nil
            self.blockMotion = nil
            self.blockInterpolatePipeline = nil
            self.splatter = nil
            return
        }

        self.splatter = FlowSplatter(device: device, library: library)
        if splatter == nil {
            PipelineLog.shared.event("generate", "motion splatting unavailable; in-between frames read the motion in place")
        }

        self.blockMotion = BlockMotionEstimator(device: device, library: library)
        self.blockInterpolatePipeline = library.makeFunction(name: "flowInterpolateBlocks")
            .flatMap { try? device.makeComputePipelineState(function: $0) }
        if blockMotion == nil || blockInterpolatePipeline == nil {
            PipelineLog.shared.event("generate", "block motion search unavailable; fast objects use Vision's flow alone")
        } else {
            PipelineLog.shared.event("generate", "block motion search ready: follows fast and independent motion up to about 320 px between captures, where Vision's flow misses it")
        }

        if let function = library.makeFunction(name: "flowInterpolate") {
            do {
                self.interpolatePipeline = try device.makeComputePipelineState(function: function)
            } catch {
                PipelineLog.shared.event("generate", "pipeline flowInterpolate failed: \(error.localizedDescription)")
                self.interpolatePipeline = nil
            }
        } else {
            PipelineLog.shared.event("generate", "missing shader function flowInterpolate")
            self.interpolatePipeline = nil
        }

        if isSupported {
            PipelineLog.shared.event(
                "generate",
                "compute pipeline ready: flowInterpolate warps both captures and checks each vector against the opposite flow. Optical flow itself comes from Vision."
            )
        } else {
            PipelineLog.shared.event(
                "generate",
                "compute pipeline missing. Frame generation can only linearly blend the two buffered captures."
            )
        }
    }

    var isSupported: Bool {
        interpolatePipeline != nil
    }

    /// True when the block search found most of the picture unmatched between two captures
    /// (a cut, a flash, a jump); nil until it knows.
    func framesUnrelated(previousID: UInt64, nextID: UInt64) -> Bool? {
        blockMotion?.pairIsUnrelated(previousID: previousID, nextID: nextID)
    }

    func unmatchedShare(previousID: UInt64, nextID: UInt64) -> Double? {
        blockMotion?.unmatchedShare(previousID: previousID, nextID: nextID)
    }

    /// How much of a pair's picture no known motion fits (0-1), once measured on the GPU.
    func pairDifficulty(previousID: UInt64, nextID: UInt64) -> Double? {
        blockMotion?.difficultyShare(previousID: previousID, nextID: nextID)
    }

    /// Average time from a capture's timestamp until its flow is usable.
    var flowReadyLatency: Double {
        visionFlowProvider.flowReadyLatency
    }

    /// Encodes the downscaled copy Vision needs for a newly staged capture.
    func prepareFlowFrame(
        from texture: MTLTexture,
        id: UInt64,
        time: CFTimeInterval,
        commandBuffer: MTLCommandBuffer
    ) -> VisionFlowProvider.FlowFrame? {
        guard isSupported else { return nil }
        blockMotion?.prepare(texture: texture, id: id, commandBuffer: commandBuffer)
        return visionFlowProvider.encodeFlowFrame(from: texture, id: id, time: time, commandBuffer: commandBuffer)
    }

    /// Starts flow for the pair once `commandBuffer`, which wrote both frames, has finished on the GPU.
    func requestFlow(
        previous: VisionFlowProvider.FlowFrame,
        next: VisionFlowProvider.FlowFrame,
        after commandBuffer: MTLCommandBuffer
    ) {
        guard CVPixelBufferGetWidth(previous.pixelBuffer) == CVPixelBufferGetWidth(next.pixelBuffer),
              CVPixelBufferGetHeight(previous.pixelBuffer) == CVPixelBufferGetHeight(next.pixelBuffer) else { return }
        blockMotion?.estimate(previousID: previous.id, nextID: next.id, commandBuffer: commandBuffer)
        let provider = visionFlowProvider
        commandBuffer.addCompletedHandler { _ in
            provider.submit(previous: previous, next: next)
        }
    }

    /// Builds the frame at `t` between two buffered captures.
    /// `.failed` means the caller should linearly blend instead.
    func attemptInterpolation(
        commandBuffer: MTLCommandBuffer,
        previous: GenerationFrame,
        next: GenerationFrame,
        t: Float,
        shotStartID: UInt64 = 0,
        artifactGuard: ArtifactGuard = .balanced
    ) -> FrameInterpolationAttempt {
        guard let interpolatePipeline else {
            return .failed("compute pipeline missing")
        }
        guard previous.texture.width == next.texture.width,
              previous.texture.height == next.texture.height else {
            return .failed("capture size changed between frames")
        }

        let flow: VisionFlowProvider.FlowResult
        let borrowed: Bool
        if let exact = visionFlowProvider.flow(previousID: previous.id, nextID: next.id) {
            flow = exact
            borrowed = false
        } else if let nearest = visionFlowProvider.nearestFlow(to: next.id),
                  distance(nearest.nextID, next.id) <= maxBorrowDistance,
                  nearest.previousID >= shotStartID {
            // Motion from before a cut says nothing about the shot after it.
            flow = nearest
            borrowed = true
        } else {
            return .failed("no optical flow for this pair yet")
        }

        let width = next.texture.width
        let height = next.texture.height
        guard let output = ensureOutputTexture(width: width, height: height, pixelFormat: next.texture.pixelFormat) else {
            return .failed("could not encode interpolation")
        }

        if !borrowed,
           let blockMotion,
           let blockInterpolatePipeline,
           let gated = blockMotion.gatedFields(
               previousID: previous.id,
               nextID: next.id,
               visionForward: flow.forward,
               visionBackward: flow.backward,
               visionGain: flow.gain,
               commandBuffer: commandBuffer
           ) {
            // The pair before, for the artifact guard's carry-over; this pair when it has none.
            let before = blockMotion.builtGatedFields(endingAt: previous.id) ?? gated
            // Each pixel's motion (Vision's, or a block vector where blocks move on their own),
            // carried to this moment: which capture sees each spot, and how it moved.
            var motion: MTLTexture?
            if let splatter {
                let fused = splatter.fusedFlow(
                    pair: (previous.id, next.id),
                    prev: previous.texture,
                    next: next.texture,
                    visionForward: flow.forward,
                    visionBackward: flow.backward,
                    gain: flow.gain,
                    gated: gated,
                    captureWidth: width,
                    commandBuffer: commandBuffer
                )
                motion = splatter.motionAtT(
                    prev: previous.texture,
                    next: next.texture,
                    forward: fused?.forward ?? flow.forward,
                    backward: fused?.backward ?? flow.backward,
                    gain: fused == nil ? flow.gain : 1,
                    t: t,
                    calm: artifactGuard.calmRange,
                    difficulty: gated.difficulty,
                    difficultyScale: gated.difficultyScale,
                    previousDifficulty: before.difficulty,
                    previousDifficultyScale: before.difficultyScale,
                    commandBuffer: commandBuffer
                )
            }
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
                return .failed("could not encode interpolation")
            }
            var params = BlockInterpolateParams(
                t: t,
                visionGain: flow.gain,
                blockToCapture: blockMotion.blockToCapture(captureWidth: width),
                matchLimit: 0.10,
                calmFrom: artifactGuard.calmRange?.from ?? 0,
                calmFull: artifactGuard.calmRange?.full ?? 0,
                difficultyScale: gated.difficultyScale,
                previousDifficultyScale: before.difficultyScale,
                splatOn: motion == nil ? 0 : 1
            )
            encoder.setComputePipelineState(blockInterpolatePipeline)
            encoder.setTexture(previous.texture, index: 0)
            encoder.setTexture(next.texture, index: 1)
            encoder.setTexture(flow.forward, index: 2)
            encoder.setTexture(flow.backward, index: 3)
            encoder.setTexture(output, index: 4)
            encoder.setTexture(gated.forward, index: 5)
            encoder.setTexture(gated.backward, index: 6)
            encoder.setTexture(gated.mask, index: 7)
            encoder.setTexture(motion ?? gated.mask, index: 8)
            encoder.setBytes(&params, length: MemoryLayout<BlockInterpolateParams>.stride, index: 0)
            encoder.setBuffer(gated.difficulty, offset: 0, index: 1)
            encoder.setBuffer(before.difficulty, offset: 0, index: 2)
            let threadWidth = blockInterpolatePipeline.threadExecutionWidth
            let threadHeight = max(1, blockInterpolatePipeline.maxTotalThreadsPerThreadgroup / threadWidth)
            encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1)
            )
            encoder.endEncoding()
            commandBuffer.addCompletedHandler { _ in
                withExtendedLifetime(flow) {}
            }
            return .produced(
                texture: output,
                flowWidth: flow.forward.width,
                flowHeight: flow.forward.height,
                flowFrameID: flow.nextID,
                latestCaptureID: next.id
            )
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return .failed("could not encode interpolation")
        }

        var params = FlowInterpolateParams(
            t: t,
            flowGain: flow.gain,
            consistency: consistency,
            colorTolerance: borrowed ? borrowedFlowColorTolerance : 0
        )
        encoder.setComputePipelineState(interpolatePipeline)
        encoder.setTexture(previous.texture, index: 0)
        encoder.setTexture(next.texture, index: 1)
        encoder.setTexture(flow.forward, index: 2)
        encoder.setTexture(flow.backward, index: 3)
        encoder.setTexture(output, index: 4)
        encoder.setBytes(&params, length: MemoryLayout<FlowInterpolateParams>.stride, index: 0)
        let threadWidth = interpolatePipeline.threadExecutionWidth
        let threadHeight = max(1, interpolatePipeline.maxTotalThreadsPerThreadgroup / threadWidth)
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        )
        encoder.endEncoding()

        // Keep the flow buffers alive until the GPU has read them.
        commandBuffer.addCompletedHandler { _ in
            withExtendedLifetime(flow) {}
        }

        return .produced(
            texture: output,
            flowWidth: flow.forward.width,
            flowHeight: flow.forward.height,
            flowFrameID: flow.nextID,
            latestCaptureID: next.id
        )
    }

    func reset() {
        visionFlowProvider.reset()
        blockMotion?.reset()
        outputTexture = nil
    }

    // MARK: - Private

    private func ensureOutputTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        if let outputTexture,
           outputTexture.width == width,
           outputTexture.height == height,
           outputTexture.pixelFormat == pixelFormat {
            return outputTexture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        outputTexture = device.makeTexture(descriptor: descriptor)
        return outputTexture
    }

    private func distance(_ a: UInt64, _ b: UInt64) -> UInt64 {
        a > b ? a - b : b - a
    }
}
