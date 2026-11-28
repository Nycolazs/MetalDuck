#include <metal_stdlib>
using namespace metal;

struct PresentUniforms {
    float2 contentScale;
    float2 texelSize;
    float sharpness;
    float blendFactor;
    // The part of the picture to show, as a share of it.
    float2 uvOrigin;
    float2 uvSize;
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
    // Past the picture's edge: the bars of a picture fitted into a differently shaped
    // output. Without this the edge pixels would smear across them.
    if (in.uv.x < 0.0 || in.uv.x > 1.0 || in.uv.y < 0.0 || in.uv.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    float2 uv = uniforms.uvOrigin + saturate(in.uv) * uniforms.uvSize;

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

// =============================================================================
// Block motion: large and independent motion
// =============================================================================
//
// Vision's optical flow follows camera motion well but barely sees an object moving across a
// still background: a 120 px move came back as 4 px. The shader then trusted that near-zero
// motion and mixed the two captures in place, which is the see-through double image on fast
// objects. A block search finds those moves (up to about 320 px between captures), and
// flowInterpolateBlocks uses it where Vision disagrees with a moving block.

// Luma at 1/4 size: the average of each 4x4 block of the capture.
kernel void blockLumaQuarter(
    texture2d<half, access::read> source [[texture(0)]],
    texture2d<float, access::write> luma [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= luma.get_width() || gid.y >= luma.get_height()) return;
    uint2 maxPixel = uint2(source.get_width() - 1, source.get_height() - 1);
    float sum = 0.0f;
    for (uint y = 0; y < 4; y++) {
        for (uint x = 0; x < 4; x++) {
            half4 c = source.read(min(gid * 4 + uint2(x, y), maxPixel));
            sum += dot(float3(c.rgb), float3(0.299f, 0.587f, 0.114f));
        }
    }
    luma.write(float4(sum / 16.0f), gid);
}

// Half that size again: 2x2 average.
kernel void blockLumaHalf(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> luma [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= luma.get_width() || gid.y >= luma.get_height()) return;
    uint2 maxPixel = uint2(source.get_width() - 1, source.get_height() - 1);
    float sum = source.read(min(gid * 2, maxPixel)).r + source.read(min(gid * 2 + uint2(1, 0), maxPixel)).r +
        source.read(min(gid * 2 + uint2(0, 1), maxPixel)).r + source.read(min(gid * 2 + uint2(1, 1), maxPixel)).r;
    luma.write(float4(sum * 0.25f), gid);
}

struct BlockSearchParams {
    int blockSize;
    int radius;
    float motionPenalty;   // cost per pixel of motion, so flat areas stay still
    int candidateScale;    // coarse vectors → this level
};

static inline float blockCost(texture2d<float, access::read> a, texture2d<float, access::read> b,
                              int2 origin, int2 offset, int blockSize, int step) {
    int2 maxA = int2(a.get_width() - 1, a.get_height() - 1);
    float sum = 0.0f;
    float count = 0.0f;
    for (int y = 0; y < blockSize; y += step) {
        for (int x = 0; x < blockSize; x += step) {
            int2 p = origin + int2(x, y);
            int2 q = p + offset;
            float pa = a.read(uint2(clamp(p, int2(0), maxA))).r;
            float pb = b.read(uint2(clamp(q, int2(0), maxA))).r;
            float outside = (q.x < 0 || q.y < 0 || q.x > maxA.x || q.y > maxA.y) ? 0.25f : 0.0f;
            sum += abs(pa - pb) + outside;
            count += 1.0f;
        }
    }
    return sum / count;
}

// Full search on the 1/8-size level, one threadgroup per 8x8 block (64x64 capture pixels).
// The block and its whole search window go into threadgroup memory first; the 256 threads
// then split the offsets and reduce to the best. Vectors are in 1/8-size pixels.
#define BLOCK_SEARCH_SIZE 8
#define BLOCK_SEARCH_RADIUS 40
#define BLOCK_SEARCH_WINDOW (BLOCK_SEARCH_SIZE + 2 * BLOCK_SEARCH_RADIUS)
kernel void blockSearchCoarse(
    texture2d<float, access::read> from [[texture(0)]],
    texture2d<float, access::read> to [[texture(1)]],
    texture2d<float, access::write> field [[texture(2)]],
    constant BlockSearchParams& params [[buffer(0)]],
    uint2 group [[threadgroup_position_in_grid]],
    uint index [[thread_index_in_threadgroup]]
) {
    threadgroup half window[BLOCK_SEARCH_WINDOW * BLOCK_SEARCH_WINDOW];
    threadgroup half blockPixels[BLOCK_SEARCH_SIZE * BLOCK_SEARCH_SIZE];
    threadgroup float bestCost[256];
    threadgroup int2 bestOffset[256];
    int2 size = int2(to.get_width(), to.get_height());
    int2 origin = int2(group) * BLOCK_SEARCH_SIZE;
    int2 windowOrigin = origin - BLOCK_SEARCH_RADIUS;
    for (int i = int(index); i < BLOCK_SEARCH_WINDOW * BLOCK_SEARCH_WINDOW; i += 256) {
        int2 p = windowOrigin + int2(i % BLOCK_SEARCH_WINDOW, i / BLOCK_SEARCH_WINDOW);
        bool outside = p.x < 0 || p.y < 0 || p.x >= size.x || p.y >= size.y;
        // Outside the frame: a value no picture has, so it never matches.
        window[i] = outside ? half(-4.0h) : half(to.read(uint2(p)).r);
    }
    for (int i = int(index); i < BLOCK_SEARCH_SIZE * BLOCK_SEARCH_SIZE; i += 256) {
        int2 p = clamp(origin + int2(i % BLOCK_SEARCH_SIZE, i / BLOCK_SEARCH_SIZE), int2(0), size - 1);
        blockPixels[i] = half(from.read(uint2(p)).r);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    const int side = 2 * BLOCK_SEARCH_RADIUS + 1;
    float best = 1e9f;
    int2 bestHere = int2(0);
    for (int i = int(index); i < side * side; i += 256) {
        int2 offset = int2(i % side, i / side);
        float sum = 0.0f;
        for (int y = 0; y < BLOCK_SEARCH_SIZE; y += 2) {
            for (int x = 0; x < BLOCK_SEARCH_SIZE; x += 2) {
                sum += min(abs(float(blockPixels[y * BLOCK_SEARCH_SIZE + x]) -
                               float(window[(offset.y + y) * BLOCK_SEARCH_WINDOW + offset.x + x])), 1.0f);
            }
        }
        int2 motion = offset - BLOCK_SEARCH_RADIUS;
        float cost = sum / 16.0f + params.motionPenalty * (abs(float(motion.x)) + abs(float(motion.y)));
        if (cost < best) { best = cost; bestHere = motion; }
    }
    bestCost[index] = best;
    bestOffset[index] = bestHere;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint stride = 128; stride > 0; stride /= 2) {
        if (index < stride && bestCost[index + stride] < bestCost[index]) {
            bestCost[index] = bestCost[index + stride];
            bestOffset[index] = bestOffset[index + stride];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (index == 0 && group.x < field.get_width() && group.y < field.get_height()) {
        field.write(float4(float2(bestOffset[0]), bestCost[0], 0), group);
    }
}

// Refinement on the 1/4-size level (8x8 blocks, 32x32 capture pixels): the coarse vectors
// around the block, scaled up, and no motion; then a small search around the best, finished
// to a fraction of a pixel with a parabola through the costs either side. Whole 1/4-size
// pixels are 4 capture pixels, and warping both captures that far out of line doubled sharp
// edges. Writes the block's texture (luma standard deviation) into .a: a flat block matches
// any motion.
kernel void blockSearchRefine(
    texture2d<float, access::read> from [[texture(0)]],
    texture2d<float, access::read> to [[texture(1)]],
    texture2d<float, access::read> coarse [[texture(2)]],
    texture2d<float, access::write> field [[texture(3)]],
    constant BlockSearchParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= field.get_width() || gid.y >= field.get_height()) return;
    int2 origin = int2(gid) * params.blockSize;
    int2 coarseMax = int2(coarse.get_width() - 1, coarse.get_height() - 1);
    int2 coarseBlock = int2(gid) / 2;
    float best = 1e9f;
    int2 bestOffset = int2(0);
    for (int cy = -1; cy <= 1; cy++) {
        for (int cx = -1; cx <= 1; cx++) {
            int2 cb = clamp(coarseBlock + int2(cx, cy), int2(0), coarseMax);
            int2 candidate = int2(round(coarse.read(uint2(cb)).rg * float(params.candidateScale)));
            float cost = blockCost(from, to, origin, candidate, params.blockSize, 2) +
                params.motionPenalty * (abs(float(candidate.x)) + abs(float(candidate.y)));
            if (cost < best) { best = cost; bestOffset = candidate; }
        }
    }
    float zeroCost = blockCost(from, to, origin, int2(0), params.blockSize, 2);
    if (zeroCost <= best) { best = zeroCost; bestOffset = int2(0); }
    int2 center = bestOffset;
    for (int dy = -params.radius; dy <= params.radius; dy++) {
        for (int dx = -params.radius; dx <= params.radius; dx++) {
            int2 candidate = center + int2(dx, dy);
            float cost = blockCost(from, to, origin, candidate, params.blockSize, 2) +
                params.motionPenalty * (abs(float(candidate.x)) + abs(float(candidate.y)));
            if (cost < best) { best = cost; bestOffset = candidate; }
        }
    }
    float c0 = blockCost(from, to, origin, bestOffset, params.blockSize, 1);
    float cl = blockCost(from, to, origin, bestOffset + int2(-1, 0), params.blockSize, 1);
    float cr = blockCost(from, to, origin, bestOffset + int2(1, 0), params.blockSize, 1);
    float cu = blockCost(from, to, origin, bestOffset + int2(0, -1), params.blockSize, 1);
    float cd = blockCost(from, to, origin, bestOffset + int2(0, 1), params.blockSize, 1);
    float subX = 0.0f, subY = 0.0f;
    float curveX = cl - 2.0f * c0 + cr;
    float curveY = cu - 2.0f * c0 + cd;
    if (curveX > 1e-5f) subX = clamp(0.5f * (cl - cr) / curveX, -0.5f, 0.5f);
    if (curveY > 1e-5f) subY = clamp(0.5f * (cu - cd) / curveY, -0.5f, 0.5f);
    int2 maxA = int2(from.get_width() - 1, from.get_height() - 1);
    float sum = 0.0f, sumSquares = 0.0f;
    for (int y = 0; y < params.blockSize; y++) {
        for (int x = 0; x < params.blockSize; x++) {
            float l = from.read(uint2(clamp(origin + int2(x, y), int2(0), maxA))).r;
            sum += l;
            sumSquares += l * l;
        }
    }
    float n = float(params.blockSize * params.blockSize);
    float mean = sum / n;
    field.write(float4(float2(bestOffset) + float2(subX, subY), best, sqrt(max(sumSquares / n - mean * mean, 0.0f))), gid);
}

// Round trip: a block's motion counts only if the opposite search, from where the block
// lands, comes back to it. Unreliable blocks keep their vector with texture (.a) zero.
kernel void blockConsistency(
    texture2d<float, access::read> field [[texture(0)]],
    texture2d<float, access::read> opposite [[texture(1)]],
    texture2d<float, access::write> checked [[texture(2)]],
    constant BlockSearchParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= checked.get_width() || gid.y >= checked.get_height()) return;
    float4 v = field.read(gid);
    int2 size = int2(field.get_width(), field.get_height());
    float2 landing = (float2(gid) + 0.5f) + v.rg / float(params.blockSize);
    int2 target = clamp(int2(floor(landing)), int2(0), size - 1);
    float closest = 1e9f;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 back = opposite.read(uint2(clamp(target + int2(x, y), int2(0), size - 1))).rg;
            closest = min(closest, length(back + v.rg));
        }
    }
    bool consistent = closest <= 1.5f + 0.1f * length(v.rg);
    checked.write(float4(v.rg, v.b, consistent ? v.a : 0.0f), gid);
}

