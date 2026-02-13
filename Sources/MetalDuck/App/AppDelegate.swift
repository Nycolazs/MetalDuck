import AppKit
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controlWindow: NSWindow?
    private var mainViewController: MainViewController?
    private var didBootstrap = false

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            let captureConfiguration = CaptureConfiguration(
                framesPerSecond: 30,
                queueDepth: 5,
                showsCursor: false,
                preferredPixelSize: CGSize(width: 1920, height: 1080)
            )
            let initialTarget: CaptureTarget = .window(nil)

            let controlWindow = NSWindow(
                contentRect: NSRect(x: 80, y: 90, width: 1360, height: 860),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )

            controlWindow.minSize = NSSize(width: 1080, height: 760)
            controlWindow.isReleasedWhenClosed = false
            controlWindow.setContentSize(NSSize(width: 1360, height: 860))
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
                settingsStore: SettingsStore(),
                captureConfiguration: captureConfiguration,
                initialTarget: initialTarget,
                outputView: overlayController.mtkView,
                overlayController: overlayController
            )

            controlWindow.contentViewController = viewController

            controlWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)

            self.controlWindow = controlWindow
            self.mainViewController = viewController

            Task { await viewController.start() }
            requestScreenCapturePermissionIfNeededAsync()
        } catch {
            presentFatalInitializationError(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let mainViewController else {
            return
        }

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            await mainViewController.stop()
            semaphore.signal()
        }

        semaphore.wait()
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
}
