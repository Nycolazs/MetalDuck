import AppKit
import CoreGraphics
import Foundation
import MetalKit

@MainActor
final class MainViewController: NSViewController {
    private struct CaptureEntry {
        let title: String
        let target: CaptureTarget
    }

    private let mtkView: MTKView
    private let controlPanel = ControlPanelView(frame: .zero)
    private let renderer: RendererCoordinator
    private let settingsStore: SettingsStore

    private var captureConfiguration: CaptureConfiguration

    private var selectedCaptureMode: CaptureModeChoice = .automatic
    private var selectedDisplayIndex: Int = 0
    private var selectedWindowIndex: Int = 0

    private var displayEntries: [CaptureEntry] = []
    private var windowEntries: [CaptureEntry] = []
    private var lastStatsUpdateTime: CFTimeInterval?

    init(
        context: MetalContext,
        captureService: FrameCaptureService,
        settingsStore: SettingsStore,
        captureConfiguration: CaptureConfiguration,
        initialTarget: CaptureTarget
    ) throws {
        self.settingsStore = settingsStore
        self.captureConfiguration = captureConfiguration

        let mtkView = MTKView(frame: .zero, device: context.device)
        mtkView.translatesAutoresizingMaskIntoConstraints = false
        self.mtkView = mtkView

        self.renderer = try RendererCoordinator(
            view: mtkView,
            context: context,
            captureService: captureService,
            captureConfiguration: captureConfiguration,
            settingsStore: settingsStore,
            initialTarget: initialTarget
        )

        super.init(nibName: nil, bundle: nil)

        switch initialTarget {
        case .automatic:
            selectedCaptureMode = .automatic
        case .display:
            selectedCaptureMode = .display
        case .window:
            selectedCaptureMode = .window
        }

        controlPanel.delegate = self
        wireRendererCallbacks()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 1560, height: 920))

        let splitView = NSSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let panelContainer = NSView()
        panelContainer.translatesAutoresizingMaskIntoConstraints = false
        panelContainer.addSubview(controlPanel)
        controlPanel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            controlPanel.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor),
            controlPanel.trailingAnchor.constraint(equalTo: panelContainer.trailingAnchor),
            controlPanel.topAnchor.constraint(equalTo: panelContainer.topAnchor),
            controlPanel.bottomAnchor.constraint(equalTo: panelContainer.bottomAnchor),
            panelContainer.widthAnchor.constraint(equalToConstant: 370)
        ])

        let renderContainer = NSView()
        renderContainer.translatesAutoresizingMaskIntoConstraints = false
        renderContainer.addSubview(mtkView)

        NSLayoutConstraint.activate([
            mtkView.leadingAnchor.constraint(equalTo: renderContainer.leadingAnchor),
            mtkView.trailingAnchor.constraint(equalTo: renderContainer.trailingAnchor),
            mtkView.topAnchor.constraint(equalTo: renderContainer.topAnchor),
            mtkView.bottomAnchor.constraint(equalTo: renderContainer.bottomAnchor)
        ])

        splitView.addArrangedSubview(panelContainer)
        splitView.addArrangedSubview(renderContainer)

        rootView.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: rootView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        self.view = rootView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(self)
        updateWindowTitle()
    }

    func start() async {
        await refreshCaptureSources()
        controlPanel.setCaptureMode(selectedCaptureMode)
        controlPanel.apply(settings: settingsStore.snapshot(), capture: captureConfiguration)
        controlPanel.setRunning(false)
        controlPanel.setStatus("Ready")
        updateWindowTitle()
    }

    func stop() async {
        await renderer.stop()
        DispatchQueue.main.async { [weak self] in
            self?.controlPanel.setRunning(false)
            self?.controlPanel.setStatus("Stopped")
            self?.updateWindowTitle()
        }
    }

    private func wireRendererCallbacks() {
        renderer.onStatsUpdate = { [weak self] stats in
            DispatchQueue.main.async {
                self?.handleRendererStats(stats)
            }
        }
    }

    private func handleRendererStats(_ stats: RendererStats) {
        lastStatsUpdateTime = CACurrentMediaTime()
        let inputLabel = "\(Int(stats.inputSize.width))x\(Int(stats.inputSize.height))"
        let outputLabel = "\(Int(stats.outputSize.width))x\(Int(stats.outputSize.height))"
        let label = String(
            format: "CAP %.1f FPS  |  OUT %.1f FPS\n%@ -> %@  |  Scale %.2fx",
            stats.captureFPS,
            stats.presentFPS,
            inputLabel,
            outputLabel,
            stats.effectiveScale
        )
        controlPanel.setStats(label)
        if stats.isRunning {
            controlPanel.setStatus("Running")
        }
    }

    private func updateWindowTitle() {
        guard let window = view.window else {
            return
        }

        let settings = settingsStore.snapshot()
        let scaleString = String(format: "%.2fx", settings.outputScale)
        let dynamic = settings.dynamicResolutionEnabled ? "DRS On" : "DRS Off"
        let fg = settings.frameGenerationEnabled ? "FG \(settings.frameGenerationMode.rawValue)" : "FG Off"

        window.title = "MetalDuck | \(settings.upscalingAlgorithm.rawValue) | \(scaleString) | \(dynamic) | \(fg)"
    }

    private func refreshCaptureSources() async {
        controlPanel.setStatus("Scanning sources...")

        let catalog = await CaptureSourceCatalogProvider.load()

        displayEntries = catalog.displays.map { source in
            CaptureEntry(title: source.title, target: .display(source.displayID))
        }

        windowEntries = catalog.windows.map { source in
            CaptureEntry(title: source.title, target: .window(source.windowID))
        }

        applyCaptureModeToPicker()
        controlPanel.setStatus("Sources updated")
    }

    private func applyCaptureModeToPicker() {
        switch selectedCaptureMode {
        case .automatic:
            controlPanel.setCaptureSourceTitles(["Automatic (Window preferred)"], selectedIndex: 0)

        case .display:
            let titles = displayEntries.map(\.title)
            controlPanel.setCaptureSourceTitles(titles, selectedIndex: selectedDisplayIndex)
            if !titles.isEmpty {
                selectedDisplayIndex = min(selectedDisplayIndex, titles.count - 1)
            }

        case .window:
            let titles = windowEntries.map(\.title)
            controlPanel.setCaptureSourceTitles(titles, selectedIndex: selectedWindowIndex)
            if !titles.isEmpty {
                selectedWindowIndex = min(selectedWindowIndex, titles.count - 1)
            }
        }
    }

    private func selectedCaptureTarget() -> CaptureTarget {
        switch selectedCaptureMode {
        case .automatic:
            return .automatic
        case .display:
            guard !displayEntries.isEmpty else { return .display(nil) }
            return displayEntries[min(selectedDisplayIndex, displayEntries.count - 1)].target
        case .window:
            guard !windowEntries.isEmpty else { return .window(nil) }
            return windowEntries[min(selectedWindowIndex, windowEntries.count - 1)].target
        }
    }

    private func applyCaptureTargetSelection() {
        let target = selectedCaptureTarget()

        Task { [weak self] in
            do {
                try await self?.renderer.reconfigureCapture(target: target)
            } catch {
                await MainActor.run {
                    self?.controlPanel.setStatus("Capture target failed", isError: true)
                }
            }
        }
    }

    private func updateCaptureConfiguration(_ mutate: (inout CaptureConfiguration) -> Void) {
        mutate(&captureConfiguration)

        Task { [weak self] in
            guard let self else { return }
            do {
                try await renderer.reconfigureCapture(configuration: self.captureConfiguration)
            } catch {
                await MainActor.run {
                    self.controlPanel.setStatus("Capture config failed", isError: true)
                }
            }
        }
    }

    private func updateRenderSettings(syncUI: Bool = false, _ mutate: (inout RenderSettings) -> Void) {
        let updated = settingsStore.update(mutate)
        if syncUI {
            controlPanel.apply(settings: updated, capture: captureConfiguration)
        }
        updateWindowTitle()
    }

    private func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        let granted = CGRequestScreenCaptureAccess()
        return granted
    }

    private func scheduleCaptureHealthCheck() {
        let startedAt = CACurrentMediaTime()
        lastStatsUpdateTime = nil

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                guard let self else { return }
                guard self.renderer.isRunning else { return }

                let receivedStats = (self.lastStatsUpdateTime ?? 0) > startedAt
                if !receivedStats {
                    self.controlPanel.setStatus(
                        "No frames received. Check Screen Recording permission and selected source.",
                        isError: true
                    )
                }
            }
        }
    }

    private func applyPreset(_ preset: ControlPreset) {
        let settings = settingsStore.update { value in
            switch preset {
            case .performance:
                value.upscalingAlgorithm = .nativeLinear
                value.outputScale = 1.0
                value.sharpness = 0.05
                value.dynamicResolutionEnabled = true
                value.dynamicScaleMinimum = 0.70
                value.dynamicScaleMaximum = 1.00
                value.targetPresentationFPS = 120
                value.frameGenerationEnabled = false
                value.frameGenerationMode = .x2

            case .balanced:
                value.upscalingAlgorithm = .metalFXSpatial
                value.outputScale = 1.5
                value.sharpness = 0.15
                value.dynamicResolutionEnabled = true
                value.dynamicScaleMinimum = 0.75
                value.dynamicScaleMaximum = 1.00
                value.targetPresentationFPS = 120
                value.frameGenerationEnabled = false
                value.frameGenerationMode = .x2

            case .quality:
                value.upscalingAlgorithm = .metalFXSpatial
                value.outputScale = 2.0
                value.sharpness = 0.20
                value.dynamicResolutionEnabled = false
                value.dynamicScaleMinimum = 1.0
                value.dynamicScaleMaximum = 1.0
                value.targetPresentationFPS = 60
                value.frameGenerationEnabled = false
                value.frameGenerationMode = .x2
            }
        }

        controlPanel.apply(settings: settings, capture: captureConfiguration)
        updateWindowTitle()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        guard let character = event.charactersIgnoringModifiers?.lowercased() else {
            super.keyDown(with: event)
            return
        }

        switch character {
        case " ":
            if renderer.isRunning {
                Task { [weak self] in
                    await self?.renderer.stop()
                    await MainActor.run {
                        self?.controlPanel.setRunning(false)
                        self?.controlPanel.setStatus("Stopped")
                        self?.updateWindowTitle()
                    }
                }
            } else {
                Task { [weak self] in
                    do {
                        try await self?.renderer.start()
                        await MainActor.run {
                            self?.controlPanel.setRunning(true)
                            self?.controlPanel.setStatus("Running")
                            self?.updateWindowTitle()
                        }
                    } catch {
                        await MainActor.run {
                            self?.controlPanel.setRunning(false)
                            self?.controlPanel.setStatus("Start failed", isError: true)
                        }
                    }
                }
            }
        default:
            super.keyDown(with: event)
        }
    }
}

