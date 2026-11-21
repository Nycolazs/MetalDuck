import Foundation
import Metal

/// A block-matching motion search for each pair of captures, run next to Vision's flow.
///
/// Vision's optical flow follows camera motion well but barely sees an object moving across a
/// still background: in tests a 60 px move came back as 6 px and a 120 px move as 4 px. The
/// interpolation then trusted that near-zero motion and mixed the two captures in place, which
/// is the see-through double image on fast objects. This search finds moves up to about 320
/// capture pixels: a full search at 1/8 size, refined at 1/4, checked by a round trip and a
/// vector median. Once a pair's Vision flow is in, `gatedFields` marks the blocks Vision gets
/// clearly wrong, and only there does `flowInterpolateBlocks` pick motion per pixel.
///
/// Measured offline against true in-between frames (moving area, PSNR): a 120 px object went
/// from 13.2 to 16.3 dB, a 117.3 px one from 13.2 to 14.9 dB, a 300 px one from 12.5 to
/// 13.2 dB, and camera pans of 100 and 93.7 px from 36.1 to 39.1 and 33.7 to 34.5 dB. The
/// search costs about 4.3 ms of GPU per pair at 1821x1138.
///
/// Not thread-safe: the renderer calls it under its render lock.
final class BlockMotionEstimator {
    struct GatedFields {
        let forward: MTLTexture
        let backward: MTLTexture
        let mask: MTLTexture
        /// The pair's difficulty, filled in by the GPU: the share of the picture no known
        /// motion fits, in 1/1024ths of a 1/4-size pixel (`difficultyScale` makes it a share).
        let difficulty: MTLBuffer
        let difficultyScale: Float
        let commandBuffer: MTLCommandBuffer

        /// The share of the picture no known motion fits, once the GPU has measured it.
        var difficultyShare: Double? {
            guard commandBuffer.status == .completed else { return nil }
            return Double(difficulty.contents().load(as: UInt32.self)) * Double(difficultyScale)
        }
    }

    // Must match Present.metal.
    private struct PairDifficultyParams {
        var visionToQuarter: Float
    }

    private struct LumaFrame {
        let id: UInt64
        let quarter: MTLTexture
        let eighth: MTLTexture
    }

    private struct Pair {
        let previousID: UInt64
        let nextID: UInt64
        let forward: MTLTexture
        let backward: MTLTexture
        var gated: GatedFields?
        /// Blocks counted, and blocks the motion could not match (filled in by the GPU).
        let matchCounts: MTLBuffer?
        let commandBuffer: MTLCommandBuffer
        var unrelated: Bool?
        var unmatchedShare: Double?
    }

    /// A block whose best match still differs by more than this (mean luma, 0-1) is unmatched.
    private static let poorMatchCost: Float = 0.04
    /// Share of unmatched blocks above which two captures are not related by motion at all.
    /// Ordinary motion left 1-7% unmatched in tests; cuts 56-66%; a flash 98%.
    private static let unrelatedShare = 0.35

    // Must match Present.metal.
    private struct SearchParams {
        var blockSize: Int32
        var radius: Int32
        var motionPenalty: Float
        var candidateScale: Int32
    }

    private static let keptFrames = 6
    private static let keptPairs = 6
    /// Block edge, in pixels of its level; also the threadgroup layout of the coarse search.
    private static let blockSize = 8

    private let device: MTLDevice
    private let lumaQuarter: MTLComputePipelineState
    private let lumaHalf: MTLComputePipelineState
    private let searchCoarse: MTLComputePipelineState
    private let searchRefine: MTLComputePipelineState
    private let consistency: MTLComputePipelineState
    private let median: MTLComputePipelineState
    private let versusVision: MTLComputePipelineState
    private let gateMask: MTLComputePipelineState
    private let matchStats: MTLComputePipelineState
    private let pairDifficulty: MTLComputePipelineState

    private var frames: [LumaFrame] = []
    private var pairs: [Pair] = []

    init?(device: MTLDevice, library: MTLLibrary) {
        func pipeline(_ name: String) -> MTLComputePipelineState? {
            guard let function = library.makeFunction(name: name) else { return nil }
            return try? device.makeComputePipelineState(function: function)
        }
        guard let lumaQuarter = pipeline("blockLumaQuarter"),
              let lumaHalf = pipeline("blockLumaHalf"),
              let searchCoarse = pipeline("blockSearchCoarse"),
              let searchRefine = pipeline("blockSearchRefine"),
              let consistency = pipeline("blockConsistency"),
              let median = pipeline("blockMedian"),
              let versusVision = pipeline("blockVersusVision"),
              let gateMask = pipeline("blockGateMask"),
              let matchStats = pipeline("blockMatchStats"),
              let pairDifficulty = pipeline("pairDifficulty") else {
            return nil
        }
        self.device = device
        self.lumaQuarter = lumaQuarter
        self.lumaHalf = lumaHalf
        self.searchCoarse = searchCoarse
        self.searchRefine = searchRefine
        self.consistency = consistency
        self.median = median
        self.versusVision = versusVision
        self.gateMask = gateMask
        self.matchStats = matchStats
        self.pairDifficulty = pairDifficulty
    }

