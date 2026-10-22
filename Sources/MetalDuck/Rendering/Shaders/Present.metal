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
// Frame interpolation
// =============================================================================

struct FlowInterpolateParams {
    float t;
    float flowGain;
    float consistency;
    float colorTolerance;
};

/// Builds the frame at time `t` between `prev` and `next`.
/// `forward` carries prev → next motion and `backward` next → prev, in flow-texture pixels
/// after `flowGain`. A side is trusted only where its vector survives a round trip through the
/// other field, so at the edge of a moving object the side that can still see the pixel wins.
/// `colorTolerance` above zero also rejects warps whose two sides disagree in colour, which is
/// how flow borrowed from a neighbouring pair of captures is kept honest.
kernel void flowInterpolate(
    texture2d<half, access::sample> prev [[texture(0)]],
    texture2d<half, access::sample> next [[texture(1)]],
    texture2d<half, access::sample> forward [[texture(2)]],
    texture2d<half, access::sample> backward [[texture(3)]],
    texture2d<half, access::write> output [[texture(4)]],
    constant FlowInterpolateParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = output.get_width();
    uint height = output.get_height();
    if (gid.x >= width || gid.y >= height) return;

    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = (float2(gid) + 0.5f) / float2(width, height);
    float2 flowSize = float2(forward.get_width(), forward.get_height());
    float t = params.t;

    float2 f = float2(forward.sample(s, uv).rg) * params.flowGain;
    float2 b = float2(backward.sample(s, uv).rg) * params.flowGain;

    float2 uvA = uv - f * t / flowSize;
    float2 uvB = uv - b * (1.0f - t) / flowSize;

    float2 fA = float2(forward.sample(s, uvA).rg) * params.flowGain;
    float2 bA = float2(backward.sample(s, uvA + fA / flowSize).rg) * params.flowGain;
    float2 bB = float2(backward.sample(s, uvB).rg) * params.flowGain;
    float2 fB = float2(forward.sample(s, uvB + bB / flowSize).rg) * params.flowGain;

    // Large motion is allowed a proportionally larger round-trip error.
    float toleranceA = params.consistency + 0.08f * length(fA);
    float toleranceB = params.consistency + 0.08f * length(bB);
    float confA = 1.0f - smoothstep(toleranceA, toleranceA * 4.0f, length(fA + bA));
    float confB = 1.0f - smoothstep(toleranceB, toleranceB * 4.0f, length(bB + fB));

    half4 cA = prev.sample(s, clamp(uvA, 0.0f, 1.0f));
    half4 cB = next.sample(s, clamp(uvB, 0.0f, 1.0f));

    float weightA = (1.0f - t) * confA;
    float weightB = t * confB;
    float weightSum = weightA + weightB;
    half4 warped = weightSum > 1e-4f
        ? half4((float4(cA) * weightA + float4(cB) * weightB) / weightSum)
        : mix(cA, cB, half(t));

    float reliability = max(confA, confB);
    if (params.colorTolerance > 0.0f) {
        // Compare small neighbourhoods, not single texels, so the decision is the same across
        // a whole badly tracked object instead of flickering between warp and blend.
        constexpr float2 taps[5] = { float2(0, 0), float2(2, 0), float2(-2, 0), float2(0, 2), float2(0, -2) };
        float colorError = 0.0f;
        for (int i = 0; i < 5; i++) {
            float2 d = taps[i] / flowSize;
            colorError += length(float3(prev.sample(s, uvA + d).rgb - next.sample(s, uvB + d).rgb));
        }
        colorError *= 0.2f;
        reliability *= 1.0f - smoothstep(params.colorTolerance, params.colorTolerance * 3.0f, colorError);
    }

    half4 blended = mix(prev.sample(s, uv), next.sample(s, uv), half(t));
    output.write(mix(blended, warped, half(reliability)), gid);
}
