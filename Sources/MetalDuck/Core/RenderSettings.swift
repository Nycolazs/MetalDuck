import Foundation
import AppKit


enum UpscalingAlgorithm: String, Codable, Equatable, CaseIterable {
    case nativeLinear = "Native Linear"
    case metalFXSpatial = "MetalFX Spatial"
    case metalFXTemporal = "MetalFX Temporal"
}

enum SamplingMode: String, Codable, Equatable, CaseIterable {
    case nearest = "Nearest"
    case linear = "Linear"
}

enum FrameGenerationMode: String, Codable, Equatable, CaseIterable {
    case x2 = "2x (30 -> 60)"
    case x3 = "3x (30 -> 90)"
    case x4 = "4x (30 -> 120)"
}

struct RenderSettings: Codable, Equatable {
    var upscalingAlgorithm: UpscalingAlgorithm
    var outputScale: Float
    var matchOutputResolution: Bool
    var samplingMode: SamplingMode
    var sharpness: Float
    var dynamicResolutionEnabled: Bool
    var dynamicScaleMinimum: Float
    var dynamicScaleMaximum: Float
    var targetPresentationFPS: Int
    var frameGenerationEnabled: Bool
    var frameGenerationMode: FrameGenerationMode

    init(
        upscalingAlgorithm: UpscalingAlgorithm = .metalFXSpatial,
        outputScale: Float = 1.0,
        matchOutputResolution: Bool = true,
        samplingMode: SamplingMode = .linear,
        sharpness: Float = 0.75,
        dynamicResolutionEnabled: Bool = false,
        dynamicScaleMinimum: Float = 0.5,
        dynamicScaleMaximum: Float = 1.0,
        targetPresentationFPS: Int = 120,
        frameGenerationEnabled: Bool = true,
        frameGenerationMode: FrameGenerationMode = .x4
    ) {
        self.upscalingAlgorithm = upscalingAlgorithm
        self.outputScale = outputScale
        self.matchOutputResolution = matchOutputResolution
        self.samplingMode = samplingMode
        self.sharpness = sharpness
        self.dynamicResolutionEnabled = dynamicResolutionEnabled
        self.dynamicScaleMinimum = dynamicScaleMinimum
        self.dynamicScaleMaximum = dynamicScaleMaximum
        self.targetPresentationFPS = targetPresentationFPS
        self.frameGenerationEnabled = frameGenerationEnabled
        self.frameGenerationMode = frameGenerationMode
    }
}

struct ShortcutSettings: Codable, Equatable {
    var enabled: Bool = false
    var keyCode: Int? = nil
    var modifiers: UInt = 0 // NSEvent.ModifierFlags rawValue
    
    /// Returns a human-readable representation of the shortcut (e.g., "⌘⇧A").
    /// Uses a manual keycode mapping for reliability across different keyboard layouts.
    var displayString: String {
        guard let keyCode = keyCode else { return "None" }
        var str = ""
        if modifiers & NSEvent.ModifierFlags.command.rawValue != 0 { str += "⌘" }
        if modifiers & NSEvent.ModifierFlags.option.rawValue != 0 { str += "⌥" }
        if modifiers & NSEvent.ModifierFlags.control.rawValue != 0 { str += "⌃" }
        if modifiers & NSEvent.ModifierFlags.shift.rawValue != 0 { str += "⇧" }
        
        let keyName: String
        switch keyCode {
        case 36: keyName = "↩"
        case 48: keyName = "⇥"
        case 49: keyName = "Space"
        case 51: keyName = "⌫"
        case 53: keyName = "⎋"
        case 123: keyName = "←"
        case 124: keyName = "→"
        case 125: keyName = "↓"
        case 126: keyName = "↑"
        case 122: keyName = "F1"
        case 120: keyName = "F2"
        case 99: keyName = "F3"
        case 118: keyName = "F4"
        case 96: keyName = "F5"
        case 97: keyName = "F6"
        case 98: keyName = "F7"
        case 100: keyName = "F8"
        case 101: keyName = "F9"
        case 109: keyName = "F10"
        case 103: keyName = "F11"
        case 111: keyName = "F12"
        default:
            let keyMap: [Int: String] = [
                0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
                8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
                16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
                23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
                30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
                37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
                43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
                50: "`",
            ]
            keyName = keyMap[keyCode] ?? "Key\(keyCode)"
        }
        
        str += keyName
        return str
    }
}



final class SettingsStore {
    private let lock = NSLock()
    private var settings = RenderSettings(
        upscalingAlgorithm: .metalFXSpatial,
        outputScale: 1.0,
        matchOutputResolution: true,
        samplingMode: .linear,
        sharpness: 0.75,
        dynamicResolutionEnabled: false,
        dynamicScaleMinimum: 0.75,
        dynamicScaleMaximum: 1.0,
        targetPresentationFPS: 120,
        frameGenerationEnabled: true,
        frameGenerationMode: .x4
    )

    private var shortcutSettings: ShortcutSettings = {
        if let data = UserDefaults.standard.data(forKey: "com.metalduck.shortcut"),
           let saved = try? JSONDecoder().decode(ShortcutSettings.self, from: data) {
            return saved
        }
        return ShortcutSettings()
    }()


    func snapshot() -> RenderSettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    func update(action: (inout RenderSettings) -> Void) -> RenderSettings {
        lock.lock()
        defer { lock.unlock() }
        action(&settings)
        return settings
    }
    
    // Conformance/Utility methods to avoid too many changes in MainVC
    var upscalingAlgorithm: UpscalingAlgorithm {
        get { snapshot().upscalingAlgorithm }
        set { update { $0.upscalingAlgorithm = newValue } }
    }
    var outputScale: Float {
        get { snapshot().outputScale }
        set { update { $0.outputScale = newValue } }
    }
    var matchOutputResolution: Bool {
        get { snapshot().matchOutputResolution }
        set { update { $0.matchOutputResolution = newValue } }
    }
    var samplingMode: SamplingMode {
        get { snapshot().samplingMode }
        set { update { $0.samplingMode = newValue } }
    }
    var sharpness: Float {
        get { snapshot().sharpness }
        set { update { $0.sharpness = newValue } }
    }
    var dynamicResolutionEnabled: Bool {
        get { snapshot().dynamicResolutionEnabled }
        set { update { $0.dynamicResolutionEnabled = newValue } }
    }
    var dynamicScaleMinimum: Float {
        get { snapshot().dynamicScaleMinimum }
        set { update { $0.dynamicScaleMinimum = newValue } }
    }
    var dynamicScaleMaximum: Float {
        get { snapshot().dynamicScaleMaximum }
        set { update { $0.dynamicScaleMaximum = newValue } }
    }
    var targetPresentationFPS: Int {
        get { snapshot().targetPresentationFPS }
        set { update { $0.targetPresentationFPS = newValue } }
    }
    var frameGenerationEnabled: Bool {
        get { snapshot().frameGenerationEnabled }
        set { update { $0.frameGenerationEnabled = newValue } }
    }
    var frameGenerationMode: FrameGenerationMode {
        get { snapshot().frameGenerationMode }
        set { update { $0.frameGenerationMode = newValue } }
    }

    var shortcut: ShortcutSettings {
        get {
            lock.lock()
            defer { lock.unlock() }
            return shortcutSettings
        }
        set {
            lock.lock()
            shortcutSettings = newValue
            lock.unlock()
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "com.metalduck.shortcut")
            }
        }
    }
}

