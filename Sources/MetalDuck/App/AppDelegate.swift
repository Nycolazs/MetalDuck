import AppKit
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controlWindow: NSWindow?
    private var mainViewController: MainViewController?
    private var didBootstrap = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.mainMenu = MainMenu.make()
        LosslessScalingLibrary.importFromSteamIfNeeded()
        bootstrapIfNeeded()
    }

    func bootstrapIfNeeded() {
        guard !didBootstrap else {
            return
        }
        didBootstrap = true

        do {
            NSApplication.shared.applicationIconImage = MetalDuckIcon.make()

            let metalContext = try MetalContext()
            PipelineLog.shared.event(
                "session",
                "launch device=\(metalContext.device.name) log=\(PipelineLog.shared.fileURL?.path ?? "memory only")"
            )
            let captureConfiguration = CaptureConfiguration(
                framesPerSecond: 30,
                queueDepth: 5,
                showsCursor: false,
                preferredPixelSize: CGSize(width: 1920, height: 1080)
            )
            let initialTarget: CaptureTarget = .window(nil)

            let controlWindow = NSWindow(
                contentRect: NSRect(x: 80, y: 90, width: 1180, height: 880),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            controlWindow.minSize = NSSize(width: 1040, height: 400)
            controlWindow.isReleasedWhenClosed = false
            controlWindow.titlebarAppearsTransparent = true
            controlWindow.titleVisibility = .hidden
            controlWindow.isMovableByWindowBackground = true
            controlWindow.isOpaque = false
            controlWindow.backgroundColor = .clear
            controlWindow.title = "MetalDuck"

            let overlayController = ScalingOverlayController(device: metalContext.device, controlWindow: controlWindow)
            let captureService = FrameCaptureFactory.make(
                context: metalContext,
                target: initialTarget,
                configuration: captureConfiguration
            )

            let viewController = try MainViewController(
                context: metalContext,
                captureService: captureService,
                initialTarget: initialTarget,
                outputView: overlayController.mtkView,
                overlayController: overlayController
            )

            controlWindow.contentViewController = viewController
            // The panel's constraints fix the height, so size to fit instead of guessing.
            viewController.view.layoutSubtreeIfNeeded()
            let fitting = viewController.view.fittingSize.height
            controlWindow.setContentSize(NSSize(width: 1180, height: fitting))
            controlWindow.center()

            controlWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)

            self.controlWindow = controlWindow
            self.mainViewController = viewController

            Task { await viewController.start() }
            requestScreenCapturePermissionIfNeededAsync()
        } catch {
            print("CRITICAL: Bootstrap failed: \(error)")
            presentFatalInitializationError(error)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Nothing to stop: quit at once.
        guard let mainViewController, mainViewController.isScaling else {
            return .terminateNow
        }

        Task { @MainActor in
            await mainViewController.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func presentFatalInitializationError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "MetalDuck failed to initialize"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }

    private func requestScreenCapturePermissionIfNeededAsync() {
        DispatchQueue.global(qos: .userInitiated).async {
            AppDelegate.requestScreenCapturePermissionIfNeeded()
        }
    }

    nonisolated private static func requestScreenCapturePermissionIfNeeded() {
        guard !CGPreflightScreenCaptureAccess() else {
            return
        }

        _ = CGRequestScreenCaptureAccess()
    }

    /// Starts a new copy of MetalDuck and quits this one. macOS applies a Screen Recording
    /// permission granted while the app runs only after it restarts.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            // Quit from the run loop, not from a main-queue block: terminating waits for the stop
            // task, which runs on the main queue and could never start inside a main-queue block.
            DispatchQueue.main.async {
                NSApplication.shared.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
            }
        }
    }
}