extension MainViewController: ControlPanelViewDelegate {
    func controlPanelDidPressStart(_ panel: ControlPanelView) {
        guard ensureScreenCapturePermission() else {
            panel.setStatus("Screen Recording permission denied.", isError: true)
            return
        }

        panel.setStatus("Starting...")

        Task { [weak self] in
            do {
                try await self?.renderer.start()
                await MainActor.run {
                    panel.setRunning(true)
                    panel.setStatus("Running (waiting for frames...)")
                    self?.scheduleCaptureHealthCheck()
                    self?.updateWindowTitle()
                }
            } catch {
                await MainActor.run {
                    panel.setRunning(false)
                    panel.setStatus("Start failed", isError: true)
                }
            }
        }
    }

    func controlPanelDidPressStop(_ panel: ControlPanelView) {
        panel.setStatus("Stopping...")

        Task { [weak self] in
            await self?.renderer.stop()
            await MainActor.run {
                panel.setRunning(false)
                panel.setStatus("Stopped")
                self?.updateWindowTitle()
            }
        }
    }

    func controlPanelDidRequestRefreshSources(_ panel: ControlPanelView) {
        Task { [weak self] in
            await self?.refreshCaptureSources()
        }
    }

    func controlPanel(_ panel: ControlPanelView, didSelectCaptureMode mode: CaptureModeChoice) {
        selectedCaptureMode = mode
        applyCaptureModeToPicker()
        applyCaptureTargetSelection()
    }

