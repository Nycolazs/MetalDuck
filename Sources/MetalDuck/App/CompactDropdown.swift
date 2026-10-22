import AppKit

/// In-app picker. Same selection API as the old pop-up button: programmatic
/// `selectItem` calls do not fire `onSelectionChanged`; only a user pick does.
@MainActor
final class CompactDropdown: NSControl {
    var items: [String] = [] {
        didSet {
            let previous = titleOfSelectedItem
            if let previous, let index = items.firstIndex(of: previous) {
                selectedIndex = index
            } else {
                selectedIndex = items.isEmpty ? -1 : 0
            }
            refreshTitle()
            openMenu?.dismiss()
        }
    }

    var onSelectionChanged: ((String, Int) -> Void)?

    private var selectedIndex = -1
    private var openMenu: GlassDropdownMenu?
    private let titleLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private let chrome = DropdownChrome()

    var titleOfSelectedItem: String? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        focusRingType = .none
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)

        chrome.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chrome)
        pin(chrome, to: self)

        titleLabel.font = GlassFont.body
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        chevron.image = GlassSymbol.image("chevron.up.chevron.down", size: 9, weight: .semibold)
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [titleLabel, chevron])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 132),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12)
        ])
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func selectItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        refreshTitle()
    }

    func selectItem(withTitle title: String) {
        guard let index = items.firstIndex(of: title) else { return }
        selectItem(at: index)
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.4
            if !isEnabled { openMenu?.dismiss() }
        }
    }

    override var intrinsicContentSize: NSSize {
        let text = titleLabel.stringValue as NSString
        let width = text.size(withAttributes: [.font: GlassFont.body]).width
        return NSSize(width: min(240, max(148, ceil(width) + 46)), height: 32)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, !items.isEmpty else { return }
        if openMenu != nil {
            openMenu?.dismiss()
        } else {
            showMenu()
        }
    }

    private func refreshTitle() {
        titleLabel.stringValue = titleOfSelectedItem ?? "—"
        toolTip = titleOfSelectedItem
        invalidateIntrinsicContentSize()
    }

    private func showMenu() {
        guard let window, selectedIndex >= 0 else { return }
        GlassDropdownMenu.dismissCurrent()
        let menu = GlassDropdownMenu(items: items, selectedIndex: selectedIndex, anchor: self)
        menu.onSelect = { [weak self] index in
            guard let self else { return }
            self.selectItem(at: index)
            if let title = self.titleOfSelectedItem {
                self.onSelectionChanged?(title, index)
            }
        }
        menu.onDismiss = { [weak self] in
            self?.openMenu = nil
            self?.chrome.setOpen(false)
        }
        openMenu = menu
        chrome.setOpen(true)
        menu.show(below: self, in: window)
    }
}

private final class DropdownChrome: AppearanceLayerView {
    private var isOpen = false
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        accentObserver = GlassAccent.observe { [weak self] in
            self?.needsDisplay = true
        }
    }

    nonisolated(unsafe) private var accentObserver: NSObjectProtocol?

    deinit {
        if let accentObserver {
            NotificationCenter.default.removeObserver(accentObserver)
        }
    }

    override func applyLayerColors() {
        let dark = effectiveAppearance.isDark
        let alpha: CGFloat = isHovered || isOpen ? (dark ? 0.12 : 0.07) : (dark ? 0.07 : 0.04)
        let base: NSColor = dark ? .white : .black
        GlassMotion.animate(layer, backgroundColor: base.withAlphaComponent(alpha).cgColor)
        layer?.borderColor = (isOpen ? GlassAccent.color : GlassColor.stroke).cgColor
    }

    func setOpen(_ open: Bool) {
        isOpen = open
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }
}

private final class GlassMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class GlassDropdownMenu {
    static weak var current: GlassDropdownMenu?

    var onSelect: ((Int) -> Void)?
    var onDismiss: (() -> Void)?

    private let panel: NSPanel
    private let rows: [MenuRow]
    private var highlightedIndex: Int
    private var monitor: Any?
    private var didDismiss = false

    init(items: [String], selectedIndex: Int, anchor: NSView) {
        highlightedIndex = selectedIndex
        let rowHeight: CGFloat = 36
        let visible = min(items.count, 8)
        let width = Self.preferredWidth(for: items, minimum: anchor.bounds.width)
        let height = CGFloat(visible) * rowHeight + 12

        panel = GlassMenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.appearance = anchor.effectiveAppearance

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: 16)
        panel.contentView = effect

        let document = FlippedView()
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0

