import Foundation

struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var settings: RenderSettings
    var capture: CaptureConfiguration
    var isBuiltIn: Bool
    /// SF Symbol shown next to the profile. Optional so older saved profiles still decode.
    var symbol: String?

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String? = nil,
        settings: RenderSettings,
        capture: CaptureConfiguration,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.settings = settings
        self.capture = capture
        self.isBuiltIn = isBuiltIn
    }

    var symbolName: String {
        symbol ?? "slider.horizontal.3"
    }
}
