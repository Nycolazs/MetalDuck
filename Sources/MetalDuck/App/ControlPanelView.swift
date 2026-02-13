import AppKit
import Foundation

private final class FlippedPanelContainerView: NSView {
    override var isFlipped: Bool { true }
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

    private let titleLabel = NSTextField(labelWithString: "MetalDuck LS")
    private let subtitleLabel = NSTextField(labelWithString: "Lossless Scaling for Apple Silicon")

    private let statusLabel = NSTextField(labelWithString: "Idle")
    private let statsLabel = NSTextField(labelWithString: "No frame data yet")

    private let startButton = NSButton(title: "Start Scaling", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)

    private let captureModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let captureSourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let refreshSourcesButton = NSButton(title: "Refresh", target: nil, action: nil)

    private let captureCursorCheckbox = NSButton(checkboxWithTitle: "Capture cursor", target: nil, action: nil)
    private let captureFPSSlider = NSSlider(value: 60, minValue: 30, maxValue: 240, target: nil, action: nil)
    private let captureFPSValueLabel = NSTextField(labelWithString: "60")
    private let queueDepthSlider = NSSlider(value: 5, minValue: 1, maxValue: 8, target: nil, action: nil)
    private let queueDepthValueLabel = NSTextField(labelWithString: "5")

    private let upscalerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let outputScaleSlider = NSSlider(value: 1.5, minValue: 0.75, maxValue: 3.0, target: nil, action: nil)
    private let outputScaleValueLabel = NSTextField(labelWithString: "1.50x")
    private let samplingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sharpnessSlider = NSSlider(value: 0.15, minValue: 0.0, maxValue: 1.0, target: nil, action: nil)
    private let sharpnessValueLabel = NSTextField(labelWithString: "0.15")

    private let dynamicResolutionCheckbox = NSButton(checkboxWithTitle: "Dynamic Resolution", target: nil, action: nil)
    private let dynamicMinSlider = NSSlider(value: 0.75, minValue: 0.5, maxValue: 1.0, target: nil, action: nil)
    private let dynamicMinValueLabel = NSTextField(labelWithString: "0.75")
    private let dynamicMaxSlider = NSSlider(value: 1.0, minValue: 0.6, maxValue: 1.25, target: nil, action: nil)
    private let dynamicMaxValueLabel = NSTextField(labelWithString: "1.00")
    private let targetFPSSlider = NSSlider(value: 120, minValue: 30, maxValue: 240, target: nil, action: nil)
    private let targetFPSValueLabel = NSTextField(labelWithString: "120")

    private let frameGenerationCheckbox = NSButton(checkboxWithTitle: "Enable Frame Generation", target: nil, action: nil)
    private let frameGenerationModePopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private let presetSegmented = NSSegmentedControl(labels: ["Performance", "Balanced", "Quality"], trackingMode: .selectOne, target: nil, action: nil)

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

