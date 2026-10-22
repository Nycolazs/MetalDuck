import AppKit
import Symbols

// MARK: - Motion

/// Small, consistent animations. Everything here honours Reduce Motion.
@MainActor
enum GlassMotion {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Fades a label to new text; no-op when the text is unchanged.
    static func crossfade(_ label: NSTextField, to text: String, duration: CFTimeInterval = 0.25) {
        guard label.stringValue != text else { return }
        if !reduceMotion {
            label.wantsLayer = true
            let transition = CATransition()
            transition.type = .fade
            transition.duration = duration
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            label.layer?.add(transition, forKey: "text")
        }
        label.stringValue = text
    }

    /// View-backed layers do not animate implicitly, so colour changes go through here.
    static func animate(_ layer: CALayer?, backgroundColor: CGColor, duration: CFTimeInterval = 0.18) {
        guard let layer else { return }
        if !reduceMotion, let from = layer.presentation()?.backgroundColor ?? layer.backgroundColor, from != backgroundColor {
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = from
            animation.toValue = backgroundColor
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "backgroundColor")
        }
        layer.backgroundColor = backgroundColor
    }

    /// Quick scale "pop" around the view's centre.
    static func pop(_ view: NSView, scale: CGFloat = 1.08) {
        guard !reduceMotion, let layer = view.layer, layer.bounds.width > 0 else { return }
        let center = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
        func scaled(_ factor: CGFloat) -> NSValue {
            var transform = CATransform3DMakeTranslation(center.x, center.y, 0)
            transform = CATransform3DScale(transform, factor, factor, 1)
            transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
            return NSValue(caTransform3D: transform)
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [scaled(1), scaled(scale), scaled(0.98), scaled(1)]
        animation.keyTimes = [0, 0.35, 0.7, 1]
        animation.duration = 0.32
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "pop")
    }

    static func bounce(_ imageView: NSImageView?) {
        guard let imageView, !reduceMotion else { return }
        imageView.addSymbolEffect(.bounce, options: .nonRepeating)
    }

    static func setPulsing(_ imageView: NSImageView, _ pulsing: Bool) {
        imageView.removeAllSymbolEffects()
        if pulsing, !reduceMotion {
            imageView.addSymbolEffect(.pulse, options: .repeating)
        }
    }

    /// Staggered fade-and-rise used when the window first appears.
    static func reveal(_ views: [NSView], delayStep: TimeInterval = 0.05) {
        guard !reduceMotion else { return }
        for (index, view) in views.enumerated() {
            view.wantsLayer = true
            view.alphaValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delayStep * Double(index)) {
                if let layer = view.layer {
                    let rise = CABasicAnimation(keyPath: "transform.translation.y")
                    rise.fromValue = -10
                    rise.toValue = 0
                    rise.duration = 0.45
                    rise.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                    layer.add(rise, forKey: "reveal")
                }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.4
                    view.animator().alphaValue = 1
                }
            }
        }
    }
}

// MARK: - Accent

extension Notification.Name {
    static let glassAccentChanged = Notification.Name("com.metalduck.accentChanged")
}

/// Blue while idle. While frame generation is running, the same spots turn ember.
@MainActor
enum GlassAccent {
    static let live = NSColor(srgbRed: 0.98, green: 0.40, blue: 0.16, alpha: 1)

    static var isLive = false {
        didSet {
            guard oldValue != isLive else { return }
            NotificationCenter.default.post(name: .glassAccentChanged, object: nil)
        }
    }

    static var color: NSColor { isLive ? live : .controlAccentColor }

    static func observe(_ update: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: .glassAccentChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                update()
            }
        }
    }
}

// MARK: - Tokens

enum GlassMetrics {
    static let sidebarWidth: CGFloat = 240
    /// Icons only: 10 pt list inset on each side of a 40 pt square row.
    static let sidebarCollapsedWidth: CGFloat = 60
    static let windowInset: CGFloat = 8
    static let contentInset: CGFloat = 24
    static let cardRadius: CGFloat = 16
    static let sidebarRadius: CGFloat = 16
    static let rowHorizontalPadding: CGFloat = 14
    static let rowHeight: CGFloat = 40
    static let rowIconWidth: CGFloat = 20
    static let rowIconSpacing: CGFloat = 10
    static let sliderTitleWidth: CGFloat = 104
    /// Shared width of trailing pickers so their edges line up down a column.
    static let controlWidth: CGFloat = 216
    static let sectionSpacing: CGFloat = 20
    static let columnSpacing: CGFloat = 16
    static let sidebarRowHeight: CGFloat = 40
}

