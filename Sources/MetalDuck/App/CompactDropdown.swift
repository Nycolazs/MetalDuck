import AppKit

// MARK: - CompactDropdown

/// A fully custom dropdown selector that matches the MetalDuck dark UI aesthetic.
/// Replaces NSPopUpButton throughout the app with a compact, floating, animated panel.
@MainActor
final class CompactDropdown: NSView {

    // MARK: - Public API

    /// The list of option titles. Setting this rebuilds the displayed items.
    var items: [String] = [] {
        didSet { rebuildItems() }
    }

    /// The currently selected item's title (read/write).
    var selectedTitle: String? {
        get { _selectedTitle }
        set {
            if let t = newValue, items.contains(t) {
                _selectedTitle = t
                updateLabel()
            }
        }
    }

    /// Zero-based index of the currently selected item, or -1 if none.
    var indexOfSelectedItem: Int {
        guard let t = _selectedTitle else { return -1 }
        return items.firstIndex(of: t) ?? -1
    }

    /// Custom enabled state — callers can disable the control (e.g. captureSourceDropdown).
    var isEnabled: Bool = true {
        didSet {
            alphaValue = isEnabled ? 1.0 : 0.45
        }
    }

    /// Called when the user picks an option. Receives (title, index).
    var onSelectionChanged: ((String, Int) -> Void)?

    // MARK: - Programmatic selection (non-triggering)

    func selectItem(withTitle title: String) {
        guard items.contains(title) else { return }
        _selectedTitle = title
        updateLabel()
    }

    func selectItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        _selectedTitle = items[index]
        updateLabel()
    }

    // MARK: - Private state

    private var _selectedTitle: String?

    // Selector field subviews
    private let selectorContainer = NSView()
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSTextField(labelWithString: "▾")

    // Floating panel
    private var panel: NSPanel?
    private var panelContentView: NSView?
    private var itemRows: [DropdownItemRow] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Setup

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        // Selector container (the visible "button" area)
        selectorContainer.translatesAutoresizingMaskIntoConstraints = false
        selectorContainer.wantsLayer = true
        selectorContainer.layer?.cornerRadius = 8
        selectorContainer.layer?.borderWidth = 1
        selectorContainer.layer?.borderColor = DropdownTheme.border.cgColor
        selectorContainer.layer?.backgroundColor = DropdownTheme.selectorBg.cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = DropdownTheme.font
        label.textColor = DropdownTheme.bodyText
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        chevron.textColor = DropdownTheme.mutedText
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.isHidden = true

        selectorContainer.addSubview(label)
        selectorContainer.addSubview(chevron)
        addSubview(selectorContainer)

        NSLayoutConstraint.activate([
            selectorContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectorContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            selectorContainer.topAnchor.constraint(equalTo: topAnchor),
            selectorContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            selectorContainer.heightAnchor.constraint(equalToConstant: 26),

            label.leadingAnchor.constraint(equalTo: selectorContainer.leadingAnchor, constant: 9),
            label.centerYAnchor.constraint(equalTo: selectorContainer.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: selectorContainer.trailingAnchor, constant: -9),

            chevron.trailingAnchor.constraint(equalTo: selectorContainer.trailingAnchor, constant: -8),
            chevron.centerYAnchor.constraint(equalTo: selectorContainer.centerYAnchor),
        ])

        // Track clicks
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleSelectorClick))
        selectorContainer.addGestureRecognizer(click)

        // Hover tracking on selector
        setupSelectorTracking()
    }

    // MARK: - Hover on Selector

    private var selectorTrackingArea: NSTrackingArea?

    private func setupSelectorTracking() {
        if let old = selectorTrackingArea {
            selectorContainer.removeTrackingArea(old)
        }
        let area = NSTrackingArea(
            rect: selectorContainer.bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        selectorContainer.addTrackingArea(area)
        selectorTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            selectorContainer.layer?.backgroundColor = DropdownTheme.selectorHoverBg.cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            selectorContainer.layer?.backgroundColor = DropdownTheme.selectorBg.cgColor
        }
    }

    // MARK: - Label Update

    private func updateLabel() {
        label.stringValue = _selectedTitle ?? ""
    }

    private func rebuildItems() {
        // If panel currently open, refresh it
        if panel != nil {
            closePanel(animated: false)
        }
    }

    // MARK: - Open / Close

    @objc private func handleSelectorClick() {
        guard isEnabled else { return }
        if panel != nil {
            closePanel(animated: true)
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let window = self.window, let _ = window.screen else { return }

        // Build content view
        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 11
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = DropdownTheme.panelBg.cgColor

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        contentView.addSubview(stack)

        itemRows = items.enumerated().map { (idx, title) in
            let row = DropdownItemRow(
                title: title,
                isSelected: title == _selectedTitle,
                onSelect: { [weak self] in
                    self?.didSelectItem(title: title, index: idx)
                }
            )
            stack.addArrangedSubview(row)
            return row
        }

        // Constrain stack to content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])

        // Make rows fill width
        let panelWidth: CGFloat = max(bounds.width, 160)
        let rowHeight: CGFloat = 28
        let panelHeight: CGFloat = CGFloat(items.count) * rowHeight + 8

        for row in itemRows {
            row.widthAnchor.constraint(equalToConstant: panelWidth - 8).isActive = true
            row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        }

        contentView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        // Create panel
        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.level = .popUpMenu
        newPanel.contentView = contentView
        newPanel.isReleasedWhenClosed = false

        // Shadow on the window
        newPanel.contentView?.wantsLayer = true

        // Position: directly below the selector field
        let selectorFrameInWindow = convert(bounds, to: nil)
        let screenFrame = window.convertToScreen(selectorFrameInWindow)
        let panelOrigin = NSPoint(
            x: screenFrame.minX,
            y: screenFrame.minY - panelHeight - 2
        )
        newPanel.setFrameOrigin(panelOrigin)

        // Animate in: start transparent + slightly scaled
        contentView.alphaValue = 0
        contentView.layer?.transform = CATransform3DMakeScale(0.98, 0.98, 1)

        window.addChildWindow(newPanel, ordered: .above)
        self.panel = newPanel
        self.panelContentView = contentView

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.13
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            contentView.alphaValue = 1
            contentView.layer?.transform = CATransform3DIdentity
        }

        // Install click-outside monitors
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.closePanel(animated: true) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            // If the click is inside the panel, allow it through
            if let p = self.panel, event.window == p { return event }
            // If the click is on this selector view, allow (handleSelectorClick will close)
            if event.window == self.window {
                let loc = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(loc) { return event }
            }
            DispatchQueue.main.async { self.closePanel(animated: true) }
            return event
        }
    }

    private func closePanel(animated: Bool) {
        removeEventMonitors()
        guard let panel = panel, let content = panelContentView else { return }
        self.panel = nil
        self.panelContentView = nil
        self.itemRows = []

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                ctx.allowsImplicitAnimation = true
                content.alphaValue = 0
            } completionHandler: {
                DispatchQueue.main.async {
                    panel.parent?.removeChildWindow(panel)
                    panel.close()
                }
            }
        } else {
            panel.parent?.removeChildWindow(panel)
            panel.close()
        }
    }

    private func removeEventMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    // MARK: - Selection

    private func didSelectItem(title: String, index: Int) {
        _selectedTitle = title
        updateLabel()
        // Refresh checkmarks visually
        for row in itemRows { row.setSelected(row.title == title) }
        closePanel(animated: true)
        onSelectionChanged?(title, index)
    }

}

