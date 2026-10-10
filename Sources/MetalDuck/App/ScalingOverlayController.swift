import AppKit
import CoreGraphics
import MetalKit

@MainActor
final class ScalingOverlayController {
    let mtkView: MTKView

    private let outputViewController: OutputViewController
    private weak var controlWindow: NSWindow?
    private var outputWindow: NSWindow?

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

        let window = ensureOutputWindow(on: targetScreen)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        if window.screen != targetScreen {
            window.setFrame(Self.defaultOutputFrame(for: targetScreen), display: true, animate: false)
        }
        outputViewController.updateColorSpace(targetScreen.colorSpace?.cgColorSpace)
        window.orderFrontRegardless()
        outputViewController.setProcessingState(isRunning: true)
    }

    func hide() {
        outputViewController.setProcessingState(isRunning: false)
        // Simply ordering out is safer than toggling fullscreen during a transition
        outputWindow?.orderOut(nil)
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
            self.outputWindow?.setFrame(cocoaRect, display: true, animate: false)
        }
    }
    func updateStats(_ stats: RendererStats) {
        outputViewController.updateStats(stats)
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

        let window = NSWindow(
            contentRect: Self.defaultOutputFrame(for: screen),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = "MetalDuck Overlay"
        // Ensure it can be perfectly sized to the source without arbitrary limits
        window.minSize = NSSize(width: 100, height: 100) 
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .transient, .stationary, .fullScreenAuxiliary]
        window.level = .screenSaver
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
