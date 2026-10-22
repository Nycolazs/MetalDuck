import AppKit

/// Monitor as a sheet of the main window, the same way Settings is attached to it.
@MainActor
final class MonitorViewController: NSViewController {
    private let monitor = MonitorView()

    override func loadView() {
        monitor.onClose = { [weak self] in
            self?.dismiss(nil)
        }
        view = monitor
        preferredContentSize = NSSize(width: MonitorView.width, height: MonitorView.height)
    }
}

// MARK: - Root view

@MainActor
final class MonitorView: NSView {
    static let width: CGFloat = 1000
    static let height: CGFloat = 590
    var onClose: (() -> Void)?

    private static let historyLength = 90

    private let titleLabel = GlassLabel.make("Monitor", font: GlassFont.largeTitle)
    private let verdictBadge = VerdictBadge()
    private let verdictLabel = GlassLabel.make(" ", font: GlassFont.body, color: .secondaryLabelColor)

    private let saveSwitch = NSSwitch()
    private let diskLabel = GlassLabel.make(" ", font: GlassFont.caption, color: .tertiaryLabelColor)
    private lazy var revealButton = GlassActionButton(title: nil, symbol: "folder", style: .neutral, height: 28)
    private lazy var deleteButton = GlassActionButton(title: nil, symbol: "trash", style: .neutral, height: 28)
    private lazy var doneButton = GlassActionButton(title: "Done", symbol: "checkmark", style: .accent, symbolSize: 11, height: 28)

    private let captureCard = StatCard(title: "Capture", symbol: "camera.viewfinder", unit: "fps", color: .systemBlue)
    private let outputCard = StatCard(title: "Output", symbol: "display", unit: "fps", color: .systemGreen)
    private let generatedCard = StatCard(title: "Generated", symbol: "sparkles", unit: "fps", color: .systemPurple)
    private let frameTimeCard = StatCard(title: "Frame time", symbol: "timer", unit: "ms", color: .systemOrange)

    private let fpsChart = LineChartView()
    private let cpuChart = LineChartView()
    private let memoryMeter = MeterRow(title: "Memory", symbol: "memorychip")
    private let drawMeter = MeterRow(title: "GPU draw", symbol: "cpu")
    private let flowMeter = MeterRow(title: "Optical flow", symbol: "wind")
    private let mixChart = StackedBarChartView()
    private let mixLegend = MixLegend()

    private let busyFact = FactView(title: "Vision busy", symbol: "hourglass")
    private let lagFact = FactView(title: "Flow lag", symbol: "arrow.triangle.2.circlepath")
    private let dropsFact = FactView(title: "Capture drops", symbol: "exclamationmark.triangle")
    private let drawMaxFact = FactView(title: "Slowest draw", symbol: "tortoise")
    private let healthLabel = NSTextField(wrappingLabelWithString: " ")

    private let feed = LogFeedView()

    private var stats: [PipelineLiveStats] = []
    private var loads: [PipelineLoad] = []
    private var lastLiveUpdate = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    private var idleTimer: Timer?
    private var cards: [NSView] = []
    private var didReveal = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        buildLayout()

