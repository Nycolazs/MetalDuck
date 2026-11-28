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
        settings.manualResolution = true
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
}
