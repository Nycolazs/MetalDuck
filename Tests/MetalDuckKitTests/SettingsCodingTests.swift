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
}