        stats = Array(PipelineLog.shared.recentStats().suffix(Self.historyLength))
        loads = stats.map(\.load)
        if let last = stats.last, Date().timeIntervalSince(last.date) < 2.5 {
            lastLiveUpdate = last.date
        }
        if loads.isEmpty {
            loads = [PipelineLog.shared.currentLoad()]
        }
        refresh(animated: false)
        refreshDiskUsage()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .pipelineLiveStats, object: nil, queue: .main) { [weak self] note in
            guard let live = note.object as? PipelineLiveStats else { return }
            MainActor.assumeIsolated { self?.append(live) }
        })
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleIdle() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !didReveal else { return }
        didReveal = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            GlassMotion.reveal(self.cards, delayStep: 0.04)
        }
    }

    // MARK: Layout

    private func buildLayout() {
        widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true

        let header = makeHeader()
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = GlassMetrics.columnSpacing

        let kpis = row([captureCard, outputCard, generatedCard, frameTimeCard])
        let charts = row([
            card("Frame rate", symbol: "waveform.path.ecg", legend: [("Capture", .systemBlue), ("Output", .systemGreen), ("Generated", .systemPurple)], content: fpsChart),
            makeLoadCard()
        ], ratios: [2, 1])
        let details = row([
            card("Output frames", symbol: "square.stack.3d.up", legend: [], content: makeMixContent()),
            card("Pipeline health", symbol: "stethoscope", legend: [], content: makeHealthContent())
        ])
        let log = card("Event log", symbol: "list.bullet.rectangle", legend: [], accessory: feed.filterControl, content: feed)
        cards = [kpis, charts, details, log]

        for view in cards {
            stack.addArrangedSubview(view)
            view.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
        log.setContentHuggingPriority(.init(1), for: .vertical)

        addSubview(header)
        addSubview(stack)
        let inset: CGFloat = 18
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

            stack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),

            kpis.heightAnchor.constraint(equalToConstant: 96),
            charts.heightAnchor.constraint(equalToConstant: 168),
            details.heightAnchor.constraint(equalToConstant: 124),
            log.heightAnchor.constraint(greaterThanOrEqualToConstant: 110)
        ])
    }

    private func makeHeader() -> NSView {
        let titleRow = NSStackView(views: [titleLabel, verdictBadge])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 10

        verdictLabel.lineBreakMode = .byTruncatingTail
        verdictLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let titles = NSStackView(views: [titleRow, verdictLabel])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 4
        titles.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        saveSwitch.controlSize = .small
        saveSwitch.state = PipelineLog.shared.isSavingToFile ? .on : .off
        saveSwitch.target = self
        saveSwitch.action = #selector(handleSaveToggle)
        let saveLabel = GlassLabel.make("Save log files", font: GlassFont.body)
        saveLabel.toolTip = "Write every event and per-second summary to ~/Library/Logs/MetalDuck. The in-app log works either way."
        let saveText = NSStackView(views: [saveLabel, diskLabel])
        saveText.orientation = .vertical
        saveText.alignment = .trailing
        saveText.spacing = 1

        revealButton.toolTip = "Show log files in Finder"
        revealButton.target = self
        revealButton.action = #selector(handleReveal)
        deleteButton.toolTip = "Delete saved log files"
        deleteButton.target = self
        deleteButton.action = #selector(handleDelete)
        doneButton.target = self
        doneButton.action = #selector(handleDone)
        doneButton.setContentHuggingPriority(.required, for: .horizontal)
        doneButton.widthAnchor.constraint(equalToConstant: 108).isActive = true

        let fileControls = NSStackView(views: [saveText, saveSwitch, revealButton, deleteButton, doneButton])
        fileControls.orientation = .horizontal
        fileControls.alignment = .centerY
        fileControls.spacing = 10
        fileControls.setCustomSpacing(14, after: saveSwitch)
        fileControls.setCustomSpacing(6, after: revealButton)
        fileControls.setCustomSpacing(14, after: deleteButton)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let header = NSStackView(views: [titles, spacer, fileControls])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.distribution = .fill
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 24
        return header
    }

    private func row(_ views: [NSView], ratios: [CGFloat]? = nil) -> NSView {
        let stack = NSStackView(views: views)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .height
        stack.spacing = GlassMetrics.columnSpacing
        if let ratios, ratios.count == views.count, let first = views.first {
            stack.distribution = .fill
            for (index, view) in views.enumerated().dropFirst() {
                view.widthAnchor.constraint(equalTo: first.widthAnchor, multiplier: ratios[index] / ratios[0]).isActive = true
            }
        } else {
            stack.distribution = .fillEqually
        }
        return stack
    }

    private func card(
        _ title: String,
        symbol: String,
        legend: [(String, NSColor)],
        accessory: NSView? = nil,
        content: NSView
    ) -> NSView {
        let surface = GlassSurface()
        var headerViews: [NSView] = [
            GlassSymbol.view(symbol, size: 12, weight: .semibold),
            GlassLabel.make(title, font: GlassFont.groupTitle, color: .secondaryLabelColor),
            NSView()
        ]
        for (name, color) in legend {
            headerViews.append(LegendItem(name: name, color: color))
        }
        if let accessory {
            headerViews.append(accessory)
        }
        let header = NSStackView(views: headerViews)
        header.translatesAutoresizingMaskIntoConstraints = false
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        for item in headerViews.dropFirst(3) {
            header.setCustomSpacing(12, after: item)
        }

        content.translatesAutoresizingMaskIntoConstraints = false
        surface.contentView.addSubview(header)
        surface.contentView.addSubview(content)
        let container = surface.contentView
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            header.heightAnchor.constraint(equalToConstant: 24),
            content.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        return surface
    }

    private func makeLoadCard() -> NSView {
        cpuChart.minimumMaximum = 25
        cpuChart.valueFormatter = { String(format: "%.0f%%", $0) }

        let meters = NSStackView(views: [memoryMeter, drawMeter, flowMeter])
        meters.orientation = .vertical
        meters.alignment = .leading
        meters.spacing = 8
        for meter in meters.arrangedSubviews {
            meter.leadingAnchor.constraint(equalTo: meters.leadingAnchor).isActive = true
            meter.trailingAnchor.constraint(equalTo: meters.trailingAnchor).isActive = true
        }

        let content = NSStackView(views: [cpuChart, meters])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        for view in content.arrangedSubviews {
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor).isActive = true
        }
        cpuChart.setContentHuggingPriority(.init(1), for: .vertical)
        return card("CPU", symbol: "gauge.with.dots.needle.33percent", legend: [("App", .systemTeal), ("System", .systemIndigo)], content: content)
    }

    private func makeMixContent() -> NSView {
        let content = NSStackView(views: [mixChart, mixLegend])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        for view in content.arrangedSubviews {
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor).isActive = true
        }
        mixChart.setContentHuggingPriority(.init(1), for: .vertical)
        return content
    }

    private func makeHealthContent() -> NSView {
        healthLabel.font = GlassFont.body
        healthLabel.textColor = .secondaryLabelColor
        healthLabel.maximumNumberOfLines = 2
        healthLabel.lineBreakMode = .byTruncatingTail
        healthLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        healthLabel.translatesAutoresizingMaskIntoConstraints = false

        let facts = NSStackView(views: [busyFact, lagFact, dropsFact, drawMaxFact])
        facts.orientation = .horizontal
        facts.distribution = .fillEqually
        facts.spacing = 12

        let content = NSStackView(views: [healthLabel, NSView(), facts])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        for view in content.arrangedSubviews {
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor).isActive = true
        }
        return content
    }

    // MARK: Data

    private var isLive: Bool {
        Date().timeIntervalSince(lastLiveUpdate) < 2.5
    }

    private func append(_ live: PipelineLiveStats) {
        lastLiveUpdate = live.date
        stats.append(live)
        loads.append(live.load)
        trim()
        refresh(animated: true)
    }

    private func sampleIdle() {
        guard !isLive else { return }
        loads.append(PipelineLog.shared.currentLoad())
        trim()
        refresh(animated: true)
    }

    private func trim() {
        if stats.count > Self.historyLength { stats.removeFirst(stats.count - Self.historyLength) }
        if loads.count > Self.historyLength { loads.removeFirst(loads.count - Self.historyLength) }
    }

    private func refresh(animated: Bool) {
        let live = isLive
        let latest = live ? stats.last : nil
        let recent = stats.suffix(30)

        func summary(_ values: [Double], unit: String) -> String {
            guard live, let low = values.min() else { return " " }
            let average = values.reduce(0, +) / Double(values.count)
            return String(format: "avg %.1f · min %.1f %@", average, low, unit)
        }

        captureCard.set(value: latest.map { String(format: "%.1f", $0.captureFPS) }, footnote: summary(recent.map(\.captureFPS), unit: "fps"))
        outputCard.set(value: latest.map { String(format: "%.1f", $0.outputFPS) }, footnote: summary(recent.map(\.outputFPS), unit: "fps"))
        generatedCard.set(
            value: latest.map { String(format: "%.1f", $0.generatedFPS) },
            footnote: latest.map { "flow \($0.flowFrames) · blend \($0.blendFrames) per second" } ?? " "
        )
        frameTimeCard.set(
            value: latest.map { String(format: "%.1f", $0.drawAverageMilliseconds) },
            footnote: latest.map { String(format: "max %.1f ms · budget 16.7", $0.drawMaxMilliseconds) } ?? " "
        )

        let samples = Array(stats)
        captureCard.setHistory(samples.map(\.captureFPS), animated: animated && live)
        outputCard.setHistory(samples.map(\.outputFPS), animated: animated && live)
        generatedCard.setHistory(samples.map(\.generatedFPS), animated: animated && live)
        frameTimeCard.setHistory(samples.map(\.drawAverageMilliseconds), animated: animated && live)

        fpsChart.capacity = Self.historyLength
        fpsChart.minimumMaximum = 30
        // Later series draw on top; generated often equals output, so it sits underneath, dashed.
        fpsChart.set(series: [
            .init(color: .systemPurple, values: samples.map(\.generatedFPS), isDashed: true),
            .init(color: .systemGreen, values: samples.map(\.outputFPS)),
            .init(color: .systemBlue, values: samples.map(\.captureFPS))
        ], animated: animated && live)

        cpuChart.capacity = Self.historyLength
        cpuChart.set(series: [
            .init(color: .systemTeal, values: loads.map(\.processCPU)),
            .init(color: .systemIndigo, values: loads.map(\.systemCPU))
        ], animated: animated)

        if let load = loads.last {
            memoryMeter.set(value: load.residentMB > 0 ? String(format: "%.0f MB", load.residentMB) : nil, fraction: load.residentMB / 2048)
        }
        drawMeter.set(value: latest.map { String(format: "%.1f ms", $0.drawAverageMilliseconds) }, fraction: (latest?.drawAverageMilliseconds ?? 0) / 16.7)
        flowMeter.set(
            value: latest.flatMap { $0.flowComputeMilliseconds > 0 ? String(format: "%.0f ms", $0.flowComputeMilliseconds) : nil },
            fraction: (latest?.flowComputeMilliseconds ?? 0) / 33.3
        )

        mixChart.capacity = 60
        mixChart.set(samples: samples.suffix(60).map { [$0.flowFrames, $0.blendFrames, $0.passthroughFrames, $0.repeatedFrames] }, animated: animated && live)
        mixLegend.set(latest.map { [$0.flowFrames, $0.blendFrames, $0.passthroughFrames, $0.repeatedFrames] } ?? [0, 0, 0, 0])

        busyFact.set(latest.map { "\($0.visionBusySkipped)/s" }, warning: (latest?.visionBusySkipped ?? 0) > 10)
        lagFact.set(latest.map { "\($0.flowLag) frames" }, warning: (latest?.flowLag ?? 0) > 2)
        dropsFact.set(latest.map { "\($0.captureDrops)/s" }, warning: (latest?.captureDrops ?? 0) > 0)
        drawMaxFact.set(latest.map { String(format: "%.1f ms", $0.drawMaxMilliseconds) }, warning: (latest?.drawMaxMilliseconds ?? 0) > 16.7)

        if let latest {
            let parts = latest.verdict.components(separatedBy: " — ")
            verdictBadge.set(VerdictBadge.Kind(verdictPrefix: parts.first ?? ""))
            let detail = parts.count > 1 ? parts.dropFirst().joined(separator: " — ") : latest.verdict
            let sentence = detail.prefix(1).uppercased() + detail.dropFirst()
            GlassMotion.crossfade(verdictLabel, to: sentence)
            GlassMotion.crossfade(healthLabel, to: sentence)
            verdictLabel.toolTip = latest.verdict
        } else {
            verdictBadge.set(.idle)
            GlassMotion.crossfade(verdictLabel, to: "Idle. Start scaling in the main window to see live numbers.")
            GlassMotion.crossfade(healthLabel, to: "Nothing is running. The last session stays on the charts.")
        }
    }

    private func refreshDiskUsage() {
        let bytes = PipelineLog.shared.savedLogsSize()
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        diskLabel.stringValue = PipelineLog.shared.isSavingToFile ? "\(size) on disk" : "Off · \(size) on disk"
        deleteButton.isEnabled = bytes > 0
    }

    // MARK: Actions

    @objc private func handleSaveToggle() {
        PipelineLog.shared.isSavingToFile = saveSwitch.state == .on
        refreshDiskUsage()
    }

    @objc private func handleReveal() {
        if let url = PipelineLog.shared.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            try? FileManager.default.createDirectory(at: PipelineLog.directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(PipelineLog.directory)
        }
    }

    @objc private func handleDone() {
        onClose?()
    }

    @objc private func handleDelete() {
        PipelineLog.shared.deleteSavedLogs()
        deleteButton.imageView.addSymbolEffect(.wiggle, options: .nonRepeating)
        refreshDiskUsage()
    }
}

