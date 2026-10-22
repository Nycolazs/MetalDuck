import AppKit
import MetalKit

@MainActor
final class OutputViewController: NSViewController {
    let mtkView: MTKView

    private let telemetryContainer = NSVisualEffectView()
    private let sourceFPSLabel = OutputViewController.valueLabel()
    private let generatedFPSLabel = OutputViewController.valueLabel()
    private let captureFPSLabel = OutputViewController.valueLabel()
    private let outputFPSLabel = OutputViewController.valueLabel()
    private let resolutionLabel = OutputViewController.valueLabel()
    private let frameGenerationBadge = GlassLabel.make("FG OFF", font: GlassFont.sidebarHeader, color: .secondaryLabelColor)
    private let detailLabel = GlassLabel.make("Processing inactive", font: GlassFont.caption, color: .secondaryLabelColor)

    init(device: MTLDevice) {
        let view = MTKView(frame: .zero, device: device)
        view.translatesAutoresizingMaskIntoConstraints = false
        self.mtkView = view
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 820))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.black.cgColor

        telemetryContainer.translatesAutoresizingMaskIntoConstraints = false
        telemetryContainer.material = .hudWindow
        telemetryContainer.blendingMode = .withinWindow
        telemetryContainer.state = .active
        telemetryContainer.appearance = NSAppearance(named: .darkAqua)
        telemetryContainer.wantsLayer = true
        telemetryContainer.layer?.cornerRadius = 14
        telemetryContainer.layer?.cornerCurve = .continuous
        telemetryContainer.layer?.borderWidth = 1
        telemetryContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        telemetryContainer.layer?.masksToBounds = true

        let title = GlassLabel.make("MetalDuck", font: GlassFont.groupTitle)
        let header = NSStackView(views: [title, NSView(), frameGenerationBadge])
        header.orientation = .horizontal
        header.alignment = .centerY

        let grid = NSGridView(views: [
            [Self.captionLabel("Source"), sourceFPSLabel],
            [Self.captionLabel("Capture"), captureFPSLabel],
            [Self.captionLabel("Generated"), generatedFPSLabel],
            [Self.captionLabel("Output"), outputFPSLabel],
            [Self.captionLabel("Resolution"), resolutionLabel]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 5
        grid.columnSpacing = 18
        grid.column(at: 1).xPlacement = .trailing

        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 2
        detailLabel.preferredMaxLayoutWidth = 260

        let stack = NSStackView(views: [header, grid, SeparatorLine(), detailLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        for view in stack.arrangedSubviews {
            view.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }

        telemetryContainer.addSubview(stack)
        rootView.addSubview(mtkView)
        rootView.addSubview(telemetryContainer)

        NSLayoutConstraint.activate([
            mtkView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            mtkView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            mtkView.topAnchor.constraint(equalTo: rootView.topAnchor),
            mtkView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            telemetryContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 16),
            telemetryContainer.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 16),

            stack.leadingAnchor.constraint(equalTo: telemetryContainer.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: telemetryContainer.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: telemetryContainer.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: telemetryContainer.bottomAnchor, constant: -12),
            stack.widthAnchor.constraint(equalToConstant: 260)
        ])

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        rootView.addGestureRecognizer(doubleClick)

        self.view = rootView
        setProcessingState(isRunning: false)
    }

    func updateStats(_ stats: RendererStats) {
        sourceFPSLabel.stringValue = String(format: "%.1f fps", stats.sourceFPS)
        captureFPSLabel.stringValue = String(format: "%.1f fps", stats.captureFPS)
        generatedFPSLabel.stringValue = String(format: "%.1f fps", stats.generatedFPS)
        outputFPSLabel.stringValue = String(format: "%.1f fps", stats.presentFPS)
        resolutionLabel.stringValue = "\(Int(stats.inputSize.width))×\(Int(stats.inputSize.height)) → \(Int(stats.outputSize.width))×\(Int(stats.outputSize.height))"

        if !stats.frameGenerationEnabled {
            setBadge("FG OFF", color: .secondaryLabelColor)
        } else if stats.generatedFPS > 0.5 {
            setBadge("FG ACTIVE", color: .systemGreen)
        } else {
            setBadge("FG IDLE", color: .systemOrange)
        }

        let scale = String(format: "Scale %.2f×", stats.effectiveScale)
        if stats.isRunning, stats.captureFPS > 20.0, stats.sourceFPS < (stats.captureFPS * 0.7) {
            detailLabel.stringValue = "\(scale) · Source app is throttling. Keep it visible or use Display mode."
        } else if stats.outputSize.width < stats.inputSize.width || stats.outputSize.height < stats.inputSize.height {
            detailLabel.stringValue = "\(scale) · Output window is smaller than the source, so nothing is upscaled."
        } else if stats.isRunning, stats.sourceFPS < 12.0, stats.captureFPS < 12.0 {
            detailLabel.stringValue = "\(scale) · Source is paused or hidden."
        } else if stats.frameGenerationEnabled, stats.generatedFPS < 0.5, stats.presentFPS <= (stats.sourceFPS + 1.0) {
            detailLabel.stringValue = "\(scale) · Raise the target FPS or keep the source visible."
        } else {
            detailLabel.stringValue = "\(scale) · Processing active"
        }
    }

    func setProcessingState(isRunning: Bool) {
        guard !isRunning else { return }
        for label in [sourceFPSLabel, captureFPSLabel, generatedFPSLabel, outputFPSLabel, resolutionLabel] {
            label.stringValue = "—"
        }
        setBadge("FG OFF", color: .secondaryLabelColor)
        detailLabel.stringValue = "Processing inactive"
    }

    func setTelemetryVisible(_ visible: Bool, animated: Bool) {
        _ = view
        telemetryContainer.isHidden = false
        let target: CGFloat = visible ? 1 : 0
        guard animated, !GlassMotion.reduceMotion else {
            telemetryContainer.alphaValue = target
            telemetryContainer.isHidden = !visible
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            telemetryContainer.animator().alphaValue = target
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.telemetryContainer.isHidden = self.telemetryContainer.alphaValue < 0.01
            }
        })
    }

    func setWaitingForFrames(message: String) {
        detailLabel.stringValue = message
    }

    func setCaptureError(_ message: String) {
        detailLabel.stringValue = message
    }

    func updateWindowTitle(_ title: String) {
        view.window?.title = title
    }

    func updateColorSpace(_ colorSpace: CGColorSpace?) {
        mtkView.colorspace = colorSpace
    }

    private func setBadge(_ text: String, color: NSColor) {
        frameGenerationBadge.stringValue = text
        frameGenerationBadge.textColor = color
    }

    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        view.window?.toggleFullScreen(nil)
    }

    private static func captionLabel(_ text: String) -> NSTextField {
        GlassLabel.make(text, font: GlassFont.caption, color: .secondaryLabelColor)
    }

    private static func valueLabel() -> NSTextField {
        let label = GlassLabel.make("—", font: GlassFont.value)
        label.alignment = .right
        return label
    }
}