// MARK: - DropdownItemRow

/// A single row inside the dropdown panel list.
@MainActor
private final class DropdownItemRow: NSView {
    let title: String
    private let onSelect: () -> Void
    private let titleLabel = NSTextField(labelWithString: "")
    private let checkLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var _isSelected = false

    init(title: String, isSelected: Bool, onSelect: @escaping () -> Void) {
        self.title = title
        self.onSelect = onSelect
        super.init(frame: .zero)
        self._isSelected = isSelected
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = DropdownTheme.font
        titleLabel.textColor = DropdownTheme.bodyText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        checkLabel.translatesAutoresizingMaskIntoConstraints = false
        checkLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        checkLabel.textColor = DropdownTheme.accent
        checkLabel.stringValue = isSelected ? "✓" : " "
        checkLabel.setContentHuggingPriority(.required, for: .horizontal)
        checkLabel.widthAnchor.constraint(equalToConstant: 16).isActive = true

        titleLabel.stringValue = title
        addSubview(titleLabel)
        addSubview(checkLabel)

        NSLayoutConstraint.activate([
            checkLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            checkLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: checkLabel.trailingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateBackground()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ selected: Bool) {
        _isSelected = selected
        checkLabel.stringValue = selected ? "✓" : " "
        updateBackground()
    }

    private func updateBackground() {
        if isHovered {
            layer?.backgroundColor = DropdownTheme.rowHoverBg.cgColor
        } else if _isSelected {
            layer?.backgroundColor = DropdownTheme.rowSelectedBg.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            ctx.allowsImplicitAnimation = true
            updateBackground()
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            ctx.allowsImplicitAnimation = true
            updateBackground()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) { onSelect() }
    }

    override func mouseDown(with event: NSEvent) {
        // Accept mouseDown so mouseUp fires in this view
    }
}

// MARK: - DropdownTheme

/// Local colour + font constants that match UniTheme / the app's card style.
private enum DropdownTheme {
    // Selector field
    static let selectorBg    = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 0.70)
    static let selectorHoverBg = NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.25, alpha: 0.80)
    static let border        = NSColor(calibratedRed: 0.26, green: 0.27, blue: 0.32, alpha: 0.35)

    // Floating panel
    static let panelBg       = NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.18, alpha: 0.98)

    // Rows
    static let rowHoverBg    = NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.26, alpha: 1.0)
    static let rowSelectedBg = NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.24, alpha: 0.60)

    // Text
    static let bodyText  = NSColor(calibratedRed: 0.78, green: 0.80, blue: 0.84, alpha: 1.0)
    static let mutedText = NSColor(calibratedRed: 0.50, green: 0.53, blue: 0.58, alpha: 1.0)
    static let accent    = NSColor(calibratedRed: 0.30, green: 0.56, blue: 0.93, alpha: 1.0)

    nonisolated(unsafe) static let font = NSFont.systemFont(ofSize: 12, weight: .medium)
}
