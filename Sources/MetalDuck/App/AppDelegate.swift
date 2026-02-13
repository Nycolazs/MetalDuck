import AppKit
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
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
            let captureConfiguration = CaptureConfiguration(framesPerSecond: 60)
            let initialTarget: CaptureTarget = .automatic
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
                initialTarget: initialTarget
            )

            let window = NSWindow(
                contentRect: NSRect(x: 120, y: 120, width: 1560, height: 920),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )

            window.minSize = NSSize(width: 1200, height: 760)
            window.isReleasedWhenClosed = false
            window.contentViewController = viewController
            window.setContentSize(NSSize(width: 1560, height: 920))
            window.center()
            window.orderFrontRegardless()
            window.makeMain()
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)

            self.window = window
            self.mainViewController = viewController

            Task { await viewController.start() }
            requestScreenCapturePermissionIfNeededAsync()
        } catch {
            fatalError("Failed to initialize MetalDuck: \(error)")
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
