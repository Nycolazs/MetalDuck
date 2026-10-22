import AppKit

/// Shown before the first start. Scaling can cover the desktop, so a personal
/// stop shortcut has to exist before the picture goes up.
@MainActor
final class StopShortcutViewController: NSViewController {
    var onReady: (() -> Void)?

    private let settingsStore: SettingsStore
    private let recorder = ShortcutRecorderField()
    private let startButton: NSButton

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        startButton = GlassButton.push("Start", target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
        startButton.target = self
        startButton.action = #selector(handleStart)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        recorder.target = self
        recorder.action = #selector(handleRecorderTapped)
        recorder.onShortcutChanged = { [weak self] recorded in
            self?.store(recorded)
        }
        recorder.shortcut = settingsStore.shortcut
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        refreshStartButton()

        let hint = GlassLabel.make(
            "\(ShortcutManager.panicDisplay) always stops scaling too. The MetalDuck icon in the menu bar does as well.",
            font: GlassFont.caption,
            color: .tertiaryLabelColor
        )
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2
        hint.preferredMaxLayoutWidth = 372

        let body = NSStackView(views: [recorder, hint])
        body.orientation = .vertical
        body.alignment = .centerX
        body.spacing = 10
        body.translatesAutoresizingMaskIntoConstraints = false

        view = GlassSheet.makeView(
            width: 420,
            symbol: "keyboard",
            title: "Set a stop shortcut",
            message: "The scaled picture can cover this window. Choose a shortcut now, so you can turn scaling off from any app.",
            body: body,
            buttons: [
                GlassButton.push("Cancel", target: self, action: #selector(handleCancel), isCancel: true),
                startButton
            ]
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        recorder.isRecording = settingsStore.shortcut.keyCode == nil
    }

    private func store(_ recorded: ShortcutSettings) {
        var shortcut = recorded
        shortcut.enabled = shortcut.keyCode != nil
        settingsStore.shortcut = shortcut
        ShortcutManager.shared.update(settings: shortcut)
        recorder.shortcut = shortcut
        refreshStartButton()
    }

    private func refreshStartButton() {
        let shortcut = settingsStore.shortcut
        let reserved = shortcut.keyCode == 53
            && shortcut.modifiers == (NSEvent.ModifierFlags.command.rawValue
                | NSEvent.ModifierFlags.option.rawValue
                | NSEvent.ModifierFlags.control.rawValue)
        startButton.isEnabled = shortcut.keyCode != nil && !reserved
        startButton.keyEquivalent = startButton.isEnabled ? "\r" : ""
    }

    @objc private func handleRecorderTapped() {
        recorder.isRecording = true
    }

    @objc private func handleStart() {
        var shortcut = settingsStore.shortcut
        guard shortcut.keyCode != nil else {
            NSSound.beep()
            return
        }
        shortcut.enabled = true
        settingsStore.shortcut = shortcut
        ShortcutManager.shared.update(settings: shortcut)
        recorder.isRecording = false
        let ready = onReady
        dismiss(nil)
        ready?()
    }

    @objc private func handleCancel() {
        recorder.isRecording = false
        dismiss(nil)
    }
}
