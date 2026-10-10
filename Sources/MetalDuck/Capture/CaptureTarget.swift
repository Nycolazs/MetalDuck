import CoreGraphics
import Foundation

enum CaptureTarget: Equatable {
    case automatic
    case display(CGDirectDisplayID)
    case window(CGWindowID?)
}

struct CaptureConfiguration: Codable, Equatable {
    var framesPerSecond: Int
    var queueDepth: Int
    var showsCursor: Bool
    var preferredPixelSize: CGSize?

    init(
        framesPerSecond: Int = 60,
        queueDepth: Int = 5,
        showsCursor: Bool = false,
        preferredPixelSize: CGSize? = nil
    ) {
        self.framesPerSecond = framesPerSecond
        self.queueDepth = queueDepth
        self.showsCursor = showsCursor
        self.preferredPixelSize = preferredPixelSize
    }
}