    func controlPanel(_ panel: ControlPanelView, didSelectCaptureSourceAt index: Int) {
        switch selectedCaptureMode {
        case .automatic:
            break
        case .display:
            selectedDisplayIndex = max(index, 0)
        case .window:
            selectedWindowIndex = max(index, 0)
        }
        applyCaptureTargetSelection()
    }

    func controlPanel(_ panel: ControlPanelView, didToggleCursor visible: Bool) {
        updateCaptureConfiguration { config in
            config.showsCursor = visible
        }
    }

    func controlPanel(_ panel: ControlPanelView, didChangeCaptureFPS fps: Int) {
        updateCaptureConfiguration { config in
            config.framesPerSecond = fps
        }
    }

    func controlPanel(_ panel: ControlPanelView, didChangeQueueDepth depth: Int) {
        updateCaptureConfiguration { config in
            config.queueDepth = depth
        }
    }

    func controlPanel(_ panel: ControlPanelView, didChangeUpscalingAlgorithm algorithm: UpscalingAlgorithm) {
        updateRenderSettings { settings in
            settings.upscalingAlgorithm = algorithm
        }
    }

    func controlPanel(_ panel: ControlPanelView, didChangeOutputScale scale: Float) {
        updateRenderSettings { settings in
            settings.outputScale = scale
        }
    }

