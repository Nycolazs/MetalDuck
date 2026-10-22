import CoreMedia
import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

private struct PresentUniforms {
    var contentScale: SIMD2<Float>
    var texelSize: SIMD2<Float>
    var sharpness: Float
    var blendFactor: Float
}

struct RendererStats {
    var isRunning: Bool
    var frameGenerationEnabled: Bool
    var sourceFPS: Double
    var captureFPS: Double
    var presentFPS: Double
    var generatedFPS: Double
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
    var onGeometryUpdate: ((CGRect) -> Void)?
    var onError: ((Error) -> Void)?

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
    private var rawCaptureFrameCounter: Int = 0
    private var presentFrameCounter: Int = 0
    private var generatedFrameCounter: Int = 0
    private var fpsWindowStart: CFTimeInterval = CACurrentMediaTime()

    private var latestFrameArrival: CFTimeInterval = 0

    private var upscaledScratchTexture: MTLTexture?
    private var secondaryUpscaledScratchTexture: MTLTexture?
    private var currentFrameTexture: MTLTexture?

    /// A capture copied into a staging slot, kept so output can trail capture by a fixed delay.
    private struct BufferedFrame {
        let slot: Int
        let id: UInt64
        let time: CFTimeInterval
        let flowFrame: VisionFlowProvider.FlowFrame?
    }

    private static let stagingSlots = 5
    /// Longer gaps mean the source was idle; only the last stretch of them is interpolated.
    private static let maxInterpolationSpan: Double = 0.1
    private var stagedFrameTextures: [MTLTexture?] = Array(repeating: nil, count: stagingSlots)
    private var stagedFrameWriteIndex: Int = 0
    private var bufferedFrames: [BufferedFrame] = []
    private var nextFrameID: UInt64 = 0
    private var captureInterval: Double = 1.0 / 60.0
    private var recentCaptureIntervals: [Double] = []
    private var presentationDelay: Double = 0
    private let presentClock = PresentClock()
    private var preferredScreenRate = 60
    private var lastShownFrameID: UInt64?
    private var latestCaptureTime: CFTimeInterval = 0
    /// The source moment the frame being drawn depicts.
    private var presentedContentTime: CFTimeInterval = 0

    private var lastInputTexture: MTLTexture?
    private var lastOutputTexture: MTLTexture?
    private var lastEffectiveScale: Float = 1.0

    private var renderPipelineState: MTLRenderPipelineState
    private var linearSampler: MTLSamplerState
    private var nearestSampler: MTLSamplerState
    private var library: MTLLibrary

    private var running = false
    private var smoothedPresentFrameTime: Double = 1.0 / 60.0
    private var lastPresentHostTime: CFTimeInterval?
    private var dynamicScaleFactor: Float = 1.0
    private var loggedMetalFXFailure = false

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
        let (pipelineState, linearSampler, nearestSampler, lib) = try Self.buildPresentationResources(
            device: context.device,
            pixelFormat: .bgra8Unorm
        )
        self.frameGenerationEngine = MetalFXFrameGenerationEngine(device: context.device, commandQueue: context.commandQueue, library: lib)

