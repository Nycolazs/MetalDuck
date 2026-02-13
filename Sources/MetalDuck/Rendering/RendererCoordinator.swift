import CoreMedia
import Foundation
import Metal
import MetalKit
import QuartzCore

private struct PresentUniforms {
    var contentScale: SIMD2<Float>
    var texelSize: SIMD2<Float>
    var sharpness: Float
    var blendFactor: Float
}

struct RendererStats {
    var isRunning: Bool
    var captureFPS: Double
    var presentFPS: Double
    var inputSize: CGSize
    var outputSize: CGSize
    var effectiveScale: Float
}

enum RendererCoordinatorError: Error {
    case shaderCompilationFailed
    case functionLookupFailed
    case pipelineCreationFailed
}

final class RendererCoordinator: NSObject {
    let settingsStore: SettingsStore
    var onStatsUpdate: ((RendererStats) -> Void)?

    private let context: MetalContext
    private let captureService: FrameCaptureService

    private var captureConfiguration: CaptureConfiguration
    private var activeCaptureTarget: CaptureTarget

    private let upscaler: MetalFXSpatialUpscaler
    private let frameGenerationEngine: MetalFXFrameGenerationEngine

    private weak var view: MTKView?

    private let frameLock = NSLock()
    private var latestFrame: CapturedFrame?
    private var latestFrameSequence: UInt64 = 0
    private var processedFrameSequence: UInt64 = 0

    private let statsLock = NSLock()
    private var captureFrameCounter: Int = 0
    private var presentFrameCounter: Int = 0
    private var fpsWindowStart: CFTimeInterval = CACurrentMediaTime()

    private var upscaledScratchTexture: MTLTexture?
    private var currentFrameTexture: MTLTexture?
    private var previousFrameTexture: MTLTexture?
    private var interpolatedBlendQueue: [Float] = []

    private var lastInputTexture: MTLTexture?
    private var lastOutputTexture: MTLTexture?
    private var lastEffectiveScale: Float = 1.0
    private var lastCaptureDeltaTime: Float = 1.0 / 60.0

    private var renderPipelineState: MTLRenderPipelineState
    private var linearSampler: MTLSamplerState
    private var nearestSampler: MTLSamplerState

    private var running = false
    private var smoothedPresentFrameTime: Double = 1.0 / 60.0
    private var lastPresentHostTime: CFTimeInterval?
    private var lastCaptureTimestamp: CMTime?
    private var dynamicScaleFactor: Float = 1.0
    private var loggedFallbackFrameGeneration = false

    // If you have motion/depth data from a game integration layer,
    // assign a provider to activate interpolation.
    var frameGenerationAuxiliaryProvider: (() -> FrameGenerationAuxiliary?)?

    @MainActor
    init(
        view: MTKView,
        context: MetalContext,
        captureService: FrameCaptureService,
        captureConfiguration: CaptureConfiguration,
        settingsStore: SettingsStore,
        initialTarget: CaptureTarget
    ) throws {
        self.context = context
        self.captureService = captureService
        self.captureConfiguration = captureConfiguration
        self.settingsStore = settingsStore
        self.activeCaptureTarget = initialTarget

        self.upscaler = MetalFXSpatialUpscaler(device: context.device)
        self.frameGenerationEngine = MetalFXFrameGenerationEngine(device: context.device)

        let (pipelineState, linearSampler, nearestSampler) = try Self.buildPresentationResources(
            device: context.device,
            pixelFormat: .bgra8Unorm
        )
        self.renderPipelineState = pipelineState
        self.linearSampler = linearSampler
        self.nearestSampler = nearestSampler

        self.view = view

        super.init()

        configure(view: view)
        installCaptureCallbacks()
    }

    var isRunning: Bool {
        running
    }

    var currentCaptureConfiguration: CaptureConfiguration {
        captureConfiguration
    }

    @MainActor
    func start() async throws {
        try await captureService.start()
        running = true
        resetFrameState()
        lastCaptureTimestamp = nil
        lastPresentHostTime = nil
        smoothedPresentFrameTime = 1.0 / 60.0
        dynamicScaleFactor = 1.0
    }

