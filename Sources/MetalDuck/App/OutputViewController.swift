import AppKit
import MetalKit

@MainActor
final class OutputViewController: NSViewController {
    let mtkView: MTKView

    private let telemetryContainer = NSVisualEffectView()
    private let statusLabel = NSTextField(labelWithString: "● STOPPED")
    private let sourceFPSLabel = NSTextField(labelWithString: "SOURCE FPS: 0.0")
    private let generatedFPSLabel = NSTextField(labelWithString: "GEN FPS: 0.0")
    private let captureFPSLabel = NSTextField(labelWithString: "CAP FPS: 0.0")
    private let outputFPSLabel = NSTextField(labelWithString: "OUT FPS: 0.0")
    private let resolutionLabel = NSTextField(labelWithString: "INPUT 0x0 -> OUTPUT 0x0")
    private let detailLabel = NSTextField(labelWithString: "Processing inactive")

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
        telemetryContainer.wantsLayer = true
        telemetryContainer.layer?.cornerRadius = 10
        telemetryContainer.layer?.masksToBounds = true

        let stack = NSStackView(views: [statusLabel, sourceFPSLabel, generatedFPSLabel, captureFPSLabel, outputFPSLabel, resolutionLabel, detailLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        sourceFPSLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        generatedFPSLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        captureFPSLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        outputFPSLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        resolutionLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        detailLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)

        sourceFPSLabel.textColor = NSColor(calibratedRed: 0.89, green: 0.95, blue: 1.0, alpha: 1.0)
        generatedFPSLabel.textColor = NSColor(calibratedRed: 0.82, green: 0.97, blue: 0.84, alpha: 1.0)
        captureFPSLabel.textColor = NSColor(calibratedRed: 0.85, green: 0.90, blue: 0.95, alpha: 1.0)
        outputFPSLabel.textColor = NSColor(calibratedRed: 0.85, green: 0.90, blue: 0.95, alpha: 1.0)
        resolutionLabel.textColor = NSColor(calibratedRed: 0.76, green: 0.80, blue: 0.85, alpha: 1.0)
        detailLabel.textColor = NSColor(calibratedRed: 0.80, green: 0.84, blue: 0.88, alpha: 1.0)

        telemetryContainer.addSubview(stack)
        rootView.addSubview(mtkView)
        rootView.addSubview(telemetryContainer)

        NSLayoutConstraint.activate([
            mtkView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            mtkView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            mtkView.topAnchor.constraint(equalTo: rootView.topAnchor),
            mtkView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            telemetryContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 14),
            telemetryContainer.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 14),

            stack.leadingAnchor.constraint(equalTo: telemetryContainer.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: telemetryContainer.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: telemetryContainer.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: telemetryContainer.bottomAnchor, constant: -10),
            stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 250)
        ])

        self.view = rootView
        setProcessingState(isRunning: false)
    }

    func updateStats(_ stats: RendererStats) {
        sourceFPSLabel.stringValue = String(format: "SOURCE FPS: %.1f", stats.sourceFPS)
        generatedFPSLabel.stringValue = String(format: "GEN FPS: %.1f", stats.generatedFPS)
        captureFPSLabel.stringValue = String(format: "CAP FPS: %.1f", stats.captureFPS)
        outputFPSLabel.stringValue = String(format: "OUT FPS: %.1f", stats.presentFPS)
        resolutionLabel.stringValue = "INPUT \(Int(stats.inputSize.width))x\(Int(stats.inputSize.height)) -> OUTPUT \(Int(stats.outputSize.width))x\(Int(stats.outputSize.height))"
        let fgState: String
        if !stats.frameGenerationEnabled {
            fgState = "FG OFF"
        } else if stats.generatedFPS > 0.5 {
            fgState = "FG ACTIVE"
        } else {
            fgState = "FG IDLE"
        }
        if stats.isRunning, stats.captureFPS > 20.0, stats.sourceFPS < (stats.captureFPS * 0.7) {
            detailLabel.stringValue = String(
                format: "Scale %.2fx  |  %@  |  Source app is throttling (keep source visible / use Display mode)",
                stats.effectiveScale,
                fgState
            )
        } else if stats.outputSize.width < stats.inputSize.width || stats.outputSize.height < stats.inputSize.height {
            detailLabel.stringValue = String(
                format: "Scale %.2fx  |  %@  |  Output window is smaller than source (no true upscale)",
                stats.effectiveScale,
                fgState
            )
        } else if stats.isRunning, stats.sourceFPS < 12.0, stats.captureFPS < 12.0 {
            detailLabel.stringValue = String(
                format: "Scale %.2fx  |  %@  |  Source throttled/paused (window hidden or app in background)",
                stats.effectiveScale,
                fgState
            )
        } else if stats.frameGenerationEnabled, stats.generatedFPS < 0.5, stats.presentFPS <= (stats.sourceFPS + 1.0) {
            detailLabel.stringValue = String(
                format: "Scale %.2fx  |  %@  |  Increase Target FPS / keep source visible",
                stats.effectiveScale,
                fgState
            )
        } else {
            detailLabel.stringValue = String(format: "Scale %.2fx  |  %@  |  Processing active", stats.effectiveScale, fgState)
        }

        if stats.isRunning && stats.sourceFPS > 0.5 {
            statusLabel.stringValue = "● ACTIVE"
            statusLabel.textColor = NSColor.systemGreen
        } else if stats.isRunning {
            statusLabel.stringValue = "● WAITING"
            statusLabel.textColor = NSColor.systemOrange
        } else {
            statusLabel.stringValue = "● STOPPED"
            statusLabel.textColor = NSColor.systemRed
        }
    }

    func setProcessingState(isRunning: Bool) {
        if isRunning {
            statusLabel.stringValue = "● WAITING"
            statusLabel.textColor = NSColor.systemOrange
            detailLabel.stringValue = "Waiting for frames..."
        } else {
            statusLabel.stringValue = "● STOPPED"
            statusLabel.textColor = NSColor.systemRed
            sourceFPSLabel.stringValue = "SOURCE FPS: 0.0"
            generatedFPSLabel.stringValue = "GEN FPS: 0.0"
            captureFPSLabel.stringValue = "CAP FPS: 0.0"
            outputFPSLabel.stringValue = "OUT FPS: 0.0"
            resolutionLabel.stringValue = "INPUT 0x0 -> OUTPUT 0x0"
            detailLabel.stringValue = "Processing inactive"
        }
    }

    func setWaitingForFrames(message: String) {
        statusLabel.stringValue = "● WAITING"
        statusLabel.textColor = NSColor.systemOrange
        detailLabel.stringValue = message
    }

    func setCaptureError(_ message: String) {
        statusLabel.stringValue = "● ERROR"
        statusLabel.textColor = NSColor.systemRed
        detailLabel.stringValue = message
    }

    func updateWindowTitle(_ title: String) {
        view.window?.title = title
    }

    func updateColorSpace(_ colorSpace: CGColorSpace?) {
        mtkView.colorspace = colorSpace
    }
}