@MainActor
enum GlassFont {
    static let largeTitle = NSFont.systemFont(ofSize: 24, weight: .bold)
    static let groupTitle = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let body = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let bodyMedium = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let caption = NSFont.systemFont(ofSize: 11, weight: .regular)
    static let captionMedium = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let sidebarHeader = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let sidebarItem = NSFont.systemFont(ofSize: 14, weight: .regular)
    static let sidebarItemSelected = NSFont.systemFont(ofSize: 14, weight: .medium)
    static let metric = NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .semibold)
    static let value = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
}

enum GlassColor {
    static let fillTop = dynamic(dark: .white.withAlphaComponent(0.14), light: .white.withAlphaComponent(0.42))
    static let fillBottom = dynamic(dark: .white.withAlphaComponent(0.05), light: .white.withAlphaComponent(0.18))
    static let stroke = dynamic(dark: .white.withAlphaComponent(0.08), light: .black.withAlphaComponent(0.06))
    static let highlight = dynamic(dark: .white.withAlphaComponent(0.22), light: .white.withAlphaComponent(0.95))
    static let hover = dynamic(dark: .white.withAlphaComponent(0.06), light: .black.withAlphaComponent(0.04))
    static let selection = dynamic(dark: .white.withAlphaComponent(0.12), light: .black.withAlphaComponent(0.07))
    static let separator = dynamic(dark: .white.withAlphaComponent(0.07), light: .black.withAlphaComponent(0.07))

    private static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.isDark ? dark : light
        }
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

// MARK: - Labels and symbols

@MainActor
enum GlassLabel {
    static func make(
        _ text: String,
        font: NSFont = GlassFont.body,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func sidebarHeader(_ text: String) -> NSTextField {
        make(text, font: GlassFont.sidebarHeader, color: .tertiaryLabelColor)
    }
}

@MainActor
enum GlassSymbol {
    static func image(_ name: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
    }

    static func view(_ name: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, tint: NSColor = .secondaryLabelColor) -> NSImageView {
        let view = NSImageView()
        view.image = image(name, size: size, weight: weight)
        view.contentTintColor = tint
        view.imageScaling = .scaleNone
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }
}

// MARK: - Surfaces

/// A view whose layer colours follow the current light/dark appearance.
class AppearanceLayerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            applyLayerColors()
        }
    }

    func applyLayerColors() {}
}

/// Hairline border plus a specular highlight that fades out down the top edge.
private final class GlassEdgeView: AppearanceLayerView {
    private let highlight = CALayer()
    private let highlightMask = CAGradientLayer()

    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        highlight.cornerRadius = cornerRadius
        highlight.cornerCurve = .continuous
        highlight.borderWidth = 1
        highlightMask.colors = [NSColor.black.cgColor, NSColor.clear.cgColor]
        highlightMask.startPoint = CGPoint(x: 0.5, y: 1)
        highlightMask.endPoint = CGPoint(x: 0.5, y: 0.55)
        highlight.mask = highlightMask
        layer?.addSublayer(highlight)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlight.frame = bounds
        highlightMask.frame = bounds
        CATransaction.commit()
    }

    override func applyLayerColors() {
        layer?.borderColor = GlassColor.stroke.cgColor
        highlight.borderColor = GlassColor.highlight.cgColor
    }
}

private final class GlassFillView: AppearanceLayerView {
    private let gradient = CAGradientLayer()

    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.isOpaque = false
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(gradient)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }

    override func applyLayerColors() {
        gradient.colors = [GlassColor.fillTop.cgColor, GlassColor.fillBottom.cgColor]
    }
}

/// Rounded glass panel. Uses Liquid Glass on macOS 26; earlier systems get a
/// translucent gradient (cards) or a behind-window blur (sidebar) with a
/// specular edge. Put content in `contentView`.
class GlassSurface: NSView {
    enum Style {
        case card
        case sidebar
    }

    let contentView = NSView()

    init(style: Style = .card, cornerRadius: CGFloat = GlassMetrics.cardRadius) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glass)
            pin(glass, to: self)
        } else {
            // Frost the window behind the panel, then lay a thin highlight and a
            // specular rim on top so the sidebar and the cards are the same glass.
            let blur = NSVisualEffectView()
            blur.material = .hudWindow
            blur.blendingMode = .withinWindow
            blur.state = .active
            blur.isEmphasized = true
            blur.maskImage = Self.roundedMask(radius: cornerRadius)
            blur.translatesAutoresizingMaskIntoConstraints = false
            let veil = GlassFillView(cornerRadius: cornerRadius)
            let edge = GlassEdgeView(cornerRadius: cornerRadius)
            addSubview(blur)
            addSubview(veil)
            addSubview(edge)
            pin(blur, to: self)
            pin(veil, to: self)
            pin(edge, to: self)
        }

        addSubview(contentView)
        pin(contentView, to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
}

