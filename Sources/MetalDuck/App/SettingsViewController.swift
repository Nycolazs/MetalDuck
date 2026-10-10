import AppKit

final class SettingsViewController: NSViewController {
    private let settingsStore: SettingsStore
    
    private let titleLabel = NSTextField(labelWithString: "Settings")
    private let shortcutToggle = NSSwitch()
    private let shortcutLabel = NSTextField(labelWithString: "Enable global shortcut")
    private let recorderField = ShortcutRecorderField()
    private let descriptionLabel = NSTextField(labelWithString: "The shortcut toggles Scale on/off.")
    
    private var clickMonitor: Any?

    
    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1.0).cgColor
        self.view = view
        
        self.preferredContentSize = NSSize(width: 320, height: 240)
        
        setupUI()
        layoutUI()
        applySettings()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        setupClickOutsideMonitor()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    private func setupClickOutsideMonitor() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let window = self.view.window else { return event }
            
            let locationInWindow = event.locationInWindow
            let locationInView = self.view.convert(locationInWindow, from: nil)
            
            if !self.view.bounds.contains(locationInView) {
                // Click is outside the view (and thus the sheet content area)
                self.dismiss(nil)
                return nil // Consume event
            }
            return event
        }
    }

    
    private func setupUI() {
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .white
        
        shortcutLabel.font = .systemFont(ofSize: 14)
        shortcutLabel.textColor = .white
        
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
        }
        
        descriptionLabel.font = .systemFont(ofSize: 11)
        descriptionLabel.textColor = .secondaryLabelColor
    }
    
    private func layoutUI() {
        let titleStack = NSStackView(views: [titleLabel])
        titleStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 10, right: 20)
        
        let toggleStack = NSStackView(views: [shortcutLabel, NSView(), shortcutToggle])
        toggleStack.orientation = .horizontal
        toggleStack.distribution = .fill
        
        let recorderStack = NSStackView(views: [recorderField])
        recorderStack.alignment = .leading
        
        let mainStack = NSStackView(views: [titleLabel, toggleStack, recorderField, descriptionLabel])
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 16
        mainStack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        
        view.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: view.topAnchor),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
            
            toggleStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -48),
            recorderField.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -48),
            recorderField.heightAnchor.constraint(equalToConstant: 32)
        ])
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
    }
    
    @objc private func handleRecorderTapped() {
        recorderField.isRecording = true
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
        didSet {
            updateAppearance()
        }
    }
    
    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        wantsLayer = true
        updateAppearance()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func updateAppearance() {
        if isRecording {
            title = "Recording... Press keys"
            layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.3).cgColor
        } else if let shortcut = shortcut, shortcut.keyCode != nil {
            title = shortcut.displayString
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        } else {
            title = "Click to record shortcut"
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        }
        
        if !isEnabled {
            alphaValue = 0.5
        } else {
            alphaValue = 1.0
        }
    }
    
    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        if isRecording {
            if event.keyCode == 51 || event.keyCode == 117 { // Delete or Backspace to clear
                let newShortcut = ShortcutSettings(enabled: true, keyCode: nil, modifiers: 0)
                self.shortcut = newShortcut
                onShortcutChanged?(newShortcut)
                isRecording = false
                return
            }
            
            if event.keyCode == 53 { // Escape
                isRecording = false
                return
            }
            
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !modifiers.isEmpty || isFunctionKey(event.keyCode) {
                let newShortcut = ShortcutSettings(enabled: true, keyCode: Int(event.keyCode), modifiers: modifiers.rawValue)
                self.shortcut = newShortcut
                onShortcutChanged?(newShortcut)
                isRecording = false
            }
        } else {
            super.keyDown(with: event)
        }
    }
    
    private func isFunctionKey(_ keyCode: UInt16) -> Bool {
        // F1-F12 keys are roughly 122-111 and others
        return (122...131).contains(keyCode) || (96...101).contains(keyCode) || (103...111).contains(keyCode)
    }
    
    override var acceptsFirstResponder: Bool { true }
}