// Vector median over 3x3 blocks. Repeated patterns (one letter matched to another) leave
// isolated wrong vectors; an object several blocks wide survives.
kernel void blockMedian(
    texture2d<float, access::read> field [[texture(0)]],
    texture2d<float, access::write> filtered [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= filtered.get_width() || gid.y >= filtered.get_height()) return;
    int2 size = int2(field.get_width(), field.get_height());
    float4 values[9];
    int n = 0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            values[n++] = field.read(uint2(clamp(int2(gid) + int2(x, y), int2(0), size - 1)));
        }
    }
    float bestSum = 1e9f;
    int bestIndex = 4;
    for (int i = 0; i < 9; i++) {
        float sum = 0.0f;
        for (int j = 0; j < 9; j++) sum += length(values[i].rg - values[j].rg);
        if (sum < bestSum) { bestSum = sum; bestIndex = i; }
    }
    float4 center = values[4];
    bool replaced = length(values[bestIndex].rg - center.rg) > 1.5f;
    filtered.write(float4(values[bestIndex].rg, center.b, replaced ? 0.0f : center.a), gid);
}

static inline float blockCostAt(texture2d<float, access::read> a, texture2d<float, access::sample> b,
                                int2 origin, float2 offset, int blockSize) {
    constexpr sampler bs(filter::linear, address::clamp_to_edge);
    int2 maxA = int2(a.get_width() - 1, a.get_height() - 1);
    float2 size = float2(b.get_width(), b.get_height());
    float sum = 0.0f;
    for (int y = 0; y < blockSize; y++) {
        for (int x = 0; x < blockSize; x++) {
            int2 p = origin + int2(x, y);
            float pa = a.read(uint2(clamp(p, int2(0), maxA))).r;
            float2 q = float2(p) + offset + 0.5f;
            float pb = b.sample(bs, q / size).r;
            float outside = (q.x < 0.0f || q.y < 0.0f || q.x > size.x || q.y > size.y) ? 0.25f : 0.0f;
            sum += abs(pa - pb) + outside;
        }
    }
    return sum / float(blockSize * blockSize);
}

