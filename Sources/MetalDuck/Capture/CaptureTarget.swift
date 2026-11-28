import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

enum CaptureTarget: Equatable {
    case automatic
    case display(CGDirectDisplayID)
    case window(CGWindowID?)
    /// Chosen in the system picker.
    case picked(PickedContent)
}

/// What the user chose in the system picker, with the identifiers the rest of the app
/// works from: following the app into full screen, and putting the overlay on its screen.
struct PickedContent: Equatable, @unchecked Sendable {
    /// The filter to capture with. Nil for a display: its filter is rebuilt at start so
    /// MetalDuck's own windows, the overlay above all, are left out of the picture.
    let filter: SCContentFilter?
    /// "Safari • Trailer", for the control panel.
    let title: String
    /// The window's own title, without the app's name. Empty for a display.
    let windowTitle: String
    let windowID: CGWindowID?
    let processID: pid_t?
    let bundleID: String?
    let displayID: CGDirectDisplayID?

    static func == (lhs: PickedContent, rhs: PickedContent) -> Bool {
        lhs.filter === rhs.filter && lhs.windowID == rhs.windowID && lhs.displayID == rhs.displayID
    }

    init(window: SCWindow, filter: SCContentFilter? = nil) {
        self.filter = filter ?? SCContentFilter(desktopIndependentWindow: window)
        self.title = Self.title(for: window)
        self.windowTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.windowID = window.windowID
        self.processID = window.owningApplication?.processID
        self.bundleID = window.owningApplication?.bundleIdentifier
        self.displayID = nil
    }

    init(display: SCDisplay) {
        self.filter = nil
        self.title = "Display • \(display.width)×\(display.height)"
        self.windowTitle = ""
        self.windowID = nil
        self.processID = nil
        self.bundleID = nil
        self.displayID = display.displayID
    }

    static func title(for window: SCWindow) -> String {
        let app = window.owningApplication?.applicationName ?? "Unknown app"
        let name = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? app : "\(app) • \(name)"
    }

    /// Reads what a filter from the system picker holds. Choosing an app gives a
    /// display-shaped picture of all its windows, which an overlay cannot sit on, so an
    /// app resolves to its largest window on screen, and the capture service follows the
    /// app from there. Nil when the app has no window to show.
    static func resolve(_ filter: SCContentFilter) async -> PickedContent? {
        switch filter.style {
        case .window:
            guard let window = filter.includedWindows.first else { return nil }
            return PickedContent(window: window, filter: filter)

        case .display:
            guard let display = filter.includedDisplays.first else { return nil }
            return PickedContent(display: display)

        case .application:
            guard let app = filter.includedApplications.first else { return nil }
            let pid = app.processID
            // The filter may already list the app's windows; otherwise ask for them.
            var windows = filter.includedWindows.filter { $0.owningApplication?.processID == pid }
            if windows.isEmpty, let content = try? await SCShareableContent.current {
                windows = content.windows.filter { $0.owningApplication?.processID == pid }
            }
            guard let window = Self.mainWindow(among: windows) else { return nil }
            return PickedContent(window: window)

        default:
            return nil
        }
    }

    /// The largest ordinary window on screen, or the largest of any if none is on screen.
    static func mainWindow(among windows: [SCWindow]) -> SCWindow? {
        let ordinary = windows.filter { $0.windowLayer == 0 && $0.frame.width >= 200 && $0.frame.height >= 150 }
        let area: (SCWindow) -> CGFloat = { $0.frame.width * $0.frame.height }
        let onScreen = ordinary.filter(\.isOnScreen)
        return (onScreen.isEmpty ? ordinary : onScreen).max { area($0) < area($1) }
    }
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