        self.renderPipelineState = pipelineState
        self.linearSampler = linearSampler
        self.nearestSampler = nearestSampler
        self.library = lib

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
        frameGenerationEngine.reset()
        lastPresentHostTime = nil
        smoothedPresentFrameTime = 1.0 / 60.0
        dynamicScaleFactor = 1.0
        let settings = settingsStore.snapshot()
        PipelineLog.shared.logSessionRunning(
            settings: settings,
            capture: captureConfiguration,
            target: activeCaptureTarget
        )
    }

    @MainActor
    func stop() async {
        await captureService.stop()
        running = false
        let settings = settingsStore.snapshot()
        PipelineLog.shared.flush(
            reason: "session stopped",
            settings: settings,
            configuredCaptureFPS: captureConfiguration.framesPerSecond,
            targetPresentFPS: preferredPresentationFPS(for: settings)
        )
        resetFrameState()
        frameGenerationEngine.reset()
    }

    @MainActor
    func reconfigureCapture(target: CaptureTarget) async throws {
        activeCaptureTarget = target
        try await captureService.reconfigure(target: target)
    }

    @MainActor
    func reconfigureCapture(configuration: CaptureConfiguration) async throws {
        captureConfiguration = configuration
        try await captureService.reconfigure(configuration: configuration)
        updateViewFPS()
    }

    @MainActor
    private func updateViewFPS() {
        guard let view = self.view else { return }
        let settings = settingsStore.snapshot()
        let targetFPS = preferredPresentationFPS(for: settings)
        if view.preferredFramesPerSecond != targetFPS {
            view.preferredFramesPerSecond = targetFPS
        }
    }

    @MainActor
    private func configure(view: MTKView) {
        view.device = context.device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1.0)
        view.framebufferOnly = false
        // IMPORTANT: Start at 120fps to ensure the render loop runs fast enough
        // to display interpolated intermediate frames. The capture rate is separate.
        let initialSettings = settingsStore.snapshot()
        view.preferredFramesPerSecond = preferredPresentationFPS(for: initialSettings)
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = self
    }

    private func installCaptureCallbacks() {
        captureService.onFrame = { [weak self] frame in
            guard let self else { return }

            let arrival = CACurrentMediaTime()
            self.frameLock.lock()
            self.latestFrame = frame
            self.latestFrameArrival = arrival
            self.latestFrameSequence &+= 1
            self.frameLock.unlock()

            self.statsLock.lock()
            self.rawCaptureFrameCounter += 1
            self.statsLock.unlock()

            self.onGeometryUpdate?(frame.targetRect)
        }

        captureService.onError = { [weak self] error in
            PipelineLog.shared.event("capture", "stream stopped with error: \(error.localizedDescription)")
            if let self {
                let settings = self.settingsStore.snapshot()
                PipelineLog.shared.flush(
                    reason: "capture error",
                    settings: settings,
                    configuredCaptureFPS: self.captureConfiguration.framesPerSecond,
                    targetPresentFPS: self.preferredPresentationFPS(for: settings)
                )
            }
            self?.running = false
            self?.onError?(error)
        }
    }

    private func snapshotLatestFrame() -> (frame: CapturedFrame, sequence: UInt64, arrival: CFTimeInterval)? {
        frameLock.lock()
        defer { frameLock.unlock() }
        guard let latestFrame else {
            return nil
        }
        return (latestFrame, latestFrameSequence, latestFrameArrival)
    }

    private func resetFrameState() {
        frameLock.lock()
        latestFrame = nil
        latestFrameSequence = 0
        processedFrameSequence = 0
        frameLock.unlock()

        upscaledScratchTexture = nil
        secondaryUpscaledScratchTexture = nil
        stagedFrameTextures = Array(repeating: nil, count: Self.stagingSlots)
        stagedFrameWriteIndex = 0
        bufferedFrames.removeAll()
        captureInterval = 1.0 / Double(max(captureConfiguration.framesPerSecond, 1))
        recentCaptureIntervals.removeAll()
        presentationDelay = 0
        presentClock.reset()
        lastShownFrameID = nil
        currentFrameTexture = nil
        lastInputTexture = nil
        lastOutputTexture = nil
        lastEffectiveScale = 1.0

        statsLock.lock()
        rawCaptureFrameCounter = 0
        presentFrameCounter = 0
        generatedFrameCounter = 0
        fpsWindowStart = CACurrentMediaTime()
        statsLock.unlock()
    }

    private static func buildPresentationResources(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat
    ) throws -> (MTLRenderPipelineState, MTLSamplerState, MTLSamplerState, MTLLibrary) {
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

        return (pipelineState, linearSampler, nearestSampler, library)
    }

    private static func loadPresentShaderSource() throws -> String {
        let resourceLocations: [(name: String, subdirectory: String?)] = [
            ("Present", "Rendering/Shaders"),
            ("Present", "Shaders"),
            ("Present", nil)
        ]

        if let bundle = Bundle.safeModule {
            for location in resourceLocations {
                if let url = bundle.url(
                    forResource: location.name,
                    withExtension: "metal",
                    subdirectory: location.subdirectory
                ),
                   let source = try? String(contentsOf: url, encoding: .utf8) {
                    return source
                }
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
    float3 color = clamp(sharpened, float3(0.0), float3(1.0));
    return float4(color, 1.0);
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

    private func encodeNativeResample(
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture,
        destinationTexture: MTLTexture,
        samplingMode: SamplingMode
    ) {
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = destinationTexture
        renderPass.colorAttachments[0].loadAction = .dontCare
        renderPass.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            return
        }

        encoder.setRenderPipelineState(renderPipelineState)

        var uniforms = PresentUniforms(
            contentScale: SIMD2<Float>(1.0, 1.0),
            texelSize: SIMD2<Float>(
                1.0 / Float(max(1, sourceTexture.width)),
                1.0 / Float(max(1, sourceTexture.height))
            ),
            sharpness: 0.0,
            blendFactor: 0.0
        )

        encoder.setVertexBytes(&uniforms, length: MemoryLayout<PresentUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PresentUniforms>.stride, index: 0)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentTexture(sourceTexture, index: 1)

        let sampler = samplingMode == .nearest ? nearestSampler : linearSampler
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func stageCurrentFrameTexture(
        commandBuffer: MTLCommandBuffer,
        frame: CapturedFrame,
        arrival: CFTimeInterval,
        frameGenerationEnabled: Bool
    ) -> MTLTexture? {
        let sourceTexture = frame.texture
        latestCaptureTime = captureTime(for: frame.timestamp, arrival: arrival)
        if !frameGenerationEnabled {
            currentFrameTexture = sourceTexture
            bufferedFrames.removeAll()
            return sourceTexture
        }

        let slot = stagedFrameWriteIndex
        bufferedFrames.removeAll { $0.slot == slot }
        if let newest = bufferedFrames.last,
           let newestTexture = stagedFrameTextures[newest.slot],
           newestTexture.width != sourceTexture.width ||
           newestTexture.height != sourceTexture.height ||
           newestTexture.pixelFormat != sourceTexture.pixelFormat {
            bufferedFrames.removeAll()
        }

        guard let writeTexture = ensureStagedTexture(
            index: slot,
            width: sourceTexture.width,
            height: sourceTexture.height,
            pixelFormat: sourceTexture.pixelFormat
        ) else {
            return nil
        }

        encodeTextureCopy(
            commandBuffer: commandBuffer,
            from: sourceTexture,
            to: writeTexture
        )

        var time = latestCaptureTime
        if let newest = bufferedFrames.last {
            time = max(time, newest.time + 0.001)
            let delta = time - newest.time
            if delta < Self.maxInterpolationSpan * 2.5 {
                recentCaptureIntervals.append(delta)
                if recentCaptureIntervals.count > 24 {
                    recentCaptureIntervals.removeFirst(recentCaptureIntervals.count - 24)
                }
                // A high percentile, so the next capture has nearly always arrived by the
                // time output reaches it, even when the source cadence wobbles.
                let sorted = recentCaptureIntervals.sorted()
                let upper = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.85))]
                captureInterval = min(max(upper, 1.0 / 240.0), Self.maxInterpolationSpan)
            }
        }

        nextFrameID &+= 1
        let flowFrame = frameGenerationEngine.prepareFlowFrame(
            from: writeTexture,
            id: nextFrameID,
            time: time,
            commandBuffer: commandBuffer
        )
        if let flowFrame, let previousFlowFrame = bufferedFrames.last?.flowFrame {
            frameGenerationEngine.requestFlow(previous: previousFlowFrame, next: flowFrame, after: commandBuffer)
        }

        bufferedFrames.append(BufferedFrame(slot: slot, id: nextFrameID, time: time, flowFrame: flowFrame))
        if bufferedFrames.count > Self.stagingSlots {
            bufferedFrames.removeFirst(bufferedFrames.count - Self.stagingSlots)
        }
        stagedFrameWriteIndex = (slot + 1) % Self.stagingSlots
        currentFrameTexture = writeTexture
        return writeTexture
    }

    /// Capture time on the host clock. ScreenCaptureKit stamps frames with it; anything else
    /// that looks off falls back to when the frame reached us.
    private func captureTime(for timestamp: CMTime, arrival: CFTimeInterval) -> CFTimeInterval {
        let seconds = CMTimeGetSeconds(timestamp)
        if seconds.isFinite, abs(arrival - seconds) < 0.25 {
            return seconds
        }
        return arrival
    }

    private func ensureStagedTexture(
        index: Int,
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat
    ) -> MTLTexture? {
        if let texture = stagedFrameTextures[index],
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

        let texture = context.device.makeTexture(descriptor: descriptor)
        stagedFrameTextures[index] = texture
        return texture
    }

    private func presentationScale(
        sourceTexture: MTLTexture,
        drawableSize: CGSize
    ) -> SIMD2<Float> {
        let sourceAspect = Float(sourceTexture.width) / Float(max(1, sourceTexture.height))
        let drawableAspect = Float(drawableSize.width) / Float(max(1, drawableSize.height))

        // Fill output to avoid visible black bars; this crops the longer axis.
        if sourceAspect > drawableAspect {
            return SIMD2<Float>(sourceAspect / drawableAspect, 1.0)
        }

        return SIMD2<Float>(1.0, drawableAspect / sourceAspect)
    }

    private func updatePresentFrameTime() {
        let now = CACurrentMediaTime()
        if let lastPresentHostTime {
            let delta = max(1.0 / 240.0, now - lastPresentHostTime)
            smoothedPresentFrameTime = (smoothedPresentFrameTime * 0.9) + (delta * 0.1)
        }
        lastPresentHostTime = now
    }

    private func effectiveScale(
        for settings: RenderSettings,
        inputTexture: MTLTexture,
        drawableSize: CGSize
    ) -> Float {
        let manualScale = max(0.5, min(settings.outputScale, 3.0))
        let baseScale: Float

        if settings.matchOutputResolution {
            let drawableWidth = max(1.0, Float(drawableSize.width))
            let drawableHeight = max(1.0, Float(drawableSize.height))
            let scaleX = drawableWidth / Float(max(1, inputTexture.width))
            let scaleY = drawableHeight / Float(max(1, inputTexture.height))
            // In match mode, keep fit-to-window as the base and allow manualScale
            // as a multiplicative bias so user changes always have visible effect.
            let fitScale = max(0.5, min(min(scaleX, scaleY), 3.0))
            baseScale = max(0.5, min(fitScale * manualScale, 3.0))
        } else {
            baseScale = manualScale
        }

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
        let configuredCaptureFPS = max(captureConfiguration.framesPerSecond, 1)

        guard settings.frameGenerationEnabled else {
            return userTarget
        }

        let multiplier: Int
        switch settings.frameGenerationMode {
        case .x2: multiplier = 2
        case .x3: multiplier = 3
        case .x4: multiplier = 4
        }
        
        let fgCeiling = configuredCaptureFPS * multiplier
        return min(userTarget, fgCeiling)
    }

    private func upscaleIfNeeded(
        commandBuffer: MTLCommandBuffer,
        inputTexture: MTLTexture,
        scratchBuffer: inout MTLTexture?,
        settings: RenderSettings,
        scale: Float
    ) -> (texture: MTLTexture, fellBack: Bool) {
        let outputWidth = max(1, Int(Float(inputTexture.width) * scale))
        let outputHeight = max(1, Int(Float(inputTexture.height) * scale))

        if outputWidth == inputTexture.width, outputHeight == inputTexture.height {
            return (inputTexture, false)
        }

        switch settings.upscalingAlgorithm {
        case .nativeLinear:
            guard let outputTexture = ensureReusableTexture(
                texture: &scratchBuffer,
                width: outputWidth,
                height: outputHeight,
                pixelFormat: inputTexture.pixelFormat
            ) else {
                return (inputTexture, false)
            }

            encodeNativeResample(
                commandBuffer: commandBuffer,
                sourceTexture: inputTexture,
                destinationTexture: outputTexture,
                samplingMode: settings.samplingMode
            )
            return (outputTexture, false)

        case .metalFXSpatial, .metalFXTemporal:
            guard let outputTexture = ensureReusableTexture(
                texture: &scratchBuffer,
                width: outputWidth,
                height: outputHeight,
                pixelFormat: inputTexture.pixelFormat
            ) else {
                return (inputTexture, true)
            }

            do {
                try upscaler.encode(
                    commandBuffer: commandBuffer,
                    inputTexture: inputTexture,
                    outputTexture: outputTexture
                )
                return (outputTexture, false)
            } catch {
                if !loggedMetalFXFailure {
                    loggedMetalFXFailure = true
                    PipelineLog.shared.event("upscale", "MetalFX failed: \(error.localizedDescription)")
                }
                return (inputTexture, true)
            }
        }
    }

    private func resolvePresentationTextures(
        commandBuffer: MTLCommandBuffer,
        settings: RenderSettings
    ) -> (primary: MTLTexture, secondary: MTLTexture, blendFactor: Float, isGenerated: Bool)? {
        guard let currentTexture = currentFrameTexture else { return nil }
        presentedContentTime = latestCaptureTime

        guard settings.frameGenerationEnabled, bufferedFrames.count >= 2 else {
            PipelineLog.shared.notePresent(.passthrough)
            return (currentTexture, currentTexture, 0.0, false)
        }

        // Output trails capture by one interval plus the time flow takes, so the pair around
        // the displayed moment is already captured and usually already has its own flow.
        // The ring only reaches a few captures back, which caps the delay.
        let flowLatency = min(max(frameGenerationEngine.flowReadyLatency, 0), 0.05)
        let targetDelay = min(captureInterval + flowLatency + 0.004, captureInterval * Double(Self.stagingSlots - 2))
        // Any change in delay shows up as a change in speed, so it only drifts slowly
        // (about 3% of real time) unless it is far off.
        if presentationDelay == 0 || abs(targetDelay - presentationDelay) > 0.03 {
            presentationDelay = targetDelay
        } else {
            presentationDelay += min(max(targetDelay - presentationDelay, -0.00025), 0.00025)
        }
        let displayTime = presentClock.alignedNow(period: 1.0 / Double(max(1, preferredScreenRate))) - presentationDelay

        guard let index = bufferedFrames.lastIndex(where: { $0.time <= displayTime }),
              index < bufferedFrames.count - 1 else {
            let shown = displayTime < bufferedFrames[0].time ? bufferedFrames[0] : bufferedFrames[bufferedFrames.count - 1]
            presentedContentTime = shown.time
            return presentCapturedFrame(shown) ?? (currentTexture, currentTexture, 0.0, false)
        }

        let older = bufferedFrames[index]
        let newer = bufferedFrames[index + 1]
        guard let olderTexture = stagedFrameTextures[older.slot],
              let newerTexture = stagedFrameTextures[newer.slot] else {
            PipelineLog.shared.notePresent(.passthrough)
            return (currentTexture, currentTexture, 0.0, false)
        }

        presentedContentTime = displayTime
        let start = max(older.time, newer.time - Self.maxInterpolationSpan)
        let t = Float(min(max((displayTime - start) / max(newer.time - start, 0.001), 0), 1))
        if t <= 0.02 {
            return presentCapturedFrame(older) ?? (olderTexture, olderTexture, 0.0, false)
        }
        if t >= 0.98 {
            return presentCapturedFrame(newer) ?? (newerTexture, newerTexture, 0.0, false)
        }
        lastShownFrameID = nil

        switch frameGenerationEngine.attemptInterpolation(
            commandBuffer: commandBuffer,
            previous: GenerationFrame(texture: olderTexture, id: older.id),
            next: GenerationFrame(texture: newerTexture, id: newer.id),
            t: t
        ) {
        case .produced(let interpolated, let flowWidth, let flowHeight, let flowFrameID, let latestCaptureID):
            PipelineLog.shared.notePresent(.flow(
                t: t,
                flowWidth: flowWidth,
                flowHeight: flowHeight,
                flowFrameID: flowFrameID,
                latestCaptureID: latestCaptureID
            ))
            return (interpolated, interpolated, 0.0, true)
        case .failed(let reason):
            PipelineLog.shared.notePresent(.blend(t: t, reason: reason))
            return (olderTexture, newerTexture, t, true)
        }
    }

    private func presentCapturedFrame(
        _ frame: BufferedFrame
    ) -> (primary: MTLTexture, secondary: MTLTexture, blendFactor: Float, isGenerated: Bool)? {
        guard let texture = stagedFrameTextures[frame.slot] else { return nil }
        PipelineLog.shared.notePresent(lastShownFrameID == frame.id ? .repeated : .passthrough)
        lastShownFrameID = frame.id
        return (texture, texture, 0.0, false)
    }

    private func publishStatsIfNeeded(
        frameGenerationEnabled: Bool,
        isGeneratedFrame: Bool,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture,
        effectiveScale: Float
    ) {
        let now = CACurrentMediaTime()

        statsLock.lock()
        presentFrameCounter += 1
        if isGeneratedFrame {
            generatedFrameCounter += 1
        }

        let elapsed = now - fpsWindowStart
        if elapsed >= 1.0 {
            let captureFPS = Double(rawCaptureFrameCounter) / elapsed
            let presentFPS = Double(presentFrameCounter) / elapsed
            let generatedFPS = Double(generatedFrameCounter) / elapsed
            let sourceFPS = captureFPS
            rawCaptureFrameCounter = 0
            presentFrameCounter = 0
            generatedFrameCounter = 0
            fpsWindowStart = now
            statsLock.unlock()

            onStatsUpdate?(RendererStats(
                isRunning: running,
                frameGenerationEnabled: frameGenerationEnabled,
                sourceFPS: sourceFPS,
                captureFPS: captureFPS,
                presentFPS: presentFPS,
                generatedFPS: generatedFPS,
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
        let drawStart = CACurrentMediaTime()
        defer {
            if running {
                let settings = settingsStore.snapshot()
                PipelineLog.shared.finishFrame(
                    drawMilliseconds: (CACurrentMediaTime() - drawStart) * 1000,
                    settings: settings,
                    configuredCaptureFPS: captureConfiguration.framesPerSecond,
                    targetPresentFPS: preferredPresentationFPS(for: settings)
                )
            }
        }

        guard let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        updatePresentFrameTime()

        guard running else {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                encoder.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        let settings = settingsStore.snapshot()
        
        let targetFPS = preferredPresentationFPS(for: settings)
        if view.preferredFramesPerSecond != targetFPS {
            view.preferredFramesPerSecond = targetFPS
        }

        let frameSnapshot = snapshotLatestFrame()
        if let frameSnapshot, frameSnapshot.sequence != processedFrameSequence {
            if stageCurrentFrameTexture(
                commandBuffer: commandBuffer,
                frame: frameSnapshot.frame,
                arrival: frameSnapshot.arrival,
                frameGenerationEnabled: settings.frameGenerationEnabled
            ) != nil {
                processedFrameSequence = frameSnapshot.sequence
                lastInputTexture = frameSnapshot.frame.texture

                lastEffectiveScale = effectiveScale(
                    for: settings,
                    inputTexture: frameSnapshot.frame.texture,
                    drawableSize: view.drawableSize
                )
            }
        }

        guard let presentation = resolvePresentationTextures(
            commandBuffer: commandBuffer,
            settings: settings
        ) else {
            PipelineLog.shared.notePresent(.noFrame)
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                encoder.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        // Now upscale the presentation textures (either the real frame or the generated frame)
        let scale = effectiveScale(
            for: settings,
            inputTexture: presentation.primary,
            drawableSize: view.drawableSize
        )
        
        let primaryUpscale = upscaleIfNeeded(
            commandBuffer: commandBuffer,
            inputTexture: presentation.primary,
            scratchBuffer: &upscaledScratchTexture,
            settings: settings,
            scale: scale
        )
        let finalPrimary = primaryUpscale.texture

        let finalSecondary: MTLTexture
        let secondaryFellBack: Bool
        if presentation.secondary === presentation.primary {
            finalSecondary = finalPrimary
            secondaryFellBack = false
        } else {
            let secondaryUpscale = upscaleIfNeeded(
                commandBuffer: commandBuffer,
                inputTexture: presentation.secondary,
                scratchBuffer: &secondaryUpscaledScratchTexture,
                settings: settings,
                scale: scale
            )
            finalSecondary = secondaryUpscale.texture
            secondaryFellBack = secondaryUpscale.fellBack
        }

        let upscaleAlgorithm: String
        if !primaryUpscale.fellBack,
           finalPrimary.width == presentation.primary.width,
           finalPrimary.height == presentation.primary.height {
            upscaleAlgorithm = "identity"
        } else {
            upscaleAlgorithm = settings.upscalingAlgorithm.rawValue
        }
        PipelineLog.shared.noteUpscale(
            algorithm: upscaleAlgorithm,
            inputWidth: presentation.primary.width,
            inputHeight: presentation.primary.height,
            outputWidth: finalPrimary.width,
            outputHeight: finalPrimary.height,
            fellBack: primaryUpscale.fellBack || secondaryFellBack
        )

        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        encoder.setRenderPipelineState(renderPipelineState)
        lastOutputTexture = finalPrimary

        var uniforms = PresentUniforms(
            contentScale: presentationScale(sourceTexture: finalPrimary, drawableSize: view.drawableSize),
            texelSize: SIMD2<Float>(
                1.0 / Float(max(1, finalPrimary.width)),
                1.0 / Float(max(1, finalPrimary.height))
            ),
            sharpness: max(0.0, min(settings.sharpness, 1.0)),
            blendFactor: presentation.blendFactor
        )

        encoder.setVertexBytes(&uniforms, length: MemoryLayout<PresentUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PresentUniforms>.stride, index: 0)
        encoder.setFragmentTexture(finalPrimary, index: 0)
        encoder.setFragmentTexture(finalSecondary, index: 1)

        let sampler = settings.samplingMode == .nearest ? nearestSampler : linearSampler
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        let inputForStats = lastInputTexture ?? presentation.primary
        let outputForStats = lastOutputTexture ?? presentation.primary
        publishStatsIfNeeded(
            frameGenerationEnabled: settings.frameGenerationEnabled,
            isGeneratedFrame: presentation.isGenerated,
            inputTexture: inputForStats,
            outputTexture: outputForStats,
            effectiveScale: lastEffectiveScale
        )

        let contentTime = presentedContentTime
        let screenFPS = view.window?.screen?.maximumFramesPerSecond ?? targetFPS
        preferredScreenRate = min(targetFPS, screenFPS)
        let expectedInterval = 1.0 / Double(max(1, preferredScreenRate))
        let clock = presentClock
        drawable.addPresentedHandler { presented in
            clock.notePresented(presented.presentedTime)
            PipelineLog.shared.notePresented(
                presentedTime: presented.presentedTime,
                contentTime: contentTime,
                expectedInterval: expectedInterval
            )
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

/// Tracks when drawables actually reach the screen, so output time can follow the display's
/// refresh grid instead of whenever the draw callback happened to run.
private final class PresentClock: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPresented: CFTimeInterval = 0

    func notePresented(_ time: CFTimeInterval) {
        guard time > 0 else { return }
        lock.lock()
        lastPresented = time
        lock.unlock()
    }

    func reset() {
        lock.lock()
        lastPresented = 0
        lock.unlock()
    }

    /// Now, snapped to the nearest refresh of the grid the last presented frame sat on.
    func alignedNow(period: Double) -> CFTimeInterval {
        let now = CACurrentMediaTime()
        lock.lock()
        let anchor = lastPresented
        lock.unlock()
        guard anchor > 0, period > 0, now - anchor < 1 else { return now }
        return anchor + ((now - anchor) / period).rounded() * period
    }
}