    func apply(settings: RenderSettings, capture: CaptureConfiguration) {
        isApplyingValues = true

        upscalerPopup.selectItem(withTitle: settings.upscalingAlgorithm.rawValue)
        outputScaleSlider.floatValue = settings.outputScale
        outputScaleValueLabel.stringValue = String(format: "%.2fx", settings.outputScale)

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
        layer?.backgroundColor = NSColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 1.0).cgColor
    }

    private func configureControls() {
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.98, alpha: 1.0)

        subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.textColor = NSColor(calibratedRed: 0.77, green: 0.79, blue: 0.82, alpha: 1.0)

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = NSColor.systemOrange

        statsLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statsLabel.textColor = NSColor(calibratedRed: 0.75, green: 0.78, blue: 0.8, alpha: 1.0)

        startButton.bezelStyle = .rounded
        stopButton.bezelStyle = .rounded
        stopButton.isEnabled = false

        startButton.target = self
        startButton.action = #selector(handleStartTapped)
        stopButton.target = self
        stopButton.action = #selector(handleStopTapped)
        refreshSourcesButton.target = self
        refreshSourcesButton.action = #selector(handleRefreshSources)

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

        captureCursorCheckbox.target = self
        captureCursorCheckbox.action = #selector(handleCursorCaptureChanged)

        captureFPSSlider.target = self
        captureFPSSlider.action = #selector(handleCaptureFPSChanged)

        queueDepthSlider.target = self
        queueDepthSlider.action = #selector(handleQueueDepthChanged)

        outputScaleSlider.target = self
        outputScaleSlider.action = #selector(handleOutputScaleChanged)

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
    }

    private func layoutUI() {
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
        stack.distribution = .fill
        stack.alignment = .leading
        stack.spacing = 10
        stack.setHuggingPriority(.required, for: .vertical)
        stack.setContentCompressionResistancePriority(.required, for: .vertical)

        let header = NSStackView(views: [titleLabel, subtitleLabel, statusLabel, statsLabel])
        header.orientation = .vertical
        header.spacing = 4
        addSection(makeSection(title: "Session", content: [header, makeSessionButtonsRow()]), to: stack)

        addSection(makeSection(title: "Capture", content: [
            makeLabeledControlRow(label: "Mode", control: captureModePopup),
            makeSourcePickerRow(),
            captureCursorCheckbox,
            makeSliderRow(label: "Capture FPS", slider: captureFPSSlider, valueLabel: captureFPSValueLabel),
            makeSliderRow(label: "Queue Depth", slider: queueDepthSlider, valueLabel: queueDepthValueLabel)
        ]), to: stack)

        addSection(makeSection(title: "Upscaling", content: [
            makeLabeledControlRow(label: "Algorithm", control: upscalerPopup),
            makeSliderRow(label: "Scale", slider: outputScaleSlider, valueLabel: outputScaleValueLabel),
            makeLabeledControlRow(label: "Sampling", control: samplingPopup),
            makeSliderRow(label: "Sharpness", slider: sharpnessSlider, valueLabel: sharpnessValueLabel)
        ]), to: stack)

        addSection(makeSection(title: "Dynamic Resolution", content: [
            dynamicResolutionCheckbox,
            makeSliderRow(label: "Minimum", slider: dynamicMinSlider, valueLabel: dynamicMinValueLabel),
            makeSliderRow(label: "Maximum", slider: dynamicMaxSlider, valueLabel: dynamicMaxValueLabel),
            makeSliderRow(label: "Target FPS", slider: targetFPSSlider, valueLabel: targetFPSValueLabel)
        ]), to: stack)

        addSection(makeSection(title: "Frame Generation", content: [
            frameGenerationCheckbox,
            makeLabeledControlRow(label: "Mode", control: frameGenerationModePopup),
            makeFootnote(text: "Without motion/depth integration, FG uses optical blend interpolation (works for 30->60, but can ghost on fast motion).")
        ]), to: stack)

        addSection(makeSection(title: "Presets", content: [presetSegmented]), to: stack)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 1).isActive = true
        stack.addArrangedSubview(spacer)

        contentView.addSubview(stack)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: clipView.topAnchor),
            contentView.bottomAnchor.constraint(greaterThanOrEqualTo: clipView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: clipView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])
    }

    private func addSection(_ section: NSView, to stack: NSStackView) {
        section.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeSessionButtonsRow() -> NSView {
        let row = NSStackView(views: [startButton, stopButton])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        return row
    }

    private func makeSourcePickerRow() -> NSView {
        let row = NSStackView(views: [captureSourcePopup, refreshSourcesButton])
        row.orientation = .horizontal
        row.spacing = 8
        refreshSourcesButton.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    private func makeSection(title: String, content: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = NSColor(calibratedRed: 0.5, green: 0.82, blue: 0.96, alpha: 1.0)

        let innerStack = NSStackView(views: content)
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        innerStack.orientation = .vertical
        innerStack.spacing = 8

        let sectionStack = NSStackView(views: [titleLabel, innerStack])
        sectionStack.translatesAutoresizingMaskIntoConstraints = false
        sectionStack.orientation = .vertical
        sectionStack.spacing = 8

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 9
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(calibratedRed: 0.2, green: 0.24, blue: 0.26, alpha: 1.0).cgColor
        container.layer?.backgroundColor = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.18, alpha: 1.0).cgColor
        container.addSubview(sectionStack)

        NSLayoutConstraint.activate([
            sectionStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            sectionStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            sectionStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            sectionStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])

        return container
    }

    private func makeLabeledControlRow(label: String, control: NSView) -> NSView {
        let labelField = NSTextField(labelWithString: label)
        labelField.textColor = NSColor(calibratedRed: 0.82, green: 0.84, blue: 0.87, alpha: 1.0)
        labelField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        labelField.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [labelField, control])
        row.orientation = .horizontal
        row.distribution = .fill
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    private func makeSliderRow(label: String, slider: NSSlider, valueLabel: NSTextField) -> NSView {
        let labelField = NSTextField(labelWithString: label)
        labelField.textColor = NSColor(calibratedRed: 0.82, green: 0.84, blue: 0.87, alpha: 1.0)
        labelField.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        valueLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = NSColor(calibratedRed: 0.86, green: 0.9, blue: 0.92, alpha: 1.0)
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let titleRow = NSStackView(views: [labelField, valueLabel])
        titleRow.orientation = .horizontal
        titleRow.spacing = 8

        let row = NSStackView(views: [titleRow, slider])
        row.orientation = .vertical
        row.spacing = 4

        return row
    }

    private func makeFootnote(text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor(calibratedRed: 0.72, green: 0.75, blue: 0.78, alpha: 1.0)
        return label
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
