import Foundation
import LSFGCore
import LosslessShaderTranslator
import Metal
import Synchronization

/// Frame generation with Lossless Scaling's LSFG 3.1, run natively in Metal by lsfg-metal.
///
/// The shaders are read from the user's own `Lossless.dll` and translated to Metal inside the app
/// (SPIRV-Cross), so nothing from the DLL ships with MetalDuck and users need no extra tools.
/// lsfg-metal runs the pass graph: for each real frame, it builds `multiplier - 1` in-between frames
/// at evenly spaced moments. Quality or performance mode and the flow scale can change at any time.
///
/// Used only under the renderer's render lock once built.
final class LosslessFrameGenerationEngine: @unchecked Sendable {
    /// Pipelines for quality mode (false) and performance mode (true), so switching never stalls a frame.
    private let kernels: [Bool: LSFGKernels]
    private let fp16: Bool

    private var lsfg: LSFG31?
    /// Real frames written into LSFG so far, newest last.
    private var pushedIDs: [UInt64] = []
    /// The real frame whose in-between frames sit in `lsfg.outputs`.
    private var generatedFor: UInt64?

    init(device: MTLDevice, dllURL: URL, fp16: Bool = true) throws {
        self.fp16 = fp16
        let start = Date()
        kernels = try Self.buildKernels(device: device, dllURL: dllURL, fp16: fp16)
        PipelineLog.shared.event(
            "lossless",
            String(format: "built LSFG kernels for both modes from Lossless.dll in %.2f s", Date().timeIntervalSince(start))
        )
    }

    func reset() {
        lsfg = nil
        pushedIDs.removeAll()
        generatedFor = nil
    }

    /// The in-between frame nearest to `t` between two buffered captures.
    func attemptInterpolation(
        commandBuffer: MTLCommandBuffer,
        previous: GenerationFrame,
        next: GenerationFrame,
        t: Float,
        multiplier: Int,
        performance: Bool = false,
        flowScale: Float = 1
    ) -> FrameInterpolationAttempt {
        let texture = next.texture
        guard previous.texture.width == texture.width, previous.texture.height == texture.height,
              previous.texture.pixelFormat == texture.pixelFormat else {
            return .failed("capture size changed between frames")
        }
        let multiplier = max(2, min(multiplier, 8))
        let flowScale = min(max(flowScale, 0.25), 1)
        if lsfg == nil || lsfg?.width != texture.width || lsfg?.height != texture.height
            || lsfg?.settings.multiplier != multiplier || lsfg?.settings.performance != performance
            || lsfg?.settings.flowScale != flowScale || lsfg?.outputs.first?.pixelFormat != texture.pixelFormat {
            reset()
            var settings = LSFGSettings()
            settings.multiplier = multiplier
            settings.flowScale = flowScale
            settings.fp16 = fp16
            settings.performance = performance
            do {
                lsfg = try LSFG31(width: texture.width, height: texture.height, format: texture.pixelFormat,
                                  settings: settings, kernels: kernels[performance]!)
            } catch {
                return .failed("LSFG could not start: \(error)")
            }
        }

        // LSFG keeps history, so each capture goes in once, in order.
        if pushedIDs.last != next.id {
            if pushedIDs.last != previous.id {
                push(previous, commandBuffer: commandBuffer)
            }
            push(next, commandBuffer: commandBuffer)
        }
        guard let lsfg, generatedFor == next.id else {
            return .failed("LSFG is filling its history")
        }

        // Output i is the moment (i + 1) / multiplier between the two captures.
        let index = min(max(Int((t * Float(multiplier)).rounded()), 1), multiplier - 1) - 1
        return .produced(
            texture: lsfg.outputs[index],
            flowWidth: Int(Float(texture.width) * flowScale),
            flowHeight: Int(Float(texture.height) * flowScale),
            flowFrameID: next.id,
            latestCaptureID: next.id
        )
    }

