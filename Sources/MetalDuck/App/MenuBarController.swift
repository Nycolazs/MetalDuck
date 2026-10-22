import AppKit

/// Menu-bar extra, present for the whole session. Clicking it opens the menu
/// whether or not scaling is running, and Stop lives there.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onShowWindow: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var isRunning = false
    private var hint = ShortcutManager.panicDisplay

    override init() {
        super.init()
        // Sit on the always-visible side of menu-bar organizers (Hidden Bar's
        // separator is near 351; lower values stay toward the system icons).
        let positionKey = "NSStatusItem Preferred Position MetalDuck"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(335.0, forKey: positionKey)
        }
        statusItem.autosaveName = "MetalDuck"

        let menu = NSMenu()
        menu.delegate = self
        // An empty menu is parked offscreen by the menu bar. Fill it before assigning.
        rebuild(menu)
        if let button = statusItem.button {
            button.image = symbol("play.rectangle", pointSize: 15)
            button.setAccessibilityLabel("MetalDuck")
        }
        statusItem.menu = menu
        statusItem.isVisible = true
        applyIcon()
    }

    func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        isRunning = running
        applyIcon()
    }

    func setHint(_ hint: String) {
        self.hint = hint
        applyIcon()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let title = NSMenuItem(title: "MetalDuck", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let state = NSMenuItem(
            title: isRunning ? "Scaling is on" : "Not running",
            action: nil,
            keyEquivalent: ""
        )
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())

        if isRunning {
            let stop = NSMenuItem(title: "Stop Scaling", action: #selector(handleStop), keyEquivalent: "")
            stop.target = self
            stop.image = symbol("stop.fill")
            menu.addItem(stop)
        } else {
            let start = NSMenuItem(title: "Start Scaling", action: #selector(handleStart), keyEquivalent: "")
            start.target = self
            start.image = symbol("play.fill")
            menu.addItem(start)
        }

        let shortcut = NSMenuItem(title: "Stop with \(hint)", action: nil, keyEquivalent: "")
        shortcut.isEnabled = false
        menu.addItem(shortcut)
        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show Window", action: #selector(handleShowWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let quit = NSMenuItem(title: "Quit MetalDuck", action: #selector(handleQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    private func applyIcon() {
        let name = isRunning ? "stop.circle.fill" : "play.rectangle"
        statusItem.button?.image = symbol(name, pointSize: 15)
        statusItem.button?.toolTip = isRunning ? "MetalDuck — Stop with \(hint)" : "MetalDuck"
    }

    private func symbol(_ name: String, pointSize: CGFloat = 13) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium))
        image?.isTemplate = true
        return image
    }

    @objc private func handleStop() {
        onStop?()
    }

    @objc private func handleStart() {
        onStart?()
    }

    @objc private func handleShowWindow() {
        onShowWindow?()
    }

    @objc private func handleQuit() {
        onQuit?()
    }
}
