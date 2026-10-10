import Foundation

struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var settings: RenderSettings
    var capture: CaptureConfiguration
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, settings: RenderSettings, capture: CaptureConfiguration, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.settings = settings
        self.capture = capture
        self.isBuiltIn = isBuiltIn
    }
}
