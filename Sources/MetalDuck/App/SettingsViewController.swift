import AppKit
import UniformTypeIdentifiers

final class SettingsViewController: NSViewController {
    var onShortcutChanged: (() -> Void)?

    private let settingsStore: SettingsStore

    private let shortcutToggle = NSSwitch()
    private let recorderField = ShortcutRecorderField()
    private let losslessStatus = GlassLabel.make("", font: GlassFont.value, color: .secondaryLabelColor)
    private lazy var losslessImportButton = smallButton("Import…", action: #selector(handleImportLossless))

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

        let losslessGroup = SettingsGroup(title: "Lossless Scaling", symbol: "shippingbox")
        let losslessControls = NSStackView(views: [losslessStatus, losslessImportButton])
        losslessControls.orientation = .horizontal
        losslessControls.spacing = 8
        losslessGroup.addRow(SettingRow.control(
            LosslessScalingLibrary.fileName,
            symbol: "doc",
            help: "Your own copy of Lossless.dll from Lossless Scaling on Steam.",
            control: losslessControls
        ))
        losslessGroup.addRow(SettingRow.control(
            "Steam console",
            symbol: "terminal",
            help: "Opens steam://open/console and copies the download command.",
            control: smallButton("Open", action: #selector(handleOpenSteamConsole))
        ))

        let losslessHint = GlassLabel.make(
            "You need Lossless Scaling in your Steam library. Open the Steam console and run \(LosslessScalingLibrary.downloadCommand) (Open copies it for you). When Steam finishes, import Lossless.dll from the folder it prints.",
            font: GlassFont.caption,
            color: .tertiaryLabelColor
        )
        losslessHint.lineBreakMode = .byWordWrapping
        losslessHint.maximumNumberOfLines = 4
        losslessHint.preferredMaxLayoutWidth = 352

        let body = NSStackView(views: [group, hint, losslessGroup, losslessHint])
        body.translatesAutoresizingMaskIntoConstraints = false
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 10
        body.setCustomSpacing(20, after: hint)
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
        refreshLosslessStatus()
    }

    private func smallButton(_ title: String, action: Selector) -> NSButton {
        let button = HandCursorButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .push
        button.controlSize = .small
        return button
    }

    private func refreshLosslessStatus() {
        if let size = LosslessScalingLibrary.installedSize {
            losslessStatus.stringValue = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            losslessImportButton.title = "Replace…"
        } else {
            losslessStatus.stringValue = "Not imported"
            losslessImportButton.title = "Import…"
        }
    }

    @objc private func handleImportLossless() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.message = "Choose Lossless.dll from your Lossless Scaling download."
        panel.prompt = "Import"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let dll = UTType(filenameExtension: "dll") {
            panel.allowedContentTypes = [dll]
        }
        if let folder = LosslessScalingLibrary.steamDownloadFolder {
            panel.directoryURL = folder
        }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try LosslessScalingLibrary.importFile(from: url)
                self.refreshLosslessStatus()
            } catch {
                self.showAlert(title: "Could not import Lossless.dll", message: error.localizedDescription)
            }
        }
    }

    @objc private func handleOpenSteamConsole() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(LosslessScalingLibrary.downloadCommand, forType: .string)
        if !LosslessScalingLibrary.openSteamConsole() {
            showAlert(
                title: "Steam is not installed",
                message: "Install Steam, sign in, then try again. The command \(LosslessScalingLibrary.downloadCommand) is on the clipboard."
            )
        }
    }

    private func showAlert(title: String, message: String) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.beginSheetModal(for: window)
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
