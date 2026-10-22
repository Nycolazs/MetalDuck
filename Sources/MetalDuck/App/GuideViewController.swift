import AppKit

/// Illustrated guide for the control panel, attached the same way as Settings.
@MainActor
final class GuideViewController: NSViewController {
    static let repository = URL(string: "https://github.com/Nycolazs/MetalDuck")!

    override func loadView() {
        let root = GuideView()
        root.onClose = { [weak self] in
            self?.dismiss(nil)
        }
        root.onOpenRepository = {
            NSWorkspace.shared.open(Self.repository)
        }
        view = root
        preferredContentSize = NSSize(width: GuideView.width, height: GuideView.height)
    }
}

@MainActor
final class GuideView: NSView {
    static let width: CGFloat = 700
    static let height: CGFloat = 560

    var onClose: (() -> Void)?
    var onOpenRepository: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        let title = GlassLabel.make("Guide", font: GlassFont.largeTitle)
        let message = GlassLabel.make(
            "Each stage only sees what the one before it produced.",
            font: GlassFont.body,
            color: .secondaryLabelColor
        )

        let github = GlassActionButton(title: "GitHub", symbol: "arrow.up.forward", style: .neutral, symbolSize: 11, height: 28)
        github.target = self
        github.action = #selector(openRepository)
        github.toolTip = "Open the MetalDuck repository"
        github.widthAnchor.constraint(equalToConstant: 108).isActive = true

        let done = GlassActionButton(title: "Done", symbol: "checkmark", style: .accent, symbolSize: 11, height: 28)
        done.target = self
        done.action = #selector(close)
        done.widthAnchor.constraint(equalToConstant: 96).isActive = true

        let actions = NSStackView(views: [github, done])
        actions.orientation = .horizontal
        actions.spacing = 8
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.setContentHuggingPriority(.required, for: .horizontal)

        let flowCard = glassCard(GuideFlowView(), insets: 16)
        flowCard.heightAnchor.constraint(equalToConstant: 108).isActive = true

        let topics = NSStackView(views: GuideTopic.all.map(GuideTopicCard.init(topic:)))
        topics.orientation = .vertical
        topics.alignment = .leading
        topics.spacing = 12
        topics.translatesAutoresizingMaskIntoConstraints = false
        topics.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 8, right: 0)

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(topics)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document

        addSubview(title)
        addSubview(message)
        addSubview(actions)
        addSubview(flowCard)
        addSubview(scroll)

        let inset = GlassMetrics.contentInset
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 22),

            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            actions.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -16),

            message.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            message.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            message.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),

            flowCard.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            flowCard.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            flowCard.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 16),

            scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            scroll.topAnchor.constraint(equalTo: flowCard.bottomAnchor, constant: 14),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),

            topics.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            topics.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            topics.topAnchor.constraint(equalTo: document.topAnchor),
            topics.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        for card in topics.arrangedSubviews {
            card.leadingAnchor.constraint(equalTo: topics.leadingAnchor).isActive = true
            card.trailingAnchor.constraint(equalTo: topics.trailingAnchor).isActive = true
        }
    }

    private func glassCard(_ content: NSView, insets: CGFloat) -> NSView {
        let surface = GlassSurface(style: .card, cornerRadius: 14)
        content.translatesAutoresizingMaskIntoConstraints = false
        surface.contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor, constant: insets),
            content.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor, constant: -insets),
            content.topAnchor.constraint(equalTo: surface.contentView.topAnchor, constant: insets),
            content.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor, constant: -insets)
        ])
        return surface
    }

    @objc private func openRepository() {
        onOpenRepository?()
    }

    @objc private func close() {
        onClose?()
    }
}

// MARK: - Pipeline strip

