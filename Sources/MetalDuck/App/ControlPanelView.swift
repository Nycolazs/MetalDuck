import AppKit
import Foundation

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

    var shortTitle: String {
        switch self {
        case .automatic:
            return "Auto"
        case .display:
            return "Display"
        case .window:
            return "Window"
        }
    }
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
    func controlPanel(_ panel: ControlPanelView, didToggleFrameGeneration enabled: Bool)
    func controlPanel(_ panel: ControlPanelView, didChangeFrameGenerationMode mode: FrameGenerationMode)
    func controlPanel(_ panel: ControlPanelView, didToggleHUD visible: Bool)

    func controlPanel(_ panel: ControlPanelView, didSelectProfile id: UUID)
    func controlPanelDidRequestAddProfile(_ panel: ControlPanelView)
    func controlPanelDidRequestSettings(_ panel: ControlPanelView)
    func controlPanelDidRequestMonitor(_ panel: ControlPanelView)
    func controlPanelDidRequestGuide(_ panel: ControlPanelView)
    func controlPanel(_ panel: ControlPanelView, didRequestRenameProfile id: UUID)
    func controlPanel(_ panel: ControlPanelView, didRequestDuplicateProfile id: UUID)
    func controlPanel(_ panel: ControlPanelView, didRequestDeleteProfile id: UUID)
}

@MainActor
final class ControlPanelView: NSView {
    weak var delegate: ControlPanelViewDelegate?

    private var isApplyingValues = false
    private var isRunning = false

    // Header
    private let profileTitleLabel = GlassLabel.make("Profile", font: GlassFont.largeTitle)
    private let statusPill = StatusPill()
    private var profileTitleRow: NSView!
    private let profileSummaryLabel = GlassLabel.make(" ", font: GlassFont.body, color: .secondaryLabelColor)
    private let primaryButton = GlassActionButton(title: "Start", symbol: "play.fill", style: .accent, symbolSize: 11)

    // Session
    private let statusMessageLabel = GlassLabel.make("Ready", font: GlassFont.caption, color: .tertiaryLabelColor)
    private let captureMetric = MetricTile(caption: "Capture", symbol: "camera.viewfinder", unit: "fps")
    private let outputMetric = MetricTile(caption: "Output", symbol: "display", unit: "fps")
    private let generatedMetric = MetricTile(caption: "Generated", symbol: "sparkles", unit: "fps")
    private let resolutionMetric = MetricTile(caption: "Resolution", symbol: "aspectratio")

    // Capture
    private let captureModeControl = GlassSegmented.make(CaptureModeChoice.allCases.map(\.shortTitle))
    private let captureSourceDropdown = CompactDropdown()
    private let refreshSourcesButton = GlassActionButton(title: nil, symbol: "arrow.clockwise", style: .neutral, height: 32)
    private let sourceTitleLabel = GlassLabel.make("Window", font: GlassFont.body)
    private let sourceIcon = GlassSymbol.view("macwindow", size: 13)
    private let autoSourceLabel = GlassLabel.make("Frontmost window, picked automatically", font: GlassFont.body, color: .secondaryLabelColor)
    private let sourcePicker = NSStackView()
    private let captureCursorSwitch = GlassSwitch()
    private let captureFPSSlider = NSSlider(value: 30, minValue: 15, maxValue: 120, target: nil, action: nil)
    private let captureFPSValueLabel = NSTextField(labelWithString: "30")
    private let queueDepthSlider = NSSlider(value: 5, minValue: 1, maxValue: 8, target: nil, action: nil)
    private let queueDepthValueLabel = NSTextField(labelWithString: "5")

    // Scaling
    private let upscalerDropdown = CompactDropdown()
    private let outputScaleSlider = NSSlider(value: 1.5, minValue: 0.75, maxValue: 3.0, target: nil, action: nil)
    private let outputScaleValueLabel = NSTextField(labelWithString: "1.50×")
    private let matchOutputResolutionSwitch = GlassSwitch()
    private let samplingControl = GlassSegmented.make(SamplingMode.allCases.map(\.rawValue))
    private let sharpnessSlider = NSSlider(value: 0.0, minValue: 0.0, maxValue: 1.0, target: nil, action: nil)
    private let sharpnessValueLabel = NSTextField(labelWithString: "0.00")

    // Dynamic resolution
    private let dynamicResolutionSwitch = GlassSwitch()
    private let dynamicMinSlider = NSSlider(value: 0.75, minValue: 0.5, maxValue: 1.0, target: nil, action: nil)
    private let dynamicMinValueLabel = NSTextField(labelWithString: "0.75")
    private let dynamicMaxSlider = NSSlider(value: 1.0, minValue: 0.6, maxValue: 1.25, target: nil, action: nil)
    private let dynamicMaxValueLabel = NSTextField(labelWithString: "1.00")

