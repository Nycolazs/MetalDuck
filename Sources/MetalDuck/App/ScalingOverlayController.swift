import AppKit
import CoreGraphics
import MetalKit

@MainActor
final class ScalingOverlayController {
    let mtkView: MTKView

    private let outputViewController: OutputViewController
    private weak var controlWindow: NSWindow?
    private var outputWindow: NSWindow?
    private var currentScreen: NSScreen?

    init(device: MTLDevice, controlWindow: NSWindow?) {
        self.outputViewController = OutputViewController(device: device)
        self.mtkView = outputViewController.mtkView
        self.controlWindow = controlWindow
    }

    func attachControlWindow(_ window: NSWindow) {
        self.controlWindow = window
    }

    func show(on displayID: CGDirectDisplayID?) {
        let targetScreen = Self.screen(for: displayID) ?? controlWindow?.screen ?? NSScreen.main
        guard let targetScreen else {
            return
        }

        currentScreen = targetScreen
        let window = ensureOutputWindow(on: targetScreen)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        if window.screen != targetScreen {
            window.setFrame(Self.defaultOutputFrame(for: targetScreen), display: true, animate: false)
        }
        outputViewController.updateColorSpace(targetScreen.colorSpace?.cgColorSpace)
        // A fresh overlay stays invisible until the first captured frame is drawn
        // (`revealPicture`). A source that sends nothing, such as a window full screen on
        // another desktop, otherwise covered the screen in black.
        if !window.isVisible {
            window.alphaValue = 0
        }
        window.orderFrontRegardless()
        outputViewController.setProcessingState(isRunning: true)
    }

    func revealPicture() {
        guard let window = outputWindow, window.isVisible, window.alphaValue < 1 else { return }
        window.alphaValue = 1
    }

    func hide() {
        outputViewController.setProcessingState(isRunning: false)
        // Simply ordering out is safer than toggling fullscreen during a transition
        outputWindow?.orderOut(nil)
        outputWindow?.level = Self.belowMenus
        setJoinsFullScreenSpaces(false)
    }

    func updateFrame(to rect: CGRect) {
        // Run on next runloop to allow window constraints to settle if it just appeared
        DispatchQueue.main.async {
            var cocoaRect = rect
            if let primaryScreen = NSScreen.screens.first {
                cocoaRect.origin.y = primaryScreen.frame.height - rect.maxY
            }
            // Add a small safety to prevent impossible sizing from causing errors
            cocoaRect.size.width = max(1.0, cocoaRect.size.width)
            cocoaRect.size.height = max(1.0, cocoaRect.size.height)

            // A full-screen source fills the display (below the notch on MacBooks with one).
            // Cover exactly what it covers, and sit under the Dock and menu bar so they
            // still slide in over the picture.
            let fullScreen = NSScreen.screens.contains { Self.isFullScreen(cocoaRect, on: $0) }
            let level: NSWindow.Level
            if fullScreen {
                level = Self.underDockAndMenus
            } else {
                if let screen = self.currentScreen ?? self.outputWindow?.screen {
                    cocoaRect = Self.clampedToVisibleFrame(cocoaRect, on: screen)
                }
                level = Self.belowMenus
            }
            // Leave one point of the source uncovered. macOS tells an app its window is
            // hidden only when none of it shows, and browsers like Firefox stop drawing then,
            // which froze the very video being scaled. One point keeps it "visible".
            if cocoaRect.height > 2 {
                cocoaRect.origin.y += 1
                cocoaRect.size.height -= 1
            }
            guard let window = self.outputWindow else { return }
            if window.level != level {
                window.level = level
                self.setJoinsFullScreenSpaces(fullScreen)
                PipelineLog.shared.event("capture", fullScreen
                    ? "source is full screen: overlay joins its Space and covers it, under the Dock and menu bar"
                    : "source left full screen: overlay back above ordinary windows")
            }
            if window.frame != cocoaRect {
                window.setFrame(cocoaRect, display: true, animate: false)
            }
        }
    }

