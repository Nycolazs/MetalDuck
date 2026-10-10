import Foundation
import Metal
import simd

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
    case shaderCompilationFailed
    case functionLookupFailed
    case pipelineCreationFailed
    case outputTextureCreationFailed
    case flowTextureCreationFailed
    case unsupportedDevice
    case incompatibleTextures
    case missingFlow
}

// MARK: - Shader param structs (must match Present.metal)

private struct FlowWarpParams {
    var scale: Float
}

private struct FlowComposeParams {
    var t: Float
    var errorThreshold: Float
    var flowThreshold: Float
}

private struct FlowOcclusionParams {
    var threshold: Float
}

// MARK: - Frame Generation Engine

/// Core engine for generating interpolated frames using motion-compensated warping.
/// Orchestrates occlusion detection, flow warping, and frame composition shaders.
final class MetalFXFrameGenerationEngine {
    private let device: MTLDevice

    // GPU pipelines for frame generation
    private let flowWarpPipeline: MTLComputePipelineState?
    private let flowOcclusionPipeline: MTLComputePipelineState?
    private let flowComposePipeline: MTLComputePipelineState?

    // Scratch textures for interpolation
    private var occlusionTexture: MTLTexture?
    private var warpedPrevTexture: MTLTexture?
    private var warpedNextTexture: MTLTexture?
    private var preGeneratedFrame: MTLTexture?

    private let flowOcclusionThreshold: Float = 1.5

    // Vision flow provider (async, runs on ANE)
    let visionFlowProvider: VisionFlowProvider
    private var flowFrameCounter: UInt64 = 0

    // Track the previous frame for flow & interpolation
    private var previousFrameTexture: MTLTexture?
    private var hasPendingInterpolatedFrame = false

    init(device: MTLDevice, commandQueue: MTLCommandQueue, library: MTLLibrary?) {
        self.device = device
        self.visionFlowProvider = VisionFlowProvider(device: device, commandQueue: commandQueue)

        // Load compute pipelines from the provided library
        guard let library = library else {
            NSLog("MetalFXFrameGenerationEngine: No MTLLibrary provided — frame generation DISABLED")
            self.flowWarpPipeline = nil
            self.flowOcclusionPipeline = nil
            self.flowComposePipeline = nil
            return
        }

        func makeCompute(_ name: String) -> MTLComputePipelineState? {
            guard let function = library.makeFunction(name: name) else {
                NSLog("MetalFXFrameGenerationEngine: Failed to find function '%@'", name)
                return nil
            }
            do {
                let pipeline = try device.makeComputePipelineState(function: function)
                NSLog("MetalFXFrameGenerationEngine: Loaded compute pipeline '%@'", name)
                return pipeline
            } catch {
                NSLog("MetalFXFrameGenerationEngine: Failed to create pipeline for '%@': %@", name, error.localizedDescription)
                return nil
            }
        }

        self.flowWarpPipeline = makeCompute("flowWarp")
        self.flowOcclusionPipeline = makeCompute("flowOcclusion")
        self.flowComposePipeline = makeCompute("flowCompose")
        
        NSLog("MetalFXFrameGenerationEngine: isSupported = %d", isSupported ? 1 : 0)
    }

    var isSupported: Bool {
        flowWarpPipeline != nil &&
        flowOcclusionPipeline != nil &&
        flowComposePipeline != nil
    }

    /// Called when a new captured frame is available.
    /// Submits flow request and stores for interpolation.
    func onNewCapturedFrame(_ texture: MTLTexture) {
        if let prev = previousFrameTexture,
           prev.width == texture.width,
           prev.height == texture.height {
            flowFrameCounter += 1
            NSLog("FrameGenEngine: Submitting flow request #%llu (%dx%d)", flowFrameCounter, texture.width, texture.height)
            visionFlowProvider.submitFlowRequest(
                prev: prev, next: texture, frameID: flowFrameCounter
            )
        } else {
            NSLog("FrameGenEngine: onNewCapturedFrame skipped (no previous or size mismatch)")
        }
        previousFrameTexture = texture
        hasPendingInterpolatedFrame = true
    }

    /// Try to generate an interpolated frame between last two captured frames.
    /// Returns the interpolated texture if successful, or nil (caller should use shader blend as fallback).
    func generateInterpolatedFrame(
        commandBuffer: MTLCommandBuffer,
        prevTexture: MTLTexture,
        currentTexture: MTLTexture,
        blendFactor: Float
    ) -> MTLTexture? {
        guard isSupported else {
            NSLog("FrameGenEngine: NOT SUPPORTED (pipeline creation failed)")
            return nil
        }
        guard prevTexture.width == currentTexture.width,
              prevTexture.height == currentTexture.height else {
            NSLog("FrameGenEngine: Size mismatch prev=%dx%d cur=%dx%d",
                  prevTexture.width, prevTexture.height, currentTexture.width, currentTexture.height)
            return nil
        }

        // Use the latest available Vision flow (may be from previous pair — temporal coherence)
        guard let flowResult = visionFlowProvider.latestFlow() else {
            // Only log occasionally to avoid spam
            return nil  // No flow available yet, caller uses shader blend fallback
        }

        let flowFwd = flowResult.forward
        let flowBwd = flowResult.backward

        // Flow textures must match frame dimensions for warp to work correctly
        // Vision may return different resolution flow — that's OK, we can still use it
        // The shader samples using UV coords so resolution mismatch is handled
        NSLog("FrameGenEngine: Using VISION FLOW (fwd=%dx%d frame=%dx%d blend=%.2f)",
              flowFwd.width, flowFwd.height, prevTexture.width, prevTexture.height, blendFactor)

        return interpolateWithFlow(
            prev: prevTexture, next: currentTexture,
            flowForward: flowFwd, flowBackward: flowBwd,
            t: blendFactor, commandBuffer: commandBuffer
        )
    }