    @MainActor
    func stop() async {
        await captureService.stop()
        running = false
        resetFrameState()
        lastCaptureTimestamp = nil
    }

    @MainActor
    func reconfigureCapture(target: CaptureTarget) async throws {
        activeCaptureTarget = target
        try await captureService.reconfigure(target: target)
    }

    @MainActor
    func reconfigureCapture(configuration: CaptureConfiguration) async throws {
        captureConfiguration = configuration
        view?.preferredFramesPerSecond = max(configuration.framesPerSecond, 1)
        try await captureService.reconfigure(configuration: configuration)
    }

    @MainActor
    private func configure(view: MTKView) {
        view.device = context.device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1.0)
        view.framebufferOnly = false
        view.preferredFramesPerSecond = max(captureConfiguration.framesPerSecond, 1)
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = self
    }

    private func installCaptureCallbacks() {
        captureService.onFrame = { [weak self] frame in
            guard let self else { return }

            self.frameLock.lock()
            self.latestFrame = frame
            self.latestFrameSequence &+= 1
            self.frameLock.unlock()

            self.statsLock.lock()
            self.captureFrameCounter += 1
            self.statsLock.unlock()
        }

        captureService.onError = { [weak self] error in
            NSLog("Capture stream stopped with error: \(error.localizedDescription)")
            self?.running = false
        }
    }

    private func snapshotLatestFrame() -> (frame: CapturedFrame, sequence: UInt64)? {
        frameLock.lock()
        defer { frameLock.unlock() }
        guard let latestFrame else {
            return nil
        }
        return (latestFrame, latestFrameSequence)
    }

    private func resetFrameState() {
        frameLock.lock()
        latestFrame = nil
        latestFrameSequence = 0
        processedFrameSequence = 0
        frameLock.unlock()

        upscaledScratchTexture = nil
        currentFrameTexture = nil
        previousFrameTexture = nil
        interpolatedBlendQueue.removeAll(keepingCapacity: true)
        lastInputTexture = nil
        lastOutputTexture = nil
        lastEffectiveScale = 1.0
        lastCaptureDeltaTime = 1.0 / 60.0
        loggedFallbackFrameGeneration = false
    }

    private static func buildPresentationResources(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat
    ) throws -> (MTLRenderPipelineState, MTLSamplerState, MTLSamplerState) {
        let source = try loadPresentShaderSource()

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: source, options: nil)
        } catch {
            throw RendererCoordinatorError.shaderCompilationFailed
        }

        guard let vertexFunction = library.makeFunction(name: "vertexFullscreen"),
              let fragmentFunction = library.makeFunction(name: "fragmentPresent") else {
            throw RendererCoordinatorError.functionLookupFailed
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        let pipelineState: MTLRenderPipelineState
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RendererCoordinatorError.pipelineCreationFailed
        }

        let linearSamplerDescriptor = MTLSamplerDescriptor()
        linearSamplerDescriptor.minFilter = .linear
        linearSamplerDescriptor.magFilter = .linear
        linearSamplerDescriptor.mipFilter = .notMipmapped
        linearSamplerDescriptor.sAddressMode = .clampToEdge
        linearSamplerDescriptor.tAddressMode = .clampToEdge

        let nearestSamplerDescriptor = MTLSamplerDescriptor()
        nearestSamplerDescriptor.minFilter = .nearest
        nearestSamplerDescriptor.magFilter = .nearest
        nearestSamplerDescriptor.mipFilter = .notMipmapped
        nearestSamplerDescriptor.sAddressMode = .clampToEdge
        nearestSamplerDescriptor.tAddressMode = .clampToEdge

        guard let linearSampler = device.makeSamplerState(descriptor: linearSamplerDescriptor),
              let nearestSampler = device.makeSamplerState(descriptor: nearestSamplerDescriptor) else {
            throw RendererCoordinatorError.pipelineCreationFailed
        }

        return (pipelineState, linearSampler, nearestSampler)
    }

    private static func loadPresentShaderSource() throws -> String {
        let resourceLocations: [(name: String, subdirectory: String?)] = [
            ("Present", "Rendering/Shaders"),
            ("Present", "Shaders"),
            ("Present", nil)
        ]

        for location in resourceLocations {
            if let url = Bundle.module.url(
                forResource: location.name,
                withExtension: "metal",
                subdirectory: location.subdirectory
            ),
               let source = try? String(contentsOf: url, encoding: .utf8) {
                return source
            }
        }

        // Guaranteed fallback to keep startup resilient when SPM resource path differs.
        return """
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
    return float4(max(sharpened, float3(0.0)), 1.0);
}
"""
    }

    private func ensureReusableTexture(
        texture: inout MTLTexture?,
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat
    ) -> MTLTexture? {
        if let texture,
           texture.width == width,
           texture.height == height,
           texture.pixelFormat == pixelFormat {
            return texture
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private

        texture = context.device.makeTexture(descriptor: descriptor)
        return texture
    }

    private func encodeTextureCopy(
        commandBuffer: MTLCommandBuffer,
        from sourceTexture: MTLTexture,
        to destinationTexture: MTLTexture
    ) {
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            return
        }

        blit.copy(
            from: sourceTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: sourceTexture.width, height: sourceTexture.height, depth: 1),
            to: destinationTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )

        blit.endEncoding()
    }

    private func stageCurrentFrameTexture(
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture
    ) -> MTLTexture? {
        let oldCurrentTexture = currentFrameTexture
        let sizeChanged = oldCurrentTexture == nil ||
            oldCurrentTexture?.width != sourceTexture.width ||
            oldCurrentTexture?.height != sourceTexture.height ||
            oldCurrentTexture?.pixelFormat != sourceTexture.pixelFormat

        guard let currentTexture = ensureReusableTexture(
            texture: &currentFrameTexture,
            width: sourceTexture.width,
            height: sourceTexture.height,
            pixelFormat: sourceTexture.pixelFormat
        ) else {
            return nil
        }

        if !sizeChanged, let oldCurrentTexture {
            guard let previousTexture = ensureReusableTexture(
                texture: &previousFrameTexture,
                width: oldCurrentTexture.width,
                height: oldCurrentTexture.height,
                pixelFormat: oldCurrentTexture.pixelFormat
            ) else {
                return nil
            }

            encodeTextureCopy(
                commandBuffer: commandBuffer,
                from: oldCurrentTexture,
                to: previousTexture
            )
        } else {
            previousFrameTexture = nil
            interpolatedBlendQueue.removeAll(keepingCapacity: true)
        }

        encodeTextureCopy(
            commandBuffer: commandBuffer,
            from: sourceTexture,
            to: currentTexture
        )

        return currentTexture
    }

    private func rebuildInterpolatedBlendQueue(mode: FrameGenerationMode) {
        interpolatedBlendQueue.removeAll(keepingCapacity: true)
        switch mode {
        case .x2:
            interpolatedBlendQueue.append(0.5)
        case .x3:
            interpolatedBlendQueue.append(contentsOf: [Float(1.0 / 3.0), Float(2.0 / 3.0)])
        }
    }

    private func clearInterpolatedBlendQueue() {
        interpolatedBlendQueue.removeAll(keepingCapacity: true)
    }

    private func presentationScale(
        sourceTexture: MTLTexture,
        drawableSize: CGSize
    ) -> SIMD2<Float> {
        let sourceAspect = Float(sourceTexture.width) / Float(max(1, sourceTexture.height))
        let drawableAspect = Float(drawableSize.width) / Float(max(1, drawableSize.height))

        if sourceAspect > drawableAspect {
            return SIMD2<Float>(1.0, drawableAspect / sourceAspect)
        }

        return SIMD2<Float>(sourceAspect / drawableAspect, 1.0)
    }

    private func captureDeltaTime(for timestamp: CMTime) -> Float {
        let delta: Float
        if let previous = lastCaptureTimestamp {
            let diff = CMTimeSubtract(timestamp, previous)
            let seconds = CMTimeGetSeconds(diff)
            if seconds.isFinite, seconds > 0 {
                delta = Float(seconds)
            } else {
                delta = 1.0 / 60.0
            }
        } else {
            delta = 1.0 / 60.0
        }

        lastCaptureTimestamp = timestamp
        return max(1.0 / 240.0, delta)
    }

    private func updatePresentFrameTime() {
        let now = CACurrentMediaTime()
        if let lastPresentHostTime {
            let delta = max(1.0 / 240.0, now - lastPresentHostTime)
            smoothedPresentFrameTime = (smoothedPresentFrameTime * 0.9) + (delta * 0.1)
        }
        lastPresentHostTime = now
    }

    private func effectiveScale(for settings: RenderSettings) -> Float {
        let baseScale = max(0.5, min(settings.outputScale, 3.0))

        guard settings.dynamicResolutionEnabled else {
            dynamicScaleFactor = 1.0
            return baseScale
        }

        let targetFPS = Double(max(settings.targetPresentationFPS, 30))
        let targetFrameTime = 1.0 / targetFPS

        if smoothedPresentFrameTime > (targetFrameTime * 1.06) {
            dynamicScaleFactor -= 0.02
        } else if smoothedPresentFrameTime < (targetFrameTime * 0.92) {
            dynamicScaleFactor += 0.01
        }

        dynamicScaleFactor = max(settings.dynamicScaleMinimum, min(dynamicScaleFactor, settings.dynamicScaleMaximum))
        return baseScale * dynamicScaleFactor
    }

    private func preferredPresentationFPS(for settings: RenderSettings) -> Int {
        let userTarget = max(settings.targetPresentationFPS, 1)
        let fallbackCaptureFPS = max(captureConfiguration.framesPerSecond, 1)
        let estimatedCaptureFPS = Int(
            (1.0 / Double(max(lastCaptureDeltaTime, 1.0 / 240.0))).rounded()
        )
        let captureFPS = max(estimatedCaptureFPS, fallbackCaptureFPS)

        guard settings.frameGenerationEnabled else {
            // Without FG we intentionally pace presentation to capture FPS.
            return min(userTarget, captureFPS)
        }

        let multiplier = settings.frameGenerationMode == .x2 ? 2 : 3
        let generatedTarget = captureFPS * multiplier
        return min(userTarget, generatedTarget)
    }

    private func upscaleIfNeeded(
        commandBuffer: MTLCommandBuffer,
        inputTexture: MTLTexture,
        settings: RenderSettings,
        scale: Float
    ) -> MTLTexture {
        let outputWidth = max(1, Int(Float(inputTexture.width) * scale))
        let outputHeight = max(1, Int(Float(inputTexture.height) * scale))

        switch settings.upscalingAlgorithm {
        case .nativeLinear:
            return inputTexture

        case .metalFXSpatial:
            guard let outputTexture = ensureReusableTexture(
                texture: &upscaledScratchTexture,
                width: outputWidth,
                height: outputHeight,
                pixelFormat: inputTexture.pixelFormat
            ) else {
                return inputTexture
            }

            do {
                try upscaler.encode(
                    commandBuffer: commandBuffer,
                    inputTexture: inputTexture,
                    outputTexture: outputTexture
                )
                return outputTexture
            } catch {
                NSLog("MetalFX spatial upscaling failed, falling back to native linear: \(error.localizedDescription)")
                return inputTexture
            }
        }
    }

    private func resolvePresentationTextures(
        commandBuffer: MTLCommandBuffer,
        settings: RenderSettings,
        deltaTime: Float
    ) -> (primary: MTLTexture, secondary: MTLTexture, blendFactor: Float)? {
        guard let currentTexture = currentFrameTexture else {
            return nil
        }

        guard settings.frameGenerationEnabled else {
            return (currentTexture, currentTexture, 0.0)
        }

        if frameGenerationEngine.isSupported,
           let previousTexture = previousFrameTexture,
           let auxiliary = frameGenerationAuxiliaryProvider?() {
            do {
                let interpolated = try frameGenerationEngine.interpolate(
                    commandBuffer: commandBuffer,
                    previousTexture: previousTexture,
                    currentTexture: currentTexture,
                    auxiliary: auxiliary,
                    deltaTime: deltaTime
                )
                return (interpolated, interpolated, 0.0)
            } catch {
                NSLog("MetalFX frame interpolation skipped: \(error.localizedDescription)")
            }
        }

        guard let previousTexture = previousFrameTexture else {
            return (currentTexture, currentTexture, 0.0)
        }

        if !loggedFallbackFrameGeneration {
            NSLog("Frame generation fallback active: blend interpolation mode")
            loggedFallbackFrameGeneration = true
        }

        if let blend = interpolatedBlendQueue.first {
            interpolatedBlendQueue.removeFirst()
            return (previousTexture, currentTexture, max(0.0, min(blend, 1.0)))
        }

        return (currentTexture, currentTexture, 0.0)
    }

    private func publishStatsIfNeeded(
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        effectiveScale: Float
    ) {
        let now = CACurrentMediaTime()

        statsLock.lock()
        presentFrameCounter += 1

        let elapsed = now - fpsWindowStart
        if elapsed >= 1.0 {
            let captureFPS = Double(captureFrameCounter) / elapsed
            let presentFPS = Double(presentFrameCounter) / elapsed
            captureFrameCounter = 0
            presentFrameCounter = 0
            fpsWindowStart = now
            statsLock.unlock()

            onStatsUpdate?(RendererStats(
                isRunning: running,
                captureFPS: captureFPS,
                presentFPS: presentFPS,
                inputSize: CGSize(width: inputTexture.width, height: inputTexture.height),
                outputSize: CGSize(width: outputTexture.width, height: outputTexture.height),
                effectiveScale: effectiveScale
            ))

            return
        }

        statsLock.unlock()
    }
}