/// Full-window blur that lets the desktop show through.
final class WindowBackdropView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .active
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class SeparatorLine: AppearanceLayerView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    override func applyLayerColors() {
        layer?.backgroundColor = GlassColor.separator.cgColor
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Grouped form

/// A titled group in the System Settings style: header above, rows inside a
/// glass card separated by inset hairlines.
final class SettingsGroup: NSView {
    private let rows = NSStackView()

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView(views: [
            GlassSymbol.view(symbol, size: 12, weight: .semibold),
            GlassLabel.make(title, font: GlassFont.groupTitle, color: .secondaryLabelColor)
        ])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6

        let card = GlassSurface()
        rows.translatesAutoresizingMaskIntoConstraints = false
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.setHuggingPriority(.required, for: .vertical)
        card.contentView.addSubview(rows)

        addSubview(header)
        addSubview(card)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            rows.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 3),
            rows.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -3)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addRow(_ view: NSView) {
        if !rows.arrangedSubviews.isEmpty {
            let separator = SeparatorLine()
            rows.addArrangedSubview(separator)
            let leading = GlassMetrics.rowHorizontalPadding + GlassMetrics.rowIconWidth + GlassMetrics.rowIconSpacing
            separator.leadingAnchor.constraint(equalTo: rows.leadingAnchor, constant: leading).isActive = true
            separator.trailingAnchor.constraint(equalTo: rows.trailingAnchor).isActive = true
        }
        rows.addArrangedSubview(view)
        view.leadingAnchor.constraint(equalTo: rows.leadingAnchor).isActive = true
        view.trailingAnchor.constraint(equalTo: rows.trailingAnchor).isActive = true
    }
}

@MainActor
enum SettingRow {
    /// Icon and title on the left, control on the right.
    static func control(_ title: String, symbol: String, help: String? = nil, control: NSView) -> NSView {
        control.setContentHuggingPriority(.required, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        return row([iconView(symbol), titleLabel(title, help: help), spacer, control])
    }

    /// Icon, fixed-width title, inline slider and trailing value.
    static func slider(_ title: String, symbol: String, help: String? = nil, slider: NSSlider, value: NSTextField) -> NSView {
        let label = titleLabel(title, help: help)
        label.widthAnchor.constraint(equalToConstant: GlassMetrics.sliderTitleWidth).isActive = true

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.controlSize = .small
        slider.setContentHuggingPriority(.init(1), for: .horizontal)

        value.translatesAutoresizingMaskIntoConstraints = false
        value.font = GlassFont.value
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: 52).isActive = true

        return row([iconView(symbol), label, slider, value])
    }

    private static func row(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = GlassMetrics.rowIconSpacing
        stack.edgeInsets = NSEdgeInsets(
            top: 0,
            left: GlassMetrics.rowHorizontalPadding,
            bottom: 0,
            right: GlassMetrics.rowHorizontalPadding
        )
        stack.heightAnchor.constraint(equalToConstant: GlassMetrics.rowHeight).isActive = true
        return stack
    }

    private static func iconView(_ symbol: String) -> NSView {
        let icon = GlassSymbol.view(symbol, size: 13)
        icon.imageScaling = .scaleProportionallyDown
        icon.widthAnchor.constraint(equalToConstant: GlassMetrics.rowIconWidth).isActive = true
        return icon
    }

    private static func titleLabel(_ title: String, help: String?) -> NSTextField {
        let label = GlassLabel.make(title, font: GlassFont.body)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.toolTip = help
        return label
    }
}

/// Pill selector drawn by the app. Setting `selectedSegment` only updates the
/// highlight; the action fires when the user clicks or drags across a segment.
@MainActor
final class GlassSegmentedControl: NSControl {
    private let titles: [String]
    private let track = SegmentChrome(filled: true)
    private let selection = SegmentChrome(filled: false)
    private var labels: [NSTextField] = []

    var selectedSegment = 0 {
        didSet {
            guard !labels.isEmpty, oldValue != selectedSegment else { return }
            refresh()
            if window != nil {
                animateSelection()
            }
        }
    }

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        focusRingType = .none
        setContentHuggingPriority(.required, for: .vertical)