        let builtRows = items.enumerated().map { index, title in
            MenuRow(title: title, showsCheck: index == selectedIndex)
        }
        rows = builtRows
        for (index, row) in rows.enumerated() {
            row.onClick = { [weak self] in self?.commit(index) }
            row.onHover = { [weak self] in
                guard let self, self.highlightedIndex != index else { return }
                self.highlightedIndex = index
                self.applyHighlight()
            }
            stack.addArrangedSubview(row)
        }

        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = items.count > visible
        scroll.autohidesScrollers = true
        scroll.documentView = document
        effect.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: effect.topAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -6),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        for row in rows {
            row.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        }
        applyHighlight()
    }

    func show(below control: NSView, in window: NSWindow) {
        Self.current = self
        let screenRect = window.convertToScreen(control.convert(control.bounds, to: nil))
        let size = panel.frame.size
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? screenRect
        var origin = NSPoint(x: screenRect.minX, y: screenRect.minY - size.height - 6)
        if origin.y < visible.minY {
            origin.y = screenRect.maxY + 6
        }
        if origin.x + size.width > visible.maxX - 8 {
            origin.x = visible.maxX - size.width - 8
        }
        if origin.x < visible.minX + 8 {
            origin.x = visible.minX + 8
        }
        if GlassMotion.reduceMotion {
            panel.setFrameOrigin(origin)
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y + 8))
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(origin)
            }
        }
        rows[highlightedIndex].scrollToVisible(rows[highlightedIndex].bounds)

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event, control: control)
        }
    }

    func dismiss() {
        guard !didDismiss else { return }
        didDismiss = true
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        let panel = self.panel
        if GlassMotion.reduceMotion {
            panel.orderOut(nil)
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated { panel.orderOut(nil) }
            })
        }
        if Self.current === self { Self.current = nil }
        onDismiss?()
    }

    static func dismissCurrent() {
        current?.dismiss()
    }

    private func handle(_ event: NSEvent, control: NSView) -> NSEvent? {
        if event.type == .keyDown {
            switch event.keyCode {
            case 53:
                dismiss()
                return nil
            case 125:
                moveHighlight(1)
                return nil
            case 126:
                moveHighlight(-1)
                return nil
            case 36, 49:
                commit(highlightedIndex)
                return nil
            default:
                return event
            }
        }
        if event.type == .leftMouseDown, let index = rowIndex(at: event) {
            commit(index)
            return nil
        }
        if event.window == panel { return event }
        if event.window == control.window {
            let point = control.convert(event.locationInWindow, from: nil)
            if control.bounds.contains(point) { return event }
        }
        dismiss()
        return event
    }

    private func moveHighlight(_ delta: Int) {
        guard !rows.isEmpty else { return }
        highlightedIndex = min(rows.count - 1, max(0, highlightedIndex + delta))
        applyHighlight()
        rows[highlightedIndex].scrollToVisible(rows[highlightedIndex].bounds)
    }

    private func applyHighlight() {
        for (index, row) in rows.enumerated() {
            row.isHighlighted = index == highlightedIndex
        }
    }

    private func commit(_ index: Int) {
        onSelect?(index)
        dismiss()
    }

    /// Clicks on a nonactivating panel often arrive in the window underneath.
    /// Resolve them in screen space so a row still selects.
    private func rowIndex(at event: NSEvent) -> Int? {
        let screenPoint = event.window?.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
            ?? NSEvent.mouseLocation
        guard panel.frame.contains(screenPoint), let content = panel.contentView else { return nil }
        let inContent = content.convert(panel.convertPoint(fromScreen: screenPoint), from: nil)
        for (index, row) in rows.enumerated() {
            if row.bounds.contains(row.convert(inContent, from: content)) {
                return index
            }
        }
        return nil
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private static func preferredWidth(for items: [String], minimum: CGFloat) -> CGFloat {
        let font = GlassFont.body
        let widest = items.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 80
        return min(360, max(minimum, ceil(widest) + 64))
    }

}

@MainActor
private final class MenuRow: AppearanceLayerView {
    var onClick: (() -> Void)?
    var onHover: (() -> Void)?
    var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    private let titleLabel: NSTextField
    private let check: NSImageView

    init(title: String, showsCheck: Bool) {
        titleLabel = GlassLabel.make(title, font: GlassFont.body)
        check = NSImageView()
        super.init(frame: .zero)
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous

        check.image = showsCheck ? GlassSymbol.image("checkmark", size: 11, weight: .semibold) : nil
        check.contentTintColor = GlassAccent.color
        check.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [check, titleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        addSubview(stack)
        NSLayoutConstraint.activate([
            check.widthAnchor.constraint(equalToConstant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func applyLayerColors() {
        GlassMotion.animate(layer, backgroundColor: (isHighlighted ? GlassColor.selection : NSColor.clear).cgColor, duration: 0.12)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