// How much of the picture the block motion explains, from the refined field (.b = best match
// cost, .a = block texture). Plain blocks match any motion, so they are counted apart:
// counts[0] = blocks, counts[1] = those whose best match still differs by more than
// `poorCost` in luma (0-1), counts[2] = blocks with detail, counts[3] = of those, unmatched.
kernel void blockMatchStats(
    texture2d<float, access::read> field [[texture(0)]],
    device atomic_uint* counts [[buffer(0)]],
    constant float& poorCost [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= field.get_width() || gid.y >= field.get_height()) return;
    float4 block = field.read(gid);
    bool poor = block.b > poorCost;
    bool detailed = block.a > 0.03f;
    atomic_fetch_add_explicit(&counts[0], 1u, memory_order_relaxed);
    if (poor) atomic_fetch_add_explicit(&counts[1], 1u, memory_order_relaxed);
    if (detailed) {
        atomic_fetch_add_explicit(&counts[2], 1u, memory_order_relaxed);
        if (poor) atomic_fetch_add_explicit(&counts[3], 1u, memory_order_relaxed);
    }
}

// Once Vision's flow is in: a block moves on its own only if Vision's motion matches it
// clearly worse than the block's own vector. Both are scored at their exact, fractional
// positions: rounding Vision's to whole pixels made it look worse than a wrong match on
// sharp text during a pan. Repeated patterns match both about equally, so Vision is kept
// there. Writes 1 or 0 into .a.
kernel void blockVersusVision(
    texture2d<float, access::read> from [[texture(0)]],
    texture2d<float, access::sample> to [[texture(1)]],
    texture2d<float, access::read> field [[texture(2)]],
    texture2d<half, access::sample> visionField [[texture(3)]],
    texture2d<float, access::write> gated [[texture(4)]],
    constant BlockSearchParams& params [[buffer(0)]],
    constant float& visionToBlockPixels [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= gated.get_width() || gid.y >= gated.get_height()) return;
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 v = field.read(gid);
    int2 origin = int2(gid) * params.blockSize;
    float2 centerUV = (float2(origin) + float(params.blockSize) * 0.5f) / float2(from.get_width(), from.get_height());
    float2 vision = float2(visionField.sample(s, centerUV).rg) * visionToBlockPixels;
    float own = blockCostAt(from, to, origin, v.rg, params.blockSize);
    float visions = blockCostAt(from, to, origin, vision, params.blockSize);
    bool independent = v.a > 0.03f && length(v.rg - vision) > 2.0f && visions > own * 1.6f + 0.01f;
    gated.write(float4(v.rg, v.b, independent ? 1.0f : 0.0f), gid);
}

