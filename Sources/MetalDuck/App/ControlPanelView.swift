import AppKit
import Foundation

private enum UITheme {
    static let bgTop = NSColor(calibratedRed: 0.11, green: 0.15, blue: 0.24, alpha: 1.0)
    static let bgBottom = NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)

    static let chrome = NSColor(calibratedRed: 0.16, green: 0.21, blue: 0.31, alpha: 0.95)
    static let sidebar = NSColor(calibratedRed: 0.14, green: 0.18, blue: 0.28, alpha: 0.97)
    static let card = NSColor(calibratedRed: 0.24, green: 0.29, blue: 0.39, alpha: 0.95)
    static let cardBorder = NSColor(calibratedRed: 0.28, green: 0.36, blue: 0.48, alpha: 1.0)

    static let title = NSColor(calibratedRed: 0.95, green: 0.97, blue: 0.99, alpha: 1.0)
    static let body = NSColor(calibratedRed: 0.85, green: 0.89, blue: 0.93, alpha: 1.0)
    static let muted = NSColor(calibratedRed: 0.70, green: 0.76, blue: 0.84, alpha: 1.0)
    static let accent = NSColor(calibratedRed: 0.17, green: 0.58, blue: 0.95, alpha: 1.0)
}

private final class FlippedPanelContainerView: NSView {
    override var isFlipped: Bool { true }
}

private final class CardView: NSView {
    let contentStack = NSStackView()

    init(title: String) {
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = UITheme.cardBorder.withAlphaComponent(0.75).cgColor
        layer?.backgroundColor = UITheme.card.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        let heading = NSTextField(labelWithString: title)
        heading.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        heading.textColor = UITheme.title

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8

        let root = NSStackView(views: [heading, contentStack])
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10

        addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

enum CaptureModeChoice: Int, CaseIterable {
    case automatic
    case display
    case window

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .display:
            return "Display"
        case .window:
            return "Window"
        }
    }
}

enum ControlPreset: Int {
    case performance
    case balanced
    case quality
}

@MainActor
protocol ControlPanelViewDelegate: AnyObject {
    func controlPanelDidPressStart(_ panel: ControlPanelView)
    func controlPanelDidPressStop(_ panel: ControlPanelView)
    func controlPanelDidRequestRefreshSources(_ panel: ControlPanelView)

    func controlPanel(_ panel: ControlPanelView, didSelectCaptureMode mode: CaptureModeChoice)
    func controlPanel(_ panel: ControlPanelView, didSelectCaptureSourceAt index: Int)

    func controlPanel(_ panel: ControlPanelView, didToggleCursor visible: Bool)
    func controlPanel(_ panel: ControlPanelView, didChangeCaptureFPS fps: Int)
    func controlPanel(_ panel: ControlPanelView, didChangeQueueDepth depth: Int)

    func controlPanel(_ panel: ControlPanelView, didChangeUpscalingAlgorithm algorithm: UpscalingAlgorithm)
    func controlPanel(_ panel: ControlPanelView, didChangeOutputScale scale: Float)
    func controlPanel(_ panel: ControlPanelView, didToggleMatchOutputResolution enabled: Bool)
    func controlPanel(_ panel: ControlPanelView, didChangeSamplingMode mode: SamplingMode)
    func controlPanel(_ panel: ControlPanelView, didChangeSharpness value: Float)

    func controlPanel(_ panel: ControlPanelView, didToggleDynamicResolution enabled: Bool)
    func controlPanel(_ panel: ControlPanelView, didChangeDynamicMinimum value: Float)
    func controlPanel(_ panel: ControlPanelView, didChangeDynamicMaximum value: Float)
    func controlPanel(_ panel: ControlPanelView, didChangeTargetPresentationFPS fps: Int)

    func controlPanel(_ panel: ControlPanelView, didToggleFrameGeneration enabled: Bool)
    func controlPanel(_ panel: ControlPanelView, didChangeFrameGenerationMode mode: FrameGenerationMode)

    func controlPanel(_ panel: ControlPanelView, didSelectPreset preset: ControlPreset)
}

@MainActor
final class ControlPanelView: NSView {
    weak var delegate: ControlPanelViewDelegate?

    private var isApplyingValues = false

    private let appNameLabel = NSTextField(labelWithString: "MetalDuck")
    private let appSubtitleLabel = NSTextField(labelWithString: "Lossless Scaling for Apple Silicon")
    private let profileTitleLabel = NSTextField(labelWithString: "Profile: \"Default\"")

