import Foundation

@MainActor
/// Manages the persistence and state of user-defined and built-in render profiles.
/// Handles creation, deletion, and selection of profiles across application sessions.
final class ProfileManager {
    static let shared = ProfileManager()
    
    private let storageKey = "com.metalduck.profiles"
    private let activeProfileIdKey = "com.metalduck.activeProfileId"
    
    private(set) var profiles: [Profile] = []
    private(set) var activeProfileId: UUID
    
    var activeProfile: Profile {
        if let found = profiles.first(where: { $0.id == activeProfileId }) {
            return found
        }
        if profiles.count > 1 {
            return profiles[1]
        }
        if let first = profiles.first {
            return first
        }
        // Absolute safety fallback
        return Profile(
            name: "Default",
            settings: RenderSettings(),
            capture: CaptureConfiguration()
        )
    }
    
    private init() {
        // Built-in profiles optimized for specific use cases
        
        // 🎮 Games: High capture rate, temporal upscaling, dynamic resolution
        // Optimized for real-time game content with fast motion
        let games = Profile(
            name: "🎮 Games",
            settings: RenderSettings(
                upscalingAlgorithm: .metalFXTemporal,
                outputScale: 1.0,
                matchOutputResolution: true,
                samplingMode: .linear,
                sharpness: 0.10,
                dynamicResolutionEnabled: true,
                dynamicScaleMinimum: 0.75,
                dynamicScaleMaximum: 1.0,
                targetPresentationFPS: 120,
                frameGenerationEnabled: true,
                frameGenerationMode: .x2
            ),
            capture: CaptureConfiguration(framesPerSecond: 60, queueDepth: 4),
            isBuiltIn: true
        )
        
        // 🎬 Anime: Low capture rate to match 24fps source, aggressive frame gen
        // High sharpness to preserve crisp line art and flat color regions
        let anime = Profile(
            name: "🎬 Anime",
            settings: RenderSettings(
                upscalingAlgorithm: .metalFXSpatial,
                outputScale: 1.25,
                matchOutputResolution: true,
                samplingMode: .linear,
                sharpness: 0.30,
                dynamicResolutionEnabled: false,
                dynamicScaleMinimum: 1.0,
                dynamicScaleMaximum: 1.0,
                targetPresentationFPS: 120,
                frameGenerationEnabled: true,
                frameGenerationMode: .x4
            ),
            capture: CaptureConfiguration(framesPerSecond: 30, queueDepth: 6),
            isBuiltIn: true
        )
        
        // 🎥 Video: Standard capture for YouTube/Films (typically 30fps)
        // Moderate sharpness for natural film look, 2x frame gen for smooth playback
        let video = Profile(
            name: "🎥 Video",
            settings: RenderSettings(
                upscalingAlgorithm: .metalFXSpatial,
                outputScale: 1.15,
                matchOutputResolution: true,
                samplingMode: .linear,
                sharpness: 0.15,
                dynamicResolutionEnabled: false,
                dynamicScaleMinimum: 1.0,
                dynamicScaleMaximum: 1.0,
                targetPresentationFPS: 60,
                frameGenerationEnabled: true,
                frameGenerationMode: .x2
            ),
            capture: CaptureConfiguration(framesPerSecond: 30, queueDepth: 5),
            isBuiltIn: true
        )
        
        // Load saved profiles or use defaults
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([Profile].self, from: data) {
            self.profiles = [games, anime, video] + saved.filter { !$0.isBuiltIn }
        } else {
            self.profiles = [games, anime, video]
        }
        
        // Restore active profile
        if let idString = UserDefaults.standard.string(forKey: activeProfileIdKey),
           let id = UUID(uuidString: idString),
           profiles.contains(where: { $0.id == id }) {
            self.activeProfileId = id
        } else {
            self.activeProfileId = video.id
        }
    }
    
    /// Selects a profile as the active one and persists the selection.
    func selectProfile(id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
        UserDefaults.standard.set(id.uuidString, forKey: activeProfileIdKey)
    }
    
    /// Creates a new custom profile with the given parameters and saves it.
    func createProfile(name: String, settings: RenderSettings, capture: CaptureConfiguration) -> Profile {
        let profile = Profile(name: name, settings: settings, capture: capture)
        profiles.append(profile)
        saveCustomProfiles()
        return profile
    }
    
    func updateActiveProfile(settings: RenderSettings? = nil, capture: CaptureConfiguration? = nil) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        
        if let settings {
            profiles[index].settings = settings
        }
        if let capture {
            profiles[index].capture = capture
        }
        
        if !profiles[index].isBuiltIn {
            saveCustomProfiles()
        }
    }
    
    /// Renames a non-built-in profile.
    func renameProfile(id: UUID, newName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }), !profiles[index].isBuiltIn else { return }
        profiles[index].name = newName
        saveCustomProfiles()
    }
    
    func deleteProfile(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }), !profiles[index].isBuiltIn else { return }
        
        profiles.remove(at: index)
        if activeProfileId == id {
            activeProfileId = profiles[1].id // Default to Anime
            UserDefaults.standard.set(activeProfileId.uuidString, forKey: activeProfileIdKey)
        }
        saveCustomProfiles()
    }
    
    func duplicateProfile(_ profile: Profile) -> Profile {
        let newName = "\(profile.name) Copy"
        return createProfile(name: newName, settings: profile.settings, capture: profile.capture)
    }
    
    private func saveCustomProfiles() {
        let custom = profiles.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