        track.translatesAutoresizingMaskIntoConstraints = false
        selection.translatesAutoresizingMaskIntoConstraints = true
        addSubview(track)
        addSubview(selection)
        pin(track, to: self)

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        for title in titles {
            let label = NSTextField(labelWithString: title)
            label.font = GlassFont.body
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            labels.append(label)
            stack.addArrangedSubview(label)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let font = GlassFont.body
        let widest = titles.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 24
        let cell = max(48, ceil(widest) + 22)
        return NSSize(width: cell * CGFloat(max(titles.count, 1)) + 6, height: 32)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.45 }
    }

    override func layout() {
        super.layout()
        track.layer?.cornerRadius = bounds.height / 2
        guard !titles.isEmpty, !isAnimatingSelection else { return }
        selection.frame = selectionFrame()
        selection.layer?.cornerRadius = selection.frame.height / 2
    }

    private var isAnimatingSelection = false

    private func selectionFrame() -> NSRect {
        let inner = bounds.insetBy(dx: 3, dy: 3)
        let width = inner.width / CGFloat(max(titles.count, 1))
        let index = CGFloat(min(max(selectedSegment, 0), titles.count - 1))
        return NSRect(x: inner.minX + width * index, y: inner.minY, width: width, height: inner.height)
    }

    /// Slides the accent pill to the selected segment with a slight overshoot.
    private func animateSelection() {
        guard !GlassMotion.reduceMotion, bounds.width > 0 else {
            needsLayout = true
            return
        }
        isAnimatingSelection = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 1.3, 0.45, 1)
            selection.animator().frame = selectionFrame()
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isAnimatingSelection = false
                self?.needsLayout = true
            }
        })
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        choose(event)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            choose(next)
        }
    }

    private func choose(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), bounds.width > 0 else { return }
        let index = min(titles.count - 1, max(0, Int(point.x / bounds.width * CGFloat(titles.count))))
        guard index != selectedSegment else { return }
        selectedSegment = index
        sendAction(action, to: target)
    }

    private func refresh() {
        for (index, label) in labels.enumerated() {
            let selected = index == selectedSegment
            let color: NSColor = selected ? .white : .secondaryLabelColor
            if label.textColor != color, !GlassMotion.reduceMotion {
                label.wantsLayer = true
                let transition = CATransition()
                transition.type = .fade
                transition.duration = 0.2
                label.layer?.add(transition, forKey: "color")
            }
            label.textColor = color
            label.font = selected ? GlassFont.bodyMedium : GlassFont.body
        }
        if !isAnimatingSelection {
            needsLayout = true
        }
    }
}

private final class SegmentChrome: AppearanceLayerView {
    private let filled: Bool

    init(filled: Bool) {
        self.filled = filled
        super.init(frame: .zero)
        layer?.cornerCurve = .continuous
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
        if filled {
            let dark = effectiveAppearance.isDark
            layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.05)).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = GlassColor.stroke.cgColor
        } else {
            layer?.backgroundColor = GlassAccent.color.cgColor
        }
    }
}

@MainActor
enum GlassSegmented {
    static func make(_ labels: [String]) -> GlassSegmentedControl {
        GlassSegmentedControl(titles: labels)
    }
}

// MARK: - Metrics and status

final class MetricTile: NSView {
    private let valueLabel = GlassLabel.make("—", font: GlassFont.metric)
    private let unitLabel = GlassLabel.make("", font: GlassFont.caption, color: .secondaryLabelColor)
    private let detailLabel = GlassLabel.make(" ", font: GlassFont.caption, color: .tertiaryLabelColor)

    init(caption: String, symbol: String, unit: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        unitLabel.stringValue = unit ?? ""

        let captionRow = NSStackView(views: [
            GlassSymbol.view(symbol, size: 11, weight: .medium, tint: .tertiaryLabelColor),
            GlassLabel.make(caption, font: GlassFont.captionMedium, color: .secondaryLabelColor)
        ])
        captionRow.orientation = .horizontal
        captionRow.alignment = .centerY
        captionRow.spacing = 5

        let valueRow = NSStackView(views: [valueLabel, unitLabel])
        valueRow.orientation = .horizontal
        valueRow.alignment = .firstBaseline
        valueRow.spacing = 4

        let stack = NSStackView(views: [captionRow, valueRow, detailLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setCustomSpacing(6, after: captionRow)

        addSubview(stack)
        pin(stack, to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(value: String, detail: String? = nil) {
        GlassMotion.crossfade(valueLabel, to: value, duration: 0.3)
        valueLabel.textColor = value == "—" ? .tertiaryLabelColor : .labelColor
        GlassMotion.crossfade(detailLabel, to: detail ?? " ")
    }
}

/// Small switch whose on-state uses the same accent as the rest of the panel.
final class GlassSwitch: NSControl {
    nonisolated(unsafe) private var accentObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.checkBox)
        accentObserver = GlassAccent.observe { [weak self] in
            self?.needsDisplay = true
        }
    }

    deinit {
        if let accentObserver {
            NotificationCenter.default.removeObserver(accentObserver)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 32, height: 18) }

    var isOn = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let on = isOn
        let track = bounds
        NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2).fill(using: on ? GlassAccent.color : NSColor.white.withAlphaComponent(0.18))
        let knob = track.height - 4
        let x = on ? track.maxX - knob - 2 : track.minX + 2
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: track.minY + 2, width: knob, height: knob)).fill()
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        isOn.toggle()
        sendAction(action, to: target)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private extension NSBezierPath {
    func fill(using color: NSColor) {
        color.setFill()
        fill()
    }
}