    // Frame generation: segment 0 is "Off", the rest map onto FrameGenerationMode.
    private let frameGenerationControl = GlassSegmented.make(["Off"] + FrameGenerationMode.allCases.map(\.title))
    private let outputTargetLabel = GlassLabel.make("—", font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold))
    private var resolvedTargetFPS = 0

    // Stats overlay (HUD on the output window)
    private let hudSwitch = GlassSwitch()
    private let hudButton = GlassActionButton(title: "Overlay", symbol: "eye", style: .neutral, symbolSize: 12)
    private var isHUDVisible = true

    private var revealViews: [NSView] = []
    private var didReveal = false

    // Sidebar
    private let profileListStack = NSStackView()
    private let profileList = SidebarListView()
    private lazy var presetsHeader = makeSidebarHeader("Presets")
    private lazy var customHeader = makeSidebarHeader("My Profiles", accessory: addProfileButton)
    private let customEmptyLabel = GlassLabel.make(
        "Use + to save the current settings",
        font: GlassFont.caption,
        color: .tertiaryLabelColor
    )
    private lazy var addProfileButton = GlassButton.icon(
        "plus",
        help: "New profile from current settings",
        target: self,
        action: #selector(handleAddProfile)
    )
    private weak var sidebarView: NSView?
    private var sidebarMark: SidebarMark?
    private weak var hoveredSidebarRow: SidebarRow?
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var footerRows: [SidebarRow] = []
    private var isSidebarExpanded = false
    private var sidebarCollapseToken = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureControls()
        layoutUI()
        resetMetrics()
        updatePrimaryButton()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    func apply(settings: RenderSettings, capture: CaptureConfiguration, profileName: String) {
        isApplyingValues = true

        GlassMotion.crossfade(profileTitleLabel, to: profileName, duration: 0.3)
        upscalerDropdown.selectItem(withTitle: settings.upscalingAlgorithm.rawValue)
        outputScaleSlider.floatValue = settings.outputScale
        outputScaleValueLabel.stringValue = String(format: "%.2f×", settings.outputScale)
        matchOutputResolutionSwitch.isOn = settings.matchOutputResolution
        samplingControl.selectedSegment = SamplingMode.allCases.firstIndex(of: settings.samplingMode) ?? 0
        sharpnessSlider.floatValue = settings.sharpness
        sharpnessValueLabel.stringValue = String(format: "%.2f", settings.sharpness)

        dynamicResolutionSwitch.isOn = settings.dynamicResolutionEnabled
        dynamicMinSlider.floatValue = settings.dynamicScaleMinimum
        dynamicMaxSlider.floatValue = settings.dynamicScaleMaximum
        dynamicMinValueLabel.stringValue = String(format: "%.2f", settings.dynamicScaleMinimum)
        dynamicMaxValueLabel.stringValue = String(format: "%.2f", settings.dynamicScaleMaximum)
        applyOutputTarget(captureFPS: capture.framesPerSecond, settings: settings)

        if settings.frameGenerationEnabled,
           let index = FrameGenerationMode.allCases.firstIndex(of: settings.frameGenerationMode) {
            frameGenerationControl.selectedSegment = index + 1
        } else {
            frameGenerationControl.selectedSegment = 0
        }

        captureCursorSwitch.isOn = capture.showsCursor
        captureFPSSlider.integerValue = capture.framesPerSecond
        captureFPSValueLabel.stringValue = "\(capture.framesPerSecond) fps"
        queueDepthSlider.integerValue = capture.queueDepth
        queueDepthValueLabel.stringValue = "\(capture.queueDepth)"

        syncDependentControls()
        refreshSummary()
        isApplyingValues = false
    }

    func setCaptureMode(_ mode: CaptureModeChoice) {
        captureModeControl.selectedSegment = mode.rawValue
        updateSourceRow(for: mode, animated: false)
    }

    func setCaptureSourceTitles(_ titles: [String], selectedIndex: Int?) {
        if titles.isEmpty {
            captureSourceDropdown.items = ["No source found"]
            captureSourceDropdown.selectItem(at: 0)
            captureSourceDropdown.isEnabled = false
            return
        }

        captureSourceDropdown.isEnabled = true
        captureSourceDropdown.items = titles
        if let selectedIndex, titles.indices.contains(selectedIndex) {
            captureSourceDropdown.selectItem(at: selectedIndex)
        }
    }

    func setHUDVisible(_ visible: Bool) {
        isHUDVisible = visible
        hudSwitch.isOn = visible
        updateHUDButton()
    }

    func setRunning(_ running: Bool) {
        let changed = running != isRunning
        isRunning = running
        GlassAccent.isLive = running
        statusPill.set(running ? .running : .idle)
        updatePrimaryButton(animated: changed)
        applySliderAccent()
        updateHUDButton(animated: false)
        if changed && running {
            primaryButton.ripple(color: GlassAccent.live)
        }
        if !running {
            resetMetrics()
        }
    }

    func setStatus(_ message: String, isError: Bool = false) {
        statusMessageLabel.stringValue = message
        statusMessageLabel.toolTip = message
        statusMessageLabel.textColor = isError ? .systemRed : .tertiaryLabelColor
        statusPill.set(isError ? .error : (isRunning ? .running : .idle))
    }

    func setStats(_ stats: RendererStats) {
        captureMetric.set(value: String(format: "%.1f", stats.captureFPS))
        outputMetric.set(value: String(format: "%.1f", stats.presentFPS))
        generatedMetric.set(
            value: String(format: "%.1f", stats.generatedFPS),
            detail: stats.frameGenerationEnabled ? nil : "Frame generation off"
        )
        resolutionMetric.set(
            value: "\(Int(stats.inputSize.width))×\(Int(stats.inputSize.height))",
            detail: String(
                format: "→ %d×%d  ·  %.2f×",
                Int(stats.outputSize.width),
                Int(stats.outputSize.height),
                stats.effectiveScale
            )
        )
    }

    func setProfiles(_ profiles: [Profile], activeId: UUID) {
        profileListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let presets = profiles.filter(\.isBuiltIn)
        let custom = profiles.filter { !$0.isBuiltIn }

        addToProfileList(presetsHeader)
        presets.forEach { addToProfileList(makeProfileRow($0, activeId: activeId)) }

        addToProfileList(customHeader)
        profileListStack.setCustomSpacing(4, after: customHeader)
        if let lastPreset = profileListStack.arrangedSubviews.dropLast().last {
            profileListStack.setCustomSpacing(isSidebarExpanded ? 18 : 4, after: lastPreset)
        }
        if custom.isEmpty {
            customEmptyLabel.isHidden = !isSidebarExpanded
            addToProfileList(customEmptyLabel, inset: 10)
        } else {
            custom.forEach { addToProfileList(makeProfileRow($0, activeId: activeId)) }
        }

        let selected = profileListStack.arrangedSubviews
            .compactMap { $0 as? SidebarRow }
            .first { $0.isSelected }
        profileList.select(selected, animated: true)
    }

    // MARK: - Configuration

    private func configureControls() {
        primaryButton.target = self
        primaryButton.action = #selector(handlePrimaryTapped)
        primaryButton.widthAnchor.constraint(equalToConstant: 112).isActive = true

        captureModeControl.selectedSegment = CaptureModeChoice.automatic.rawValue
        captureModeControl.target = self
        captureModeControl.action = #selector(handleCaptureModeChanged)

        captureSourceDropdown.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        captureSourceDropdown.onSelectionChanged = { [weak self] _, index in
            guard let self, !self.isApplyingValues else { return }
            self.delegate?.controlPanel(self, didSelectCaptureSourceAt: index)
        }
        refreshSourcesButton.toolTip = "Refresh windows and displays"
        refreshSourcesButton.setAccessibilityLabel("Refresh windows and displays")
        refreshSourcesButton.target = self
        refreshSourcesButton.action = #selector(handleRefreshSources)

        upscalerDropdown.items = UpscalingAlgorithm.allCases.map(\.rawValue)
        upscalerDropdown.onSelectionChanged = { [weak self] title, _ in
            guard let self, !self.isApplyingValues,
                  let value = UpscalingAlgorithm(rawValue: title) else { return }
            self.refreshSummary()
            self.delegate?.controlPanel(self, didChangeUpscalingAlgorithm: value)
        }

        samplingControl.target = self
        samplingControl.action = #selector(handleSamplingChanged)

        frameGenerationControl.target = self
        frameGenerationControl.action = #selector(handleFrameGenerationChanged)

        for control in [frameGenerationControl, samplingControl, upscalerDropdown] as [NSView] {
            control.widthAnchor.constraint(equalToConstant: GlassMetrics.controlWidth).isActive = true
        }

        hudButton.target = self
        hudButton.action = #selector(handleHUDButton)
        hudButton.widthAnchor.constraint(equalToConstant: 112).isActive = true
        updateHUDButton(animated: false)

        let switches: [(GlassSwitch, Selector)] = [
            (captureCursorSwitch, #selector(handleCursorCaptureChanged)),
            (matchOutputResolutionSwitch, #selector(handleMatchOutputResolutionChanged)),
            (dynamicResolutionSwitch, #selector(handleDynamicResolutionChanged)),
            (hudSwitch, #selector(handleHUDSwitch))
        ]
        for (control, action) in switches {
            control.controlSize = .small
            control.target = self
            control.action = action
        }

        let sliders: [(NSSlider, Selector)] = [
            (captureFPSSlider, #selector(handleCaptureFPSChanged)),
            (queueDepthSlider, #selector(handleQueueDepthChanged)),
            (outputScaleSlider, #selector(handleOutputScaleChanged)),
            (sharpnessSlider, #selector(handleSharpnessChanged)),
            (dynamicMinSlider, #selector(handleDynamicMinChanged)),
            (dynamicMaxSlider, #selector(handleDynamicMaxChanged))
        ]
        for (control, action) in sliders {
            control.target = self
            control.action = action
        }
        applySliderAccent()
    }

    private func applySliderAccent() {
        let color = GlassAccent.color
        for slider in [captureFPSSlider, queueDepthSlider, outputScaleSlider, sharpnessSlider, dynamicMinSlider, dynamicMaxSlider] {
            slider.trackFillColor = color
        }
    }

    // MARK: - Layout

    private func layoutUI() {
        let backdrop = WindowBackdropView()
        addSubview(backdrop)
        pin(backdrop, to: self)

        let sidebar = makeSidebar()
        let header = makeHeader()
        let session = makeSessionCard()
        let sections = makeSections()
        let mark = SidebarMark()
        sidebarMark = mark

        addSubview(sidebar)
        addSubview(header)
        addSubview(mark)
        addSubview(session)
        addSubview(sections)

        let inset = GlassMetrics.windowInset
        let content = GlassMetrics.contentInset
        let sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: GlassMetrics.sidebarCollapsedWidth)
        sidebarWidthConstraint = sidebarWidth
        sidebarView = sidebar
        sidebar.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: [Self.sidebarTrackingKey: true]
        ))
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            // Share the card column's top and bottom, so the rail is not taller than the panels.
            sidebar.topAnchor.constraint(equalTo: session.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: sections.bottomAnchor),
            sidebarWidth,

            header.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: content),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -content),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 28),

            // Sit on the profile name and its status, not on the line underneath.
            mark.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            mark.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            mark.centerYAnchor.constraint(equalTo: profileTitleLabel.centerYAnchor, constant: 2),

            session.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            session.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            session.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),

            sections.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            sections.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            sections.topAnchor.constraint(equalTo: session.bottomAnchor, constant: GlassMetrics.sectionSpacing),
            // The window height follows the content, so the cards always end
            // level with the sidebar instead of leaving an empty band.
            sections.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)
        ])
        applySidebarState(animated: false)
    }

    // MARK: - Sidebar expand on hover

    private static let sidebarTrackingKey = "sidebar"

    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea?.userInfo?[Self.sidebarTrackingKey] != nil else {
            super.mouseEntered(with: event)
            return
        }
        sidebarCollapseToken += 1
        setSidebarExpanded(true)
        updateSidebarHover(at: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard event.trackingArea?.userInfo?[Self.sidebarTrackingKey] != nil else {
            super.mouseMoved(with: event)
            return
        }
        updateSidebarHover(at: event)
    }

    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea?.userInfo?[Self.sidebarTrackingKey] != nil else {
            super.mouseExited(with: event)
            return
        }
        hoveredSidebarRow?.setPointerInside(false)
        hoveredSidebarRow = nil
        sidebarCollapseToken += 1
        let token = sidebarCollapseToken
        // A short grace period, so brushing past the edge does not snap it shut.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, token == self.sidebarCollapseToken, !self.isMouseInSidebar else { return }
                self.setSidebarExpanded(false)
            }
        }
    }

    /// Lights up the row under the pointer and plays its icon effect. Row tracking
    /// alone misses these buttons, so the sidebar follows the pointer itself.
    private func updateSidebarHover(at event: NSEvent) {
        let hit = hitTest(convert(event.locationInWindow, from: nil))
        var row: SidebarRow?
        var view = hit
        while let current = view {
            if let found = current as? SidebarRow {
                row = found
                break
            }
            view = current.superview
        }
        guard row !== hoveredSidebarRow else { return }
        hoveredSidebarRow?.setPointerInside(false)
        hoveredSidebarRow = row
        row?.setPointerInside(true)
    }

    private var isMouseInSidebar: Bool {
        guard let window, let sidebarView else { return false }
        let point = sidebarView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return sidebarView.bounds.contains(point)
    }

    private func setSidebarExpanded(_ expanded: Bool) {
        guard expanded != isSidebarExpanded else { return }
        isSidebarExpanded = expanded
        applySidebarState(animated: !GlassMotion.reduceMotion && window != nil)
    }

    /// Collapsed shows icons only; expanding widens the sidebar and pushes the content right.
    private func applySidebarState(animated: Bool) {
        let expanded = isSidebarExpanded
        let width = expanded ? GlassMetrics.sidebarWidth : GlassMetrics.sidebarCollapsedWidth
        let rows = profileListStack.arrangedSubviews.compactMap { $0 as? SidebarRow } + footerRows
        let apply = { [self] in
            if animated {
                sidebarWidthConstraint?.animator().constant = width
                customEmptyLabel.animator().alphaValue = expanded ? 1 : 0
            } else {
                sidebarWidthConstraint?.constant = width
                customEmptyLabel.alphaValue = expanded ? 1 : 0
            }
            rows.forEach { $0.setTitleVisible(expanded, animated: animated) }
            presetsHeader.setCompact(!expanded, animated: animated)
            customHeader.setCompact(!expanded, animated: animated)
            sidebarMark?.setExpanded(expanded, animated: animated)
            customEmptyLabel.isHidden = !expanded
            if let index = profileListStack.arrangedSubviews.firstIndex(of: customHeader), index > 0 {
                let above = profileListStack.arrangedSubviews[index - 1]
                profileListStack.setCustomSpacing(expanded ? 18 : 4, after: above)
            }
        }
        guard animated else {
            apply()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = expanded ? 0.34 : 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1, 0.35, 1)
            apply()
        }
    }

    private func makeSidebar() -> NSView {
        let surface = GlassSurface(style: .sidebar, cornerRadius: GlassMetrics.sidebarRadius)

        profileListStack.translatesAutoresizingMaskIntoConstraints = false
        profileListStack.orientation = .vertical
        profileListStack.alignment = .leading
        profileListStack.spacing = 4

        let listDocument = profileList
        listDocument.translatesAutoresizingMaskIntoConstraints = false
        listDocument.addSubview(profileListStack)

        let listScroll = NSScrollView()
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.documentView = listDocument

        let guideRow = SidebarRow(title: "Guide", symbol: "book.closed")
        guideRow.toolTip = "What each control changes"
        guideRow.onHover = { [weak guideRow] in
            guard !GlassMotion.reduceMotion else { return }
            guideRow?.icon.addSymbolEffect(.bounce, options: .nonRepeating)
        }
        guideRow.onClick = { [weak self] in
            guard let self else { return }
            self.delegate?.controlPanelDidRequestGuide(self)
        }
        let monitorRow = SidebarRow(title: "Monitor", symbol: "waveform.path.ecg.rectangle")
        monitorRow.toolTip = "Live charts, load and the event log"
        monitorRow.onHover = { [weak monitorRow] in
            guard !GlassMotion.reduceMotion else { return }
            monitorRow?.icon.addSymbolEffect(.variableColor.iterative, options: .nonRepeating)
        }
        monitorRow.onClick = { [weak self] in
            guard let self else { return }
            self.delegate?.controlPanelDidRequestMonitor(self)
        }
        let settingsRow = SidebarRow(title: "Settings", symbol: "gearshape")
        settingsRow.onHover = { [weak settingsRow] in
            guard !GlassMotion.reduceMotion else { return }
            settingsRow?.icon.addSymbolEffect(.rotate, options: .nonRepeating)
        }
        settingsRow.onClick = { [weak self] in
            guard let self else { return }
            self.delegate?.controlPanelDidRequestSettings(self)
        }

        footerRows = [guideRow, monitorRow, settingsRow]
        let footer = NSStackView(views: [guideRow, monitorRow, settingsRow])
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 4

        let container = surface.contentView
        container.addSubview(listScroll)
        container.addSubview(footer)

        NSLayoutConstraint.activate([
            listScroll.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            listScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            listScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            listScroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),

            listDocument.leadingAnchor.constraint(equalTo: listScroll.contentView.leadingAnchor),
            listDocument.trailingAnchor.constraint(equalTo: listScroll.contentView.trailingAnchor),
            listDocument.topAnchor.constraint(equalTo: listScroll.contentView.topAnchor),
            profileListStack.leadingAnchor.constraint(equalTo: listDocument.leadingAnchor),
            profileListStack.trailingAnchor.constraint(equalTo: listDocument.trailingAnchor),
            profileListStack.topAnchor.constraint(equalTo: listDocument.topAnchor),
            profileListStack.bottomAnchor.constraint(equalTo: listDocument.bottomAnchor),

            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
        for view in footer.arrangedSubviews {
            view.leadingAnchor.constraint(equalTo: footer.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: footer.trailingAnchor).isActive = true
        }

        return surface
    }

    private func makeSidebarHeader(_ title: String, accessory: NSView? = nil) -> SidebarHeaderView {
        SidebarHeaderView(title: title, accessory: accessory)
    }

    private func makeProfileRow(_ profile: Profile, activeId: UUID) -> SidebarRow {
        let row = SidebarRow(title: profile.name, symbol: profile.symbolName)
        row.drawsSelectionBackground = false
        row.isSelected = profile.id == activeId
        row.setTitleVisible(isSidebarExpanded, animated: false)
        row.toolTip = profile.isBuiltIn ? "Built-in preset · right-click for more" : "Right-click to rename or delete"
        row.onClick = { [weak self] in
            guard let self else { return }
            self.delegate?.controlPanel(self, didSelectProfile: profile.id)
        }
        row.menu = makeProfileMenu(for: profile)
        return row
    }

    private func addToProfileList(_ view: NSView, inset: CGFloat = 0) {
        profileListStack.addArrangedSubview(view)
        view.leadingAnchor.constraint(equalTo: profileListStack.leadingAnchor, constant: inset).isActive = true
        view.trailingAnchor.constraint(equalTo: profileListStack.trailingAnchor).isActive = true
    }

    private func makeHeader() -> NSView {
        profileTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        profileSummaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let titleRow = NSStackView(views: [profileTitleLabel, statusPill])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 10
        profileTitleRow = titleRow

        let titles = NSStackView(views: [titleRow, profileSummaryLabel])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 4

        let header = NSStackView(views: [titles, NSView(), hudButton, primaryButton])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 16
        header.setCustomSpacing(10, after: hudButton)
        return header
    }

    private func makeSessionCard() -> NSView {
        let surface = GlassSurface()

        let metrics = NSStackView(views: [captureMetric, outputMetric, generatedMetric, resolutionMetric])
        metrics.translatesAutoresizingMaskIntoConstraints = false
        metrics.orientation = .horizontal
        metrics.distribution = .fillEqually
        metrics.spacing = 16

        statusMessageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [metrics, statusMessageLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        surface.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: surface.contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor, constant: -10),
            metrics.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            metrics.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            statusMessageLabel.trailingAnchor.constraint(lessThanOrEqualTo: stack.trailingAnchor)
        ])
        return surface
    }

    private func makeSections() -> NSView {
        let groups = [makeCaptureGroup(), makeFrameGenerationGroup(), makeScalingGroup(), makeDynamicResolutionGroup()]
        let leftColumn = makeColumn([groups[0], groups[1]])
        let rightColumn = makeColumn([groups[2], groups[3]])
        revealViews.append(contentsOf: [groups[0], groups[2], groups[1], groups[3]])

        let columns = NSStackView(views: [leftColumn, rightColumn])
        columns.translatesAutoresizingMaskIntoConstraints = false
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = GlassMetrics.columnSpacing
        columns.setHuggingPriority(.required, for: .vertical)
        return columns
    }

    private func makeColumn(_ groups: [NSView]) -> NSView {
        let column = NSStackView(views: groups)
        column.translatesAutoresizingMaskIntoConstraints = false
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = GlassMetrics.sectionSpacing
        column.setHuggingPriority(.required, for: .vertical)
        for group in groups {
            group.leadingAnchor.constraint(equalTo: column.leadingAnchor).isActive = true
            group.trailingAnchor.constraint(equalTo: column.trailingAnchor).isActive = true
        }
        return column
    }

    private func makeCaptureGroup() -> NSView {
        let group = SettingsGroup(title: "Capture", symbol: "camera.viewfinder")

        let modeIcon = GlassSymbol.view("rectangle.on.rectangle", size: 13)
        let modeTitle = GlassLabel.make("Mode", font: GlassFont.body)
        modeTitle.toolTip = "Capture a window, a whole display, or let MetalDuck pick."
        group.addRow(makeWideRow(icon: modeIcon, title: modeTitle, control: captureModeControl))
        group.addRow(makeWideRow(icon: sourceIcon, title: sourceTitleLabel, control: sourcePicker))
        configureSourcePicker()
        group.addRow(SettingRow.control("Show cursor", symbol: "cursorarrow", control: captureCursorSwitch))
        group.addRow(SettingRow.slider("Capture rate", symbol: "timer", help: "Expected cadence of the source.", slider: captureFPSSlider, value: captureFPSValueLabel))
        group.addRow(SettingRow.slider("Queue depth", symbol: "square.stack.3d.up", help: "Buffered frames. Higher is steadier, lower has less latency.", slider: queueDepthSlider, value: queueDepthValueLabel))
        return group
    }

    /// Row with a fixed title column and a control that fills the rest, so the
    /// mode selector and the source picker share both edges.
    private func makeWideRow(icon: NSImageView, title: NSTextField, control: NSView) -> NSView {
        icon.imageScaling = .scaleProportionallyDown
        icon.widthAnchor.constraint(equalToConstant: GlassMetrics.rowIconWidth).isActive = true
        title.widthAnchor.constraint(equalToConstant: 64).isActive = true
        control.setContentHuggingPriority(.init(1), for: .horizontal)

        let row = NSStackView(views: [icon, title, control])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = GlassMetrics.rowIconSpacing
        row.edgeInsets = NSEdgeInsets(
            top: 0,
            left: GlassMetrics.rowHorizontalPadding,
            bottom: 0,
            right: GlassMetrics.rowHorizontalPadding
        )
        row.heightAnchor.constraint(equalToConstant: GlassMetrics.rowHeight).isActive = true
        return row
    }

    private func configureSourcePicker() {
        autoSourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        autoSourceLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        captureSourceDropdown.setContentHuggingPriority(.init(1), for: .horizontal)

        sourcePicker.orientation = .horizontal
        sourcePicker.distribution = .fill
        sourcePicker.alignment = .centerY
        sourcePicker.spacing = 6
        sourcePicker.detachesHiddenViews = true
        for view in [captureSourceDropdown, refreshSourcesButton, autoSourceLabel] as [NSView] {
            sourcePicker.addArrangedSubview(view)
        }
        updateSourceRow(for: .automatic, animated: false)
    }

    private func updateSourceRow(for mode: CaptureModeChoice, animated: Bool) {
        let isAuto = mode == .automatic
        let title: String
        let symbol: String
        switch mode {
        case .automatic:
            title = "Source"
            symbol = "sparkle.magnifyingglass"
        case .display:
            title = "Display"
            symbol = "display"
        case .window:
            title = "Window"
            symbol = "macwindow"
        }
        GlassMotion.crossfade(sourceTitleLabel, to: title, duration: animated ? 0.25 : 0)
        if let image = GlassSymbol.image(symbol, size: 13) {
            if animated, !GlassMotion.reduceMotion {
                sourceIcon.setSymbolImage(image, contentTransition: .replace.downUp)
            } else {
                sourceIcon.image = image
            }
        }

        let show: [NSView] = isAuto ? [autoSourceLabel] : [captureSourceDropdown, refreshSourcesButton]
        let hide: [NSView] = isAuto ? [captureSourceDropdown, refreshSourcesButton] : [autoSourceLabel]
        hide.forEach { $0.isHidden = true }
        for view in show {
            view.isHidden = false
            if animated, !GlassMotion.reduceMotion {
                view.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    view.animator().alphaValue = 1
                }
            }
        }
    }

    private func makeFrameGenerationGroup() -> NSView {
        let group = SettingsGroup(title: "Frame Generation", symbol: "sparkles.rectangle.stack")
        outputTargetLabel.alignment = .right
        outputTargetLabel.setContentHuggingPriority(.required, for: .horizontal)
        outputTargetLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        group.addRow(SettingRow.control("Multiplier", symbol: "sparkles", help: "2×, 3× and 4× mean that many presented frames per captured frame.", control: frameGenerationControl))
        group.addRow(SettingRow.control("Output", symbol: "gauge.with.dots.needle.67percent", help: "The frame rate MetalDuck presents: capture rate × multiplier. It follows the multiplier, so there is no separate limit to guess.", control: outputTargetLabel))
        group.addRow(SettingRow.control("Stats overlay", symbol: "chart.bar.xaxis", help: "Show capture, generated and output FPS in the corner of the scaled window.", control: hudSwitch))
        return group
    }

    private func makeScalingGroup() -> NSView {
        let group = SettingsGroup(title: "Scaling", symbol: "arrow.up.left.and.arrow.down.right")
        group.addRow(SettingRow.control("Upscaler", symbol: "wand.and.stars", help: "MetalFX Spatial is sharper; Native Linear is cheaper.", control: upscalerDropdown))
        group.addRow(SettingRow.control("Fit to output", symbol: "display", help: "Scale the source to fill the output window, then apply the factor.", control: matchOutputResolutionSwitch))
        group.addRow(SettingRow.slider("Scale factor", symbol: "plus.magnifyingglass", slider: outputScaleSlider, value: outputScaleValueLabel))
        group.addRow(SettingRow.control("Sampling", symbol: "square.grid.3x3", help: "Filter used for native resampling.", control: samplingControl))
        group.addRow(SettingRow.slider("Sharpness", symbol: "circle.lefthalf.filled", help: "Post-process sharpening strength.", slider: sharpnessSlider, value: sharpnessValueLabel))
        return group
    }

    private func makeDynamicResolutionGroup() -> NSView {
        let group = SettingsGroup(title: "Dynamic Resolution", symbol: "aspectratio")
        group.addRow(SettingRow.control("Enabled", symbol: "bolt.badge.automatic", help: "Lower the render scale when output falls behind the target.", control: dynamicResolutionSwitch))
        group.addRow(SettingRow.slider("Minimum", symbol: "arrow.down.right.and.arrow.up.left", slider: dynamicMinSlider, value: dynamicMinValueLabel))
        group.addRow(SettingRow.slider("Maximum", symbol: "arrow.up.left.and.arrow.down.right", slider: dynamicMaxSlider, value: dynamicMaxValueLabel))
        return group
    }

    // MARK: - Motion

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !didReveal else { return }
        didReveal = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            GlassMotion.reveal(self.revealViews, delayStep: 0.06)
        }
    }

    /// The eye morphs into a slashed eye (and back) via Magic Replace.
    private func updateHUDButton(animated: Bool = true) {
        hudButton.setSymbol(isHUDVisible ? "eye" : "eye.slash", animated: animated)
        hudButton.symbolTint = isHUDVisible ? GlassAccent.color : .secondaryLabelColor
        hudButton.toolTip = isHUDVisible ? "Hide the stats overlay on the scaled window" : "Show the stats overlay on the scaled window"
    }

    private func toggleHUD(_ visible: Bool) {
        setHUDVisible(visible)
        delegate?.controlPanel(self, didToggleHUD: visible)
    }

    @objc private func handleHUDButton() {
        toggleHUD(!isHUDVisible)
    }

    @objc private func handleHUDSwitch() {
        toggleHUD(hudSwitch.isOn)
    }

    // MARK: - State helpers

    /// Play morphs into stop, the label fades and the capsule shifts from
    /// accent to red; starting also sends out a single ring.
    private func updatePrimaryButton(animated: Bool = false) {
        primaryButton.setSymbol(isRunning ? "stop.fill" : "play.fill", animated: animated)
        primaryButton.title = isRunning ? "Stop" : "Start"
        primaryButton.style = .accent
        primaryButton.toolTip = isRunning ? "Stop scaling" : "Start scaling"
    }

    private func resetMetrics() {
        captureMetric.set(value: "—")
        outputMetric.set(value: "—")
        generatedMetric.set(value: "—")
        resolutionMetric.set(value: "—")
    }

    private var selectedFrameGenerationMode: FrameGenerationMode? {
        let index = frameGenerationControl.selectedSegment - 1
        let modes = FrameGenerationMode.allCases
        return modes.indices.contains(index) ? modes[index] : nil
    }

    /// Output rate is capture × multiplier, shown as the equation so the number
    /// is explained wherever it comes from (a profile, the capture slider, 2×/3×/4×).
    private func applyOutputTarget(captureFPS: Int, settings: RenderSettings) {
        let capture = max(captureFPS, 1)
        let text: String
        if settings.frameGenerationEnabled {
            let multiplier = settings.frameGenerationMode.multiplier
            resolvedTargetFPS = capture * multiplier
            text = "\(capture) × \(multiplier) = \(resolvedTargetFPS) fps"
        } else {
            resolvedTargetFPS = capture
            text = "\(capture) fps"
        }
        GlassMotion.crossfade(outputTargetLabel, to: text, duration: 0.25)
        outputTargetLabel.toolTip = settings.frameGenerationEnabled
            ? "\(capture) captured frames per second, \(settings.frameGenerationMode.multiplier)× generation, \(resolvedTargetFPS) presented."
            : "Frame generation is off, so output matches the capture rate."
    }

    private func refreshSummary() {
        var parts: [String] = []
        if let upscaler = upscalerDropdown.titleOfSelectedItem {
            parts.append(upscaler)
        }
        parts.append(String(format: "%.2f×", outputScaleSlider.floatValue))
        if let mode = selectedFrameGenerationMode {
            parts.append("\(mode.title) frame generation")
        } else {
            parts.append("No frame generation")
        }
        if resolvedTargetFPS > 0 {
            parts.append("\(resolvedTargetFPS) fps output")
        }
        profileSummaryLabel.stringValue = parts.joined(separator: "  ·  ")
    }

    private func syncDependentControls() {
        let dynamicEnabled = dynamicResolutionSwitch.isOn
        for (slider, label) in [(dynamicMinSlider, dynamicMinValueLabel), (dynamicMaxSlider, dynamicMaxValueLabel)] {
            slider.isEnabled = dynamicEnabled
            label.textColor = dynamicEnabled ? .secondaryLabelColor : .tertiaryLabelColor
        }
    }

    // MARK: - Profile menu

    private func makeProfileMenu(for profile: Profile) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let duplicate = NSMenuItem(title: "Duplicate", action: #selector(handleDuplicateProfile(_:)), keyEquivalent: "")
        duplicate.image = GlassSymbol.image("plus.square.on.square")
        let rename = NSMenuItem(title: "Rename…", action: #selector(handleRenameProfile(_:)), keyEquivalent: "")
        rename.image = GlassSymbol.image("pencil")
        rename.isEnabled = !profile.isBuiltIn
        let delete = NSMenuItem(title: "Delete…", action: #selector(handleDeleteProfile(_:)), keyEquivalent: "")
        delete.image = GlassSymbol.image("trash")
        delete.isEnabled = !profile.isBuiltIn

        for item in [duplicate, rename, delete] {
            item.target = self
            item.representedObject = profile.id
        }
        menu.addItem(duplicate)
        menu.addItem(.separator())
        menu.addItem(rename)
        menu.addItem(delete)
        return menu
    }

    @objc private func handleDuplicateProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        delegate?.controlPanel(self, didRequestDuplicateProfile: id)
    }

    @objc private func handleRenameProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        delegate?.controlPanel(self, didRequestRenameProfile: id)
    }

    @objc private func handleDeleteProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        delegate?.controlPanel(self, didRequestDeleteProfile: id)
    }

    // MARK: - Actions

    @objc private func handlePrimaryTapped() {
        if isRunning {
            delegate?.controlPanelDidPressStop(self)
        } else {
            delegate?.controlPanelDidPressStart(self)
        }
    }

    @objc private func handleRefreshSources() {
        if !GlassMotion.reduceMotion {
            refreshSourcesButton.imageView.addSymbolEffect(.rotate, options: .nonRepeating)
        }
        delegate?.controlPanelDidRequestRefreshSources(self)
    }

    @objc private func handleAddProfile() {
        delegate?.controlPanelDidRequestAddProfile(self)
    }

    @objc private func handleCaptureModeChanged() {
        guard !isApplyingValues,
              let mode = CaptureModeChoice(rawValue: captureModeControl.selectedSegment) else { return }
        updateSourceRow(for: mode, animated: true)
        delegate?.controlPanel(self, didSelectCaptureMode: mode)
    }

    @objc private func handleSamplingChanged() {
        guard !isApplyingValues else { return }
        let modes = SamplingMode.allCases
        let index = samplingControl.selectedSegment
        guard modes.indices.contains(index) else { return }
        delegate?.controlPanel(self, didChangeSamplingMode: modes[index])
    }

    @objc private func handleFrameGenerationChanged() {
        guard !isApplyingValues else { return }
        refreshSummary()
        if let mode = selectedFrameGenerationMode {
            delegate?.controlPanel(self, didChangeFrameGenerationMode: mode)
            delegate?.controlPanel(self, didToggleFrameGeneration: true)
        } else {
            delegate?.controlPanel(self, didToggleFrameGeneration: false)
        }
    }

    @objc private func handleCursorCaptureChanged() {
        guard !isApplyingValues else { return }
        delegate?.controlPanel(self, didToggleCursor: captureCursorSwitch.isOn)
    }

    @objc private func handleCaptureFPSChanged() {
        guard !isApplyingValues else { return }
        let value = captureFPSSlider.integerValue
        captureFPSValueLabel.stringValue = "\(value) fps"
        delegate?.controlPanel(self, didChangeCaptureFPS: value)
    }

    @objc private func handleQueueDepthChanged() {
        guard !isApplyingValues else { return }
        let value = queueDepthSlider.integerValue
        queueDepthValueLabel.stringValue = "\(value)"
        delegate?.controlPanel(self, didChangeQueueDepth: value)
    }

    @objc private func handleOutputScaleChanged() {
        guard !isApplyingValues else { return }
        let value = outputScaleSlider.floatValue
        outputScaleValueLabel.stringValue = String(format: "%.2f×", value)
        refreshSummary()
        delegate?.controlPanel(self, didChangeOutputScale: value)
    }

    @objc private func handleMatchOutputResolutionChanged() {
        guard !isApplyingValues else { return }
        delegate?.controlPanel(self, didToggleMatchOutputResolution: matchOutputResolutionSwitch.isOn)
    }

    @objc private func handleSharpnessChanged() {
        guard !isApplyingValues else { return }
        let value = sharpnessSlider.floatValue
        sharpnessValueLabel.stringValue = String(format: "%.2f", value)
        delegate?.controlPanel(self, didChangeSharpness: value)
    }

    @objc private func handleDynamicResolutionChanged() {
        guard !isApplyingValues else { return }
        syncDependentControls()
        delegate?.controlPanel(self, didToggleDynamicResolution: dynamicResolutionSwitch.isOn)
    }

    @objc private func handleDynamicMinChanged() {
        guard !isApplyingValues else { return }
        let value = min(dynamicMinSlider.floatValue, dynamicMaxSlider.floatValue)
        dynamicMinSlider.floatValue = value
        dynamicMinValueLabel.stringValue = String(format: "%.2f", value)
        delegate?.controlPanel(self, didChangeDynamicMinimum: value)
    }

    @objc private func handleDynamicMaxChanged() {
        guard !isApplyingValues else { return }
        let value = max(dynamicMaxSlider.floatValue, dynamicMinSlider.floatValue)
        dynamicMaxSlider.floatValue = value
        dynamicMaxValueLabel.stringValue = String(format: "%.2f", value)
        delegate?.controlPanel(self, didChangeDynamicMaximum: value)
    }

}

