import Foundation

enum UpscalingAlgorithm: String, CaseIterable {
    case metalFXSpatial = "MetalFX Spatial"
    case nativeLinear = "Native Linear"
}

enum SamplingMode: String, CaseIterable {
    case linear = "Linear"
    case nearest = "Nearest"
}

enum FrameGenerationMode: String, CaseIterable {
    case x2 = "2x"
    case x3 = "3x"
}

struct RenderSettings {
    var upscalingAlgorithm: UpscalingAlgorithm = .metalFXSpatial
    var outputScale: Float = 1.0
    var matchOutputResolution: Bool = true
    var samplingMode: SamplingMode = .linear
    var sharpness: Float = 0.0
    var dynamicResolutionEnabled: Bool = false
    var dynamicScaleMinimum: Float = 0.75
    var dynamicScaleMaximum: Float = 1.0
    var targetPresentationFPS: Int = 60
    var frameGenerationEnabled: Bool = true
    var frameGenerationMode: FrameGenerationMode = .x2
}

final class SettingsStore {
    private let lock = NSLock()
    private var settings = RenderSettings()

    func snapshot() -> RenderSettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    @discardableResult
    func update(_ mutate: (inout RenderSettings) -> Void) -> RenderSettings {
        lock.lock()
        mutate(&settings)
        let snapshot = settings
        lock.unlock()
        return snapshot
    }
}
