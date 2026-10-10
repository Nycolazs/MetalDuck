import AppKit

/// A custom button view used in profile modals with hover, pressed states, and pointer cursor.
/// Matches MetalDuck dark UI theme.
final class ModalActionButton: NSView {
    /// Visual style of the button.
    enum Style {
        case primary    // Blue accent (Create, Save)
        case destructive // Red (Delete)
        case secondary  // Muted with border (Cancel)
    }
    
    private let style: Style
    private let label: NSTextField
    private var isHovered = false { didSet { updateAppearance() } }
    private var isPressed = false { didSet { updateAppearance() } }
    private var trackingArea: NSTrackingArea?
    private var actionTarget: AnyObject?
    private var actionSelector: Selector?
    
    init(title: String, style: Style) {
        self.style = style
        self.label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 6
        
        label.font = .systemFont(ofSize: 13, weight: style == .secondary ? .medium : .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
        ])
        
        updateAppearance()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func setAction(_ action: Selector, target: AnyObject) {
        self.actionTarget = target
        self.actionSelector = action
    }
    
    // MARK: - Appearance
    
    private var baseBackground: NSColor {
        switch style {
        case .primary:
            return NSColor(calibratedRed: 0.30, green: 0.56, blue: 0.93, alpha: 1.0)
        case .destructive:
            return NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.25, alpha: 0.85)
        case .secondary:
            return NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 0.6)
        }
    }
    
    private var hoverBackground: NSColor {
        switch style {
        case .primary:
            return NSColor(calibratedRed: 0.35, green: 0.61, blue: 0.98, alpha: 1.0)
        case .destructive:
            return NSColor(calibratedRed: 0.92, green: 0.30, blue: 0.30, alpha: 0.95)
        case .secondary:
            return NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.25, alpha: 0.7)
        }
    }
    
    private var pressedBackground: NSColor {
        switch style {
        case .primary:
            return NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.85, alpha: 1.0)
        case .destructive:
            return NSColor(calibratedRed: 0.72, green: 0.18, blue: 0.18, alpha: 1.0)
        case .secondary:
            return NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.18, alpha: 0.8)
        }
    }
    
    private func updateAppearance() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            if isPressed {
                layer?.backgroundColor = pressedBackground.cgColor
            } else if isHovered {
                layer?.backgroundColor = hoverBackground.cgColor
            } else {
                layer?.backgroundColor = baseBackground.cgColor
            }
        }
        
        let textColor: NSColor
        switch style {
        case .primary, .destructive:
            textColor = .white
        case .secondary:
            textColor = isHovered
                ? NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1.0)
                : NSColor(calibratedRed: 0.78, green: 0.80, blue: 0.84, alpha: 1.0)
        }
        label.textColor = textColor
        
        if style == .secondary {
            layer?.borderWidth = 1
            layer?.borderColor = isHovered
                ? NSColor(calibratedRed: 0.36, green: 0.37, blue: 0.42, alpha: 0.5).cgColor
                : NSColor(calibratedRed: 0.26, green: 0.27, blue: 0.32, alpha: 0.35).cgColor
        }
    }
    
    // MARK: - Tracking & Events
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .cursorUpdate],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }
    
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
    }
    
    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }
    
    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        if wasPressed {
            let location = convert(event.locationInWindow, from: nil)
            if bounds.contains(location) {
                _ = actionTarget?.perform(actionSelector, with: self)
            }
        }
    }
}
