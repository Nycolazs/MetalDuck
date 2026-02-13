import CoreGraphics
import Foundation
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

struct CaptureDisplaySource {
    let displayID: CGDirectDisplayID
    let title: String
}

struct CaptureWindowSource {
    let windowID: CGWindowID
    let title: String
}

struct CaptureSourceCatalog {
    let displays: [CaptureDisplaySource]
    let windows: [CaptureWindowSource]

    static let empty = CaptureSourceCatalog(displays: [], windows: [])
}

enum CaptureSourceCatalogProvider {
    static func load() async -> CaptureSourceCatalog {
        if #available(macOS 12.3, *) {
            do {
                return try await loadFromScreenCaptureKit()
            } catch {
                return loadFromCoreGraphics()
            }
        }

        return loadFromCoreGraphics()
    }

    @available(macOS 12.3, *)
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

        let windows: [CaptureWindowSource] = content.windows
            .filter { window in
                window.isOnScreen &&
                    window.windowLayer == 0 &&
                    window.owningApplication?.processID != currentPID
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
                let title = "\(appName) • \(baseTitle)"
                return CaptureWindowSource(windowID: window.windowID, title: title)
            }

        return CaptureSourceCatalog(displays: displays, windows: Array(windows))
    }

    private static func loadFromCoreGraphics() -> CaptureSourceCatalog {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let displaySources = activeDisplayIDs()
            .enumerated()
            .map { index, displayID in
                let width = CGDisplayPixelsWide(displayID)
                let height = CGDisplayPixelsHigh(displayID)
                let title = "Display \(index + 1) • ID \(displayID) • \(width)x\(height)"
                return CaptureDisplaySource(displayID: displayID, title: title)
            }

        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []

        let windowSources: [CaptureWindowSource] = windows
            .compactMap { info in
                guard let layer = info[kCGWindowLayer as String] as? NSNumber,
                      layer.intValue == 0,
                      let ownerPIDValue = info[kCGWindowOwnerPID as String] as? NSNumber,
                      pid_t(ownerPIDValue.intValue) != currentPID,
                      let rawID = info[kCGWindowNumber as String] as? NSNumber else {
                    return nil
                }

                let owner = (info[kCGWindowOwnerName as String] as? String) ?? "Unknown App"
                let windowName = (info[kCGWindowName as String] as? String).flatMap { text in
                    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return cleaned.isEmpty ? nil : cleaned
                } ?? "Untitled Window"

                return CaptureWindowSource(
                    windowID: CGWindowID(rawID.uint32Value),
                    title: "\(owner) • \(windowName)"
                )
            }
            .prefix(120)
            .map { $0 }

        return CaptureSourceCatalog(displays: displaySources, windows: Array(windowSources))
    }

    private static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return [CGMainDisplayID()]
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        let status = CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        guard status == .success else {
            return [CGMainDisplayID()]
        }

        return Array(displays.prefix(Int(displayCount)))
    }
}