// 1 where this block or one around it moves on its own, forward or backward.
kernel void blockGateMask(
    texture2d<float, access::read> forward [[texture(0)]],
    texture2d<float, access::read> backward [[texture(1)]],
    texture2d<float, access::write> mask [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= mask.get_width() || gid.y >= mask.get_height()) return;
    int2 size = int2(forward.get_width(), forward.get_height());
    float any = 0.0f;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            uint2 b = uint2(clamp(int2(gid) + int2(x, y), int2(0), size - 1));
            any = max(any, max(forward.read(b).a, backward.read(b).a));
        }
    }
    mask.write(float4(any > 0.5f ? 1.0f : 0.0f), gid);
}

// How hard a pair is to build in-betweens for. At 1/4 size on luma, each motion known for
// the area (none, Vision's, the block vectors around, the block motion backwards) is tried at
// the midpoint between the captures and the best fit kept. Where even that fits badly, any
// in-between is a guess, and fast action is where the guesses show: tears and see-through
// copies of what moves. The badly fitting share of the picture is summed into difficulty[0]
// (in 1/1024ths of a pixel), and flowInterpolateBlocks keeps hard pairs closer to the real
// frames. Decided once per pair, so a pair's in-betweens never disagree with each other.
struct PairDifficultyParams {
    float visionToQuarter;   // Vision's flow values → 1/4-size pixels
};

kernel void pairDifficulty(
    texture2d<float, access::sample> prevLuma [[texture(0)]],
    texture2d<float, access::sample> nextLuma [[texture(1)]],
    texture2d<half, access::sample> visionForward [[texture(2)]],
    texture2d<float, access::read> blockForward [[texture(3)]],
    texture2d<float, access::read> blockBackward [[texture(4)]],
    device atomic_uint* difficulty [[buffer(0)]],
    constant PairDifficultyParams& params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= prevLuma.get_width() || gid.y >= prevLuma.get_height()) return;
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 size = float2(prevLuma.get_width(), prevLuma.get_height());
    float2 texel = 1.0f / size;
    float2 uv = (float2(gid) + 0.5f) * texel;
    int2 fieldSize = int2(blockForward.get_width(), blockForward.get_height());
    int2 block = clamp(int2(uv * float2(fieldSize)), int2(0), fieldSize - 1);

    float2 candidates[12];
    int count = 0;
    candidates[count++] = float2(0.0f);
    candidates[count++] = float2(visionForward.sample(s, uv).rg) * params.visionToQuarter;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            candidates[count++] = blockForward.read(uint2(clamp(block + int2(x, y), int2(0), fieldSize - 1))).rg;
        }
    }
    candidates[count++] = -blockBackward.read(uint2(block)).rg;

    float best = 1e9f;
    for (int i = 0; i < count; i++) {
        float2 halfway = candidates[i] * 0.5f * texel;
        float mismatch = 0.0f;
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                float2 d = float2(x, y) * texel;
                mismatch += abs(prevLuma.sample(s, uv - halfway + d).r - nextLuma.sample(s, uv + halfway + d).r);
            }
        }
        best = min(best, mismatch / 9.0f);
    }
    // Mean luma mismatch: noise and compression stay under 0.05; nothing lines up above 0.10.
    float misfit = smoothstep(0.05f, 0.10f, best);
    if (misfit > 0.0f) {
        atomic_fetch_add_explicit(&difficulty[0], uint(misfit * 1024.0f + 0.5f), memory_order_relaxed);
    }
}

// The moment a frame is drawn at, after the artifact guard: a hard pair (see pairDifficulty)
// draws its in-betweens toward the nearer real frame, all of the picture alike, so nothing
// tears or doubles. Part of the pair before carries over, so a scene near the limit does not
// switch between smooth and calmed with every pair.
static inline float calmedTime(float t, float calmFrom, float calmFull, float difficultyScale,
                               float previousDifficultyScale, device const uint* difficulty,
                               device const uint* previousDifficulty) {
    if (calmFull <= 0.0f) return t;
    float calm = smoothstep(calmFrom, calmFull, float(difficulty[0]) * difficultyScale);
    float calmBefore = smoothstep(calmFrom, calmFull, float(previousDifficulty[0]) * previousDifficultyScale);
    calm = max(calm, calmBefore * 0.6f);
    return t < 0.5f ? t * (1.0f - calm) : 1.0f - (1.0f - t) * (1.0f - calm);
}

// =============================================================================
// Motion at the in-between moment, by splatting
// =============================================================================
//
// Vision's flow belongs to the captures, not to the moment being built. Read at the moment's
// pixel, it describes whatever stood there in the older capture: just behind a walking person
// that is the person, so the background uncovered there was dragged along with them, and the
// edge they are about to cover was handled the other way round. That is the halo and the
// see-through edge around people and other large moving things, at any speed.
//
// Here every flow pixel of both captures is carried to where it is at time t, forward from the
// older capture and backward from the newer one. Where both captures land, both see the spot;
// where only one lands, only that one does: background just uncovered, or about to be
// covered. Where two layers land on one spot, the pixel whose own match holds best wins it
// (colour, and the round trip through the other flow): a background pixel about to be
// covered matches the thing covering it, not itself, and loses to it. Whether a capture sees
// a spot depends only on whether anything of it landed there, not on that match: on
// textured, blurred motion Vision's vectors are rough, and judged by match quality whole
// moving figures counted as seen by neither capture.