    private func push(_ frame: GenerationFrame, commandBuffer: MTLCommandBuffer) {
        guard var lsfg, let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: frame.texture, to: lsfg.nextInput)
        blit.endEncoding()
        // In-between frames are valid once two earlier captures are in the history (as lsfg-vk).
        let warm = lsfg.frameIndex >= 2
        do {
            try lsfg.encode(into: commandBuffer, generate: warm)
            generatedFor = warm ? frame.id : nil
        } catch {
            generatedFor = nil
        }
        self.lsfg = lsfg
        pushedIDs.append(frame.id)
        if pushedIDs.count > 3 { pushedIDs.removeFirst() }
    }

    // MARK: - Kernels

    /// Translates the DLL's SPIR-V for every pass of both modes and builds its pipeline.
    /// Slow (compiles each kernel): call it off the main thread.
    private static func buildKernels(device: MTLDevice, dllURL: URL, fp16: Bool) throws -> [Bool: LSFGKernels] {
        let spirv = try LSFGShaderLibrary(dll: dllURL).spirv
        let quality = LSFG31Shaders.allIDs(fp16: fp16, performance: false)
        let fast = LSFG31Shaders.allIDs(fp16: fp16, performance: true)
        let ids = quality.union(fast).sorted()
        for id in ids where spirv[id] == nil {
            throw KernelError("Lossless.dll has no shader \(id). This Lossless Scaling version is not supported yet.")
        }

        let built = Mutex<[UInt32: LSFGKernels.Kernel]>([:])
        let failure = Mutex<String?>(nil)
        DispatchQueue.concurrentPerform(iterations: ids.count) { index in
            let id = ids[index]
            do {
                let kernel = try buildKernel(id: id, spirv: spirv[id]!, device: device)
                built.withLock { $0[id] = kernel }
            } catch {
                failure.withLock { $0 = $0 ?? error.localizedDescription }
            }
        }
        if let message = failure.withLock({ $0 }) { throw KernelError(message) }
        let all = built.withLock { $0 }
        return [
            false: LSFGKernels(device: device, kernels: all.filter { quality.contains($0.key) }),
            true: LSFGKernels(device: device, kernels: all.filter { fast.contains($0.key) }),
        ]
    }

    private static func buildKernel(id: UInt32, spirv: Data, device: MTLDevice) throws -> LSFGKernels.Kernel {
        var translation = spirv.withUnsafeBytes { raw in
            let words = raw.bindMemory(to: UInt32.self)
            return lsfg_translate_spirv(words.baseAddress, words.count)
        }
        defer { lsfg_translation_free(&translation) }
        guard let msl = translation.msl, let entry = translation.entryPoint else {
            let reason = translation.error.map { String(cString: $0) } ?? "unknown error"
            throw KernelError("Could not translate shader \(id) to Metal: \(reason)")
        }

        let options = MTLCompileOptions()
        options.languageVersion = .version3_0
        // Same output as safe math in the self-test, at about a third of the GPU time.
        options.mathMode = .fast
        let function: MTLFunction
        do {
            let library = try device.makeLibrary(source: String(cString: msl), options: options)
            guard let made = library.makeFunction(name: String(cString: entry)) else {
                throw KernelError("Shader \(id) has no kernel \(String(cString: entry)).")
            }
            function = made
        } catch let error as KernelError {
            throw error
        } catch {
            throw KernelError("Could not compile shader \(id) for Metal: \(error.localizedDescription)")
        }
        let pipeline = try device.makeComputePipelineState(function: function)
        let size = MTLSize(width: Int(translation.localSize.0), height: Int(translation.localSize.1),
                           depth: Int(translation.localSize.2))
        guard size.width * size.height * size.depth <= pipeline.maxTotalThreadsPerThreadgroup else {
            throw KernelError("Shader \(id) needs \(size.width)x\(size.height) threads per group; this GPU allows \(pipeline.maxTotalThreadsPerThreadgroup).")
        }
        return LSFGKernels.Kernel(pipeline: pipeline, threadgroupSize: size)
    }

    struct KernelError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