// MARK: - Cards

@MainActor
private final class StatCard: GlassSurface {
    private let valueLabel = GlassLabel.make("—", font: GlassFont.metric)
    private let footnoteLabel = GlassLabel.make(" ", font: GlassFont.caption, color: .tertiaryLabelColor)
    private let sparkline = LineChartView()
    private let color: NSColor

    init(title: String, symbol: String, unit: String, color: NSColor) {
        self.color = color
        super.init(style: .card, cornerRadius: GlassMetrics.cardRadius)
        sparkline.isCompact = true
        sparkline.minimumMaximum = 1

        let caption = NSStackView(views: [
            GlassSymbol.view(symbol, size: 11, weight: .medium, tint: color),
            GlassLabel.make(title, font: GlassFont.captionMedium, color: .secondaryLabelColor)
        ])
        caption.orientation = .horizontal
        caption.spacing = 5

        let unitLabel = GlassLabel.make(unit, font: GlassFont.caption, color: .secondaryLabelColor)
        let valueRow = NSStackView(views: [valueLabel, unitLabel])
        valueRow.orientation = .horizontal
        valueRow.alignment = .firstBaseline
        valueRow.spacing = 4

        let text = NSStackView(views: [caption, valueRow, footnoteLabel])
        text.translatesAutoresizingMaskIntoConstraints = false
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        footnoteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        sparkline.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sparkline)
        contentView.addSubview(text)
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            text.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            text.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            footnoteLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            sparkline.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sparkline.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            sparkline.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sparkline.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.42)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(value: String?, footnote: String) {
        GlassMotion.crossfade(valueLabel, to: value ?? "—", duration: 0.3)
        valueLabel.textColor = value == nil ? .tertiaryLabelColor : .labelColor
        GlassMotion.crossfade(footnoteLabel, to: footnote)
    }

    func setHistory(_ values: [Double], animated: Bool) {
        sparkline.capacity = 60
        sparkline.set(series: [.init(color: color, values: Array(values.suffix(60)))], animated: animated)
    }
}