    func reset() {
        visionFlowProvider.reset()
        flowFrameCounter = 0
        previousFrameTexture = nil
        hasPendingInterpolatedFrame = false
        occlusionTexture = nil
        warpedPrevTexture = nil
        warpedNextTexture = nil
        preGeneratedFrame = nil
    }

    // MARK: - Private

    private func interpolateWithFlow(
        prev: MTLTexture, next: MTLTexture,
        flowForward: MTLTexture, flowBackward: MTLTexture,
        t: Float, commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let flowWarpPipeline,
              let flowOcclusionPipeline,
              let flowComposePipeline else { return nil }

        let w = prev.width
        let h = prev.height

        guard let occlusion = ensureTexture(&occlusionTexture, width: w, height: h, pixelFormat: .r16Float),
              let warpPrev = ensureTexture(&warpedPrevTexture, width: w, height: h),
              let warpNext = ensureTexture(&warpedNextTexture, width: w, height: h),
              let output = ensureTexture(&preGeneratedFrame, width: w, height: h) else { return nil }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }

        // 1. Occlusion detection
        var occParams = FlowOcclusionParams(threshold: flowOcclusionThreshold)
        encoder.setComputePipelineState(flowOcclusionPipeline)
        encoder.setTexture(flowForward, index: 0)
        encoder.setTexture(flowBackward, index: 1)
        encoder.setTexture(occlusion, index: 2)
        encoder.setBytes(&occParams, length: MemoryLayout<FlowOcclusionParams>.size, index: 0)
        dispatchThreads(pipeline: flowOcclusionPipeline, encoder: encoder, width: w, height: h)

        // 2. Warp prev frame forward by t
        var warpPrevParams = FlowWarpParams(scale: t)
        encoder.setComputePipelineState(flowWarpPipeline)
        encoder.setTexture(prev, index: 0)
        encoder.setTexture(flowForward, index: 1)
        encoder.setTexture(warpPrev, index: 2)
        encoder.setBytes(&warpPrevParams, length: MemoryLayout<FlowWarpParams>.size, index: 0)
        dispatchThreads(pipeline: flowWarpPipeline, encoder: encoder, width: w, height: h)

        // 3. Warp next frame backward by (1-t)
        var warpNextParams = FlowWarpParams(scale: (1.0 - t))
        encoder.setComputePipelineState(flowWarpPipeline)
        encoder.setTexture(next, index: 0)
        encoder.setTexture(flowBackward, index: 1)
        encoder.setTexture(warpNext, index: 2)
        encoder.setBytes(&warpNextParams, length: MemoryLayout<FlowWarpParams>.size, index: 0)
        dispatchThreads(pipeline: flowWarpPipeline, encoder: encoder, width: w, height: h)

        // 4. Compose final interpolated frame
        var composeParams = FlowComposeParams(
            t: t,
            errorThreshold: 0.1,
            flowThreshold: flowOcclusionThreshold
        )
        encoder.setComputePipelineState(flowComposePipeline)
        encoder.setTexture(warpPrev, index: 0)
        encoder.setTexture(warpNext, index: 1)
        encoder.setTexture(occlusion, index: 2)
        encoder.setTexture(prev, index: 3)
        encoder.setTexture(next, index: 4)
        encoder.setTexture(output, index: 5)
        encoder.setBytes(&composeParams, length: MemoryLayout<FlowComposeParams>.size, index: 0)
        dispatchThreads(pipeline: flowComposePipeline, encoder: encoder, width: w, height: h)

        encoder.endEncoding()
        return output
    }

    private func ensureTexture(_ texture: inout MTLTexture?, width: Int, height: Int,
                                pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
        if let tex = texture,
           tex.width == width,
           tex.height == height,
           tex.pixelFormat == pixelFormat {
            return tex
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        texture = device.makeTexture(descriptor: desc)
        return texture
    }

    private func dispatchThreads(pipeline: MTLComputePipelineState,
                                 encoder: MTLComputeCommandEncoder,
                                 width: Int, height: Int) {
        let threadW = pipeline.threadExecutionWidth
        let threadH = pipeline.maxTotalThreadsPerThreadgroup / threadW
        let threadsPerGroup = MTLSize(width: threadW, height: threadH, depth: 1)
        let grid = MTLSize(width: (width + threadW - 1) / threadW,
                           height: (height + threadH - 1) / threadH,
                           depth: 1)
        encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: threadsPerGroup)
    }
}
