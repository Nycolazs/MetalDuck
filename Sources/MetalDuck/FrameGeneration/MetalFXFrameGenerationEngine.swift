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
}

private struct InterpolationUniforms {
    var blendFactor: Float
    var invOutputSize: SIMD2<Float>
    var globalMotionUV: SIMD2<Float>
    var flowInfluence: Float
}

private struct FlowUniforms {
    var imageSize: SIMD2<UInt32>
    var flowSize: SIMD2<UInt32>
    var blockSize: UInt32
    var searchRadius: UInt32
    var sampleStep: UInt32
    var searchStep: UInt32
}

final class MetalFXFrameGenerationEngine {
    private static let flowBlockSize: Int = 8

    private let device: MTLDevice
    private let interpolationPipelineState: MTLRenderPipelineState?
    private let flowPipelineState: MTLComputePipelineState?
    private let colorSampler: MTLSamplerState?
    private let flowSampler: MTLSamplerState?

    private var outputTexture: MTLTexture?
    private var flowTexture: MTLTexture?

    init(device: MTLDevice) {
        self.device = device
        let resources = Self.buildResources(device: device)
        self.interpolationPipelineState = resources.interpolationPipelineState
        self.flowPipelineState = resources.flowPipelineState
        self.colorSampler = resources.colorSampler
        self.flowSampler = resources.flowSampler
    }

    var isSupported: Bool {
        interpolationPipelineState != nil &&
            flowPipelineState != nil &&
            colorSampler != nil &&
            flowSampler != nil
    }

    func interpolate(
        commandBuffer: MTLCommandBuffer,
        previousTexture: MTLTexture,
        currentTexture: MTLTexture,
        auxiliary: FrameGenerationAuxiliary,
        deltaTime: Float
    ) throws -> MTLTexture {
        _ = auxiliary
        let normalizedDelta = max(0.0, min(deltaTime * 60.0, 1.0))
        let blendFactor = max(0.25, min(0.75, normalizedDelta * 0.5))
        return try interpolate(
            commandBuffer: commandBuffer,
            previousTexture: previousTexture,
            currentTexture: currentTexture,
            blendFactor: blendFactor,
            motionHint: .zero
        )
    }

    func interpolate(
        commandBuffer: MTLCommandBuffer,
        previousTexture: MTLTexture,
        currentTexture: MTLTexture,
        blendFactor: Float,
        motionHint: SIMD2<Float> = .zero
    ) throws -> MTLTexture {
        guard isSupported,
              let interpolationPipelineState,
              let flowPipelineState,
              let colorSampler,
              let flowSampler else {
            throw FrameGenerationError.unsupportedDevice
        }

        guard previousTexture.width == currentTexture.width,
              previousTexture.height == currentTexture.height,
              previousTexture.pixelFormat == currentTexture.pixelFormat else {
            throw FrameGenerationError.incompatibleTextures
        }

        guard let outputTexture = ensureOutputTexture(matching: currentTexture) else {
            throw FrameGenerationError.outputTextureCreationFailed
        }
        guard let flowTexture = ensureFlowTexture(matching: currentTexture) else {
            throw FrameGenerationError.flowTextureCreationFailed
        }

        try encodeFlowEstimation(
            commandBuffer: commandBuffer,
            pipelineState: flowPipelineState,
            previousTexture: previousTexture,
            currentTexture: currentTexture,
            flowTexture: flowTexture
        )

        try encodeInterpolation(
            commandBuffer: commandBuffer,
            pipelineState: interpolationPipelineState,
            colorSampler: colorSampler,
            flowSampler: flowSampler,
            previousTexture: previousTexture,
            currentTexture: currentTexture,
            flowTexture: flowTexture,
            outputTexture: outputTexture,
            blendFactor: blendFactor,
            motionHint: motionHint
        )

        return outputTexture
    }

    private func encodeFlowEstimation(
        commandBuffer: MTLCommandBuffer,
        pipelineState: MTLComputePipelineState,
        previousTexture: MTLTexture,
        currentTexture: MTLTexture,
        flowTexture: MTLTexture
    ) throws {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw FrameGenerationError.pipelineCreationFailed
        }

        let pixelCount = previousTexture.width * previousTexture.height
        let searchRadius: UInt32
        let sampleStep: UInt32
        if pixelCount >= (2560 * 1440) {
            searchRadius = 2
            sampleStep = 3
        } else if pixelCount >= (1920 * 1080) {
            searchRadius = 2
            sampleStep = 2
        } else {
            searchRadius = 3
            sampleStep = 2
        }

