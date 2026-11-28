import Foundation
import Testing
@testable import MetalDuckKit

@MainActor
@Suite struct ProfileManagerTests {
    private func freshDefaults() -> UserDefaults {
        let name = "metalduck.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func editsToACustomProfileSurviveAReload() {
        let defaults = freshDefaults()
        let manager = ProfileManager(defaults: defaults)
        let custom = manager.createProfile(
            name: "Mine",
            settings: RenderSettings(sharpness: 0.2),
            capture: CaptureConfiguration(framesPerSecond: 60)
        )
        manager.selectProfile(id: custom.id)

        var settings = custom.settings
        settings.sharpness = 0.9
        manager.updateActiveProfile(settings: settings, capture: CaptureConfiguration(framesPerSecond: 48))

        let reloaded = ProfileManager(defaults: defaults)
        #expect(reloaded.activeProfileId == custom.id)
        #expect(reloaded.activeProfile.settings.sharpness == 0.9)
        #expect(reloaded.activeProfile.capture.framesPerSecond == 48)
    }

    @Test func editsToABuiltInProfileAreMarkedAndNotSaved() {
        let defaults = freshDefaults()
        let manager = ProfileManager(defaults: defaults)
        let games = manager.profiles.first { $0.name == "Games" }!
        manager.selectProfile(id: games.id)
        #expect(!manager.isActiveBuiltInEdited)

        var settings = games.settings
        settings.sharpness = 0.95
        manager.updateActiveProfile(settings: settings)
        #expect(manager.isActiveBuiltInEdited)

        let reloaded = ProfileManager(defaults: defaults)
        #expect(reloaded.activeProfile.settings.sharpness == games.settings.sharpness)
        #expect(!reloaded.isActiveBuiltInEdited)
    }

    @Test func aSavedTemporalUpscalerLoadsAsSpatial() throws {
        let data = try JSONEncoder().encode(RenderSettings())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["upscalingAlgorithm"] = "MetalFX Temporal"
        let old = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(RenderSettings.self, from: old).upscalingAlgorithm == .metalFXSpatial)
    }

    @Test func noBuiltInProfileOffersTheTemporalUpscaler() {
        #expect(UpscalingAlgorithm.allCases.map(\.rawValue) == ["Native Linear", "MetalFX Spatial"])
    }
}