// Before splatting, each flow pixel of each capture picks its motion: Vision's, or where blocks
// move on their own (the gate mask), the block vector around it that lines its own small patch
// up with the other capture clearly better. Chosen in the capture, where a pixel belongs to
// one layer only; chosen at the in-between moment instead, a path behind a moving leg, from
// background to background, could win there and show background through the leg.
struct FuseParams {
    float gain;          // Vision's values → flow pixels
    float blockToFlow;   // block vectors (1/4-size pixels) → flow pixels
};

static inline float sourcePatchCost(texture2d<half, access::sample> here, texture2d<half, access::sample> other,
                                    sampler s, float2 position, float2 v, float2 flowSize) {
    float cost = 0.0f;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 d = float2(x, y);
            float3 a = float3(here.sample(s, (position + d) / flowSize).rgb);
            float3 b = float3(other.sample(s, (position + v + d) / flowSize).rgb);
            cost += abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b);
        }
    }
    float2 end = (position + v) / flowSize;
    float outside = (end.x < 0.0f || end.y < 0.0f || end.x > 1.0f || end.y > 1.0f) ? 0.3f : 0.0f;
    return cost / 27.0f + outside;
}

kernel void fuseFlow(
    texture2d<half, access::sample> prev [[texture(0)]],
    texture2d<half, access::sample> next [[texture(1)]],
    texture2d<half, access::sample> forward [[texture(2)]],
    texture2d<half, access::sample> backward [[texture(3)]],
    texture2d<float, access::read> blockForward [[texture(4)]],
    texture2d<float, access::read> blockBackward [[texture(5)]],
    texture2d<float, access::read> gateMask [[texture(6)]],
    texture2d<half, access::write> fusedForward [[texture(7)]],
    texture2d<half, access::write> fusedBackward [[texture(8)]],
    constant FuseParams& params [[buffer(0)]],
    uint3 gid [[thread_position_in_grid]]
) {
    uint width = forward.get_width();
    uint height = forward.get_height();
    if (gid.x >= width || gid.y >= height) return;
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    bool fromNewer = gid.z == 1;
    float2 flowSize = float2(width, height);
    float2 position = float2(gid.xy) + 0.5f;
    float2 chosen = float2(fromNewer ? backward.read(gid.xy).rg : forward.read(gid.xy).rg) * params.gain;
    int2 fieldSize = int2(blockForward.get_width(), blockForward.get_height());
    int2 block = clamp(int2(position / flowSize * float2(fieldSize)), int2(0), fieldSize - 1);
    if (gateMask.read(uint2(block)).r > 0.5f) {
        float visionCost = fromNewer ? sourcePatchCost(next, prev, s, position, chosen, flowSize)
                                     : sourcePatchCost(prev, next, s, position, chosen, flowSize);
        float bestCost = 1e9f;
        float2 best = chosen;
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                uint2 b = uint2(clamp(block + int2(x, y), int2(0), fieldSize - 1));
                float2 v = (fromNewer ? blockBackward.read(b).rg : blockForward.read(b).rg) * params.blockToFlow;
                float cost = fromNewer ? sourcePatchCost(next, prev, s, position, v, flowSize)
                                       : sourcePatchCost(prev, next, s, position, v, flowSize);
                if (cost < bestCost) {
                    bestCost = cost;
                    best = v;
                }
            }
        }
        if (bestCost < visionCost * 0.6f && bestCost < 0.08f) chosen = best;
    }
    if (fromNewer) {
        fusedBackward.write(half4(half2(chosen), 0.0h, 0.0h), gid.xy);
    } else {
        fusedForward.write(half4(half2(chosen), 0.0h, 0.0h), gid.xy);
    }
}

struct SplatParams {
    float t;
    float gain;                     // Vision's values → flow pixels
    float colourWeight;             // weight falls as exp(-colourWeight * colour mismatch, 0-1)
    float roundTripWeight;          // and exp(-roundTripWeight * round trip, in flow pixels)
    float calmFrom;                 // the artifact guard, as in BlockInterpolateParams
    float calmFull;
    float difficultyScale;
    float previousDifficultyScale;
};