        let uniforms = FlowUniforms(
            imageSize: SIMD2<UInt32>(
                UInt32(previousTexture.width),
                UInt32(previousTexture.height)
            ),
            flowSize: SIMD2<UInt32>(
                UInt32(flowTexture.width),
                UInt32(flowTexture.height)
            ),
            blockSize: UInt32(Self.flowBlockSize),
            searchRadius: searchRadius,
            sampleStep: sampleStep,
            searchStep: 2
        )

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(previousTexture, index: 0)
        encoder.setTexture(currentTexture, index: 1)
        encoder.setTexture(flowTexture, index: 2)
        var uniformsCopy = uniforms
        encoder.setBytes(&uniformsCopy, length: MemoryLayout<FlowUniforms>.stride, index: 0)

        let w = pipelineState.threadExecutionWidth
        let h = max(1, pipelineState.maxTotalThreadsPerThreadgroup / w)
        let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
        let threadCount = MTLSize(width: flowTexture.width, height: flowTexture.height, depth: 1)
        encoder.dispatchThreads(threadCount, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }

    private func encodeInterpolation(
        commandBuffer: MTLCommandBuffer,
        pipelineState: MTLRenderPipelineState,
        colorSampler: MTLSamplerState,
        flowSampler: MTLSamplerState,
        previousTexture: MTLTexture,
        currentTexture: MTLTexture,
        flowTexture: MTLTexture,
        outputTexture: MTLTexture,
        blendFactor: Float,
        motionHint: SIMD2<Float>
    ) throws {
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = outputTexture
        renderPass.colorAttachments[0].loadAction = .dontCare
        renderPass.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            throw FrameGenerationError.pipelineCreationFailed
        }

        let globalMotionUV = SIMD2<Float>(
            motionHint.x / Float(max(1, currentTexture.width)),
            motionHint.y / Float(max(1, currentTexture.height))
        )