    func controlPanel(_ panel: ControlPanelView, didChangeSamplingMode mode: SamplingMode) {
        updateRenderSettings { settings in
            settings.samplingMode = mode
        }
    }

    func controlPanel(_ panel: ControlPanelView, didChangeSharpness value: Float) {
        updateRenderSettings { settings in
            settings.sharpness = value
        }
    }

    func controlPanel(_ panel: ControlPanelView, didToggleDynamicResolution enabled: Bool) {
        updateRenderSettings { settings in
            settings.dynamicResolutionEnabled = enabled
        }
    }

    func controlPanel(_ panel: ControlPanelView, didChangeDynamicMinimum value: Float) {
        updateRenderSettings(syncUI: true) { settings in
            settings.dynamicScaleMinimum = value
            if settings.dynamicScaleMaximum < value {
                settings.dynamicScaleMaximum = value
            }
        }
    }

    func controlPanel(_ panel: ControlPanelView, didChangeDynamicMaximum value: Float) {
        updateRenderSettings(syncUI: true) { settings in
            settings.dynamicScaleMaximum = value
            if settings.dynamicScaleMinimum > value {
                settings.dynamicScaleMinimum = value
            }
        }
    }

    func controlPanel(_ panel: ControlPanelView, didChangeTargetPresentationFPS fps: Int) {
        updateRenderSettings { settings in
            settings.targetPresentationFPS = fps
        }
    }

    func controlPanel(_ panel: ControlPanelView, didToggleFrameGeneration enabled: Bool) {
        updateRenderSettings { settings in
            settings.frameGenerationEnabled = enabled
        }
    }

    func controlPanel(_ panel: ControlPanelView, didChangeFrameGenerationMode mode: FrameGenerationMode) {
        updateRenderSettings { settings in
            settings.frameGenerationMode = mode
        }
    }

    func controlPanel(_ panel: ControlPanelView, didSelectPreset preset: ControlPreset) {
        applyPreset(preset)
    }
}
