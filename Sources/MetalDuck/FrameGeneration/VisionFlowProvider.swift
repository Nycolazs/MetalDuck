import Foundation
@preconcurrency import Metal
import Vision
@preconcurrency import CoreVideo
import QuartzCore
import os
import MetalPerformanceShaders

/// Optical flow from Vision for the frame-generation pass.
///
/// Captures are downscaled on the GPU straight into IOSurface pixel buffers, so Vision reads them
/// without a CPU copy, and its output is wrapped as a Metal texture the same way.
///
/// Revision 1 of `VNGenerateOpticalFlowRequest` is chosen on purpose. On Apple silicon it takes
/// about 15 ms at 800 px and reports vectors in pixels. Revision 2 takes 55–85 ms and reports
/// them at a fraction of a pixel that changes with size and accuracy.
final class VisionFlowProvider: @unchecked Sendable {
    /// One capture, downscaled for Vision.
    struct FlowFrame: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer
        fileprivate let metalTexture: CVMetalTexture
        let id: UInt64
        let time: CFTimeInterval
    }

    /// Vectors between two captures, in pixels of the flow texture once multiplied by `gain`.
    struct FlowResult: @unchecked Sendable {
        let forward: MTLTexture
        let backward: MTLTexture
        let gain: Float
        let previousID: UInt64
        let nextID: UInt64
        fileprivate let backing: [AnyObject]
    }

    static let maxDimension = 800.0
    private static let maxInFlight = 2
    private static let keptResults = 6

    private let device: MTLDevice
    private let flowQueue = DispatchQueue(label: "com.metalduck.visionflow", qos: .userInteractive, attributes: .concurrent)
    private var textureCache: CVMetalTextureCache?
    private let scaler: MPSImageBilinearScale
    private let revision: Int
    private let gain: Float

    // Render thread only.
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolWidth = 0
    private var poolHeight = 0

    private var lock = os_unfair_lock()
    private var results: [FlowResult] = []
    private var inFlight = 0
    private var pending: (FlowFrame, FlowFrame)?
    private var generation: UInt64 = 0
    private var readyLatency: Double = 0.03

    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.scaler = MPSImageBilinearScale(device: device)

        if VNGenerateOpticalFlowRequest.supportedRevisions.contains(VNGenerateOpticalFlowRequestRevision1) {
            revision = VNGenerateOpticalFlowRequestRevision1
            gain = 1
        } else {
            revision = VNGenerateOpticalFlowRequest.defaultRevision
            // Revision 2 at .high and 800 px reports roughly 0.38 of the real displacement.
            gain = 2.6
        }

        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        if status != kCVReturnSuccess {
            PipelineLog.shared.event("generate", "Vision flow texture cache failed, status \(status)")
        } else {
            PipelineLog.shared.event(
                "generate",
                "Vision optical flow ready on \(device.name): revision \(revision), up to \(Int(Self.maxDimension)) px, forward and backward in parallel, \(Self.maxInFlight) pairs in flight. Frames reach Vision through IOSurface without a CPU copy."
            )
        }
    }

    /// Average time from a capture's timestamp to its flow being usable.
    var flowReadyLatency: Double {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return readyLatency
    }

    /// Flow computed for exactly this pair of captures.
    func flow(previousID: UInt64, nextID: UInt64) -> FlowResult? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return results.last { $0.previousID == previousID && $0.nextID == nextID }
    }

    /// The finished flow whose pair is closest to `nextID`.
    func nearestFlow(to nextID: UInt64) -> FlowResult? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return results.min {
            distance($0.nextID, nextID) < distance($1.nextID, nextID)
        }
    }

    /// Downscales `texture` into a Vision-ready buffer as part of `commandBuffer`.
    /// The buffer holds valid pixels once the command buffer completes.
    func encodeFlowFrame(
        from texture: MTLTexture,
        id: UInt64,
        time: CFTimeInterval,
        commandBuffer: MTLCommandBuffer
    ) -> FlowFrame? {
        let scale = min(1.0, Self.maxDimension / Double(max(texture.width, texture.height)))
        let width = max(2, Int((Double(texture.width) * scale).rounded()) & ~1)
        let height = max(2, Int((Double(texture.height) * scale).rounded()) & ~1)

        guard let cache = textureCache, let pool = pool(width: width, height: height) else { return nil }

        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return nil }

        let attributes = [kCVMetalTextureUsage as String: MTLTextureUsage([.shaderRead, .shaderWrite]).rawValue] as CFDictionary
        var cvTexture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, attributes, .bgra8Unorm, width, height, 0, &cvTexture
        ) == kCVReturnSuccess,
              let cvTexture,
              let target = CVMetalTextureGetTexture(cvTexture) else { return nil }

        scaler.encode(commandBuffer: commandBuffer, sourceTexture: texture, destinationTexture: target)
        let frame = FlowFrame(pixelBuffer: pixelBuffer, metalTexture: cvTexture, id: id, time: time)
        commandBuffer.addCompletedHandler { _ in
            withExtendedLifetime(frame) {}
        }
        return frame
    }

    /// Starts flow for a pair whose pixels are already on the GPU.
    /// When Vision is saturated, the newest waiting pair replaces an older one.
    func submit(previous: FlowFrame, next: FlowFrame) {
        os_unfair_lock_lock(&lock)
        guard inFlight < Self.maxInFlight else {
            let replaced = pending != nil
            pending = (previous, next)
            os_unfair_lock_unlock(&lock)
            if replaced {
                PipelineLog.shared.noteFlowSkippedBusy()
            }
            return
        }
        inFlight += 1
        let generation = generation
        os_unfair_lock_unlock(&lock)

        start(previous: previous, next: next, generation: generation)
    }

    func reset() {
        os_unfair_lock_lock(&lock)
        results.removeAll()
        pending = nil
        generation &+= 1
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Private

    private func start(previous: FlowFrame, next: FlowFrame, generation: UInt64) {
        PipelineLog.shared.noteFlowStarted()
        flowQueue.async { [weak self] in
            guard let self else { return }
            let started = CACurrentMediaTime()
            let outcome = self.computePair(previous: previous, next: next)
            let finished = CACurrentMediaTime()
            let milliseconds = (finished - started) * 1000

            os_unfair_lock_lock(&self.lock)
            var following: (FlowFrame, FlowFrame)?
            if generation == self.generation {
                if case .success(let result) = outcome {
                    self.results.append(result)
                    if self.results.count > Self.keptResults {
                        self.results.removeFirst(self.results.count - Self.keptResults)
                    }
                    let latency = finished - next.time
                    if latency > 0, latency < 0.5 {
                        self.readyLatency = self.readyLatency * 0.85 + latency * 0.15
                    }
                }
                following = self.pending
                self.pending = nil
            }
            if following == nil {
                self.inFlight -= 1
            }
            let currentGeneration = self.generation
            os_unfair_lock_unlock(&self.lock)

            switch outcome {
            case .success(let result):
                PipelineLog.shared.noteFlowFinished(
                    milliseconds: milliseconds,
                    width: result.forward.width,
                    height: result.forward.height
                )
            case .failure(let error):
                PipelineLog.shared.noteFlowFailed(milliseconds: milliseconds, reason: error.reason)
            }

            if let following {
                self.start(previous: following.0, next: following.1, generation: currentGeneration)
            }
        }
    }

    private struct FlowFailure: Error {
        let reason: String
    }

    private final class PairSlots: @unchecked Sendable {
        var forward: (MTLTexture, [AnyObject])?
        var backward: (MTLTexture, [AnyObject])?
        var failure: String?
    }

    private func computePair(previous: FlowFrame, next: FlowFrame) -> Result<FlowResult, FlowFailure> {
        let slots = PairSlots()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            let isForward = index == 0
            let outcome = runVision(
                source: isForward ? previous.pixelBuffer : next.pixelBuffer,
                target: isForward ? next.pixelBuffer : previous.pixelBuffer
            )
            switch outcome {
            case .success(let flow):
                if isForward { slots.forward = flow } else { slots.backward = flow }
            case .failure(let error):
                slots.failure = error.reason
            }
        }

        guard let forward = slots.forward, let backward = slots.backward else {
            return .failure(FlowFailure(reason: slots.failure ?? "VNGenerateOpticalFlowRequest returned no vectors"))
        }
        return .success(FlowResult(
            forward: forward.0,
            backward: backward.0,
            gain: gain,
            previousID: previous.id,
            nextID: next.id,
            backing: forward.1 + backward.1
        ))
    }

    private func runVision(source: CVPixelBuffer, target: CVPixelBuffer) -> Result<(MTLTexture, [AnyObject]), FlowFailure> {
        let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: target)
        request.revision = revision
        request.computationAccuracy = .high
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent16Half

        do {
            try VNImageRequestHandler(cvPixelBuffer: source, options: [:]).perform([request])
        } catch {
            return .failure(FlowFailure(reason: error.localizedDescription))
        }
        guard let flowBuffer = request.results?.first?.pixelBuffer else {
            return .failure(FlowFailure(reason: "VNGenerateOpticalFlowRequest returned no vectors"))
        }

        let width = CVPixelBufferGetWidth(flowBuffer)
        let height = CVPixelBufferGetHeight(flowBuffer)

        if let cache = textureCache, CVPixelBufferGetIOSurface(flowBuffer) != nil {
            var cvTexture: CVMetalTexture?
            if CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, cache, flowBuffer, nil, .rg16Float, width, height, 0, &cvTexture
            ) == kCVReturnSuccess,
               let cvTexture,
               let texture = CVMetalTextureGetTexture(cvTexture) {
                return .success((texture, [cvTexture, flowBuffer]))
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg16Float, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return .failure(FlowFailure(reason: "could not allocate a flow texture"))
        }
        CVPixelBufferLockBaseAddress(flowBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(flowBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(flowBuffer) else {
            return .failure(FlowFailure(reason: "flow buffer has no CPU address"))
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: base,
            bytesPerRow: CVPixelBufferGetBytesPerRow(flowBuffer)
        )
        return .success((texture, []))
    }

    private func pool(width: Int, height: Int) -> CVPixelBufferPool? {
        if let pixelBufferPool, poolWidth == width, poolHeight == height {
            return pixelBufferPool
        }
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
        pixelBufferPool = pool
        poolWidth = width
        poolHeight = height
        return pool
    }

    private func distance(_ a: UInt64, _ b: UInt64) -> UInt64 {
        a > b ? a - b : b - a
    }
}