/// Capsule with a coloured dot, e.g. "● Idle".
final class StatusPill: AppearanceLayerView {
    enum State {
        case idle
        case running
        case error

        var title: String {
            switch self {
            case .idle: return "Idle"
            case .running: return "Running"
            case .error: return "Attention"
            }
        }

    }

    private func color(for state: State) -> NSColor {
        switch state {
        case .idle: return .secondaryLabelColor
        case .running: return GlassAccent.live
        case .error: return .systemRed
        }
    }

    private let dot = NSImageView()
    private let label = GlassLabel.make("Idle", font: GlassFont.captionMedium)
    private var state: State = .idle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        dot.image = GlassSymbol.image("circle.fill", size: 7)
        dot.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [dot, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 20),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        set(.idle)
    }

    func set(_ state: State) {
        let changed = state != self.state
        self.state = state
        dot.contentTintColor = color(for: state)
        GlassMotion.crossfade(label, to: state.title)
        label.textColor = state == .idle ? .secondaryLabelColor : color(for: state)
        needsDisplay = true
        if changed {
            GlassMotion.setPulsing(dot, state == .running)
            GlassMotion.pop(self)
        }
    }

    override func applyLayerColors() {
        let alpha: CGFloat = state == .idle ? 0.12 : 0.16
        GlassMotion.animate(layer, backgroundColor: color(for: state).withAlphaComponent(alpha).cgColor, duration: 0.3)
    }
}

// MARK: - Sidebar rows

final class SidebarRow: AppearanceLayerView {
    var onClick: (() -> Void)?
    /// Plays when the pointer enters the row. Monitor and Settings use this for their icon.
    var onHover: (() -> Void)?
    /// Off when a `SidebarListView` draws a sliding selection behind the row.
    var drawsSelectionBackground = true

    var isSelected = false {
        didSet { refreshHoverAppearance() }
    }

    private let titleLabel: NSTextField
    let icon: NSImageView
    private var isHovered = false {
        didSet { refreshHoverAppearance() }
    }

    init(title: String, symbol: String) {
        titleLabel = GlassLabel.make(title, font: GlassFont.sidebarItem)
        icon = GlassSymbol.view(symbol, size: 16)
        icon.imageScaling = .scaleProportionallyDown
        super.init(frame: .zero)
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous

        icon.widthAnchor.constraint(equalToConstant: GlassMetrics.rowIconWidth).isActive = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [icon, titleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        addSubview(stack)

        // Gives way when the sidebar collapses to icons and the row is only 40 pt wide.
        let trailing = stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10)
        trailing.priority = .defaultHigh
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: GlassMetrics.sidebarRowHeight),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            trailing,
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        accentObserver = GlassAccent.observe { [weak self] in
            self?.refreshHoverAppearance()
        }
    }

    nonisolated(unsafe) private var accentObserver: NSObjectProtocol?

    deinit {
        if let accentObserver {
            NotificationCenter.default.removeObserver(accentObserver)
        }
    }

    /// Call inside an animation group to fade the title with the sidebar.
    func setTitleVisible(_ visible: Bool, animated: Bool) {
        let alpha: CGFloat = visible ? 1 : 0
        if animated {
            titleLabel.animator().alphaValue = alpha
        } else {
            titleLabel.alphaValue = alpha
        }
    }

    private func refreshHoverAppearance() {
        titleLabel.font = isSelected ? GlassFont.sidebarItemSelected : GlassFont.sidebarItem
        if isSelected {
            icon.contentTintColor = GlassAccent.color
        } else if isHovered {
            icon.contentTintColor = .labelColor
        } else {
            icon.contentTintColor = .secondaryLabelColor
        }
        needsDisplay = true
    }

    override func applyLayerColors() {
        let color: NSColor
        if isSelected && drawsSelectionBackground {
            color = GlassColor.selection
        } else if isHovered {
            color = GlassColor.selection
        } else {
            color = .clear
        }
        GlassMotion.animate(layer, backgroundColor: color.cgColor)
    }

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

    /// Pointer entered or left. The icon effect plays on the way in.
    func setPointerInside(_ inside: Bool) {
        guard inside != isHovered else { return }
        isHovered = inside
        if inside {
            onHover?()
        } else {
            icon.removeAllSymbolEffects()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        setPointerInside(true)
    }

    override func mouseExited(with event: NSEvent) {
        setPointerInside(false)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }
}

/// Sidebar list whose selection highlight slides between rows.
final class SidebarListView: FlippedView {
    private let indicator = SidebarSelectionIndicator()
    private weak var selectedRow: NSView?
    private var isAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        indicator.isHidden = true
        addSubview(indicator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if subview !== indicator {
            addSubview(indicator, positioned: .below, relativeTo: subview)
        }
    }

