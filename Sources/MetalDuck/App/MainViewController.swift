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

    private let controlPanel = ControlPanelView(frame: .zero)
    private let renderer: RendererCoordinator
    private let settingsStore: SettingsStore
    private let overlayController: ScalingOverlayController

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
        initialTarget: CaptureTarget,
        outputView: MTKView,
        overlayController: ScalingOverlayController
    ) throws {
        self.settingsStore = settingsStore
        self.captureConfiguration = captureConfiguration
        self.overlayController = overlayController

        self.renderer = try RendererCoordinator(
            view: outputView,
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
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 920))
        rootView.addSubview(controlPanel)
        controlPanel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            controlPanel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            controlPanel.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            controlPanel.topAnchor.constraint(equalTo: rootView.topAnchor),
            controlPanel.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
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
        applyCaptureTargetSelection()
        controlPanel.apply(settings: settingsStore.snapshot(), capture: captureConfiguration)
        controlPanel.setRunning(false)
        controlPanel.setStatus("Ready")
        overlayController.hide()
        updateWindowTitle()
    }

    func stop() async {
        await renderer.stop()
        DispatchQueue.main.async { [weak self] in
            self?.controlPanel.setRunning(false)
            self?.controlPanel.setStatus("Stopped")
            self?.overlayController.hide()
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
            format: "SOURCE %.1f FPS  |  OUT %.1f FPS\nGEN %.1f FPS  |  CAP %.1f FPS\n%@ -> %@  |  Scale %.2fx",
            stats.sourceFPS,
            stats.presentFPS,
            stats.generatedFPS,
            stats.captureFPS,
            inputLabel,
            outputLabel,
            stats.effectiveScale
        )
        controlPanel.setStats(label)
        overlayController.updateStats(stats)
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
        let nativeMatch = settings.matchOutputResolution ? "MatchOut On" : "MatchOut Off"
        let dynamic = settings.dynamicResolutionEnabled ? "DRS On" : "DRS Off"
        let fg = settings.frameGenerationEnabled ? "FG \(settings.frameGenerationMode.rawValue)" : "FG Off"

        let title = "MetalDuck | \(settings.upscalingAlgorithm.rawValue) | \(scaleString) | \(nativeMatch) | \(dynamic) | \(fg)"
        window.title = title
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

        if selectedCaptureMode == .window,
           !windowEntries.isEmpty {
            let browserHints = ["Firefox", "Google Chrome", "Safari", "Brave", "Arc"]
            if let browserIndex = windowEntries.firstIndex(where: { entry in
                browserHints.contains(where: { entry.title.localizedCaseInsensitiveContains($0) })
            }) {
                selectedWindowIndex = browserIndex
            } else {
                selectedWindowIndex = min(selectedWindowIndex, windowEntries.count - 1)
            }
        }

        applyCaptureModeToPicker()
        applyCaptureTargetSelection()
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
            guard let self else { return }
            do {
                try await self.renderer.reconfigureCapture(target: target)
                await MainActor.run {
                    if self.renderer.isRunning {
                        self.overlayController.show(on: self.outputDisplayID(for: target))
                    }
                }
            } catch {
                await MainActor.run {
                    self.controlPanel.setStatus("Capture target failed", isError: true)
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

    private func outputDisplayID(for target: CaptureTarget) -> CGDirectDisplayID? {
        switch target {
        case .display(let displayID):
            return displayID ?? displayIDForScreen(view.window?.screen)
        case .window(let windowID):
            return displayIDForWindow(windowID) ?? displayIDForScreen(view.window?.screen)
        case .automatic:
            return displayIDForFrontmostExternalWindow() ?? displayIDForScreen(view.window?.screen)
        }
    }

    private func displayIDForWindow(_ windowID: CGWindowID?) -> CGDirectDisplayID? {
        guard let windowID else {
            return nil
        }

        guard let rawInfo = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let info = rawInfo.first,
              let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }

        var bounds = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds) else {
            return nil
        }

        return displayIDForBounds(bounds)
    }

    private func displayIDForFrontmostExternalWindow() -> CGDirectDisplayID? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for entry in entries {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  pid_t(ownerPID.intValue) != currentPID,
                  let layer = entry[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary else {
                continue
            }

            var bounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds) else {
                continue
            }

            if let displayID = displayIDForBounds(bounds) {
                return displayID
            }
        }

        return nil
    }

    private func displayIDForBounds(_ bounds: CGRect) -> CGDirectDisplayID? {
        var bestDisplayID: CGDirectDisplayID?
        var bestArea: CGFloat = 0

        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(bounds)
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestDisplayID = displayIDForScreen(screen)
            }
        }

        return bestDisplayID
    }

    private func displayIDForScreen(_ screen: NSScreen?) -> CGDirectDisplayID? {
        guard let screen,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
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
                    self.overlayController.setWaitingForFrames(message: "Waiting for frames...")
                }
            }
        }
    }

    private func applyPreset(_ preset: ControlPreset) {
        var presetCaptureFPS: Int = captureConfiguration.framesPerSecond
        var presetQueueDepth: Int = captureConfiguration.queueDepth
        let settings = settingsStore.update { value in
            switch preset {
            case .performance:
                presetCaptureFPS = 30
                presetQueueDepth = 4
                value.upscalingAlgorithm = .nativeLinear
                value.outputScale = 1.0
                value.matchOutputResolution = true
                value.samplingMode = .nearest
                value.sharpness = 0.0
                value.dynamicResolutionEnabled = true
                value.dynamicScaleMinimum = 0.70
                value.dynamicScaleMaximum = 1.00
                value.targetPresentationFPS = 60
                value.frameGenerationEnabled = false
                value.frameGenerationMode = .x2

            case .balanced:
                presetCaptureFPS = 30
                presetQueueDepth = 5
                value.upscalingAlgorithm = .metalFXSpatial
                value.outputScale = 1.15
                value.matchOutputResolution = true
                value.samplingMode = .linear
                value.sharpness = 0.12
                value.dynamicResolutionEnabled = false
                value.dynamicScaleMinimum = 1.0
                value.dynamicScaleMaximum = 1.0
                value.targetPresentationFPS = 60
                value.frameGenerationEnabled = true
                value.frameGenerationMode = .x2

            case .quality:
                presetCaptureFPS = 30
                presetQueueDepth = 6
                value.upscalingAlgorithm = .metalFXSpatial
                value.outputScale = 1.35
                value.matchOutputResolution = false
                value.samplingMode = .linear
                value.sharpness = 0.22
                value.dynamicResolutionEnabled = false
                value.dynamicScaleMinimum = 1.0
                value.dynamicScaleMaximum = 1.0
                value.targetPresentationFPS = 60
                value.frameGenerationEnabled = true
                value.frameGenerationMode = .x2
            }
        }

        if captureConfiguration.framesPerSecond != presetCaptureFPS || captureConfiguration.queueDepth != presetQueueDepth {
            updateCaptureConfiguration { config in
                config.framesPerSecond = presetCaptureFPS
                config.queueDepth = presetQueueDepth
            }
        }

        controlPanel.apply(settings: settings, capture: captureConfiguration)
        switch preset {
        case .performance:
            controlPanel.setStatus("Preset applied: Performance (max FPS / low latency)")
        case .balanced:
            controlPanel.setStatus("Preset applied: Balanced (30 -> 60 + moderate upscale)")
        case .quality:
            controlPanel.setStatus("Preset applied: Quality (strong upscale + FG)")
        }
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
                        self?.overlayController.hide()
                        self?.updateWindowTitle()
                    }
                }
            } else {
                Task { [weak self] in
                    guard let self else { return }
                    let target = self.selectedCaptureTarget()
                    let outputDisplayID = self.outputDisplayID(for: target)
                    do {
                        await MainActor.run {
                            self.overlayController.show(on: outputDisplayID)
                            self.overlayController.setWaitingForFrames(message: "Starting capture...")
                        }

                        try await self.renderer.reconfigureCapture(target: target)
                        try await self.renderer.start()
                        await MainActor.run {
                            self.controlPanel.setRunning(true)
                            self.controlPanel.setStatus("Running (waiting for frames...)")
                            self.overlayController.setWaitingForFrames(message: "Processing active")
                            self.updateWindowTitle()
                            self.scheduleCaptureHealthCheck()
                        }
                    } catch {
                        NSLog("Renderer start failed: \(error.localizedDescription)")
                        await MainActor.run {
                            self.controlPanel.setRunning(false)
                            self.controlPanel.setStatus("Start failed", isError: true)
                            self.overlayController.setCaptureError("Start failed")
                            self.overlayController.hide()
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
            overlayController.setCaptureError("Screen Recording permission denied")
            return
        }

        panel.setStatus("Starting...")
        let target = selectedCaptureTarget()
        overlayController.show(on: outputDisplayID(for: target))
        overlayController.setWaitingForFrames(message: "Starting capture...")

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.renderer.reconfigureCapture(target: target)
                try await self.renderer.start()
                await MainActor.run {
                    panel.setRunning(true)
                    panel.setStatus("Running (waiting for frames...)")
                    self.overlayController.setWaitingForFrames(message: "Processing active")
                    self.scheduleCaptureHealthCheck()
                    self.updateWindowTitle()
                }
            } catch {
                NSLog("Renderer start failed: \(error.localizedDescription)")
                await MainActor.run {
                    panel.setRunning(false)
                    panel.setStatus("Start failed", isError: true)
                    self.overlayController.setCaptureError("Start failed: \(error.localizedDescription)")
                    self.overlayController.hide()
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
                self?.overlayController.hide()
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
        updateRenderSettings(syncUI: true) { settings in
            guard settings.frameGenerationEnabled else { return }
            let multiplier = settings.frameGenerationMode == .x2 ? 2 : 3
            let minimumTarget = max(60, fps * multiplier)
            if settings.targetPresentationFPS < minimumTarget {
                settings.targetPresentationFPS = minimumTarget
            }
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
        panel.setStatus("Upscaling: \(algorithm.rawValue)")
    }

    func controlPanel(_ panel: ControlPanelView, didChangeOutputScale scale: Float) {
        updateRenderSettings { settings in
            settings.outputScale = scale
        }
        panel.setStatus(String(format: "Scale factor: %.2fx", scale))
    }

    func controlPanel(_ panel: ControlPanelView, didToggleMatchOutputResolution enabled: Bool) {
        updateRenderSettings { settings in
            settings.matchOutputResolution = enabled
        }
        panel.setStatus(enabled ? "Match output resolution: On" : "Match output resolution: Off")
    }

    func controlPanel(_ panel: ControlPanelView, didChangeSamplingMode mode: SamplingMode) {
        updateRenderSettings { settings in
            settings.samplingMode = mode
        }
        panel.setStatus("Sampling: \(mode.rawValue)")
    }

    func controlPanel(_ panel: ControlPanelView, didChangeSharpness value: Float) {
        updateRenderSettings { settings in
            settings.sharpness = value
        }
        panel.setStatus(String(format: "Sharpness: %.2f", value))
    }

    func controlPanel(_ panel: ControlPanelView, didToggleDynamicResolution enabled: Bool) {
        updateRenderSettings { settings in
            settings.dynamicResolutionEnabled = enabled
        }
        panel.setStatus(enabled ? "Dynamic Resolution: On" : "Dynamic Resolution: Off")
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
        panel.setStatus("Target FPS: \(fps)")
    }

    func controlPanel(_ panel: ControlPanelView, didToggleFrameGeneration enabled: Bool) {
        updateRenderSettings(syncUI: true) { settings in
            settings.frameGenerationEnabled = enabled
            guard enabled else { return }
            let multiplier = settings.frameGenerationMode == .x2 ? 2 : 3
            let minimumTarget = max(60, captureConfiguration.framesPerSecond * multiplier)
            if settings.targetPresentationFPS < minimumTarget {
                settings.targetPresentationFPS = minimumTarget
            }
        }
        panel.setStatus(enabled ? "Frame Generation: On" : "Frame Generation: Off")
    }

    func controlPanel(_ panel: ControlPanelView, didChangeFrameGenerationMode mode: FrameGenerationMode) {
        updateRenderSettings(syncUI: true) { settings in
            settings.frameGenerationMode = mode
            guard settings.frameGenerationEnabled else { return }
            let multiplier = mode == .x2 ? 2 : 3
            let minimumTarget = max(60, captureConfiguration.framesPerSecond * multiplier)
            if settings.targetPresentationFPS < minimumTarget {
                settings.targetPresentationFPS = minimumTarget
            }
        }
        panel.setStatus("FG Mode: \(mode.rawValue)")
    }

    func controlPanel(_ panel: ControlPanelView, didSelectPreset preset: ControlPreset) {
        applyPreset(preset)
    }
}
