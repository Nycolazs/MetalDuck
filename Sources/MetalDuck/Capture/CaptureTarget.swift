import CoreGraphics

enum CaptureTarget: Equatable {
    case automatic
    case display(CGDirectDisplayID?)
    case window(CGWindowID?)
}

struct CaptureConfiguration {
    var framesPerSecond: Int = 60
    var queueDepth: Int = 5
    var showsCursor: Bool = false
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