@MainActor
private final class LegendItem: NSStackView {
    init(name: String, color: NSColor) {
        super.init(frame: .zero)
        let dot = AppearanceDot(color: color)
        addArrangedSubview(dot)
        addArrangedSubview(GlassLabel.make(name, font: GlassFont.caption, color: .secondaryLabelColor))
        orientation = .horizontal
        alignment = .centerY
        spacing = 5
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class AppearanceDot: AppearanceLayerView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        layer?.cornerRadius = 3.5
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 7),
            heightAnchor.constraint(equalToConstant: 7)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func applyLayerColors() {
        layer?.backgroundColor = color.cgColor
    }
}

/// Small label/value pair with an icon that turns orange when the value is a concern.
@MainActor
private final class FactView: NSView {
    private let icon: NSImageView
    private let valueLabel = GlassLabel.make("—", font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold))
    private var isWarning = false

    init(title: String, symbol: String) {
        icon = GlassSymbol.view(symbol, size: 11, weight: .medium, tint: .tertiaryLabelColor)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let caption = NSStackView(views: [icon, GlassLabel.make(title, font: GlassFont.caption, color: .secondaryLabelColor)])
        caption.orientation = .horizontal
        caption.spacing = 5
        let stack = NSStackView(views: [caption, valueLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        addSubview(stack)
        pin(stack, to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(_ value: String?, warning: Bool) {
        GlassMotion.crossfade(valueLabel, to: value ?? "—")
        valueLabel.textColor = value == nil ? .tertiaryLabelColor : (warning ? .systemOrange : .labelColor)
        if warning != isWarning {
            isWarning = warning
            icon.contentTintColor = warning ? .systemOrange : .tertiaryLabelColor
            if warning, !GlassMotion.reduceMotion {
                icon.addSymbolEffect(.wiggle, options: .nonRepeating)
            }
        }
    }
}

@MainActor
private final class MixLegend: NSStackView {
    static let names = ["Flow", "Blend", "Passthrough", "Repeated"]
    static let colors: [NSColor] = [.systemGreen, .systemOrange, .systemBlue, .systemGray]
    private var labels: [NSTextField] = []

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 14
        for (name, color) in zip(Self.names, Self.colors) {
            let label = GlassLabel.make("\(name) 0", font: GlassFont.caption, color: .secondaryLabelColor)
            labels.append(label)
            let item = NSStackView(views: [AppearanceDot(color: color), label])
            item.orientation = .horizontal
            item.alignment = .centerY
            item.spacing = 5
            addArrangedSubview(item)
        }
        addArrangedSubview(NSView())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(_ counts: [Int]) {
        for (index, label) in labels.enumerated() where counts.indices.contains(index) {
            GlassMotion.crossfade(label, to: "\(Self.names[index]) \(counts[index])")
        }
    }
}

// MARK: - Charts

/// Line chart that scrolls left by one sample when a value is appended.
@MainActor
final class LineChartView: AppearanceLayerView {
    struct Series {
        var color: NSColor
        var values: [Double]
        var isDashed = false
    }

    var capacity = 90
    var minimumMaximum: Double = 1
    var isCompact = false
    var valueFormatter: (Double) -> String = { String(format: "%.0f", $0) }

    private var series: [Series] = []
    private let plotLayer = CALayer()
    private let gridLayer = CAShapeLayer()
    private var lineLayers: [CAShapeLayer] = []
    private var fillLayers: [CAGradientLayer] = []
    private let topLabel = GlassLabel.make("", font: .monospacedDigitSystemFont(ofSize: 10, weight: .regular), color: .tertiaryLabelColor)
    private let midLabel = GlassLabel.make("", font: .monospacedDigitSystemFont(ofSize: 10, weight: .regular), color: .tertiaryLabelColor)
    private let emptyLabel = GlassLabel.make("Waiting for data", font: GlassFont.caption, color: .tertiaryLabelColor)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = true
        layer?.addSublayer(gridLayer)
        layer?.addSublayer(plotLayer)
        gridLayer.lineWidth = 1
        gridLayer.lineDashPattern = [2, 4]
        gridLayer.fillColor = nil
        for label in [topLabel, midLabel, emptyLabel] {
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            topLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            topLabel.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            midLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            midLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(series newSeries: [Series], animated: Bool) {
        let grew = zip(series, newSeries).contains { $0.values.count >= capacity && $1.values.count >= capacity }
            || zip(series, newSeries).contains { $1.values.count > $0.values.count }
        series = newSeries
        rebuildLayersIfNeeded()
        redraw()
        if animated, grew, !GlassMotion.reduceMotion {
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = step
            slide.toValue = 0
            slide.duration = 0.6
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            plotLayer.add(slide, forKey: "scroll")
        }
    }

    private var step: CGFloat {
        bounds.width / CGFloat(max(capacity - 1, 1))
    }

    private func rebuildLayersIfNeeded() {
        guard lineLayers.count != series.count else { return }
        lineLayers.forEach { $0.removeFromSuperlayer() }
        fillLayers.forEach { $0.removeFromSuperlayer() }
        lineLayers = series.map { _ in
            let line = CAShapeLayer()
            line.fillColor = nil
            line.lineWidth = isCompact ? 1.5 : 1.75
            line.lineJoin = .round
            line.lineCap = .round
            return line
        }
        fillLayers = series.map { _ in
            let gradient = CAGradientLayer()
            gradient.mask = CAShapeLayer()
            return gradient
        }
        for (fill, line) in zip(fillLayers, lineLayers) {
            plotLayer.addSublayer(fill)
            plotLayer.addSublayer(line)
        }
        applyLayerColors()
    }

    override func layout() {
        super.layout()
        redraw()
    }

    private func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plotLayer.frame = bounds
        gridLayer.frame = bounds

        let peak = series.flatMap(\.values).max() ?? 0
        let maximum = Self.niceCeiling(max(peak * 1.1, minimumMaximum))
        let top: CGFloat = isCompact ? 6 : 16
        let plot = CGRect(x: 0, y: 1, width: bounds.width, height: max(bounds.height - top - 1, 1))

        for (index, item) in series.enumerated() where index < lineLayers.count {
            let path = linePath(item.values, maximum: maximum, in: plot)
            lineLayers[index].path = path
            lineLayers[index].lineDashPattern = item.isDashed ? [5, 4] : nil
            fillLayers[index].isHidden = item.isDashed
            let fillPath = CGMutablePath()
            if let first = item.values.indices.first, !item.values.isEmpty {
                fillPath.addPath(path)
                fillPath.addLine(to: CGPoint(x: x(for: item.values.count - 1, count: item.values.count, in: plot), y: plot.minY))
                fillPath.addLine(to: CGPoint(x: x(for: first, count: item.values.count, in: plot), y: plot.minY))
                fillPath.closeSubpath()
            }
            fillLayers[index].frame = bounds
            (fillLayers[index].mask as? CAShapeLayer)?.frame = bounds
            (fillLayers[index].mask as? CAShapeLayer)?.path = fillPath
        }

        let grid = CGMutablePath()
        if !isCompact {
            for fraction in [0.0, 0.5, 1.0] {
                let y = plot.minY + plot.height * fraction
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: bounds.width, y: y))
            }
        }
        gridLayer.path = grid
        CATransaction.commit()

        let hasData = series.contains { $0.values.count > 1 }
        topLabel.isHidden = isCompact || !hasData
        midLabel.isHidden = isCompact || !hasData
        emptyLabel.isHidden = isCompact || hasData
        topLabel.stringValue = valueFormatter(maximum)
        midLabel.stringValue = valueFormatter(maximum / 2)
    }

    private func x(for index: Int, count: Int, in plot: CGRect) -> CGFloat {
        plot.maxX - CGFloat(count - 1 - index) * step
    }

    private func linePath(_ values: [Double], maximum: Double, in plot: CGRect) -> CGPath {
        let path = CGMutablePath()
        guard values.count > 1 else { return path }
        let points = values.enumerated().map { index, value in
            CGPoint(
                x: x(for: index, count: values.count, in: plot),
                y: plot.minY + plot.height * CGFloat(min(max(value / maximum, 0), 1))
            )
        }
        path.move(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midX = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: midX, y: previous.y),
                control2: CGPoint(x: midX, y: current.y)
            )
        }
        return path
    }

    private static func niceCeiling(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(value)))
        for multiple in [1.0, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10] where multiple * magnitude >= value {
            return multiple * magnitude
        }
        return 10 * magnitude
    }

    override func applyLayerColors() {
        gridLayer.strokeColor = GlassColor.separator.cgColor
        for (index, item) in series.enumerated() where index < lineLayers.count {
            lineLayers[index].strokeColor = item.color.cgColor
            fillLayers[index].colors = [
                item.color.withAlphaComponent(isCompact ? 0.22 : 0.18).cgColor,
                item.color.withAlphaComponent(0).cgColor
            ]
            fillLayers[index].startPoint = CGPoint(x: 0.5, y: 1)
            fillLayers[index].endPoint = CGPoint(x: 0.5, y: 0)
        }
    }
}