    private let sessionStateTag = NSTextField(labelWithString: "SESSION")
    private let statusLabel = NSTextField(labelWithString: "Stopped")
    private let statsLabel = NSTextField(labelWithString: "SOURCE 0.0 FPS | OUT 0.0 FPS")

    private let startButton = NSButton(title: "Scale", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)

    private let captureModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let captureSourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let refreshSourcesButton = NSButton(title: "Refresh", target: nil, action: nil)

    private let captureCursorCheckbox = NSButton(checkboxWithTitle: "Capture cursor", target: nil, action: nil)
    private let captureFPSSlider = NSSlider(value: 30, minValue: 15, maxValue: 120, target: nil, action: nil)
    private let captureFPSValueLabel = NSTextField(labelWithString: "30")
    private let queueDepthSlider = NSSlider(value: 5, minValue: 1, maxValue: 8, target: nil, action: nil)
    private let queueDepthValueLabel = NSTextField(labelWithString: "5")

    private let upscalerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let outputScaleSlider = NSSlider(value: 1.5, minValue: 0.75, maxValue: 3.0, target: nil, action: nil)
    private let outputScaleValueLabel = NSTextField(labelWithString: "1.50x")
    private let matchOutputResolutionCheckbox = NSButton(checkboxWithTitle: "Resize before scaling", target: nil, action: nil)
    private let samplingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sharpnessSlider = NSSlider(value: 0.0, minValue: 0.0, maxValue: 1.0, target: nil, action: nil)
    private let sharpnessValueLabel = NSTextField(labelWithString: "0.00")

    private let dynamicResolutionCheckbox = NSButton(checkboxWithTitle: "Dynamic Resolution", target: nil, action: nil)
    private let dynamicMinSlider = NSSlider(value: 0.75, minValue: 0.5, maxValue: 1.0, target: nil, action: nil)
    private let dynamicMinValueLabel = NSTextField(labelWithString: "0.75")
    private let dynamicMaxSlider = NSSlider(value: 1.0, minValue: 0.6, maxValue: 1.25, target: nil, action: nil)
    private let dynamicMaxValueLabel = NSTextField(labelWithString: "1.00")
    private let targetFPSSlider = NSSlider(value: 60, minValue: 30, maxValue: 240, target: nil, action: nil)
    private let targetFPSValueLabel = NSTextField(labelWithString: "60")

    private let frameGenerationCheckbox = NSButton(checkboxWithTitle: "Enable Frame Generation", target: nil, action: nil)
    private let frameGenerationModePopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private let presetSegmented = NSSegmentedControl(labels: ["Performance", "Balanced", "Quality"], trackingMode: .selectOne, target: nil, action: nil)