    func select(_ row: NSView?, animated: Bool) {
        selectedRow = row
        layoutSubtreeIfNeeded()
        guard let row, row.bounds.height > 0 else {
            indicator.isHidden = row == nil
            needsLayout = true
            return
        }
        let target = convert(row.bounds, from: row)
        if !animated || indicator.isHidden || GlassMotion.reduceMotion || window == nil {
            indicator.isHidden = false
            indicator.frame = target
            return
        }
        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.42
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 1.25, 0.4, 1)
            indicator.animator().frame = target
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isAnimating = false
                self?.needsLayout = true
            }
        })
        indicator.flashAccent()
    }

    override func layout() {
        super.layout()
        guard !isAnimating, let row = selectedRow, row.superview != nil, row.bounds.height > 0 else { return }
        indicator.isHidden = false
        indicator.frame = convert(row.bounds, from: row)
    }
}

/// Glass capsule with a short accent bar on its leading edge.
private final class SidebarSelectionIndicator: AppearanceLayerView {
    private let accentBar = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        accentBar.cornerRadius = 1.5
        layer?.addSublayer(accentBar)
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

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        accentBar.frame = CGRect(x: 0, y: bounds.midY - 8, width: 3, height: 16)
        CATransaction.commit()
    }

    func flashAccent() {
        guard !GlassMotion.reduceMotion else { return }
        let grow = CAKeyframeAnimation(keyPath: "transform.scale.y")
        grow.values = [0.2, 1.25, 1]
        grow.keyTimes = [0, 0.6, 1]
        grow.duration = 0.4
        accentBar.add(grow, forKey: "flash")
    }

    override func applyLayerColors() {
        layer?.backgroundColor = GlassColor.selection.cgColor
        layer?.borderColor = GlassColor.stroke.cgColor
        accentBar.backgroundColor = GlassAccent.color.cgColor
    }
}

// MARK: - Buttons

final class HandCursorButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// Capsule button drawn by the app: springs on press, brightens on hover and
/// morphs its symbol when the state it represents changes.
@MainActor
final class GlassActionButton: NSControl {
    enum Style {
        case accent
        case neutral
        case destructive
    }

    var style: Style {
        didSet { applyStyle() }
    }

    /// Tint for the symbol in the neutral style.
    var symbolTint: NSColor = .secondaryLabelColor {
        didSet { applyStyle() }
    }

    let imageView = NSImageView()
    private let chrome = ButtonChrome()
    private let titleLabel: NSTextField?
    private let symbolSize: CGFloat
    nonisolated(unsafe) private var accentObserver: NSObjectProtocol?
    private var isHovered = false {
        didSet { applyStyle() }
    }