/// Capture → generate → scale → the picture you see.
@MainActor
private final class GuideFlowView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        let steps: [(String, String)] = [
            ("camera.viewfinder", "Capture"),
            ("sparkles", "Generate"),
            ("arrow.up.left.and.arrow.down.right", "Scale"),
            ("display", "Picture")
        ]
        var views: [NSView] = []
        for (index, step) in steps.enumerated() {
            if index > 0 {
                views.append(GlassSymbol.view("arrow.right", size: 11, weight: .semibold, tint: .tertiaryLabelColor))
            }
            views.append(GuideFlowStep(symbol: step.0, title: step.1, emphasizes: index == steps.count - 1))
        }
        let row = NSStackView(views: views)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.distribution = .equalSpacing
        row.alignment = .centerY
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class GuideFlowStep: NSView {
    private let icon: NSImageView
    private let well = AppearanceLayerView(frame: .zero)
    private let emphasizes: Bool
    nonisolated(unsafe) private var accentObserver: NSObjectProtocol?

    init(symbol: String, title: String, emphasizes: Bool) {
        icon = GlassSymbol.view(symbol, size: 16, weight: .medium)
        self.emphasizes = emphasizes
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        well.translatesAutoresizingMaskIntoConstraints = false
        well.wantsLayer = true
        well.layer?.cornerRadius = 18
        well.addSubview(icon)

        let caption = GlassLabel.make(title, font: GlassFont.captionMedium, color: .secondaryLabelColor)
        let column = NSStackView(views: [well, caption])
        column.translatesAutoresizingMaskIntoConstraints = false
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 6
        addSubview(column)

        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(equalToConstant: 36),
            well.heightAnchor.constraint(equalToConstant: 36),
            icon.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        accentObserver = GlassAccent.observe { [weak self] in
            self?.applyTint()
        }
        applyTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let accentObserver {
            NotificationCenter.default.removeObserver(accentObserver)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint()
    }

    private func applyTint() {
        let tint: NSColor = emphasizes ? GlassAccent.color : .secondaryLabelColor
        icon.contentTintColor = tint
        well.layer?.backgroundColor = (emphasizes ? tint.withAlphaComponent(0.16) : GlassColor.selection).cgColor
    }
}

// MARK: - Topics

private struct GuideTopic {
    let sketch: GuideSketch.Kind
    let title: String
    let affects: String
    let body: String

    static let all: [GuideTopic] = [
        GuideTopic(
            sketch: .capture,
            title: "Capture",
            affects: "Decides the frames everything else works from.",
            body: "Mode picks a whole display or one window. Capture rate is how many of its frames MetalDuck takes each second. A deeper queue holds a few back, so a hitch in the source does not drop the picture, at the cost of a little delay."
        ),
        GuideTopic(
            sketch: .generation,
            title: "Frame generation",
            affects: "Multiplies the capture rate. It does not have its own fps.",
            body: "Off shows each captured frame as it arrived. 2×, 3× and 4× draw that many frames for every one captured, inventing the ones in between by following the motion between two real captures. That needs the next capture first, so the picture trails the source by roughly one capture plus a few milliseconds. The output rate is always capture × multiplier, so 30 fps at 2× is 60 fps."
        ),
        GuideTopic(
            sketch: .scaling,
            title: "Scaling",
            affects: "Changes how large and how sharp the picture is drawn.",
            body: "Fit to output sizes the picture to the output window first. Scale factor then multiplies that size. MetalFX Spatial rebuilds detail; Linear only resamples and costs less. Sharpness runs after the resize."
        ),
        GuideTopic(
            sketch: .resolution,
            title: "Dynamic resolution",
            affects: "Gives back size when the output cannot keep up.",
            body: "When drawing falls behind the output rate, the render scale slides down between Minimum and Maximum, then climbs back. The picture gets slightly smaller instead of stuttering."
        ),
        GuideTopic(
            sketch: .session,
            title: "Start and stop",
            affects: "Runs the chain, and lets you leave it from anywhere.",
            body: "The first Start asks you to choose a stop shortcut. After that, Start begins scaling. The menu-bar icon stops it whether or not generation is running, and ⌃⌥⌘⎋ always stops it. Stats overlay draws capture, generated and output fps on the picture."
        )
    ]
}

@MainActor
private final class GuideTopicCard: NSView {
    init(topic: GuideTopic) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let surface = GlassSurface(style: .card, cornerRadius: 14)
        addSubview(surface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let sketch = GuideSketch(kind: topic.sketch)
        let title = GlassLabel.make(topic.title, font: GlassFont.groupTitle)
        let affects = GlassLabel.make(topic.affects, font: GlassFont.captionMedium, color: .secondaryLabelColor)
        affects.lineBreakMode = .byWordWrapping
        affects.maximumNumberOfLines = 2
        let body = NSTextField(wrappingLabelWithString: topic.body)
        body.font = GlassFont.body
        body.textColor = .secondaryLabelColor
        body.translatesAutoresizingMaskIntoConstraints = false
        body.preferredMaxLayoutWidth = 440

        let copy = NSStackView(views: [title, affects, body])
        copy.translatesAutoresizingMaskIntoConstraints = false
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 4
        copy.setCustomSpacing(8, after: affects)

        surface.contentView.addSubview(sketch)
        surface.contentView.addSubview(copy)
        NSLayoutConstraint.activate([
            sketch.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor, constant: 14),
            sketch.centerYAnchor.constraint(equalTo: surface.contentView.centerYAnchor),
            sketch.widthAnchor.constraint(equalToConstant: 148),
            sketch.heightAnchor.constraint(equalToConstant: 78),

            copy.leadingAnchor.constraint(equalTo: sketch.trailingAnchor, constant: 16),
            copy.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor, constant: -16),
            copy.topAnchor.constraint(equalTo: surface.contentView.topAnchor, constant: 14),
            copy.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor, constant: -14),

            affects.leadingAnchor.constraint(equalTo: copy.leadingAnchor),
            affects.trailingAnchor.constraint(equalTo: copy.trailingAnchor),
            body.leadingAnchor.constraint(equalTo: copy.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: copy.trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Sketches

/// Small diagram of one cause and its effect. Drawn, so it follows light and dark.
@MainActor
final class GuideSketch: NSView {
    enum Kind {
        case capture
        case generation
        case scaling
        case resolution
        case session
    }

    private let kind: Kind
    nonisolated(unsafe) private var accentObserver: NSObjectProtocol?

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        accentObserver = GlassAccent.observe { [weak self] in
            self?.needsDisplay = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let accentObserver {
            NotificationCenter.default.removeObserver(accentObserver)
        }
    }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        switch kind {
        case .capture: drawCapture()
        case .generation: drawGeneration()
        case .scaling: drawScaling()
        case .resolution: drawResolution()
        case .session: drawSession()
        }
    }

    private var ink: NSColor { .secondaryLabelColor }
    private var faint: NSColor { .tertiaryLabelColor }
    private var accent: NSColor { GlassAccent.color }

    private func drawCapture() {
        roundedRect(NSRect(x: 4, y: 10, width: 46, height: 40), radius: 6, stroke: ink)
        NSBezierPath(rect: NSRect(x: 4, y: 18, width: 46, height: 1)).fill(using: faint)
        arrow(from: NSPoint(x: 56, y: 24), to: NSPoint(x: 72, y: 24))
        let frames = [
            NSRect(x: 78, y: 14, width: 16, height: 24),
            NSRect(x: 98, y: 10, width: 16, height: 24),
            NSRect(x: 118, y: 6, width: 16, height: 24)
        ]
        for (index, frame) in frames.enumerated() {
            roundedRect(frame, radius: 3, stroke: index == frames.count - 1 ? accent : faint, fill: index == frames.count - 1 ? accent.withAlphaComponent(0.18) : nil)
        }
        drawText("30 fps", in: NSRect(x: 74, y: 46, width: 64, height: 14), color: faint, alignment: .center)
    }

    private func drawGeneration() {
        roundedRect(NSRect(x: 4, y: 16, width: 26, height: 32), radius: 4, stroke: ink)
        drawText("in", in: NSRect(x: 4, y: 24, width: 26, height: 16), color: faint, alignment: .center)
        drawText("×2", in: NSRect(x: 34, y: 8, width: 36, height: 16), color: accent, alignment: .center, weight: .semibold)
        arrow(from: NSPoint(x: 36, y: 32), to: NSPoint(x: 68, y: 32))
        roundedRect(NSRect(x: 74, y: 18, width: 24, height: 28), radius: 4, stroke: faint)
        roundedRect(NSRect(x: 102, y: 12, width: 24, height: 28), radius: 4, stroke: accent, fill: accent.withAlphaComponent(0.18), dashed: true)
        drawText("30 × 2 = 60", in: NSRect(x: 0, y: 54, width: 140, height: 16), color: ink, alignment: .center, weight: .medium)
    }

    private func drawScaling() {
        roundedRect(NSRect(x: 8, y: 26, width: 28, height: 18), radius: 3, stroke: faint)
        arrow(from: NSPoint(x: 42, y: 35), to: NSPoint(x: 62, y: 35))
        roundedRect(NSRect(x: 68, y: 12, width: 62, height: 42), radius: 6, stroke: accent, fill: accent.withAlphaComponent(0.14))
        drawText("1.15×", in: NSRect(x: 68, y: 25, width: 62, height: 16), color: accent, alignment: .center, weight: .semibold)
    }

    private func drawResolution() {
        let track = NSRect(x: 8, y: 30, width: 132, height: 8)
        roundedRect(track, radius: 4, stroke: faint, fill: GlassColor.selection)
        roundedRect(NSRect(x: 8, y: 30, width: 86, height: 8), radius: 4, stroke: .clear, fill: accent)
        drawText("0.75", in: NSRect(x: 4, y: 44, width: 40, height: 14), color: faint, alignment: .left)
        drawText("1.00", in: NSRect(x: 96, y: 44, width: 44, height: 14), color: faint, alignment: .right)
        drawText("scale", in: NSRect(x: 8, y: 8, width: 132, height: 16), color: ink, alignment: .left, weight: .medium)
    }

    private func drawSession() {
        let play = NSRect(x: 6, y: 16, width: 28, height: 28)
        roundedRect(play, radius: 14, stroke: accent, fill: accent.withAlphaComponent(0.16))
        drawSymbol("play.fill", in: play.insetBy(dx: 7, dy: 7), tint: accent)
        arrow(from: NSPoint(x: 40, y: 30), to: NSPoint(x: 56, y: 30))
        let stop = NSRect(x: 62, y: 16, width: 72, height: 28)
        roundedRect(stop, radius: 14, stroke: ink)
        drawSymbol("stop.fill", in: NSRect(x: 72, y: 22, width: 16, height: 16), tint: ink)
        drawText("menu", in: NSRect(x: 90, y: 22, width: 38, height: 16), color: ink, alignment: .left, weight: .medium)
        drawText("⌃⌥⌘⎋", in: NSRect(x: 4, y: 52, width: 140, height: 16), color: faint, alignment: .center)
    }

    private func roundedRect(_ rect: NSRect, radius: CGFloat, stroke: NSColor, fill: NSColor? = nil, dashed: Bool = false) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if let fill {
            fill.setFill()
            path.fill()
        }
        stroke.setStroke()
        path.lineWidth = 1.25
        if dashed {
            path.setLineDash([3, 2], count: 2, phase: 0)
        }
        path.stroke()
    }

    private func arrow(from start: NSPoint, to end: NSPoint) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head: CGFloat = 5
        path.move(to: end)
        path.line(to: NSPoint(x: end.x - head * cos(angle - 0.45), y: end.y - head * sin(angle - 0.45)))
        path.move(to: end)
        path.line(to: NSPoint(x: end.x - head * cos(angle + 0.45), y: end.y - head * sin(angle + 0.45)))
        faint.setStroke()
        path.lineWidth = 1.25
        path.lineCapStyle = .round
        path.stroke()
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        color: NSColor,
        alignment: NSTextAlignment,
        weight: NSFont.Weight = .regular
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        text.draw(in: rect, withAttributes: attributes)
    }

    private func drawSymbol(_ name: String, in rect: NSRect, tint: NSColor) {
        guard var image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: rect.height, weight: .semibold)) else { return }
        image = image.withSymbolConfiguration(.init(paletteColors: [tint])) ?? image
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

private extension NSBezierPath {
    func fill(using color: NSColor) {
        color.setFill()
        fill()
    }
}