    /// Capture pixels per unit of a block vector (vectors are in 1/4-size pixels).
    func blockToCapture(captureWidth: Int) -> Float {
        let quarterWidth = (captureWidth + 3) / 4
        return Float(captureWidth) / Float(max(quarterWidth, 1))
    }

    /// Encodes the luma pyramid of a newly staged capture.
    func prepare(texture: MTLTexture, id: UInt64, commandBuffer: MTLCommandBuffer) {
        let quarterWidth = (texture.width + 3) / 4
        let quarterHeight = (texture.height + 3) / 4
        let eighthWidth = (quarterWidth + 1) / 2
        let eighthHeight = (quarterHeight + 1) / 2

        var reusable: LumaFrame?
        if frames.count >= Self.keptFrames {
            reusable = frames.removeFirst()
        }
        let quarter: MTLTexture
        let eighth: MTLTexture
        if let reusable, reusable.quarter.width == quarterWidth, reusable.quarter.height == quarterHeight {
            quarter = reusable.quarter
            eighth = reusable.eighth
        } else {
            guard let q = makeTexture(.r16Float, quarterWidth, quarterHeight),
                  let e = makeTexture(.r16Float, eighthWidth, eighthHeight) else { return }
            quarter = q
            eighth = e
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(lumaQuarter)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(quarter, index: 1)
        dispatch(encoder, lumaQuarter, quarterWidth, quarterHeight)
        encoder.setComputePipelineState(lumaHalf)
        encoder.setTexture(quarter, index: 0)
        encoder.setTexture(eighth, index: 1)
        dispatch(encoder, lumaHalf, eighthWidth, eighthHeight)
        encoder.endEncoding()
        frames.removeAll { $0.id == id }
        frames.append(LumaFrame(id: id, quarter: quarter, eighth: eighth))
    }

    /// Encodes the search in both directions for two prepared captures.
    func estimate(previousID: UInt64, nextID: UInt64, commandBuffer: MTLCommandBuffer) {
        guard let previous = frames.first(where: { $0.id == previousID }),
              let next = frames.first(where: { $0.id == nextID }),
              previous.quarter.width == next.quarter.width,
              previous.quarter.height == next.quarter.height else { return }
        let coarseWidth = (previous.eighth.width + Self.blockSize - 1) / Self.blockSize
        let coarseHeight = (previous.eighth.height + Self.blockSize - 1) / Self.blockSize
        let fineWidth = (previous.quarter.width + Self.blockSize - 1) / Self.blockSize
        let fineHeight = (previous.quarter.height + Self.blockSize - 1) / Self.blockSize
        guard let coarseForward = makeField(coarseWidth, coarseHeight),
              let coarseBackward = makeField(coarseWidth, coarseHeight),
              let fineForward = makeField(fineWidth, fineHeight),
              let fineBackward = makeField(fineWidth, fineHeight),
              let checkedForward = makeField(fineWidth, fineHeight),
              let checkedBackward = makeField(fineWidth, fineHeight),
              let forward = makeField(fineWidth, fineHeight),
              let backward = makeField(fineWidth, fineHeight),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        var coarseParams = SearchParams(blockSize: Int32(Self.blockSize), radius: 40, motionPenalty: 0.0004, candidateScale: 0)
        encoder.setComputePipelineState(searchCoarse)
        for (from, to, field) in [(previous.eighth, next.eighth, coarseForward), (next.eighth, previous.eighth, coarseBackward)] {
            encoder.setTexture(from, index: 0)
            encoder.setTexture(to, index: 1)
            encoder.setTexture(field, index: 2)
            encoder.setBytes(&coarseParams, length: MemoryLayout<SearchParams>.stride, index: 0)
            encoder.dispatchThreadgroups(
                MTLSize(width: coarseWidth, height: coarseHeight, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1)
            )
        }

        var fineParams = SearchParams(blockSize: Int32(Self.blockSize), radius: 2, motionPenalty: 0.0002, candidateScale: 2)
        encoder.setComputePipelineState(searchRefine)
        for (from, to, coarse, field) in [
            (previous.quarter, next.quarter, coarseForward, fineForward),
            (next.quarter, previous.quarter, coarseBackward, fineBackward)
        ] {
            encoder.setTexture(from, index: 0)
            encoder.setTexture(to, index: 1)
            encoder.setTexture(coarse, index: 2)
            encoder.setTexture(field, index: 3)
            encoder.setBytes(&fineParams, length: MemoryLayout<SearchParams>.stride, index: 0)
            dispatch(encoder, searchRefine, fineWidth, fineHeight)
        }

        encoder.setComputePipelineState(consistency)
        for (field, opposite, checked) in [(fineForward, fineBackward, checkedForward), (fineBackward, fineForward, checkedBackward)] {
            encoder.setTexture(field, index: 0)
            encoder.setTexture(opposite, index: 1)
            encoder.setTexture(checked, index: 2)
            encoder.setBytes(&fineParams, length: MemoryLayout<SearchParams>.stride, index: 0)
            dispatch(encoder, consistency, fineWidth, fineHeight)
        }

        encoder.setComputePipelineState(median)
        for (checked, filtered) in [(checkedForward, forward), (checkedBackward, backward)] {
            encoder.setTexture(checked, index: 0)
            encoder.setTexture(filtered, index: 1)
            dispatch(encoder, median, fineWidth, fineHeight)
        }

        // How much of the picture the motion explains, for `pairIsUnrelated`.
        let counts = device.makeBuffer(length: 4 * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        if let counts {
            counts.contents().initializeMemory(as: UInt32.self, repeating: 0, count: 4)
            var poorCost = Self.poorMatchCost
            encoder.setComputePipelineState(matchStats)
            // The refined field, before the checks clear the texture of unreliable blocks.
            encoder.setTexture(fineForward, index: 0)
            encoder.setBuffer(counts, offset: 0, index: 0)
            encoder.setBytes(&poorCost, length: MemoryLayout<Float>.stride, index: 1)
            dispatch(encoder, matchStats, fineWidth, fineHeight)
        }
        encoder.endEncoding()

        pairs.removeAll { $0.previousID == previousID && $0.nextID == nextID }
        pairs.append(Pair(
            previousID: previousID,
            nextID: nextID,
            forward: forward,
            backward: backward,
            gated: nil,
            matchCounts: counts,
            commandBuffer: commandBuffer,
            unrelated: nil,
            unmatchedShare: nil
        ))
        if pairs.count > Self.keptPairs {
            pairs.removeFirst(pairs.count - Self.keptPairs)
        }
    }

    /// The pair's fields with each block marked where it moves on its own (Vision's motion
    /// matches it clearly worse), a mask of those areas, and how hard the pair is. Built once
    /// per pair, when its Vision flow is first used. `visionGain` turns Vision's values into
    /// flow pixels.
    func gatedFields(
        previousID: UInt64,
        nextID: UInt64,
        visionForward: MTLTexture,
        visionBackward: MTLTexture,
        visionGain: Float,
        commandBuffer: MTLCommandBuffer
    ) -> GatedFields? {
        guard let index = pairs.firstIndex(where: { $0.previousID == previousID && $0.nextID == nextID }) else {
            return nil
        }
        if let gated = pairs[index].gated {
            return gated
        }
        guard let previous = frames.first(where: { $0.id == previousID }),
              let next = frames.first(where: { $0.id == nextID }) else { return nil }
        let pair = pairs[index]
        let width = pair.forward.width
        let height = pair.forward.height
        guard let gatedForward = makeField(width, height),
              let gatedBackward = makeField(width, height),
              let mask = makeField(width, height),
              let difficulty = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        difficulty.contents().storeBytes(of: UInt32(0), as: UInt32.self)

        var params = SearchParams(blockSize: Int32(Self.blockSize), radius: 0, motionPenalty: 0, candidateScale: 0)
        // Vision's vectors are in pixels of its flow texture; the blocks work in 1/4-size pixels.
        var visionToBlockPixels = visionGain * Float(previous.quarter.width) / Float(max(visionForward.width, 1))
        encoder.setComputePipelineState(versusVision)
        for (from, to, field, vision, gated) in [
            (previous.quarter, next.quarter, pair.forward, visionForward, gatedForward),
            (next.quarter, previous.quarter, pair.backward, visionBackward, gatedBackward)
        ] {
            encoder.setTexture(from, index: 0)
            encoder.setTexture(to, index: 1)
            encoder.setTexture(field, index: 2)
            encoder.setTexture(vision, index: 3)
            encoder.setTexture(gated, index: 4)
            encoder.setBytes(&params, length: MemoryLayout<SearchParams>.stride, index: 0)
            encoder.setBytes(&visionToBlockPixels, length: MemoryLayout<Float>.stride, index: 1)
            dispatch(encoder, versusVision, width, height)
        }
        encoder.setComputePipelineState(gateMask)
        encoder.setTexture(gatedForward, index: 0)
        encoder.setTexture(gatedBackward, index: 1)
        encoder.setTexture(mask, index: 2)
        dispatch(encoder, gateMask, width, height)

        // How much of the picture no known motion fits, at the midpoint (see pairDifficulty).
        let quarterWidth = previous.quarter.width
        let quarterHeight = previous.quarter.height
        var difficultyParams = PairDifficultyParams(
            visionToQuarter: visionGain * Float(quarterWidth) / Float(max(visionForward.width, 1))
        )
        encoder.setComputePipelineState(pairDifficulty)
        encoder.setTexture(previous.quarter, index: 0)
        encoder.setTexture(next.quarter, index: 1)
        encoder.setTexture(visionForward, index: 2)
        encoder.setTexture(gatedForward, index: 3)
        encoder.setTexture(gatedBackward, index: 4)
        encoder.setBuffer(difficulty, offset: 0, index: 0)
        encoder.setBytes(&difficultyParams, length: MemoryLayout<PairDifficultyParams>.stride, index: 1)
        dispatch(encoder, pairDifficulty, quarterWidth, quarterHeight)
        encoder.endEncoding()

        let gated = GatedFields(
            forward: gatedForward, backward: gatedBackward, mask: mask,
            difficulty: difficulty,
            difficultyScale: 1 / (1024 * Float(max(quarterWidth * quarterHeight, 1))),
            commandBuffer: commandBuffer
        )
        pairs[index].gated = gated
        return gated
    }

    /// True when most of the picture cannot be matched between the two captures: a cut, a
    /// flash, a jump. Nothing should be built between such frames. Nil until the GPU has
    /// finished the pair's search, or when there is no search for it.
    func pairIsUnrelated(previousID: UInt64, nextID: UInt64) -> Bool? {
        guard let index = pairs.firstIndex(where: { $0.previousID == previousID && $0.nextID == nextID }) else {
            return nil
        }
        if let verdict = pairs[index].unrelated {
            return verdict
        }
        guard pairs[index].commandBuffer.status == .completed,
              let counts = pairs[index].matchCounts else { return nil }
        let values = counts.contents().assumingMemoryBound(to: UInt32.self)
        let total = Double(values[0])
        let detailed = Double(values[2])
        guard total > 0 else { return nil }
        // Judge by the blocks with detail: plain areas match any motion and would dilute a
        // cut between two dark shots. A picture with almost no detail (black to white) is
        // judged on all of it.
        let share = detailed >= total * 0.1 ? Double(values[3]) / detailed : Double(values[1]) / total
        let verdict = share > Self.unrelatedShare
        pairs[index].unrelated = verdict
        pairs[index].unmatchedShare = share
        return verdict
    }

    /// The share of blocks the motion could not match, once `pairIsUnrelated` has decided.
    func unmatchedShare(previousID: UInt64, nextID: UInt64) -> Double? {
        pairs.first(where: { $0.previousID == previousID && $0.nextID == nextID })?.unmatchedShare
    }

    /// The gated fields of the pair ending at `nextID`, if they were built.
    func builtGatedFields(endingAt nextID: UInt64) -> GatedFields? {
        pairs.last(where: { $0.nextID == nextID })?.gated
    }

    /// The share of the picture no known motion fits for a pair, once its gated fields are
    /// built and measured (see `gatedFields`).
    func difficultyShare(previousID: UInt64, nextID: UInt64) -> Double? {
        pairs.first(where: { $0.previousID == previousID && $0.nextID == nextID })?.gated?.difficultyShare
    }

    func reset() {
        frames.removeAll()
        pairs.removeAll()
    }

    // MARK: - Private

    private func makeTexture(_ format: MTLPixelFormat, _ width: Int, _ height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private func makeField(_ width: Int, _ height: Int) -> MTLTexture? {
        makeTexture(.rgba32Float, width, height)
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState, _ width: Int, _ height: Int) {
        let threadWidth = min(pipeline.threadExecutionWidth, 16)
        let threadHeight = max(1, min(pipeline.maxTotalThreadsPerThreadgroup / threadWidth, 16))
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        )
    }
}
