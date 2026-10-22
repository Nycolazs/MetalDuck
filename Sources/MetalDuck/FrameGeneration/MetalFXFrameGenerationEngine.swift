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

/// Builds in-between frames by warping two captures along Vision optical flow.
final class MetalFXFrameGenerationEngine {
    private let device: MTLDevice
    private let interpolatePipeline: MTLComputePipelineState?
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
            return
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
        t: Float
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
                  distance(nearest.nextID, next.id) <= maxBorrowDistance {
            flow = nearest
            borrowed = true
        } else {
            return .failed("no optical flow for this pair yet")
        }

        let width = next.texture.width
        let height = next.texture.height
        guard let output = ensureOutputTexture(width: width, height: height, pixelFormat: next.texture.pixelFormat),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
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