extension RendererCoordinator: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        _ = size
    }

    func draw(in view: MTKView) {
        guard let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        updatePresentFrameTime()

        guard running,
              let frameSnapshot = snapshotLatestFrame() else {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                encoder.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        let settings = settingsStore.snapshot()
        let targetPresentationFPS = preferredPresentationFPS(for: settings)

        if view.preferredFramesPerSecond != targetPresentationFPS {
            view.preferredFramesPerSecond = targetPresentationFPS
        }

        if frameSnapshot.sequence != processedFrameSequence {
            let scale = effectiveScale(for: settings)
            let upscaled = upscaleIfNeeded(
                commandBuffer: commandBuffer,
                inputTexture: frameSnapshot.frame.texture,
                settings: settings,
                scale: scale
            )

            if let stagedTexture = stageCurrentFrameTexture(
                commandBuffer: commandBuffer,
                sourceTexture: upscaled
            ) {
                processedFrameSequence = frameSnapshot.sequence
                lastCaptureDeltaTime = captureDeltaTime(for: frameSnapshot.frame.timestamp)
                lastInputTexture = frameSnapshot.frame.texture
                lastOutputTexture = stagedTexture
                lastEffectiveScale = scale

                if settings.frameGenerationEnabled, previousFrameTexture != nil {
                    rebuildInterpolatedBlendQueue(mode: settings.frameGenerationMode)
                } else {
                    clearInterpolatedBlendQueue()
                }
            }
        } else if !settings.frameGenerationEnabled {
            clearInterpolatedBlendQueue()
        }

        guard let presentation = resolvePresentationTextures(
            commandBuffer: commandBuffer,
            settings: settings,
            deltaTime: lastCaptureDeltaTime
        ) else {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                encoder.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        encoder.setRenderPipelineState(renderPipelineState)

        var uniforms = PresentUniforms(
            contentScale: presentationScale(sourceTexture: presentation.primary, drawableSize: view.drawableSize),
            texelSize: SIMD2<Float>(
                1.0 / Float(max(1, presentation.primary.width)),
                1.0 / Float(max(1, presentation.primary.height))
            ),
            sharpness: max(0.0, min(settings.sharpness, 1.0)),
            blendFactor: presentation.blendFactor
        )

        encoder.setVertexBytes(&uniforms, length: MemoryLayout<PresentUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PresentUniforms>.stride, index: 0)
        encoder.setFragmentTexture(presentation.primary, index: 0)
        encoder.setFragmentTexture(presentation.secondary, index: 1)

        let sampler = settings.samplingMode == .nearest ? nearestSampler : linearSampler
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        let inputForStats = lastInputTexture ?? frameSnapshot.frame.texture
        let outputForStats = lastOutputTexture ?? presentation.primary
        publishStatsIfNeeded(
            inputTexture: inputForStats,
            outputTexture: outputForStats,
            effectiveScale: lastEffectiveScale
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
