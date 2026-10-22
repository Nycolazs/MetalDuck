import AppKit

final class SettingsViewController: NSViewController {
    var onShortcutChanged: (() -> Void)?

    private let settingsStore: SettingsStore

    private let shortcutToggle = NSSwitch()
    private let recorderField = ShortcutRecorderField()

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        shortcutToggle.controlSize = .small
        shortcutToggle.target = self
        shortcutToggle.action = #selector(handleToggleChanged)

        recorderField.target = self
        recorderField.action = #selector(handleRecorderTapped)
        recorderField.onShortcutChanged = { [weak self] newShortcut in
            guard let self else { return }
            var current = self.settingsStore.shortcut
            current.keyCode = newShortcut.keyCode
            current.modifiers = newShortcut.modifiers
            self.settingsStore.shortcut = current
            ShortcutManager.shared.update(settings: current)
            self.onShortcutChanged?()
        }

        let hint = GlassLabel.make(
            "Click the field, then press a key with ⌘, ⌥, ⌃ or ⇧, or a function key. Delete clears it. \(ShortcutManager.panicDisplay) always stops scaling.",
            font: GlassFont.caption,
            color: .tertiaryLabelColor
        )
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 3
        hint.preferredMaxLayoutWidth = 352

        recorderField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        let group = SettingsGroup(title: "Keyboard", symbol: "keyboard")
        group.addRow(SettingRow.control("Global shortcut", symbol: "command", help: "Starts or stops scaling from any app.", control: shortcutToggle))
        group.addRow(SettingRow.control("Shortcut", symbol: "record.circle", control: recorderField))

        let body = NSStackView(views: [group, hint])
        body.translatesAutoresizingMaskIntoConstraints = false
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10
        for row in body.arrangedSubviews {
            row.leadingAnchor.constraint(equalTo: body.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: body.trailingAnchor).isActive = true
        }

        view = GlassSheet.makeView(
            width: 400,
            symbol: "gearshape",
            title: "Settings",
            message: "Control MetalDuck without switching apps.",
            body: body,
            buttons: [GlassButton.push("Done", target: self, action: #selector(handleDone), isDefault: true)]
        )
        applySettings()
    }

    private func applySettings() {
        let shortcut = settingsStore.shortcut
        shortcutToggle.state = shortcut.enabled ? .on : .off
        recorderField.shortcut = shortcut
        recorderField.isEnabled = shortcut.enabled
    }

    @objc private func handleToggleChanged() {
        var current = settingsStore.shortcut
        current.enabled = shortcutToggle.state == .on
        settingsStore.shortcut = current
        recorderField.isEnabled = current.enabled
        ShortcutManager.shared.update(settings: current)
        onShortcutChanged?()
    }

    @objc private func handleRecorderTapped() {
        recorderField.isRecording = true
    }

    @objc private func handleDone() {
        recorderField.isRecording = false
        dismiss(nil)
    }
}

final class ShortcutRecorderField: NSButton {
    var onShortcutChanged: ((ShortcutSettings) -> Void)?

    var isRecording = false {
        didSet {
            updateAppearance()
            if isRecording {
                window?.makeFirstResponder(self)
            }
        }
    }

    var shortcut: ShortcutSettings? {
        didSet { updateAppearance() }
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        bezelStyle = .push
        controlSize = .large
        setButtonType(.momentaryPushIn)
        font = GlassFont.value
        heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        if isRecording {
            title = "Press a shortcut…"
            bezelColor = .controlAccentColor
            contentTintColor = .white
        } else if let shortcut, shortcut.keyCode != nil {
            title = shortcut.displayString
            bezelColor = nil
            contentTintColor = nil
        } else {
            title = "Record Shortcut"
            bezelColor = nil
            contentTintColor = .secondaryLabelColor
        }
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            let cleared = ShortcutSettings(enabled: true, keyCode: nil, modifiers: 0)
            shortcut = cleared
            onShortcutChanged?(cleared)
            isRecording = false
            return
        }

        if event.keyCode == 53 {
            isRecording = false
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !modifiers.isEmpty || isFunctionKey(event.keyCode) {
            let recorded = ShortcutSettings(enabled: true, keyCode: Int(event.keyCode), modifiers: modifiers.rawValue)
            shortcut = recorded
            onShortcutChanged?(recorded)
            isRecording = false
        }
    }

    private func isFunctionKey(_ keyCode: UInt16) -> Bool {
        (122...131).contains(keyCode) || (96...101).contains(keyCode) || (103...111).contains(keyCode)
    }

    override var acceptsFirstResponder: Bool { true }
}
