import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

struct CaptureDisplaySource: Sendable {
    let displayID: CGDirectDisplayID
    let title: String
}

struct CaptureWindowSource: @unchecked Sendable {
    let windowID: CGWindowID
    let title: String
    let bundleID: String?
    /// The window's own title, without the app's name.
    let windowTitle: String
    let window: SCWindow
}

struct CaptureSourceCatalog: Sendable {
    let displays: [CaptureDisplaySource]
    let windows: [CaptureWindowSource]

    static let empty = CaptureSourceCatalog(displays: [], windows: [])
}

enum CaptureSourceCatalogProvider {
    /// Empty when ScreenCaptureKit refuses, which is what a missing Screen Recording
    /// permission looks like.
    static func load() async -> CaptureSourceCatalog {
        (try? await loadFromScreenCaptureKit()) ?? .empty
    }

    private static func loadFromScreenCaptureKit() async throws -> CaptureSourceCatalog {
        let content = try await SCShareableContent.current
        let currentPID = ProcessInfo.processInfo.processIdentifier

        let displays: [CaptureDisplaySource] = content.displays
            .sorted { $0.displayID < $1.displayID }
            .enumerated()
            .map { index, display in
                let title = "Display \(index + 1) • ID \(display.displayID) • \(display.width)x\(display.height)"
                return CaptureDisplaySource(displayID: display.displayID, title: title)
            }

        // A full-screen window lives on its own Space, so it is not "on screen" while you are
        // here picking it. Keep windows that fill a display, too.
        let windows: [CaptureWindowSource] = content.windows
            .filter { window in
                window.windowLayer == 0 &&
                    window.owningApplication?.processID != currentPID &&
                    (window.isOnScreen || ScreenCaptureKitCaptureService.fillsDisplay(window.frame))
            }
            .sorted { lhs, rhs in
                let lhsArea = lhs.frame.width * lhs.frame.height
                let rhsArea = rhs.frame.width * rhs.frame.height
                return lhsArea > rhsArea
            }
            .prefix(120)
            .map { window in
                let appName = window.owningApplication?.applicationName ?? "Unknown App"
                let trimmedWindowTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let baseTitle = trimmedWindowTitle.isEmpty ? "Untitled Window" : trimmedWindowTitle
                let fullScreen = ScreenCaptureKitCaptureService.fillsDisplay(window.frame) ? " (full screen)" : ""
                let title = "\(appName) • \(baseTitle)\(fullScreen)"
                return CaptureWindowSource(
                    windowID: window.windowID,
                    title: title,
                    bundleID: window.owningApplication?.bundleIdentifier,
                    windowTitle: trimmedWindowTitle,
                    window: window
                )
            }

        return CaptureSourceCatalog(displays: displays, windows: Array(windows))
    }
}