    /// True when `rect` (Cocoa coordinates) fills `screen`: full width, down to the bottom,
    /// and up to the top or to just under the notch strip. Apps stop at different heights
    /// there (Firefox leaves the menu bar's 37 pt, the notch itself is 32 pt), so allow up
    /// to 60 pt, which no ordinary window that fills the width reaches by accident.
    private static func isFullScreen(_ rect: CGRect, on screen: NSScreen) -> Bool {
        let frame = screen.frame
        let topGap = frame.maxY - rect.maxY
        return abs(rect.minX - frame.minX) <= 2 && abs(rect.width - frame.width) <= 4 &&
            abs(rect.minY - frame.minY) <= 2 && topGap >= -2 && topGap <= 60
    }

    /// macOS only lets another app's window into a full-screen Space when that app runs
    /// as a menu-bar (accessory) app. While the source is full screen, MetalDuck does:
    /// its Dock icon steps aside, and the menu-bar item stays for Stop.
    private func setJoinsFullScreenSpaces(_ joins: Bool) {
        let policy: NSApplication.ActivationPolicy = joins ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Re-show the picture only when joining a full-screen Space. On the way out the
        // window may already be hidden (Stop); bringing it back left a black screen.
        if joins, let window = outputWindow, window.isVisible {
            window.orderFrontRegardless()
        }
    }

    /// Popup menus are 101. Stay above the game, Dock, and ordinary windows, but under every menu.
    static let belowMenus = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
    /// Over a full-screen app's window, but under the Dock (20) and the menu bar (24),
    /// which macOS slides in over a full-screen Space.
    static let underDockAndMenus = NSWindow.Level(rawValue: 19)

    /// Keeps the menu bar and Dock outside the picture, so Force Quit stays reachable.
    private static func clampedToVisibleFrame(_ rect: CGRect, on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        var clamped = rect
        if clamped.minX < visible.minX {
            clamped.size.width -= visible.minX - clamped.minX
            clamped.origin.x = visible.minX
        }
        if clamped.maxX > visible.maxX {
            clamped.size.width -= clamped.maxX - visible.maxX
        }
        if clamped.minY < visible.minY {
            clamped.size.height -= visible.minY - clamped.minY
            clamped.origin.y = visible.minY
        }
        if clamped.maxY > visible.maxY {
            clamped.size.height -= clamped.maxY - visible.maxY
        }
        clamped.size.width = max(1, clamped.size.width)
        clamped.size.height = max(1, clamped.size.height)
        return clamped
    }

    func updateStats(_ stats: RendererStats) {
        outputViewController.updateStats(stats)
    }

    func setHUDVisible(_ visible: Bool, animated: Bool) {
        outputViewController.setTelemetryVisible(visible, animated: animated)
    }

    func setWaitingForFrames(message: String) {
        outputViewController.setWaitingForFrames(message: message)
    }

    func setCaptureError(_ message: String) {
        outputViewController.setCaptureError(message)
    }

    private func ensureOutputWindow(on screen: NSScreen) -> NSWindow {
        if let outputWindow {
            return outputWindow
        }

        // A non-activating panel: macOS only shows another app's window inside a
        // full-screen Space when it is a panel marked as a full-screen auxiliary. A plain
        // window stayed on the desktop while the video played full screen.
        let window = OverlayPanel(
            contentRect: Self.defaultOutputFrame(for: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.title = "MetalDuck Overlay"
        // Ensure it can be perfectly sized to the source without arbitrary limits
        window.minSize = NSSize(width: 100, height: 100)
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Just under popup menus. screenSaver (1000) sits above the menu bar, so the
        // status menu and Quit open behind the picture and cannot be clicked.
        window.level = Self.belowMenus
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.contentViewController = outputViewController
        outputViewController.updateColorSpace(screen.colorSpace?.cgColorSpace)

        outputWindow = window
        return window
    }

    private static func defaultOutputFrame(for screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let width = max(1280, visible.width * 0.90)
        let height = max(720, visible.height * 0.90)
        let x = visible.midX - (width * 0.5)
        let y = visible.midY - (height * 0.5)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private static func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else {
            return nil
        }

        return NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(screenNumber.uint32Value) == displayID
        }
    }
}

/// The scaled picture. It never takes focus, so the source keeps the keyboard and mouse.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