kernel void splatFlow(
    texture2d<half, access::sample> prev [[texture(0)]],
    texture2d<half, access::sample> next [[texture(1)]],
    texture2d<half, access::sample> forward [[texture(2)]],
    texture2d<half, access::sample> backward [[texture(3)]],
    device atomic_uint* winners [[buffer(0)]],   // per flow pixel and capture: the best pixel landed
    constant SplatParams& params [[buffer(1)]],
    device const uint* difficulty [[buffer(2)]],
    device const uint* previousDifficulty [[buffer(3)]],
    uint3 gid [[thread_position_in_grid]]
) {
    uint width = forward.get_width();
    uint height = forward.get_height();
    if (gid.x >= width || gid.y >= height) return;
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float t = calmedTime(params.t, params.calmFrom, params.calmFull, params.difficultyScale,
                         params.previousDifficultyScale, difficulty, previousDifficulty);
    bool fromNewer = gid.z == 1;
    float2 flowSize = float2(width, height);
    float2 position = float2(gid.xy) + 0.5f;
    float2 v = float2(fromNewer ? backward.read(gid.xy).rg : forward.read(gid.xy).rg) * params.gain;
    float2 there = (position + v) / flowSize;
    float3 here = float3(fromNewer ? next.sample(s, position / flowSize).rgb : prev.sample(s, position / flowSize).rgb);
    float3 other = float3(fromNewer ? prev.sample(s, there).rgb : next.sample(s, there).rgb);
    float3 d = abs(here - other);
    float colourError = (d.r + d.g + d.b) / 3.0f;
    float2 back = float2(fromNewer ? forward.sample(s, there).rg : backward.sample(s, there).rg) * params.gain;
    float roundTrip = length(v + back) / (1.0f + 0.05f * length(v));
    float weight = exp(-params.colourWeight * colourError - params.roundTripWeight * roundTrip);
    if (there.x < 0.0f || there.y < 0.0f || there.x > 1.0f || there.y > 1.0f) weight *= 0.05f;

    // Onto the nearest flow pixel, one atomic per pixel (sums of float motion spread over four
    // pixels cost 5 ms a frame): the key is the weight in its top 12 bits and the source
    // pixel's index below, so the best-matching pixel landed is kept, and 0 means none.
    int2 p = int2(floor(position + v * (fromNewer ? 1.0f - t : t)));
    if (p.x < 0 || p.y < 0 || p.x >= int(width) || p.y >= int(height)) return;
    uint key = ((uint(clamp(weight, 0.0f, 1.0f) * 4094.0f + 0.5f) + 1u) << 20) | (gid.y * width + gid.x);
    atomic_fetch_max_explicit(&winners[(uint(p.y) * width + uint(p.x)) * 2u + (fromNewer ? 1u : 0u)], key, memory_order_relaxed);
}

// Per flow pixel at time t: the motion (x, y, flow pixels, older → newer), whether the older
// capture sees the spot (z, 0-1) and whether the newer one does (w). Each source pixel landed
// on one pixel, so sight is judged by how many pixels around got something from that capture
// (about all of them where it sees the area). The motion is that of the pixels that won this
// spot, else the best around it (where motion spreads apart and leaves gaps).
struct SplatWinner {
    float2 motion;   // older → newer, flow pixels
    float weight;    // 0 when nothing landed
};

static inline SplatWinner splatWinner(uint key, bool fromNewer, texture2d<half, access::read> forward,
                                      texture2d<half, access::read> backward, float gain) {
    SplatWinner winner = { float2(0.0f), 0.0f };
    if (key == 0u) return winner;
    uint width = forward.get_width();
    uint source = key & 0xFFFFFu;
    uint2 at = uint2(source % width, source / width);
    winner.motion = fromNewer ? -float2(backward.read(at).rg) * gain : float2(forward.read(at).rg) * gain;
    winner.weight = float(key >> 20) / 4095.0f;
    return winner;
}

kernel void resolveSplatFlow(
    device const uint* winners [[buffer(0)]],
    constant float& gain [[buffer(1)]],
    texture2d<float, access::write> motionAtT [[texture(0)]],
    texture2d<half, access::read> forward [[texture(1)]],
    texture2d<half, access::read> backward [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = motionAtT.get_width();
    uint height = motionAtT.get_height();
    if (gid.x >= width || gid.y >= height) return;
    uint index = gid.y * width + gid.x;
    uint ownOlder = winners[index * 2u];
    uint ownNewer = winners[index * 2u + 1u];
    uint bestOlder = 0u, bestNewer = 0u;
    float countOlder = 0.0f, countNewer = 0.0f;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            int2 p = clamp(int2(gid) + int2(x, y), int2(0), int2(width - 1, height - 1));
            uint j = uint(p.y) * width + uint(p.x);
            uint older = winners[j * 2u];
            uint newer = winners[j * 2u + 1u];
            countOlder += older != 0u ? 1.0f : 0.0f;
            countNewer += newer != 0u ? 1.0f : 0.0f;
            bestOlder = max(bestOlder, older);
            bestNewer = max(bestNewer, newer);
        }
    }
    if (bestOlder == 0u && bestNewer == 0u) {
        for (int y = -2; y <= 2; y++) {
            for (int x = -2; x <= 2; x++) {
                int2 p = clamp(int2(gid) + int2(x, y), int2(0), int2(width - 1, height - 1));
                uint j = uint(p.y) * width + uint(p.x);
                bestOlder = max(bestOlder, winners[j * 2u]);
                bestNewer = max(bestNewer, winners[j * 2u + 1u]);
            }
        }
    }
    bool own = ownOlder != 0u || ownNewer != 0u;
    SplatWinner older = splatWinner(own ? ownOlder : bestOlder, false, forward, backward, gain);
    SplatWinner newer = splatWinner(own ? ownNewer : bestNewer, true, forward, backward, gain);
    // Both captures' winners: where they belong to one layer they agree; where one matches far
    // better, it is the layer in front.
    float wOlder = older.weight + (older.weight > 0.0f ? 1e-3f : 0.0f);
    float wNewer = newer.weight + (newer.weight > 0.0f ? 1e-3f : 0.0f);
    float2 motion = wOlder + wNewer > 0.0f ? (older.motion * wOlder + newer.motion * wNewer) / (wOlder + wNewer) : float2(0.0f);
    motionAtT.write(float4(motion, smoothstep(0.2f, 0.55f, countOlder / 9.0f), smoothstep(0.2f, 0.55f, countNewer / 9.0f)), gid);
}

struct BlockInterpolateParams {
    float t;
    float visionGain;
    float blockToCapture;   // capture pixels per unit of the block vectors
    float matchLimit;       // a candidate matching worse than this is never taken
    float calmFrom;         // pair difficulty (share of the picture) from which in-betweens are
    float calmFull;         // drawn toward the nearer real frame, fully at calmFull; 0 = never
    float difficultyScale;  // difficulty[0] → share of the picture
    float previousDifficultyScale;  // the same for the pair before
    float splatOn;          // 1 when motionAtT holds the motion at this moment (see splatFlow)
};