        var uniforms = InterpolationUniforms(
            blendFactor: max(0.0, min(blendFactor, 1.0)),
            invOutputSize: SIMD2<Float>(
                1.0 / Float(max(1, currentTexture.width)),
                1.0 / Float(max(1, currentTexture.height))
            ),
            globalMotionUV: simd_clamp(
                globalMotionUV,
                SIMD2<Float>(repeating: -0.08),
                SIMD2<Float>(repeating: 0.08)
            ),
            flowInfluence: 1.0
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(previousTexture, index: 0)
        encoder.setFragmentTexture(currentTexture, index: 1)
        encoder.setFragmentTexture(flowTexture, index: 2)
        encoder.setFragmentSamplerState(colorSampler, index: 0)
        encoder.setFragmentSamplerState(flowSampler, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<InterpolationUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func ensureOutputTexture(matching texture: MTLTexture) -> MTLTexture? {
        if let outputTexture,
           outputTexture.width == texture.width,
           outputTexture.height == texture.height,
           outputTexture.pixelFormat == texture.pixelFormat {
            return outputTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        outputTexture = device.makeTexture(descriptor: descriptor)
        return outputTexture
    }

    private func ensureFlowTexture(matching texture: MTLTexture) -> MTLTexture? {
        let flowWidth = max(1, (texture.width + (Self.flowBlockSize - 1)) / Self.flowBlockSize)
        let flowHeight = max(1, (texture.height + (Self.flowBlockSize - 1)) / Self.flowBlockSize)

        if let flowTexture,
           flowTexture.width == flowWidth,
           flowTexture.height == flowHeight,
           flowTexture.pixelFormat == .rg16Float {
            return flowTexture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg16Float,
            width: flowWidth,
            height: flowHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private

        flowTexture = device.makeTexture(descriptor: descriptor)
        return flowTexture
    }

    private static func buildResources(device: MTLDevice) -> (
        interpolationPipelineState: MTLRenderPipelineState?,
        flowPipelineState: MTLComputePipelineState?,
        colorSampler: MTLSamplerState?,
        flowSampler: MTLSamplerState?
    ) {
        let source = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct InterpolationUniforms {
    float blendFactor;
    float2 invOutputSize;
    float2 globalMotionUV;
    float flowInfluence;
};

struct FlowUniforms {
    uint2 imageSize;
    uint2 flowSize;
    uint blockSize;
    uint searchRadius;
    uint sampleStep;
    uint searchStep;
};

inline uint2 clampCoord(int2 coord, uint2 size) {
    const int maxX = int(size.x) - 1;
    const int maxY = int(size.y) - 1;
    return uint2(
        uint(clamp(coord.x, 0, maxX)),
        uint(clamp(coord.y, 0, maxY))
    );
}

inline float luminance(float3 color) {
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

kernel void kernelEstimateFlow(
    texture2d<float, access::read> previousTexture [[texture(0)]],
    texture2d<float, access::read> currentTexture [[texture(1)]],
    texture2d<half, access::write> flowTexture [[texture(2)]],
    constant FlowUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uniforms.flowSize.x || gid.y >= uniforms.flowSize.y) {
        return;
    }

    const int2 center = int2(
        int(gid.x * uniforms.blockSize + (uniforms.blockSize / 2)),
        int(gid.y * uniforms.blockSize + (uniforms.blockSize / 2))
    );

    const int radius = int(uniforms.searchRadius);
    const int sampleStep = max(1, int(uniforms.sampleStep));
    const int searchStep = max(1, int(uniforms.searchStep));

    float bestError = 1e20;
    int2 bestOffset = int2(0);

    for (int oy = -radius; oy <= radius; ++oy) {
        for (int ox = -radius; ox <= radius; ++ox) {
            const int2 candidateOffset = int2(ox * searchStep, oy * searchStep);
            float error = 0.0;

            for (int sy = -1; sy <= 1; ++sy) {
                for (int sx = -1; sx <= 1; ++sx) {
                    const int2 sampleOffset = int2(sx * sampleStep, sy * sampleStep);
                    const uint2 prevCoord = clampCoord(center + sampleOffset, uniforms.imageSize);
                    const uint2 currCoord = clampCoord(center + sampleOffset + candidateOffset, uniforms.imageSize);

                    const float prevLuma = luminance(previousTexture.read(prevCoord).rgb);
                    const float currLuma = luminance(currentTexture.read(currCoord).rgb);
                    error += fabs(prevLuma - currLuma);
                }
            }

            if (error < bestError) {
                bestError = error;
                bestOffset = candidateOffset;
            }
        }
    }

    flowTexture.write(half2(float2(bestOffset)), gid);
}

vertex VertexOut vertexFullscreen(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };

    constexpr float2 uvs[3] = {
        float2(0.0, 1.0),
        float2(2.0, 1.0),
        float2(0.0, -1.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

fragment float4 fragmentInterpolate(
    VertexOut in [[stage_in]],
    texture2d<float> previousTexture [[texture(0)]],
    texture2d<float> currentTexture [[texture(1)]],
    texture2d<half> flowTexture [[texture(2)]],
    sampler colorSampler [[sampler(0)]],
    sampler flowSampler [[sampler(1)]],
    constant InterpolationUniforms &uniforms [[buffer(0)]]
) {
    const float2 uv = saturate(in.uv);
    const float blend = saturate(uniforms.blendFactor);

    const float2 flowPixels = float2(flowTexture.sample(flowSampler, uv));
    const float2 flowUV = (flowPixels * uniforms.invOutputSize * uniforms.flowInfluence) + uniforms.globalMotionUV;

    const float2 prevUV = saturate(uv - (flowUV * blend));
    const float2 currUV = saturate(uv + (flowUV * (1.0 - blend)));

    const float3 prevWarped = previousTexture.sample(colorSampler, prevUV).rgb;
    const float3 currWarped = currentTexture.sample(colorSampler, currUV).rgb;
    const float3 warped = mix(prevWarped, currWarped, blend);

    const float3 prevCenter = previousTexture.sample(colorSampler, uv).rgb;
    const float3 currCenter = currentTexture.sample(colorSampler, uv).rgb;
    const float3 fallback = mix(prevCenter, currCenter, blend);

    const float warpMismatch = length(prevWarped - currWarped);
    const float fallbackWeight = clamp(warpMismatch * 2.25, 0.0, 1.0) * 0.45;
    const float3 color = mix(warped, fallback, fallbackWeight);

    return float4(color, 1.0);
}
"""

        guard let library = try? device.makeLibrary(source: source, options: nil),
              let vertex = library.makeFunction(name: "vertexFullscreen"),
              let fragment = library.makeFunction(name: "fragmentInterpolate"),
              let flowKernel = library.makeFunction(name: "kernelEstimateFlow") else {
            return (nil, nil, nil, nil)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let interpolationPipelineState = try? device.makeRenderPipelineState(descriptor: descriptor),
              let flowPipelineState = try? device.makeComputePipelineState(function: flowKernel) else {
            return (nil, nil, nil, nil)
        }

        let colorSamplerDescriptor = MTLSamplerDescriptor()
        colorSamplerDescriptor.minFilter = .linear
        colorSamplerDescriptor.magFilter = .linear
        colorSamplerDescriptor.mipFilter = .notMipmapped
        colorSamplerDescriptor.sAddressMode = .clampToEdge
        colorSamplerDescriptor.tAddressMode = .clampToEdge

        let flowSamplerDescriptor = MTLSamplerDescriptor()
        flowSamplerDescriptor.minFilter = .linear
        flowSamplerDescriptor.magFilter = .linear
        flowSamplerDescriptor.mipFilter = .notMipmapped
        flowSamplerDescriptor.sAddressMode = .clampToEdge
        flowSamplerDescriptor.tAddressMode = .clampToEdge

        guard let colorSampler = device.makeSamplerState(descriptor: colorSamplerDescriptor),
              let flowSampler = device.makeSamplerState(descriptor: flowSamplerDescriptor) else {
            return (nil, nil, nil, nil)
        }

        return (interpolationPipelineState, flowPipelineState, colorSampler, flowSampler)
    }
}
