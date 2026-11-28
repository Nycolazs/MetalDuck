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

    /// Called on the main thread when the part of the source's picture the overlay shows
    /// changes (see `OverlayPlan.sourceCrop`).
    var onSourceCrop: ((CGRect) -> Void)?
    private var lastSourceCrop = OverlayPlan.wholePicture

    /// Places the overlay for a source at `rect` (global points, origin top left).
    func updateFrame(to rect: CGRect, placement: OutputPlacement, output: PixelSize?) {
        // Run on next runloop to allow window constraints to settle if it just appeared
        DispatchQueue.main.async {
            var source = rect
            if let primaryScreen = NSScreen.screens.first {
                source.origin.y = primaryScreen.frame.height - rect.maxY
            }
            // Add a small safety to prevent impossible sizing from causing errors
            source.size.width = max(1.0, source.size.width)
            source.size.height = max(1.0, source.size.height)

            guard let window = self.outputWindow,
                  let screen = Self.screen(containing: source) ?? self.currentScreen ?? window.screen else { return }
            let plan = ScalePlan.overlayPlan(
                source: source,
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                backingScale: screen.backingScaleFactor,
                output: output,
                placement: placement
            )

            // A picture that fills the screen sits under the Dock and menu bar, so they
            // still slide in over it. Otherwise it stays just under popup menus.
            let level = plan.fillsScreen ? Self.underDockAndMenus : Self.belowMenus
            if window.level != level {
                window.level = level
                self.setJoinsFullScreenSpaces(plan.fillsScreen)
                PipelineLog.shared.event("capture", plan.fillsScreen
                    ? "picture fills the screen: overlay joins the Space and covers it, under the Dock and menu bar"
                    : "picture no longer fills the screen: overlay back above ordinary windows")
            }
            if window.frame != plan.frame {
                window.setFrame(plan.frame, display: true, animate: false)
            }
            if plan.sourceCrop != self.lastSourceCrop {
                self.lastSourceCrop = plan.sourceCrop
                self.onSourceCrop?(plan.sourceCrop)
            }
        }
    }

    /// The screen showing most of `rect` (Cocoa coordinates).
    private static func screen(containing rect: CGRect) -> NSScreen? {
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let overlap = screen.frame.intersection(rect)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        return best
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