/// Glass mark in the gap above the rail, left of the profile name.
/// The name appears beside it only while the rail is open.
final class SidebarMark: NSView {
    private let title = GlassLabel.make("MetalDuck", font: GlassFont.sidebarItem, color: .secondaryLabelColor)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.image = MetalDuckIcon.glassMark()
        icon.setAccessibilityLabel("MetalDuck")

        title.alphaValue = 0
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(icon)
        addSubview(title)
        // Same axis as the 20 pt row icons: their centre is 30 pt from the rail edge.
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            title.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        let alpha: CGFloat = expanded ? 1 : 0
        if animated {
            title.animator().alphaValue = alpha
        } else {
            title.alphaValue = alpha
        }
    }
}

/// Sidebar section title. When the sidebar shows icons only, the title fades
/// and the accessory (the + button) moves into the icon column.
final class SidebarHeaderView: NSView {
    private let label: NSTextField
    private var heightConstraint: NSLayoutConstraint!
    private var accessoryTrailing: NSLayoutConstraint?

    /// Centres a 22 pt accessory over the 20 pt icons of 40 pt collapsed rows.
    private static let compactTrailing: CGFloat = -9
    private static let regularTrailing: CGFloat = -2

    init(title: String, accessory: NSView?) {
        label = GlassLabel.sidebarHeader(title)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(label)
        let height = heightAnchor.constraint(equalToConstant: 28)
        heightConstraint = height
        NSLayoutConstraint.activate([
            height,
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        let labelEnd: NSLayoutConstraint
        if let accessory {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            addSubview(accessory)
            let trailing = accessory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: Self.regularTrailing)
            accessoryTrailing = trailing
            NSLayoutConstraint.activate([trailing, accessory.centerYAnchor.constraint(equalTo: centerYAnchor)])
            labelEnd = label.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -6)
        } else {
            labelEnd = label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2)
        }
        // Gives way at the collapsed width, where the faded title has no room.
        labelEnd.priority = .defaultHigh
        labelEnd.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Call inside an animation group to move with the sidebar.
    func setCompact(_ compact: Bool, animated: Bool) {
        let alpha: CGFloat = compact ? 0 : 1
        let trailing = compact ? Self.compactTrailing : Self.regularTrailing
        // A title with nothing else under it is just a blank band once the words fade.
        // The new-profile header keeps a row so its + stays with the icons.
        let height: CGFloat = accessoryTrailing == nil ? (compact ? 0 : 28) : (compact ? 40 : 28)
        if animated {
            label.animator().alphaValue = alpha
            accessoryTrailing?.animator().constant = trailing
            heightConstraint.animator().constant = height
        } else {
            label.alphaValue = alpha
            accessoryTrailing?.constant = trailing
            heightConstraint.constant = height
        }
    }
}
