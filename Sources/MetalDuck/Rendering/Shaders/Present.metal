#include <metal_stdlib>
using namespace metal;

struct PresentUniforms {
    float2 contentScale;
    float2 texelSize;
    float sharpness;
    float blendFactor;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vertexFullscreen(uint vertexID [[vertex_id]], constant PresentUniforms &uniforms [[buffer(0)]]) {
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

    float2 position = positions[vertexID];
    position *= uniforms.contentScale;

    out.position = float4(position, 0.0, 1.0);
    out.uv = uvs[vertexID];

    return out;
}

fragment float4 fragmentPresent(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTextureA [[texture(0)]],
    texture2d<float> sourceTextureB [[texture(1)]],
    sampler sourceSampler [[sampler(0)]],
    constant PresentUniforms &uniforms [[buffer(0)]]
) {
    float2 uv = saturate(in.uv);

    float blendFactor = saturate(uniforms.blendFactor);
    float3 centerA = sourceTextureA.sample(sourceSampler, uv).rgb;
    float3 centerB = sourceTextureB.sample(sourceSampler, uv).rgb;
    float3 center = mix(centerA, centerB, blendFactor);

    if (uniforms.sharpness <= 0.001) {
        return float4(center, 1.0);
    }

    float2 tx = uniforms.texelSize;

    float3 northA = sourceTextureA.sample(sourceSampler, saturate(uv + float2(0.0, -tx.y))).rgb;
    float3 southA = sourceTextureA.sample(sourceSampler, saturate(uv + float2(0.0, tx.y))).rgb;
    float3 eastA = sourceTextureA.sample(sourceSampler, saturate(uv + float2(tx.x, 0.0))).rgb;
    float3 westA = sourceTextureA.sample(sourceSampler, saturate(uv + float2(-tx.x, 0.0))).rgb;

    float3 northB = sourceTextureB.sample(sourceSampler, saturate(uv + float2(0.0, -tx.y))).rgb;
    float3 southB = sourceTextureB.sample(sourceSampler, saturate(uv + float2(0.0, tx.y))).rgb;
    float3 eastB = sourceTextureB.sample(sourceSampler, saturate(uv + float2(tx.x, 0.0))).rgb;
    float3 westB = sourceTextureB.sample(sourceSampler, saturate(uv + float2(-tx.x, 0.0))).rgb;

    float3 north = mix(northA, northB, blendFactor);
    float3 south = mix(southA, southB, blendFactor);
    float3 east = mix(eastA, eastB, blendFactor);
    float3 west = mix(westA, westB, blendFactor);

    float3 neighbors = (north + south + east + west) * 0.25;
    float amount = uniforms.sharpness * 1.35;

    float3 sharpened = center + (center - neighbors) * amount;
    float3 color = clamp(sharpened, float3(0.0), float3(1.0));
    return float4(color, 1.0);
}

// =============================================================================
// Frame Generation GPU Kernels (ported from MetalGoose)
// =============================================================================

struct FlowWarpParams {
    float scale;
};

struct FlowComposeParams {
    float t;
    float errorThreshold;
    float flowThreshold;
};

struct FlowOcclusionParams {
    float threshold;
};

/// Warps a texture along optical flow vectors scaled by `params.scale`.
kernel void flowWarp(
    texture2d<half, access::sample> input [[texture(0)]],
    texture2d<half, access::sample> flowTex [[texture(1)]],
    texture2d<half, access::write> output [[texture(2)]],
    constant FlowWarpParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = output.get_width();
    uint height = output.get_height();
    if (gid.x >= width || gid.y >= height) return;
    float2 size = float2(output.get_width(), output.get_height());
    float2 uv = (float2(gid) + 0.5f) / size;
    
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    
    // Sample flow (using UV ensures full-screen coverage from low-res flow texture)
    half2 flow = flowTex.sample(s, uv).rg * 2.0h;
    
    // Calculate UV-space offset
    float2 flowSize = float2(flowTex.get_width(), flowTex.get_height());
    float2 offset = float2(flow) * params.scale / flowSize;
    float2 sampleUV = clamp(uv - offset, float2(0.0f), float2(1.0f));
    
    half4 color = input.sample(s, sampleUV);
    output.write(color, gid);
}

/// Detects occluded regions via forward+backward flow consistency check.
/// Outputs raw error magnitude in R channel.
kernel void flowOcclusion(
    texture2d<half, access::sample> flowForward [[texture(0)]],
    texture2d<half, access::sample> flowBackward [[texture(1)]],
    texture2d<half, access::write> occlusion [[texture(2)]],
    constant FlowOcclusionParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = occlusion.get_width();
    uint height = occlusion.get_height();
    if (gid.x >= width || gid.y >= height) return;

    float2 size = float2(width, height);
    float2 uv = (float2(gid) + 0.5f) / size;
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    half2 f = flowForward.sample(s, uv).rg * 2.0h; 

    // Check flow consistency: F(p) + B(p + F(p)) should be close to 0
    float2 flowSize = float2(flowForward.get_width(), flowForward.get_height());
    float2 uvNext = clamp(uv + float2(f) / flowSize, float2(0.0f), float2(1.0f));
    half2 b = flowBackward.sample(s, uvNext).rg * 2.0h; 

    // Output raw error magnitude
    float2 sum = float2(f + b);
    half err = half(length(sum));

    occlusion.write(half4(err, 0.0h, 0.0h, 0.0h), gid);
}

/// Composes the final interpolated frame from warped prev/next frames
/// using confidence-weighted blending based on flow and color errors.
kernel void flowCompose(
    texture2d<half, access::read> warpPrev [[texture(0)]],
    texture2d<half, access::read> warpNext [[texture(1)]],
    texture2d<half, access::sample> occlusion [[texture(2)]],
    texture2d<half, access::read> origPrev [[texture(3)]],
    texture2d<half, access::read> origNext [[texture(4)]],
    texture2d<half, access::write> output [[texture(5)]],
    constant FlowComposeParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = output.get_width();
    uint height = output.get_height();
    if (gid.x >= width || gid.y >= height) return;

    half4 wA = warpPrev.read(gid);
    half4 wB = warpNext.read(gid);
    float2 size = float2(width, height);
    float2 uv = (float2(gid) + 0.5f) / size;
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    half t = half(params.t);

    // Confidence check
    half flowErr = occlusion.sample(s, uv).r;
    half colorErr = length(wA.rgb - wB.rgb);

    // Soft confidence mask - significantly loosened for Anime/Large Displacement
    // Allow much larger flow errors before falling back
    half flowConf = 1.0h - smoothstep(half(params.flowThreshold) * 2.0h, half(params.flowThreshold) * 10.0h, flowErr);
    // Allow massive color divergence (typical of fast anime characters)
    half colorConf = 1.0h - smoothstep(0.8h, 1.2h, colorErr);
    half confidence = min(flowConf, colorConf);

    // Final composition
    half4 oA = origPrev.read(gid);
    half4 oB = origNext.read(gid);
    half4 fallback = mix(oA, oB, t);
    
    half4 interpolated = mix(wA, wB, t);
    half4 finalColor = mix(fallback, interpolated, confidence);
    
    // DEBUG: Add a very subtle green tint to generated frames 
    // This confirms they are actually being shown to the user.
    // finalColor.g += 0.05h; 
    
    output.write(finalColor, gid);
}
