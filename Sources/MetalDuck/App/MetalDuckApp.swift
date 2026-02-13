import AppKit

@MainActor
@main
enum MetalDuckApp {
    private static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = appDelegate
        appDelegate.bootstrapIfNeeded()
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