static inline float patchError(texture2d<half, access::sample> prev, texture2d<half, access::sample> next,
                               sampler s, float2 uvA, float2 uvB, float2 texel) {
    float error = 0.0f;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 d = float2(x, y) * 4.0f * texel;
            float3 a = float3(prev.sample(s, uvA + d).rgb);
            float3 b = float3(next.sample(s, uvB + d).rgb);
            error += abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b);
        }
    }
    return error / 9.0f;
}

static inline float insideFrame(float2 uv) {
    return (uv.x >= 0.0f && uv.y >= 0.0f && uv.x <= 1.0f && uv.y <= 1.0f) ? 1.0f : 0.0f;
}

// Distance from v to the nearest of the 3x3 block vectors around uv. Blocks on an object's
// edge hold either motion, so the nearest is the fair comparison.
static inline float blockDisagreement(texture2d<float, access::read> field, float2 uv, int2 fieldSize, float scale, float2 v) {
    int2 center = int2(uv * float2(fieldSize));
    float closest = 1e9f;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            int2 b = clamp(center + int2(x, y), int2(0), fieldSize - 1);
            closest = min(closest, length(field.read(uint2(b)).rg * scale - v));
        }
    }
    return closest;
}

// Distance from v to the nearest of the 2x2 block vectors whose centres surround uv. The
// candidate test uses this: with the 3x3 ring, a block of the wrong layer one block away let
// fast objects' motion through onto blurred background beside them, as block-shaped tears.
static inline float blockDisagreementNear(texture2d<float, access::read> field, float2 uv, int2 fieldSize, float scale, float2 v) {
    int2 base = int2(floor(uv * float2(fieldSize) - 0.5f));
    float closest = 1e9f;
    for (int y = 0; y <= 1; y++) {
        for (int x = 0; x <= 1; x++) {
            int2 b = clamp(base + int2(x, y), int2(0), fieldSize - 1);
            closest = min(closest, length(field.read(uint2(b)).rg * scale - v));
        }
    }
    return closest;
}

/// flowInterpolate's warp along Vision's flow, with its round-trip check and blend fallback.
static inline half4 visionWarp(texture2d<half, access::sample> prev, texture2d<half, access::sample> next,
                               texture2d<half, access::sample> forward, texture2d<half, access::sample> backward,
                               sampler s, float2 uv, float t, float gain, float2 flowSize) {
    float2 f = float2(forward.sample(s, uv).rg) * gain;
    float2 b = float2(backward.sample(s, uv).rg) * gain;
    float2 uvA = uv - f * t / flowSize;
    float2 uvB = uv - b * (1.0f - t) / flowSize;
    float2 fA = float2(forward.sample(s, uvA).rg) * gain;
    float2 bA = float2(backward.sample(s, uvA + fA / flowSize).rg) * gain;
    float2 bB = float2(backward.sample(s, uvB).rg) * gain;
    float2 fB = float2(forward.sample(s, uvB + bB / flowSize).rg) * gain;
    float toleranceA = 1.0f + 0.08f * length(fA);
    float toleranceB = 1.0f + 0.08f * length(bB);
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
    half4 blended = mix(prev.sample(s, uv), next.sample(s, uv), half(t));
    return mix(blended, warped, half(max(confA, confB)));
}

/// The warp along the motion at time t (see splatFlow), each capture only where it sees the
/// spot. `fallback` where neither does.
static inline half4 splatWarp(texture2d<half, access::sample> prev, texture2d<half, access::sample> next,
                              float4 motion, sampler s, float2 uv, float t, float2 flowSize, half4 fallback) {
    float2 uvA = uv - motion.xy * t / flowSize;
    float2 uvB = uv + motion.xy * (1.0f - t) / flowSize;
    float weightA = (1.0f - t) * motion.z * insideFrame(uvA);
    float weightB = t * motion.w * insideFrame(uvB);
    if (weightA + weightB < 1e-4f) return fallback;
    half4 cA = prev.sample(s, uvA);
    half4 cB = next.sample(s, uvB);
    half4 warped = half4((float4(cA) * weightA + float4(cB) * weightB) / (weightA + weightB));
    return mix(fallback, warped, half(max(motion.z, motion.w)));
}