/// One stacked bar per second showing how output frames were produced.
@MainActor
private final class StackedBarChartView: AppearanceLayerView {
    var capacity = 60
    private var samples: [[Int]] = []
    private let plotLayer = CALayer()
    private var segmentLayers: [CAShapeLayer] = []
    private let emptyLabel = GlassLabel.make("No frames yet", font: GlassFont.caption, color: .tertiaryLabelColor)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = true
        layer?.addSublayer(plotLayer)
        segmentLayers = MixLegend.colors.map { _ in CAShapeLayer() }
        segmentLayers.forEach(plotLayer.addSublayer)
        addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(samples newSamples: [[Int]], animated: Bool) {
        let grew = newSamples.count > samples.count || (newSamples.count >= capacity && animated)
        samples = newSamples
        redraw()
        if animated, grew, !GlassMotion.reduceMotion {
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = slot
            slide.toValue = 0
            slide.duration = 0.6
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            plotLayer.add(slide, forKey: "scroll")
        }
    }

    private var slot: CGFloat {
        bounds.width / CGFloat(max(capacity, 1))
    }

    override func layout() {
        super.layout()
        redraw()
    }

    private func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plotLayer.frame = bounds
        let paths = segmentLayers.map { _ in CGMutablePath() }
        let barWidth = max(slot - 2, 1)
        for (offset, counts) in samples.enumerated() {
            let total = CGFloat(counts.reduce(0, +))
            guard total > 0 else { continue }
            let x = bounds.width - CGFloat(samples.count - offset) * slot + 1
            var y: CGFloat = 0
            for (index, count) in counts.enumerated() where index < paths.count && count > 0 {
                let height = bounds.height * CGFloat(count) / total
                paths[index].addRect(CGRect(x: x, y: y, width: barWidth, height: height))
                y += height
            }
        }
        for (layer, path) in zip(segmentLayers, paths) {
            layer.frame = bounds
            layer.path = path
        }
        CATransaction.commit()
        emptyLabel.isHidden = samples.contains { $0.reduce(0, +) > 0 }
    }

    override func applyLayerColors() {
        for (layer, color) in zip(segmentLayers, MixLegend.colors) {
            layer.fillColor = color.withAlphaComponent(0.85).cgColor
        }
    }
}

