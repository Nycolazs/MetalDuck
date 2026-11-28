import AppKit

/// The app's entry point. The executable target only calls `run()`, so everything else
/// lives in the library and can be tested.
@MainActor
public enum MetalDuckApplication {
    private static let appDelegate = AppDelegate()

    public static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = appDelegate
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