/// flowInterpolate where Vision is right; around blocks that move on their own, the motion
/// per pixel is the candidate that lines up the two captures best (Vision's, the block
/// vectors around it, Vision's backward), and each side is weighted by whether it can see
/// the pixel. No candidate wins unless it matches clearly better than Vision.
kernel void flowInterpolateBlocks(
    texture2d<half, access::sample> prev [[texture(0)]],
    texture2d<half, access::sample> next [[texture(1)]],
    texture2d<half, access::sample> forward [[texture(2)]],
    texture2d<half, access::sample> backward [[texture(3)]],
    texture2d<half, access::write> output [[texture(4)]],
    texture2d<float, access::read> blockForward [[texture(5)]],
    texture2d<float, access::read> blockBackward [[texture(6)]],
    texture2d<float, access::read> gateMask [[texture(7)]],
    texture2d<float, access::sample> motionAtT [[texture(8)]],
    constant BlockInterpolateParams& params [[buffer(0)]],
    device const uint* difficulty [[buffer(1)]],
    device const uint* previousDifficulty [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = output.get_width();
    uint height = output.get_height();
    if (gid.x >= width || gid.y >= height) return;
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 size = float2(width, height);
    float2 texel = 1.0f / size;
    float2 uv = (float2(gid) + 0.5f) * texel;
    float t = calmedTime(params.t, params.calmFrom, params.calmFull, params.difficultyScale,
                         params.previousDifficultyScale, difficulty, previousDifficulty);
    // Within a few percent of a real frame, the real frame itself: a guess drawn that close
    // can still pick its far side where it thinks the near one is covered, and show it.
    if (t <= 0.04f || t >= 0.96f) {
        output.write(t < 0.5f ? prev.sample(s, uv) : next.sample(s, uv), gid);
        return;
    }
    float2 flowSize = float2(forward.get_width(), forward.get_height());
    float2 visionScale = params.visionGain * size / flowSize;
    int2 fieldSize = int2(blockForward.get_width(), blockForward.get_height());
    float k = params.blockToCapture;
    int2 block = clamp(int2(uv * float2(fieldSize)), int2(0), fieldSize - 1);

    // What flowInterpolate makes of this pixel: the picture everywhere no block moves on its own,
    // and the fallback inside those areas, so their edges never show.
    half4 visionResult = visionWarp(prev, next, forward, backward, s, uv, t, params.visionGain, flowSize);
    float4 motion = params.splatOn > 0.5f ? motionAtT.sample(s, uv) : float4(0.0f);
    half4 base = params.splatOn > 0.5f ? splatWarp(prev, next, motion, s, uv, t, flowSize, visionResult) : visionResult;
    if (gateMask.read(uint2(block)).r < 0.5f) {
        output.write(base, gid);
        return;
    }
    // Seen by one capture only (uncovered, or about to be covered): no motion can line the two
    // captures up there, and one that seems to is a coincidence on plain background.
    if (params.splatOn > 0.5f && max(motion.z, motion.w) > 0.5f && min(motion.z, motion.w) < 0.5f) {
        output.write(base, gid);
        return;
    }

    float2 vision = params.splatOn > 0.5f && max(motion.z, motion.w) > 0.5f
        ? motion.xy * size / flowSize
        : float2(forward.sample(s, uv).rg) * visionScale;
    float visionError = patchError(prev, next, s, uv - vision * texel * t, uv + vision * texel * (1.0f - t), texel);
    float2 best = vision;
    float bestError = visionError;
    bool taken = false;
    float2 candidates[11];
    int count = 0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            candidates[count++] = blockForward.read(uint2(clamp(block + int2(x, y), int2(0), fieldSize - 1))).rg * k;
        }
    }
    candidates[count++] = -blockBackward.read(uint2(block)).rg * k;
    candidates[count++] = -float2(backward.sample(s, uv).rg) * visionScale;
    for (int i = 0; i < count; i++) {
        float2 v = candidates[i];
        float2 a = uv - v * texel * t;
        float2 b = uv + v * texel * (1.0f - t);
        if (insideFrame(a) == 0.0f || insideFrame(b) == 0.0f) continue;
        // One moving layer, seen from both sides: the motion recorded where the candidate
        // starts and where it ends both agree with it. Shifting background by an object's
        // motion fails this, which is what tore text next to moving objects; requiring one
        // side only also let block-sized pieces of the wrong layer through near fast objects.
        float tolerance = 4.0f + 0.1f * length(v);
        bool agrees = blockDisagreementNear(blockForward, a, fieldSize, k, v) < tolerance &&
            blockDisagreementNear(blockBackward, b, fieldSize, -k, v) < tolerance;
        if (!agrees) continue;
        float error = patchError(prev, next, s, a, b, texel);
        // With the splat on, only where its motion clearly fails at this spot: where it merely
        // fits a little worse, the winner was often a path behind a moving limb, from
        // background to background, and showed background through the limb.
        bool baseFails = params.splatOn < 0.5f || visionError > params.matchLimit * 1.2f;
        if (baseFails && error < bestError && error < visionError * 0.5f && error < params.matchLimit) {
            best = v;
            bestError = error;
            taken = true;
        }
    }
    // No block motion lines the captures up clearly better than the motion at this moment.
    if (params.splatOn > 0.5f && !taken) {
        output.write(base, gid);
        return;
    }
    float2 uvA = uv - best * texel * t;
    float2 uvB = uv + best * texel * (1.0f - t);
    float tolerance = 6.0f + 0.15f * length(best);
    // Can each side see this pixel? Where the motion recorded at the sampled spot disagrees,
    // that side shows something else there: it is covered, so the other side is used.
    float seeA = insideFrame(uvA) * (1.0f - smoothstep(tolerance, tolerance * 3.0f, blockDisagreement(blockForward, uvA, fieldSize, k, best)));
    float seeB = insideFrame(uvB) * (1.0f - smoothstep(tolerance, tolerance * 3.0f, blockDisagreement(blockBackward, uvB, fieldSize, -k, best)));
    half4 cA = prev.sample(s, uvA);
    half4 cB = next.sample(s, uvB);
    float weightA = (1.0f - t) * (0.02f + seeA);
    float weightB = t * (0.02f + seeB);
    half4 warped = half4((float4(cA) * weightA + float4(cB) * weightB) / (weightA + weightB));
    // No candidate lines the captures up (an object faster than the search, or something
    // appearing): what the area around gets. The nearer capture here (no motion at all) left
    // block-shaped seams against neighbours warped along a camera pan; Vision's warp does not.
    float trust = 1.0f - smoothstep(params.matchLimit * 2.5f, params.matchLimit * 5.0f, bestError);
    output.write(mix(base, warped, half(trust)), gid);
}