    init(title: String?, symbol: String, style: Style, symbolSize: CGFloat = 12, height: CGFloat = 32) {
        self.style = style
        self.symbolSize = symbolSize
        titleLabel = title.map { GlassLabel.make($0, font: GlassFont.bodyMedium) }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        focusRingType = .none

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = GlassSymbol.image(symbol, size: symbolSize, weight: .semibold)
        imageView.imageScaling = .scaleNone
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        accentObserver = GlassAccent.observe { [weak self] in
            self?.applyStyle()
        }

        chrome.layer?.cornerRadius = height / 2
        addSubview(chrome)
        pin(chrome, to: self)

        let content = NSStackView(views: [imageView] + (titleLabel.map { [$0] } ?? []))
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 6
        addSubview(content)

        var constraints = [
            heightAnchor.constraint(equalToConstant: height),
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]
        if titleLabel == nil {
            constraints.append(widthAnchor.constraint(equalToConstant: height))
        } else {
            constraints.append(content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16))
            constraints.append(widthAnchor.constraint(greaterThanOrEqualToConstant: 96))
        }
        NSLayoutConstraint.activate(constraints)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        applyStyle()
    }

    deinit {
        if let accentObserver {
            NotificationCenter.default.removeObserver(accentObserver)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var title: String {
        get { titleLabel?.stringValue ?? "" }
        set {
            guard let titleLabel else { return }
            GlassMotion.crossfade(titleLabel, to: newValue, duration: 0.2)
            setAccessibilityLabel(newValue)
        }
    }

    /// Swaps the symbol; `.replace.magic` draws slashes and badges in or out.
    func setSymbol(_ name: String, animated: Bool = true) {
        guard let image = GlassSymbol.image(name, size: symbolSize, weight: .semibold) else { return }
        if animated, !GlassMotion.reduceMotion, window != nil {
            imageView.setSymbolImage(image, contentTransition: .replace.magic(fallback: .replace.downUp.byLayer))
        } else {
            imageView.image = image
        }
    }

    /// One expanding ring around the capsule, used to confirm a state change.
    func ripple(color: NSColor) {
        guard !GlassMotion.reduceMotion, let host = layer, bounds.width > 0 else { return }
        let ring = CAShapeLayer()
        ring.frame = bounds
        ring.path = CGPath(
            roundedRect: bounds,
            cornerWidth: bounds.height / 2,
            cornerHeight: bounds.height / 2,
            transform: nil
        )
        ring.fillColor = nil
        ring.strokeColor = color.cgColor
        ring.lineWidth = 2
        ring.opacity = 0
        host.insertSublayer(ring, at: 0)

        let scale = CABasicAnimation(keyPath: "transform")
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var grown = CATransform3DMakeTranslation(center.x, center.y, 0)
        grown = CATransform3DScale(grown, 1 + 18 / bounds.width, 1 + 18 / bounds.height, 1)
        grown = CATransform3DTranslate(grown, -center.x, -center.y, 0)
        scale.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        scale.toValue = NSValue(caTransform3D: grown)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.7
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.55
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "ripple")
        CATransaction.commit()
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.45 }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

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
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        setPressed(true)
        var inside = true
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let nowInside = bounds.contains(convert(next.locationInWindow, from: nil))
            if nowInside != inside {
                inside = nowInside
                setPressed(inside)
            }
            if next.type == .leftMouseUp { break }
        }
        if inside {
            setPressed(false)
            sendAction(action, to: target)
        }
    }

    private func setPressed(_ pressed: Bool) {
        guard !GlassMotion.reduceMotion, let layer, bounds.width > 0 else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        func scaled(_ factor: CGFloat) -> CATransform3D {
            var transform = CATransform3DMakeTranslation(center.x, center.y, 0)
            transform = CATransform3DScale(transform, factor, factor, 1)
            return CATransform3DTranslate(transform, -center.x, -center.y, 0)
        }
        let from = layer.presentation()?.transform ?? layer.transform
        let to = pressed ? scaled(0.94) : CATransform3DIdentity
        let animation: CABasicAnimation
        if pressed {
            animation = CABasicAnimation(keyPath: "transform")
            animation.duration = 0.1
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        } else {
            let spring = CASpringAnimation(keyPath: "transform")
            spring.damping = 11
            spring.stiffness = 320
            spring.mass = 0.8
            spring.duration = spring.settlingDuration
            animation = spring
        }
        animation.fromValue = NSValue(caTransform3D: from)
        animation.toValue = NSValue(caTransform3D: to)
        layer.transform = to
        layer.add(animation, forKey: "press")
    }

    private func applyStyle() {
        let foreground: NSColor
        switch style {
        case .accent:
            let accent = GlassAccent.color
            chrome.fill = isHovered ? accent.blended(withFraction: 0.12, of: .white) ?? accent : accent
            chrome.border = .clear
            foreground = .white
            imageView.contentTintColor = .white
        case .neutral:
            chrome.fill = isHovered ? GlassColor.selection : GlassColor.fillTop
            chrome.border = GlassColor.stroke
            foreground = .labelColor
            imageView.contentTintColor = symbolTint
        case .destructive:
            chrome.fill = NSColor.systemRed.withAlphaComponent(isHovered ? 0.26 : 0.18)
            chrome.border = NSColor.systemRed.withAlphaComponent(0.3)
            foreground = .systemRed
            imageView.contentTintColor = .systemRed
        }
        titleLabel?.textColor = foreground
        chrome.needsDisplay = true
    }
}

private final class ButtonChrome: AppearanceLayerView {
    var fill: NSColor = .clear
    var border: NSColor = .clear

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func applyLayerColors() {
        GlassMotion.animate(layer, backgroundColor: fill.cgColor, duration: 0.25)
        layer?.borderColor = border.cgColor
    }
}