    private let backgroundGradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
        configureControls()
        layoutUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        backgroundGradient.frame = bounds
    }

    func apply(settings: RenderSettings, capture: CaptureConfiguration) {
        isApplyingValues = true

        upscalerPopup.selectItem(withTitle: settings.upscalingAlgorithm.rawValue)
        outputScaleSlider.floatValue = settings.outputScale
        outputScaleValueLabel.stringValue = String(format: "%.2fx", settings.outputScale)
        matchOutputResolutionCheckbox.state = settings.matchOutputResolution ? .on : .off

        samplingPopup.selectItem(withTitle: settings.samplingMode.rawValue)

        sharpnessSlider.floatValue = settings.sharpness
        sharpnessValueLabel.stringValue = String(format: "%.2f", settings.sharpness)

        dynamicResolutionCheckbox.state = settings.dynamicResolutionEnabled ? .on : .off
        dynamicMinSlider.floatValue = settings.dynamicScaleMinimum
        dynamicMaxSlider.floatValue = settings.dynamicScaleMaximum
        dynamicMinValueLabel.stringValue = String(format: "%.2f", settings.dynamicScaleMinimum)
        dynamicMaxValueLabel.stringValue = String(format: "%.2f", settings.dynamicScaleMaximum)

        targetFPSSlider.integerValue = settings.targetPresentationFPS
        targetFPSValueLabel.stringValue = "\(settings.targetPresentationFPS)"

        frameGenerationCheckbox.state = settings.frameGenerationEnabled ? .on : .off
        frameGenerationModePopup.selectItem(withTitle: settings.frameGenerationMode.rawValue)

        captureCursorCheckbox.state = capture.showsCursor ? .on : .off
        captureFPSSlider.integerValue = capture.framesPerSecond
        captureFPSValueLabel.stringValue = "\(capture.framesPerSecond)"
        queueDepthSlider.integerValue = capture.queueDepth
        queueDepthValueLabel.stringValue = "\(capture.queueDepth)"

        syncDynamicControlsEnabledState()

        isApplyingValues = false
    }

    func setCaptureMode(_ mode: CaptureModeChoice) {
        captureModePopup.selectItem(at: mode.rawValue)
    }

    func setCaptureSourceTitles(_ titles: [String], selectedIndex: Int?) {
        captureSourcePopup.removeAllItems()

        if titles.isEmpty {
            captureSourcePopup.addItem(withTitle: "No source found")
            captureSourcePopup.isEnabled = false
            return
        }

        captureSourcePopup.isEnabled = true
        captureSourcePopup.addItems(withTitles: titles)

        if let selectedIndex, selectedIndex >= 0, selectedIndex < titles.count {
            captureSourcePopup.selectItem(at: selectedIndex)
        }
    }

    func setRunning(_ running: Bool) {
        startButton.isEnabled = !running
        stopButton.isEnabled = running

        startButton.alphaValue = running ? 0.75 : 1.0
        stopButton.alphaValue = running ? 1.0 : 0.75

        statusLabel.textColor = running ? NSColor.systemGreen : NSColor.systemOrange
    }

    func setStatus(_ message: String, isError: Bool = false) {
        statusLabel.stringValue = message
        if isError {
            statusLabel.textColor = NSColor.systemRed
        } else {
            statusLabel.textColor = stopButton.isEnabled ? NSColor.systemGreen : NSColor.systemOrange
        }
    }

    func setStats(_ message: String) {
        statsLabel.stringValue = message
    }

    private func configureView() {
        wantsLayer = true
        layer?.masksToBounds = true

        backgroundGradient.colors = [UITheme.bgTop.cgColor, UITheme.bgBottom.cgColor]
        backgroundGradient.locations = [0.0, 1.0]
        backgroundGradient.startPoint = CGPoint(x: 0.0, y: 1.0)
        backgroundGradient.endPoint = CGPoint(x: 1.0, y: 0.0)
        layer?.addSublayer(backgroundGradient)
    }

    private func configureControls() {
        appNameLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        appNameLabel.textColor = UITheme.title

        appSubtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        appSubtitleLabel.textColor = UITheme.muted

        profileTitleLabel.font = NSFont.systemFont(ofSize: 44, weight: .bold)
        profileTitleLabel.textColor = UITheme.title

        sessionStateTag.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        sessionStateTag.textColor = UITheme.accent

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 34, weight: .semibold)
        statusLabel.textColor = NSColor.systemOrange

        statsLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        statsLabel.textColor = UITheme.body
        statsLabel.lineBreakMode = .byWordWrapping

        startButton.bezelStyle = .rounded
        startButton.bezelColor = UITheme.accent
        startButton.contentTintColor = .white
        startButton.font = NSFont.systemFont(ofSize: 14, weight: .semibold)

        stopButton.bezelStyle = .rounded
        stopButton.bezelColor = NSColor(calibratedRed: 0.30, green: 0.34, blue: 0.42, alpha: 1.0)
        stopButton.contentTintColor = UITheme.body
        stopButton.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        stopButton.isEnabled = false
        stopButton.alphaValue = 0.75

        refreshSourcesButton.bezelStyle = .rounded
        refreshSourcesButton.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        [captureModePopup, captureSourcePopup, upscalerPopup, samplingPopup, frameGenerationModePopup].forEach {
            $0.controlSize = .regular
            $0.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        }

        CaptureModeChoice.allCases.forEach { captureModePopup.addItem(withTitle: $0.title) }
        captureModePopup.selectItem(at: CaptureModeChoice.automatic.rawValue)
        captureModePopup.target = self
        captureModePopup.action = #selector(handleCaptureModeChanged)

        captureSourcePopup.target = self
        captureSourcePopup.action = #selector(handleCaptureSourceChanged)

        upscalerPopup.addItems(withTitles: UpscalingAlgorithm.allCases.map(\.rawValue))
        upscalerPopup.target = self
        upscalerPopup.action = #selector(handleUpscalerChanged)

        samplingPopup.addItems(withTitles: SamplingMode.allCases.map(\.rawValue))
        samplingPopup.target = self
        samplingPopup.action = #selector(handleSamplingChanged)

        frameGenerationModePopup.addItems(withTitles: FrameGenerationMode.allCases.map(\.rawValue))
        frameGenerationModePopup.target = self
        frameGenerationModePopup.action = #selector(handleFrameGenerationModeChanged)

        [captureCursorCheckbox, matchOutputResolutionCheckbox, dynamicResolutionCheckbox, frameGenerationCheckbox].forEach {
            $0.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            $0.contentTintColor = UITheme.body
        }

        [captureFPSSlider, queueDepthSlider, outputScaleSlider, sharpnessSlider, dynamicMinSlider, dynamicMaxSlider, targetFPSSlider].forEach {
            $0.controlSize = .regular
        }

        startButton.target = self
        startButton.action = #selector(handleStartTapped)

        stopButton.target = self
        stopButton.action = #selector(handleStopTapped)

        refreshSourcesButton.target = self
        refreshSourcesButton.action = #selector(handleRefreshSources)

        captureCursorCheckbox.target = self
        captureCursorCheckbox.action = #selector(handleCursorCaptureChanged)

        captureFPSSlider.target = self
        captureFPSSlider.action = #selector(handleCaptureFPSChanged)

        queueDepthSlider.target = self
        queueDepthSlider.action = #selector(handleQueueDepthChanged)

        outputScaleSlider.target = self
        outputScaleSlider.action = #selector(handleOutputScaleChanged)

        matchOutputResolutionCheckbox.target = self
        matchOutputResolutionCheckbox.action = #selector(handleMatchOutputResolutionChanged)

        sharpnessSlider.target = self
        sharpnessSlider.action = #selector(handleSharpnessChanged)

        dynamicResolutionCheckbox.target = self
        dynamicResolutionCheckbox.action = #selector(handleDynamicResolutionChanged)

        dynamicMinSlider.target = self
        dynamicMinSlider.action = #selector(handleDynamicMinChanged)

        dynamicMaxSlider.target = self
        dynamicMaxSlider.action = #selector(handleDynamicMaxChanged)

        targetFPSSlider.target = self
        targetFPSSlider.action = #selector(handleTargetFPSChanged)

        frameGenerationCheckbox.target = self
        frameGenerationCheckbox.action = #selector(handleFrameGenerationEnabledChanged)

        presetSegmented.selectedSegment = ControlPreset.balanced.rawValue
        presetSegmented.target = self
        presetSegmented.action = #selector(handlePresetChanged)
        presetSegmented.controlSize = .regular
        presetSegmented.setWidth(104, forSegment: 0)
        presetSegmented.setWidth(104, forSegment: 1)
        presetSegmented.setWidth(104, forSegment: 2)
    }

    private func layoutUI() {
        let topBar = makeTopBar()
        let sidebar = makeSidebar()
        let main = makeMainContent()

        let body = NSStackView(views: [sidebar, main])
        body.translatesAutoresizingMaskIntoConstraints = false
        body.orientation = .horizontal
        body.alignment = .top
        body.distribution = .fill
        body.spacing = 14

        addSubview(topBar)
        addSubview(body)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            topBar.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            topBar.heightAnchor.constraint(equalToConstant: 68),

            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            body.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
    }

    private func makeTopBar() -> NSView {
        let container = NSVisualEffectView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.material = .underWindowBackground
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 13
        container.layer?.borderWidth = 1
        container.layer?.borderColor = UITheme.cardBorder.cgColor

        let titleBlock = NSStackView(views: [appNameLabel, appSubtitleLabel])
        titleBlock.orientation = .vertical
        titleBlock.spacing = 1

        let actions = NSStackView(views: [startButton, stopButton])
        actions.orientation = .horizontal
        actions.spacing = 8

        let row = NSStackView(views: [titleBlock, NSView(), actions])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY

        container.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])

        return container
    }

    private func makeSidebar() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.borderWidth = 1
        container.layer?.borderColor = UITheme.cardBorder.cgColor
        container.layer?.backgroundColor = UITheme.sidebar.cgColor

        let title = NSTextField(labelWithString: "Game Profiles")
        title.font = NSFont.systemFont(ofSize: 30, weight: .bold)
        title.textColor = UITheme.title

        let selectedProfile = NSTextField(labelWithString: "Default")
        selectedProfile.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        selectedProfile.textColor = UITheme.title

        let selectedCapsule = NSView()
        selectedCapsule.translatesAutoresizingMaskIntoConstraints = false
        selectedCapsule.wantsLayer = true
        selectedCapsule.layer?.cornerRadius = 9
        selectedCapsule.layer?.backgroundColor = UITheme.accent.withAlphaComponent(0.25).cgColor
        selectedCapsule.layer?.borderWidth = 1
        selectedCapsule.layer?.borderColor = UITheme.accent.withAlphaComponent(0.7).cgColor
        selectedCapsule.addSubview(selectedProfile)
        selectedProfile.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            selectedProfile.leadingAnchor.constraint(equalTo: selectedCapsule.leadingAnchor, constant: 12),
            selectedProfile.trailingAnchor.constraint(equalTo: selectedCapsule.trailingAnchor, constant: -12),
            selectedProfile.topAnchor.constraint(equalTo: selectedCapsule.topAnchor, constant: 8),
            selectedProfile.bottomAnchor.constraint(equalTo: selectedCapsule.bottomAnchor, constant: -8)
        ])

        let addButton = makeSecondaryButton(title: "+")
        let editButton = makeSecondaryButton(title: "Edit")
        let deleteButton = makeSecondaryButton(title: "Delete")
        addButton.isEnabled = false
        editButton.isEnabled = false
        deleteButton.isEnabled = false

        let actionRow = NSStackView(views: [addButton, editButton, deleteButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 8

        let manual = NSTextField(labelWithString: "Manual")
        manual.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        manual.textColor = UITheme.muted

        let settings = NSTextField(labelWithString: "Settings")
        settings.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        settings.textColor = UITheme.muted

        let spacer = NSView()

        let stack = NSStackView(views: [title, selectedCapsule, actionRow, spacer, manual, settings])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        container.addSubview(stack)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 280),

            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])

        return container
    }

    private func makeMainContent() -> NSView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let contentView = FlippedPanelContainerView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        let clipView = scrollView.contentView

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 12

        stack.addArrangedSubview(profileTitleLabel)

        let sessionCard = makeSessionCard()
        stack.addArrangedSubview(sessionCard)
        sessionCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let fgScalingRow = makeCardRow(left: makeFrameGenerationCard(), right: makeScalingCard())
        stack.addArrangedSubview(fgScalingRow)
        fgScalingRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let captureRenderingRow = makeCardRow(left: makeCaptureCard(), right: makeRenderingCard())
        stack.addArrangedSubview(captureRenderingRow)
        captureRenderingRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let presetsCard = makePresetsCard()
        stack.addArrangedSubview(presetsCard)
        presetsCard.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.52).isActive = true

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: clipView.topAnchor),
            contentView.bottomAnchor.constraint(greaterThanOrEqualTo: clipView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: clipView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])

        return scrollView
    }

    private func makeSessionCard() -> NSView {
        let card = CardView(title: "Session")

        sessionStateTag.setContentHuggingPriority(.required, for: .vertical)
        statusLabel.setContentHuggingPriority(.required, for: .vertical)

        card.contentStack.addArrangedSubview(sessionStateTag)
        card.contentStack.addArrangedSubview(statusLabel)
        card.contentStack.addArrangedSubview(statsLabel)

        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 168).isActive = true

        return card
    }

    private func makeFrameGenerationCard() -> NSView {
        let card = CardView(title: "Frame Generation")

        card.contentStack.addArrangedSubview(frameGenerationCheckbox)
        card.contentStack.addArrangedSubview(makeLabeledControlRow(label: "Mode", control: frameGenerationModePopup))
        card.contentStack.addArrangedSubview(makeFootnote(text: "Interpolation is optimized for 30->60 and 30->90. True motion/depth vectors still improve hard scenes."))

        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 176).isActive = true

        return card
    }

    private func makeScalingCard() -> NSView {
        let card = CardView(title: "Scaling")

        card.contentStack.addArrangedSubview(makeLabeledControlRow(label: "Type", control: upscalerPopup))
        card.contentStack.addArrangedSubview(makeSliderRow(label: "Factor", slider: outputScaleSlider, valueLabel: outputScaleValueLabel))
        card.contentStack.addArrangedSubview(matchOutputResolutionCheckbox)
        card.contentStack.addArrangedSubview(makeLabeledControlRow(label: "Sampling", control: samplingPopup))
        card.contentStack.addArrangedSubview(makeSliderRow(label: "Sharpness", slider: sharpnessSlider, valueLabel: sharpnessValueLabel))

        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 176).isActive = true

        return card
    }

    private func makeCaptureCard() -> NSView {
        let card = CardView(title: "Capture")

        card.contentStack.addArrangedSubview(makeLabeledControlRow(label: "Mode", control: captureModePopup))
        card.contentStack.addArrangedSubview(makeSourcePickerRow())
        card.contentStack.addArrangedSubview(captureCursorCheckbox)
        card.contentStack.addArrangedSubview(makeSliderRow(label: "Capture FPS", slider: captureFPSSlider, valueLabel: captureFPSValueLabel))
        card.contentStack.addArrangedSubview(makeSliderRow(label: "Queue Depth", slider: queueDepthSlider, valueLabel: queueDepthValueLabel))

        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 198).isActive = true

        return card
    }

    private func makeRenderingCard() -> NSView {
        let card = CardView(title: "Rendering")

        card.contentStack.addArrangedSubview(dynamicResolutionCheckbox)
        card.contentStack.addArrangedSubview(makeSliderRow(label: "Minimum Scale", slider: dynamicMinSlider, valueLabel: dynamicMinValueLabel))
        card.contentStack.addArrangedSubview(makeSliderRow(label: "Maximum Scale", slider: dynamicMaxSlider, valueLabel: dynamicMaxValueLabel))
        card.contentStack.addArrangedSubview(makeSliderRow(label: "Target FPS", slider: targetFPSSlider, valueLabel: targetFPSValueLabel))

        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 198).isActive = true

        return card
    }

    private func makePresetsCard() -> NSView {
        let card = CardView(title: "Presets")
        card.contentStack.addArrangedSubview(presetSegmented)
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        return card
    }

    private func makeCardRow(left: NSView, right: NSView) -> NSView {
        left.translatesAutoresizingMaskIntoConstraints = false
        right.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [left, right])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.alignment = .top
        row.spacing = 12

        return row
    }

    private func makeLabeledControlRow(label: String, control: NSView) -> NSView {
        let text = NSTextField(labelWithString: label)
        text.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        text.textColor = UITheme.body
        text.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [text, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func makeSliderRow(label: String, slider: NSSlider, valueLabel: NSTextField) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = UITheme.body

        valueLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        valueLabel.textColor = UITheme.title
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let rowHeader = NSStackView(views: [title, valueLabel])
        rowHeader.orientation = .horizontal
        rowHeader.alignment = .centerY
        rowHeader.spacing = 8

        let row = NSStackView(views: [rowHeader, slider])
        row.orientation = .vertical
        row.spacing = 3
        row.alignment = .leading

        return row
    }

    private func makeSourcePickerRow() -> NSView {
        let row = NSStackView(views: [captureSourcePopup, refreshSourcesButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        refreshSourcesButton.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    private func makeFootnote(text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = UITheme.muted
        return label
    }

    private func makeSecondaryButton(title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.bezelColor = NSColor(calibratedRed: 0.30, green: 0.35, blue: 0.44, alpha: 1.0)
        button.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        return button
    }

    private func syncDynamicControlsEnabledState() {
        let enabled = dynamicResolutionCheckbox.state == .on
        dynamicMinSlider.isEnabled = enabled
        dynamicMaxSlider.isEnabled = enabled
    }

    @objc
    private func handleStartTapped() {
        delegate?.controlPanelDidPressStart(self)
    }

    @objc
    private func handleStopTapped() {
        delegate?.controlPanelDidPressStop(self)
    }

    @objc
    private func handleRefreshSources() {
        delegate?.controlPanelDidRequestRefreshSources(self)
    }

    @objc
    private func handleCaptureModeChanged() {
        guard !isApplyingValues,
              let mode = CaptureModeChoice(rawValue: captureModePopup.indexOfSelectedItem) else {
            return
        }
        delegate?.controlPanel(self, didSelectCaptureMode: mode)
    }

    @objc
    private func handleCaptureSourceChanged() {
        guard !isApplyingValues else {
            return
        }
        delegate?.controlPanel(self, didSelectCaptureSourceAt: captureSourcePopup.indexOfSelectedItem)
    }

    @objc
    private func handleCursorCaptureChanged() {
        guard !isApplyingValues else {
            return
        }
        delegate?.controlPanel(self, didToggleCursor: captureCursorCheckbox.state == .on)
    }

    @objc
    private func handleCaptureFPSChanged() {
        guard !isApplyingValues else {
            return
        }
        let value = captureFPSSlider.integerValue
        captureFPSValueLabel.stringValue = "\(value)"
        delegate?.controlPanel(self, didChangeCaptureFPS: value)
    }

    @objc
    private func handleQueueDepthChanged() {
        guard !isApplyingValues else {
            return
        }
        let value = queueDepthSlider.integerValue
        queueDepthValueLabel.stringValue = "\(value)"
        delegate?.controlPanel(self, didChangeQueueDepth: value)
    }

    @objc
    private func handleUpscalerChanged() {
        guard !isApplyingValues,
              let title = upscalerPopup.selectedItem?.title,
              let value = UpscalingAlgorithm(rawValue: title) else {
            return
        }
        delegate?.controlPanel(self, didChangeUpscalingAlgorithm: value)
    }

    @objc
    private func handleOutputScaleChanged() {
        guard !isApplyingValues else {
            return
        }
        let value = outputScaleSlider.floatValue
        outputScaleValueLabel.stringValue = String(format: "%.2fx", value)
        delegate?.controlPanel(self, didChangeOutputScale: value)
    }

    @objc
    private func handleMatchOutputResolutionChanged() {
        guard !isApplyingValues else {
            return
        }
        delegate?.controlPanel(self, didToggleMatchOutputResolution: matchOutputResolutionCheckbox.state == .on)
    }

    @objc
    private func handleSamplingChanged() {
        guard !isApplyingValues,
              let title = samplingPopup.selectedItem?.title,
              let value = SamplingMode(rawValue: title) else {
            return
        }
        delegate?.controlPanel(self, didChangeSamplingMode: value)
    }

    @objc
    private func handleSharpnessChanged() {
        guard !isApplyingValues else {
            return
        }
        let value = sharpnessSlider.floatValue
        sharpnessValueLabel.stringValue = String(format: "%.2f", value)
        delegate?.controlPanel(self, didChangeSharpness: value)
    }

    @objc
    private func handleDynamicResolutionChanged() {
        guard !isApplyingValues else {
            return
        }
        syncDynamicControlsEnabledState()
        delegate?.controlPanel(self, didToggleDynamicResolution: dynamicResolutionCheckbox.state == .on)
    }

    @objc
    private func handleDynamicMinChanged() {
        guard !isApplyingValues else {
            return
        }
        let value = min(dynamicMinSlider.floatValue, dynamicMaxSlider.floatValue)
        dynamicMinSlider.floatValue = value
        dynamicMinValueLabel.stringValue = String(format: "%.2f", value)
        delegate?.controlPanel(self, didChangeDynamicMinimum: value)
    }

    @objc
    private func handleDynamicMaxChanged() {
        guard !isApplyingValues else {
            return
        }
        let value = max(dynamicMaxSlider.floatValue, dynamicMinSlider.floatValue)
        dynamicMaxSlider.floatValue = value
        dynamicMaxValueLabel.stringValue = String(format: "%.2f", value)
        delegate?.controlPanel(self, didChangeDynamicMaximum: value)
    }

    @objc
    private func handleTargetFPSChanged() {
        guard !isApplyingValues else {
            return
        }
        let value = targetFPSSlider.integerValue
        targetFPSValueLabel.stringValue = "\(value)"
        delegate?.controlPanel(self, didChangeTargetPresentationFPS: value)
    }

    @objc
    private func handleFrameGenerationEnabledChanged() {
        guard !isApplyingValues else {
            return
        }
        delegate?.controlPanel(self, didToggleFrameGeneration: frameGenerationCheckbox.state == .on)
    }

    @objc
    private func handleFrameGenerationModeChanged() {
        guard !isApplyingValues,
              let title = frameGenerationModePopup.selectedItem?.title,
              let mode = FrameGenerationMode(rawValue: title) else {
            return
        }
        delegate?.controlPanel(self, didChangeFrameGenerationMode: mode)
    }

    @objc
    private func handlePresetChanged() {
        guard !isApplyingValues,
              let preset = ControlPreset(rawValue: presetSegmented.selectedSegment) else {
            return
        }

        delegate?.controlPanel(self, didSelectPreset: preset)
    }
}
