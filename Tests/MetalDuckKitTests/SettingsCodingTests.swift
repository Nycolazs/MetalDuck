import Foundation
import Testing
@testable import MetalDuckKit

@Suite struct SettingsCodingTests {
    @Test func renderSettingsRoundTrip() throws {
        var settings = RenderSettings()
        settings.sharpness = 0.4
        settings.frameGenerationMode = .x3
        settings.artifactGuard = .strong
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(RenderSettings.self, from: data) == settings)
    }

    /// Profiles saved before the artifact guard existed have no such key.
    @Test func settingsWithoutArtifactGuardLoadAsBalanced() throws {
        let data = try JSONEncoder().encode(RenderSettings(artifactGuard: .off))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "artifactGuard")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(RenderSettings.self, from: stripped).artifactGuard == .balanced)
    }

    @Test func profileRoundTrip() throws {
        let profile = Profile(
            name: "Mine",
            symbol: "star",
            settings: RenderSettings(),
            capture: CaptureConfiguration(framesPerSecond: 48, queueDepth: 4, showsCursor: true)
        )
        let data = try JSONEncoder().encode([profile])
        #expect(try JSONDecoder().decode([Profile].self, from: data) == [profile])
    }

    @Test func artifactGuardRanges() {
        #expect(ArtifactGuard.off.calmRange == nil)
        let balanced = ArtifactGuard.balanced.calmRange!
        let strong = ArtifactGuard.strong.calmRange!
        #expect(balanced.from < balanced.full)
        #expect(strong.from < strong.full)
        // Strong acts sooner than balanced at both ends.
        #expect(strong.from < balanced.from)
        #expect(strong.full < balanced.full)
    }

    @Test func frameGenerationMultipliers() {
        #expect(FrameGenerationMode.allCases.map(\.multiplier) == [2, 3, 4])
    }

    /// A profile written by 1.3: scale factor and fit switch, no resolution keys.
    @Test func settingsFromBeforeManualResolutionLoadAsAutomatic() throws {
        let json = """
        {"upscalingAlgorithm":"MetalFX Spatial","outputScale":1.25,"matchOutputResolution":true,
         "samplingMode":"Linear","sharpness":0.3,"dynamicResolutionEnabled":true,
         "dynamicScaleMinimum":0.75,"dynamicScaleMaximum":1.25,"targetPresentationFPS":120,
         "frameGenerationEnabled":true,"frameGenerationMode":"4x (30 -> 120)"}
        """
        let settings = try JSONDecoder().decode(RenderSettings.self, from: Data(json.utf8))
        #expect(!settings.manualResolution)
        #expect(settings.requestedInput == nil)
        #expect(settings.requestedOutput == nil)
        #expect(settings.effectiveAspectMode == .fill)
        #expect(settings.sharpness == 0.3)
        // Capture cannot exceed its usual size, so the old 1.25 ceiling comes down to 1.
        #expect(settings.dynamicScaleMaximum == 1)
    }

    @Test func manualResolutionAsksForItsSizesAndPausesDynamicResolution() {
        var settings = RenderSettings(dynamicResolutionEnabled: true)
        #expect(settings.dynamicResolutionActive)
        settings.resolutionMode = .manual
        settings.inputResolution = PixelSize(width: 1280, height: 720)
        settings.outputResolution = PixelSize(width: 2560, height: 1440)
        settings.aspectMode = .stretch
        #expect(settings.requestedInput == PixelSize(width: 1280, height: 720))
        #expect(settings.requestedOutput == PixelSize(width: 2560, height: 1440))
        #expect(settings.effectiveAspectMode == .stretch)
        #expect(!settings.dynamicResolutionActive)
    }

    /// A capture configuration saved by 1.3 may carry `preferredPixelSize`, which is gone.
    @Test func oldCaptureConfigurationsStillLoad() throws {
        let json = #"{"framesPerSecond":30,"queueDepth":6,"showsCursor":false,"preferredPixelSize":[1920,1080]}"#
        let capture = try JSONDecoder().decode(CaptureConfiguration.self, from: Data(json.utf8))
        #expect(capture.framesPerSecond == 30)
        #expect(capture.inputResolution == nil)
    }

    @Test func nativeResolutionAsksForTheSourceAsItIs() {
        let settings = RenderSettings(resolutionMode: .native, dynamicResolutionEnabled: true)
        #expect(settings.requestedInput == ScalePlan.nativeInput)
        #expect(settings.requestedOutput == nil)
        #expect(settings.effectivePlacement == .overSource)
        #expect(!settings.dynamicResolutionActive)
        // Asked for that, any source is captured at its own size, past the pixel budget.
        let budget = PixelSize(width: 1920, height: 1080)
        for native in [PixelSize(width: 3456, height: 2234), PixelSize(width: 1280, height: 720), PixelSize(width: 5120, height: 2880)] {
            #expect(ScalePlan.streamSize(native: native, requested: settings.requestedInput, budget: budget) == native)
        }
    }

    /// Over the source, a native capture needs no scaler: the overlay shows it pixel for pixel.
    @Test func nativeResolutionSkipsTheScaler() {
        let capture = PixelSize(width: 3456, height: 2234)
        let crop = CGRect(x: 0, y: 0, width: 1, height: 1116.0 / 1117.0)
        let drawable = PixelSize(width: 3456, height: 2232)
        let target = ScalePlan.renderSize(
            input: capture,
            requested: nil,
            drawable: ScalePlan.drawable(drawable, showing: crop),
            aspect: .fill
        )
        #expect(target == capture)
    }

    @Test func videoProfilesShipAtNativeResolution() async {
        let modes = await MainActor.run {
            let manager = ProfileManager(defaults: UserDefaults(suiteName: "metalduck.tests.\(UUID().uuidString)")!)
            return Dictionary(uniqueKeysWithValues: manager.profiles.map { ($0.name, $0.settings.resolutionMode) })
        }
        #expect(modes["Anime"] == .native)
        #expect(modes["Video"] == .native)
        #expect(modes["Games"] == .automatic)
    }
}