@MainActor
enum GlassButton {
    /// Borderless symbol button, as used in sidebars and toolbars.
    static func icon(_ symbol: String, help: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = HandCursorButton(
            image: GlassSymbol.image(symbol, size: 12, weight: .medium) ?? NSImage(),
            target: target,
            action: action
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = help
        button.setAccessibilityLabel(help)
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    static func push(_ title: String, target: AnyObject?, action: Selector?, isDefault: Bool = false, isCancel: Bool = false) -> NSButton {
        let button = HandCursorButton(title: title, target: target, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .push
        button.controlSize = .large
        if isDefault {
            button.keyEquivalent = "\r"
        }
        if isCancel {
            button.keyEquivalent = "\u{1b}"
        }
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
        return button
    }
}

// MARK: - Sheets

/// Shared layout for the small modal sheets: a centred icon badge, title and
/// message, an optional full-width body, and equal-width buttons.
@MainActor
enum GlassSheet {
    static func makeView(
        width: CGFloat,
        symbol: String? = nil,
        symbolTint: NSColor = .controlAccentColor,
        title: String,
        message: String?,
        body: NSView? = nil,
        buttons: [NSButton]
    ) -> NSView {
        let root = SheetRootView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        let contentWidth = width - 2 * GlassMetrics.contentInset

        var stackViews: [NSView] = []
        if let symbol {
            let badge = SheetBadge(symbol: symbol, tint: symbolTint)
            root.badge = badge
            stackViews.append(badge)
        }

        let titleLabel = GlassLabel.make(title, font: .systemFont(ofSize: 15, weight: .semibold))
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        stackViews.append(titleLabel)

        if let message {
            let label = NSTextField(wrappingLabelWithString: message)
            label.font = GlassFont.body
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            label.preferredMaxLayoutWidth = contentWidth
            stackViews.append(label)
        }
        if let body {
            stackViews.append(body)
        }

        let buttonRow = NSStackView(views: buttons)
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 10
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        stackViews.append(buttonRow)

        let stack = NSStackView(views: stackViews)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        if root.badge != nil {
            stack.setCustomSpacing(12, after: stackViews[0])
        }
        stack.setCustomSpacing(6, after: titleLabel)
        stack.setCustomSpacing(22, after: stackViews[stackViews.count - 2])
        root.addSubview(stack)
        root.revealViews = stackViews

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: width),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: GlassMetrics.contentInset),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -GlassMetrics.contentInset),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: GlassMetrics.contentInset),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
            buttonRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
        if let body {
            body.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            body.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
        return root
    }

    static func textField(value: String, placeholder: String) -> NSTextField {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.controlSize = .large
        field.font = GlassFont.body
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }
}

/// Sheet background that plays a short entrance once it lands in a window.
final class SheetRootView: NSVisualEffectView {
    var badge: SheetBadge?
    var revealViews: [NSView] = []
    private var didReveal = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .sheet
        blendingMode = .behindWindow
        state = .active
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !didReveal else { return }
        didReveal = true
        GlassMotion.reveal(revealViews, delayStep: 0.035)
        if let badge {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                GlassMotion.pop(badge, scale: 1.12)
                GlassMotion.bounce(badge.imageView)
            }
        }
    }
}

/// Round tinted badge holding a sheet's symbol.
final class SheetBadge: AppearanceLayerView {
    let imageView: NSImageView
    private let tint: NSColor
    private static let diameter: CGFloat = 52

    init(symbol: String, tint: NSColor) {
        self.tint = tint
        imageView = GlassSymbol.view(symbol, size: 22, weight: .semibold, tint: tint)
        super.init(frame: .zero)
        addSubview(imageView)
        layer?.cornerRadius = Self.diameter / 2
        layer?.borderWidth = 1
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func applyLayerColors() {
        layer?.backgroundColor = tint.withAlphaComponent(0.16).cgColor
        layer?.borderColor = tint.withAlphaComponent(0.28).cgColor
    }
}

// MARK: - Dismiss a sheet by clicking the window around it

/// Closes a sheet when the click lands on the parent window, outside the sheet.
/// Clicks inside the sheet are left alone.
final class OutsideClickDismisser: @unchecked Sendable {
    private weak var controller: NSViewController?
    private var monitor: Any?

    func start(_ controller: NSViewController) {
        stop()
        self.controller = controller
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown], handler: Self.handler(self))
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        controller = nil
    }

    private static func handler(_ dismisser: OutsideClickDismisser) -> (NSEvent) -> NSEvent? {
        { [weak dismisser] event in
            guard let dismisser else { return event }
            // The monitor callback is not MainActor-isolated, but it always runs
            // on the main thread. The box keeps the non-Sendable event on that hop.
            let box = EventBox(event: event)
            let dismiss = MainActor.assumeIsolated {
                dismisser.shouldDismiss(box.event)
            }
            guard dismiss else { return event }
            MainActor.assumeIsolated {
                dismisser.performDismiss()
            }
            return nil
        }
    }

    @MainActor
    private func shouldDismiss(_ event: NSEvent) -> Bool {
        guard let controller, let sheetWindow = controller.view.window else { return false }
        if event.window === sheetWindow { return false }
        return event.window === sheetWindow.sheetParent
    }

    @MainActor
    private func performDismiss() {
        guard let controller else { return }
        stop()
        controller.dismiss(nil)
    }
}

private struct EventBox: @unchecked Sendable {
    let event: NSEvent
}

// MARK: - Layout helper

@MainActor
func pin(_ view: NSView, to container: NSView, inset: CGFloat = 0) {
    NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
        view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
        view.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
        view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset)
    ])
}