// MARK: - Meters

@MainActor
private final class MeterRow: NSView {
    private let bar = MeterBar()
    private let valueLabel = GlassLabel.make("—", font: GlassFont.value, color: .secondaryLabelColor)

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let icon = GlassSymbol.view(symbol, size: 12, tint: .tertiaryLabelColor)
        icon.imageScaling = .scaleProportionallyDown
        let label = GlassLabel.make(title, font: GlassFont.caption, color: .secondaryLabelColor)
        valueLabel.alignment = .right

        let stack = NSStackView(views: [icon, label, bar, valueLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        addSubview(stack)
        pin(stack, to: self)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            label.widthAnchor.constraint(equalToConstant: 76),
            valueLabel.widthAnchor.constraint(equalToConstant: 58),
            heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(value: String?, fraction: Double) {
        GlassMotion.crossfade(valueLabel, to: value ?? "—")
        bar.set(fraction: value == nil ? 0 : fraction)
    }
}

/// Rounded track with an animated fill that shifts green → orange → red.
@MainActor
private final class MeterBar: AppearanceLayerView {
    private let fill = CALayer()
    private var fraction: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerRadius = 3
        layer?.masksToBounds = true
        fill.cornerRadius = 3
        layer?.addSublayer(fill)
        heightAnchor.constraint(equalToConstant: 6).isActive = true
        setContentHuggingPriority(.init(1), for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(fraction: Double) {
        self.fraction = min(max(fraction, 0), 1)
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setAnimationDuration(GlassMotion.reduceMotion ? 0 : 0.55)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        CATransaction.commit()
    }

    override func applyLayerColors() {
        layer?.backgroundColor = GlassColor.separator.cgColor
        let color: NSColor = fraction < 0.6 ? .systemGreen : (fraction < 0.85 ? .systemOrange : .systemRed)
        fill.backgroundColor = color.cgColor
    }
}

/// Short pipeline verdict: Working / Partial / Not working / Idle.
@MainActor
private final class VerdictBadge: AppearanceLayerView {
    enum Kind {
        case idle
        case working
        case partial
        case failing

        init(verdictPrefix prefix: String) {
            if prefix.hasPrefix("WORKING, BUT") || prefix.hasPrefix("PARTIAL") || prefix.hasPrefix("WAITING") || prefix.hasPrefix("DEGRADED") {
                self = .partial
            } else if prefix.hasPrefix("WORKING") {
                self = .working
            } else if prefix.hasPrefix("NOT WORKING") {
                self = .failing
            } else {
                self = .idle
            }
        }

        var title: String {
            switch self {
            case .idle: return "Idle"
            case .working: return "Working"
            case .partial: return "Partial"
            case .failing: return "Not working"
            }
        }

        var color: NSColor {
            switch self {
            case .idle: return .secondaryLabelColor
            case .working: return .systemGreen
            case .partial: return .systemOrange
            case .failing: return .systemRed
            }
        }
    }

    private let label = GlassLabel.make("Idle", font: GlassFont.captionMedium)
    private var kind: Kind = .idle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 20),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        set(.idle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(_ kind: Kind) {
        let changed = kind != self.kind
        self.kind = kind
        label.textColor = kind.color
        GlassMotion.crossfade(label, to: kind.title)
        needsDisplay = true
        if changed {
            GlassMotion.pop(self)
        }
    }

    override func applyLayerColors() {
        GlassMotion.animate(layer, backgroundColor: kind.color.withAlphaComponent(0.14).cgColor)
    }
}

// MARK: - Event log

@MainActor
private final class LogFeedView: NSView {
    let filterControl = GlassSegmented.make(["Events", "All", "Issues"])
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private var observer: NSObjectProtocol?
    private var pendingReload = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        filterControl.selectedSegment = 0
        filterControl.target = self
        filterControl.action = #selector(handleFilterChanged)
        filterControl.heightAnchor.constraint(equalToConstant: 26).isActive = true
        filterControl.widthAnchor.constraint(equalToConstant: 216).isActive = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        addSubview(scrollView)
        pin(scrollView, to: self)

        reload()
        observer = NotificationCenter.default.addObserver(forName: .pipelineLogLine, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Coalesces bursts of log lines into one redraw.
    private func scheduleReload() {
        guard !pendingReload else { return }
        pendingReload = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.pendingReload = false
            self.reload()
        }
    }

    private func reload() {
        let filter = filterControl.selectedSegment
        let lines = PipelineLog.shared.recentLines()
            .filter { line in
                switch filter {
                case 0: return line.category != "summary"
                case 2: return Self.isIssue(line)
                default: return true
                }
            }
            .suffix(300)

        let clip = scrollView.contentView
        let atBottom = clip.bounds.maxY >= textView.frame.height - 24

        let text = NSMutableAttributedString()
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let tagFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 4
        paragraph.lineBreakMode = .byWordWrapping

        if lines.isEmpty {
            text.append(NSAttributedString(
                string: filter == 2 ? "No issues so far." : "No events yet.",
                attributes: [.font: bodyFont, .foregroundColor: NSColor.tertiaryLabelColor]
            ))
        }
        for line in lines {
            text.append(NSAttributedString(
                string: Self.timeFormatter.string(from: line.date) + "  ",
                attributes: [.font: timeFont, .foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: paragraph]
            ))
            text.append(NSAttributedString(
                string: line.category.uppercased().padding(toLength: 9, withPad: " ", startingAt: 0),
                attributes: [.font: tagFont, .foregroundColor: Self.color(for: line), .paragraphStyle: paragraph]
            ))
            text.append(NSAttributedString(
                string: line.message + "\n",
                attributes: [.font: bodyFont, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
            ))
        }
        textView.textStorage?.setAttributedString(text)
        if atBottom || lines.count < 12 {
            textView.scrollToEndOfDocument(nil)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func isIssue(_ line: PipelineLogLine) -> Bool {
        let message = line.message.lowercased()
        if message.contains("fail") || message.contains("error") || message.contains("denied") || message.contains("stall") {
            return true
        }
        if line.category == "summary" {
            return message.contains("not working") || message.contains("partial") || message.contains("degraded") || message.contains("slow")
        }
        return false
    }

    private static func color(for line: PipelineLogLine) -> NSColor {
        let message = line.message.lowercased()
        if message.contains("fail") || message.contains("error") || message.contains("denied") || message.contains("not working") {
            return .systemRed
        }
        switch line.category {
        case "summary": return .systemTeal
        case "capture": return .systemBlue
        case "session": return .systemPurple
        case "vision", "flow", "generate": return .systemOrange
        case "ui": return .systemPink
        default: return .secondaryLabelColor
        }
    }

    @objc private func handleFilterChanged() {
        reload()
        textView.scrollToEndOfDocument(nil)
    }
}
