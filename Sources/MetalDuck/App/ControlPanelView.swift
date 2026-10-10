import AppKit
import Foundation

private enum UITheme {
    static let bgTop = NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1.0)
    static let bgBottom = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1.0)

    static let chrome = NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.19, alpha: 0.95)
    static let sidebar = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 0.97)
    static let card = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 0.60)
    static let cardBorder = NSColor(calibratedRed: 0.26, green: 0.27, blue: 0.32, alpha: 0.35)

    static let title = NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1.0)
    static let body = NSColor(calibratedRed: 0.78, green: 0.80, blue: 0.84, alpha: 1.0)
    static let muted = NSColor(calibratedRed: 0.50, green: 0.53, blue: 0.58, alpha: 1.0)
    static let accent = NSColor(calibratedRed: 0.30, green: 0.56, blue: 0.93, alpha: 1.0)
}

private final class FlippedPanelContainerView: NSView {
    override var isFlipped: Bool { true }
}

private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

private final class CardView: NSView {
    let contentStack = NSStackView()

    private let titleLabel: NSTextField
    private let headerAccessory: NSView?

    init(title: String, iconName: String? = nil, headerAccessory: NSView? = nil) {
        self.titleLabel = NSTextField(labelWithString: title)
        self.headerAccessory = headerAccessory
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 0
        layer?.backgroundColor = UITheme.card.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.04
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = UITheme.title

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10

        var headerViews: [NSView] = []
        if let iconName {
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            icon.contentTintColor = UITheme.title
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
            icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
            headerViews.append(icon)
        }
        headerViews.append(titleLabel)
        
        if let headerAccessory {
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            headerViews.append(spacer)
            headerViews.append(headerAccessory)
        }

        let header = NSStackView(views: headerViews)
        header.translatesAutoresizingMaskIntoConstraints = false
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6

        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = UITheme.cardBorder.withAlphaComponent(0.5).cgColor
        divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true

        let root = NSStackView(views: [header, divider, contentStack])
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.setHuggingPriority(.required, for: .vertical)

        addSubview(root)

        // Single strategy: pin root to card edges, pin children to root width
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitle(_ title: String) {
        titleLabel.stringValue = title
    }
}

private final class PresetButton: NSView {
    let preset: ControlPreset
    let nameLabel: NSTextField
    let indicator: NSView
    
    var target: AnyObject?
    var action: Selector?
    
    private(set) var isActive: Bool
    
    init(preset: ControlPreset, isActive: Bool) {
        self.preset = preset
        self.isActive = isActive
        let title = "\(preset)".prefix(1).uppercased() + "\(preset)".dropFirst()
        self.nameLabel = NSTextField(labelWithString: title)
        self.indicator = NSView()
        
        super.init(frame: .zero)
        
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 3
        indicator.layer?.backgroundColor = UITheme.accent.cgColor
        indicator.isHidden = !isActive
        
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: isActive ? .semibold : .medium)
        nameLabel.textColor = isActive ? UITheme.title : UITheme.muted
        nameLabel.isEditable = false
        nameLabel.isBordered = false
        nameLabel.drawsBackground = false
        
        let stack = NSStackView(views: [indicator, nameLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        
        addSubview(stack)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            indicator.widthAnchor.constraint(equalToConstant: 6),
            indicator.heightAnchor.constraint(equalToConstant: 6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        updateAppearance()
        
        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func updateAppearance(isHovered: Bool = false) {
        if isActive {
            layer?.backgroundColor = UITheme.accent.withAlphaComponent(0.25).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = UITheme.accent.withAlphaComponent(0.4).cgColor
        } else if isHovered {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        updateAppearance(isHovered: true)
    }
    
    override func mouseExited(with event: NSEvent) {
        updateAppearance(isHovered: false)
    }
    
    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = UITheme.accent.withAlphaComponent(0.4).cgColor
        let _ = target?.perform(action, with: self)
    }
}


private final class SidebarIconButton: NSButton {
    var drawsBackground: Bool = true {
        didSet { updateAppearance() }
    }
    
    var onHover: ((Bool) -> Void)?
    
    private var isHovered: Bool = false {
        didSet { 
            updateAppearance()
            onHover?(isHovered)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        title = ""
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = UITheme.card.cgColor
        contentTintColor = UITheme.body
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
    }

    private func updateAppearance() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            if isHovered {
                layer?.backgroundColor = UITheme.accent.withAlphaComponent(0.3).cgColor
                contentTintColor = UITheme.title
            } else {
                layer?.backgroundColor = drawsBackground ? UITheme.card.cgColor : NSColor.clear.cgColor
                contentTintColor = UITheme.body
            }

        }
    }
}

private final class ProfileButton: NSView {

    let profileId: UUID
    let nameLabel: NSTextField
    let indicator: NSView
    
    var target: AnyObject?
    var action: Selector?
    
    private(set) var isActive: Bool
    
    init(profile: Profile, isActive: Bool) {
        self.profileId = profile.id
        self.isActive = isActive
        self.nameLabel = NSTextField(labelWithString: profile.name)
        self.indicator = NSView()
        
        super.init(frame: .zero)
        
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 3
        indicator.layer?.backgroundColor = UITheme.accent.cgColor
        indicator.isHidden = !isActive
        
        nameLabel.font = NSFont.systemFont(ofSize: 14, weight: isActive ? .semibold : .medium)
        nameLabel.textColor = isActive ? UITheme.title : UITheme.body.withAlphaComponent(0.8)

        nameLabel.isEditable = false
        nameLabel.isBordered = false
        nameLabel.drawsBackground = false
        
        let stack = NSStackView(views: [indicator, nameLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        
        addSubview(stack)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            indicator.widthAnchor.constraint(equalToConstant: 6),
            indicator.heightAnchor.constraint(equalToConstant: 6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        updateAppearance()
        
        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func updateAppearance(isHovered: Bool = false) {
        if isActive {
            layer?.backgroundColor = UITheme.accent.withAlphaComponent(0.25).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = UITheme.accent.withAlphaComponent(0.4).cgColor
        } else if isHovered {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
        }

    }
    
    override func mouseEntered(with event: NSEvent) {
        updateAppearance(isHovered: true)
    }
    
    override func mouseExited(with event: NSEvent) {
        updateAppearance(isHovered: false)
    }
    
    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = UITheme.accent.withAlphaComponent(0.4).cgColor
        let _ = target?.perform(action, with: self)
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

    func controlPanel(_ panel: ControlPanelView, didSelectProfile id: UUID)
    func controlPanelDidRequestAddProfile(_ panel: ControlPanelView)
    func controlPanelDidRequestSettings(_ panel: ControlPanelView)
    func controlPanel(_ panel: ControlPanelView, didRequestRenameProfile id: UUID)
    func controlPanel(_ panel: ControlPanelView, didRequestDuplicateProfile id: UUID)
    func controlPanel(_ panel: ControlPanelView, didRequestDeleteProfile id: UUID)
}

@MainActor
final class ControlPanelView: NSView {
    weak var delegate: ControlPanelViewDelegate?

    private var isApplyingValues = false

    private let appNameLabel = NSTextField(labelWithString: "MetalDuck")
    private let appSubtitleLabel = NSTextField(labelWithString: "Lossless Scaling for Apple Silicon")
    private let profileTitleLabel = NSTextField(labelWithString: "Profile: \"Default\"")

    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "Stopped")
    private let statsLabel = NSTextField(labelWithString: "SOURCE 0.0 FPS | OUT 0.0 FPS")

    private let startButton = NSButton(title: "Scale", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)

    private let captureModeDropdown = CompactDropdown()
    private let captureSourceDropdown = CompactDropdown()
    private let refreshSourcesButton = NSButton(title: "Refresh", target: nil, action: nil)

    private let captureCursorSwitch = NSSwitch()
    private let captureFPSSlider = NSSlider(value: 30, minValue: 15, maxValue: 120, target: nil, action: nil)
    private let captureFPSValueLabel = NSTextField(labelWithString: "30")
    private let queueDepthSlider = NSSlider(value: 5, minValue: 1, maxValue: 8, target: nil, action: nil)
    private let queueDepthValueLabel = NSTextField(labelWithString: "5")

    private let upscalerDropdown = CompactDropdown()
    private let outputScaleSlider = NSSlider(value: 1.5, minValue: 0.75, maxValue: 3.0, target: nil, action: nil)
    private let outputScaleValueLabel = NSTextField(labelWithString: "1.50x")
    private let matchOutputResolutionSwitch = NSSwitch()
    private let samplingDropdown = CompactDropdown()
    private let sharpnessSlider = NSSlider(value: 0.0, minValue: 0.0, maxValue: 1.0, target: nil, action: nil)
    private let sharpnessValueLabel = NSTextField(labelWithString: "0.00")

    private let dynamicResolutionSwitch = NSSwitch()
    private let dynamicMinSlider = NSSlider(value: 0.75, minValue: 0.5, maxValue: 1.0, target: nil, action: nil)
    private let dynamicMinValueLabel = NSTextField(labelWithString: "0.75")
    private let dynamicMaxSlider = NSSlider(value: 1.0, minValue: 0.6, maxValue: 1.25, target: nil, action: nil)
    private let dynamicMaxValueLabel = NSTextField(labelWithString: "1.00")
    private let targetFPSSlider = NSSlider(value: 60, minValue: 30, maxValue: 240, target: nil, action: nil)
    private let targetFPSValueLabel = NSTextField(labelWithString: "60")

    private let frameGenerationSwitch = NSSwitch()
    private let frameGenerationModeDropdown = CompactDropdown()

    private let profileListStack = FlippedStackView()
    private let addProfileButton = SidebarIconButton()
    private let duplicateProfileButton = SidebarIconButton()
    private let renameProfileButton = SidebarIconButton()
    private let deleteProfileButton = SidebarIconButton()

    private var activeProfileId: UUID?

    private let backgroundGradient = CAGradientLayer()
    private let advancedToggleButton = NSButton(title: "", target: nil, action: nil)
    private let advancedContentStack = NSStackView()
    private var isAdvancedVisible = false

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

    func apply(settings: RenderSettings, capture: CaptureConfiguration, profileName: String) {
        isApplyingValues = true

        profileTitleLabel.stringValue = "Profile: \"\(profileName)\""
        upscalerDropdown.selectItem(withTitle: settings.upscalingAlgorithm.rawValue)
        outputScaleSlider.floatValue = settings.outputScale
        outputScaleValueLabel.stringValue = String(format: "%.2fx", settings.outputScale)
        matchOutputResolutionSwitch.state = settings.matchOutputResolution ? .on : .off

        samplingDropdown.selectItem(withTitle: settings.samplingMode.rawValue)

        sharpnessSlider.floatValue = settings.sharpness
        sharpnessValueLabel.stringValue = String(format: "%.2f", settings.sharpness)

        dynamicResolutionSwitch.state = settings.dynamicResolutionEnabled ? .on : .off
        dynamicMinSlider.floatValue = settings.dynamicScaleMinimum
        dynamicMaxSlider.floatValue = settings.dynamicScaleMaximum
        dynamicMinValueLabel.stringValue = String(format: "%.2f", settings.dynamicScaleMinimum)
        dynamicMaxValueLabel.stringValue = String(format: "%.2f", settings.dynamicScaleMaximum)

        targetFPSSlider.integerValue = settings.targetPresentationFPS
        targetFPSValueLabel.stringValue = "\(settings.targetPresentationFPS)"

        frameGenerationSwitch.state = settings.frameGenerationEnabled ? .on : .off
        frameGenerationModeDropdown.selectItem(withTitle: settings.frameGenerationMode.rawValue)

        captureCursorSwitch.state = capture.showsCursor ? .on : .off
        captureFPSSlider.integerValue = capture.framesPerSecond
        captureFPSValueLabel.stringValue = "\(capture.framesPerSecond)"
        queueDepthSlider.integerValue = capture.queueDepth
        queueDepthValueLabel.stringValue = "\(capture.queueDepth)"

        syncDynamicControlsEnabledState()

        isApplyingValues = false
    }

    func setCaptureMode(_ mode: CaptureModeChoice) {
        captureModeDropdown.selectItem(at: mode.rawValue)
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

        if let selectedIndex, selectedIndex >= 0, selectedIndex < titles.count {
            captureSourceDropdown.selectItem(at: selectedIndex)
        }
    }

    func setRunning(_ running: Bool) {
        startButton.isEnabled = !running
        stopButton.isEnabled = running

        startButton.alphaValue = running ? 0.75 : 1.0
        stopButton.alphaValue = running ? 1.0 : 0.75

        if running {
            statusLabel.textColor = UITheme.accent
            statusDot.layer?.backgroundColor = UITheme.accent.cgColor
        } else {
            statusLabel.textColor = UITheme.muted
            statusDot.layer?.backgroundColor = UITheme.muted.cgColor
        }
    }

    func setStatus(_ message: String, isError: Bool = false) {
        statusLabel.stringValue = message
        if isError {
            statusLabel.textColor = NSColor.systemRed
            statusDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        } else if stopButton.isEnabled {
            statusLabel.textColor = UITheme.accent
            statusDot.layer?.backgroundColor = UITheme.accent.cgColor
        } else {
            statusLabel.textColor = UITheme.muted
            statusDot.layer?.backgroundColor = UITheme.muted.cgColor
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
        appNameLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        appNameLabel.textColor = UITheme.title

        appSubtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        appSubtitleLabel.textColor = UITheme.muted.withAlphaComponent(0.7)

        profileTitleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        profileTitleLabel.textColor = UITheme.title

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.layer?.backgroundColor = UITheme.muted.cgColor
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8)
        ])

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .semibold)
        statusLabel.textColor = UITheme.muted

        statsLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        statsLabel.textColor = UITheme.body
        statsLabel.lineBreakMode = .byWordWrapping

        startButton.bezelStyle = .rounded
        startButton.wantsLayer = true
        startButton.isBordered = false
        startButton.layer?.cornerRadius = 8
        startButton.layer?.backgroundColor = UITheme.accent.cgColor
        startButton.contentTintColor = .white
        startButton.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true
        startButton.heightAnchor.constraint(equalToConstant: 30).isActive = true

        stopButton.bezelStyle = .rounded
        stopButton.wantsLayer = true
        stopButton.isBordered = false
        stopButton.layer?.cornerRadius = 8
        stopButton.layer?.backgroundColor = NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.25, alpha: 1.0).cgColor
        stopButton.contentTintColor = UITheme.body
        stopButton.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        stopButton.isEnabled = false
        stopButton.alphaValue = 0.75
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true
        stopButton.heightAnchor.constraint(equalToConstant: 30).isActive = true

        refreshSourcesButton.bezelStyle = .rounded
        refreshSourcesButton.wantsLayer = true
        refreshSourcesButton.isBordered = false
        refreshSourcesButton.layer?.cornerRadius = 6
        refreshSourcesButton.layer?.backgroundColor = UITheme.card.cgColor
        refreshSourcesButton.layer?.borderWidth = 1
        refreshSourcesButton.layer?.borderColor = UITheme.cardBorder.cgColor
        refreshSourcesButton.contentTintColor = UITheme.body
        refreshSourcesButton.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        refreshSourcesButton.translatesAutoresizingMaskIntoConstraints = false
        refreshSourcesButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        refreshSourcesButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true

        // CompactDropdown configuration
        captureModeDropdown.items = CaptureModeChoice.allCases.map(\.title)
        captureModeDropdown.selectItem(at: CaptureModeChoice.automatic.rawValue)
        captureModeDropdown.onSelectionChanged = { [weak self] _, index in
            guard let self, !self.isApplyingValues,
                  let mode = CaptureModeChoice(rawValue: index) else { return }
            self.delegate?.controlPanel(self, didSelectCaptureMode: mode)
        }

        captureSourceDropdown.onSelectionChanged = { [weak self] _, index in
            guard let self, !self.isApplyingValues else { return }
            self.delegate?.controlPanel(self, didSelectCaptureSourceAt: index)
        }

        upscalerDropdown.items = UpscalingAlgorithm.allCases.map(\.rawValue)
        upscalerDropdown.onSelectionChanged = { [weak self] title, _ in
            guard let self, !self.isApplyingValues,
                  let value = UpscalingAlgorithm(rawValue: title) else { return }
            self.delegate?.controlPanel(self, didChangeUpscalingAlgorithm: value)
        }

        samplingDropdown.items = SamplingMode.allCases.map(\.rawValue)
        samplingDropdown.onSelectionChanged = { [weak self] title, _ in
            guard let self, !self.isApplyingValues,
                  let value = SamplingMode(rawValue: title) else { return }
            self.delegate?.controlPanel(self, didChangeSamplingMode: value)
        }

        frameGenerationModeDropdown.items = FrameGenerationMode.allCases.map(\.rawValue)
        frameGenerationModeDropdown.onSelectionChanged = { [weak self] title, _ in
            guard let self, !self.isApplyingValues,
                  let mode = FrameGenerationMode(rawValue: title) else { return }
            self.delegate?.controlPanel(self, didChangeFrameGenerationMode: mode)
        }

        // Switch configuration
        [captureCursorSwitch, matchOutputResolutionSwitch, frameGenerationSwitch, dynamicResolutionSwitch].forEach {
            $0.controlSize = .regular
            $0.state = .off
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

        captureCursorSwitch.target = self
        captureCursorSwitch.action = #selector(handleCursorCaptureChanged)

        captureFPSSlider.target = self
        captureFPSSlider.action = #selector(handleCaptureFPSChanged)

        queueDepthSlider.target = self
        queueDepthSlider.action = #selector(handleQueueDepthChanged)

        outputScaleSlider.target = self
        outputScaleSlider.action = #selector(handleOutputScaleChanged)

        matchOutputResolutionSwitch.target = self
        matchOutputResolutionSwitch.action = #selector(handleMatchOutputResolutionChanged)

        sharpnessSlider.target = self
        sharpnessSlider.action = #selector(handleSharpnessChanged)

        dynamicResolutionSwitch.target = self
        dynamicResolutionSwitch.action = #selector(handleDynamicResolutionChanged)

        dynamicMinSlider.target = self
        dynamicMinSlider.action = #selector(handleDynamicMinChanged)

        dynamicMaxSlider.target = self
        dynamicMaxSlider.action = #selector(handleDynamicMaxChanged)

        targetFPSSlider.target = self
        targetFPSSlider.action = #selector(handleTargetFPSChanged)

        frameGenerationSwitch.action = #selector(handleFrameGenerationEnabledChanged)

        addProfileButton.target = self
        addProfileButton.action = #selector(handleAddProfile)
        
        duplicateProfileButton.target = self
        duplicateProfileButton.action = #selector(handleDuplicateProfile)
        
        renameProfileButton.target = self
        renameProfileButton.action = #selector(handleRenameProfile)
        
        deleteProfileButton.target = self
        deleteProfileButton.action = #selector(handleDeleteProfile)


        advancedToggleButton.bezelStyle = .inline
        advancedToggleButton.isBordered = false
        advancedToggleButton.contentTintColor = UITheme.muted
        
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        advancedToggleButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Show")?.withSymbolConfiguration(config)
        advancedToggleButton.imagePosition = .imageOnly
        
        advancedToggleButton.target = self
        advancedToggleButton.action = #selector(handleAdvancedToggle)
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
        body.spacing = 20

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
        container.layer?.cornerRadius = 12
        container.layer?.borderWidth = 0

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
        container.layer?.cornerRadius = 12
        container.layer?.borderWidth = 0
        container.layer?.backgroundColor = UITheme.sidebar.cgColor

        // 1. Profiles title — pinned to top
        let title = NSTextField(labelWithString: "Profiles")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.textColor = UITheme.title

        // 2. Action buttons — pinned directly under title
        let actionsContainer = NSStackView(views: [
            setupSidebarButton(addProfileButton, symbol: "plus"),
            setupSidebarButton(duplicateProfileButton, symbol: "plus.square.on.square"),
            setupSidebarButton(renameProfileButton, symbol: "pencil"),
            setupSidebarButton(deleteProfileButton, symbol: "trash")
        ])
        actionsContainer.translatesAutoresizingMaskIntoConstraints = false
        actionsContainer.orientation = .horizontal
        actionsContainer.spacing = 8

        // Header block: title + buttons, fixed at top
        let headerStack = NSStackView(views: [title, actionsContainer])
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 14
        headerStack.setContentHuggingPriority(.required, for: .vertical)

        let headerDivider = NSView()
        headerDivider.translatesAutoresizingMaskIntoConstraints = false
        headerDivider.wantsLayer = true
        headerDivider.layer?.backgroundColor = UITheme.cardBorder.withAlphaComponent(0.4).cgColor
        headerDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true


        // 3. Profiles list — inside a scroll view that fills remaining space
        profileListStack.orientation = .vertical
        profileListStack.alignment = .leading
        profileListStack.spacing = 4
        profileListStack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = profileListStack

        // 4. Footer items
        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = UITheme.cardBorder.withAlphaComponent(0.4).cgColor
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let settingsButton = SidebarIconButton()
        settingsButton.drawsBackground = false
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        
        let gearConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let gearIcon = NSImageView()
        gearIcon.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")?.withSymbolConfiguration(gearConfig)
        gearIcon.contentTintColor = UITheme.body
        gearIcon.translatesAutoresizingMaskIntoConstraints = false
        
        let settingsLabel = NSTextField(labelWithString: "Settings")
        settingsLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        settingsLabel.textColor = UITheme.body
        
        let contentStack = NSStackView(views: [gearIcon, settingsLabel])
        contentStack.orientation = .horizontal
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        
        settingsButton.addSubview(contentStack)
        let leadingConstraint = contentStack.leadingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: 12)
        leadingConstraint.isActive = true
        contentStack.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor).isActive = true
        
        settingsButton.onHover = { [weak settingsButton, weak contentStack, weak leadingConstraint] hovered in
            guard let _ = settingsButton, let stack = contentStack, let constraint = leadingConstraint else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                if hovered {
                    // Center it: (ButtonWidth - ContentWidth) / 2
                    // Button is 140 wide, content is ~80 wide.
                    let buttonWidth: CGFloat = 140
                    let contentWidth = stack.fittingSize.width
                    constraint.animator().constant = (buttonWidth - contentWidth) / 2
                    settingsLabel.animator().textColor = UITheme.title
                    gearIcon.animator().contentTintColor = UITheme.title
                } else {
                    constraint.animator().constant = 12
                    settingsLabel.animator().textColor = UITheme.body
                    gearIcon.animator().contentTintColor = UITheme.body
                }
            }
        }
        
        settingsButton.target = self
        settingsButton.action = #selector(handleSettingsTapped)

        let settingsStack = NSStackView(views: [settingsButton])
        settingsStack.translatesAutoresizingMaskIntoConstraints = false
        settingsStack.orientation = .horizontal
        settingsStack.spacing = 0
        settingsStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)




        let footerStack = NSStackView(views: [divider, settingsStack])
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        footerStack.orientation = .vertical
        footerStack.alignment = .leading
        footerStack.spacing = 10
        footerStack.setContentHuggingPriority(.required, for: .vertical)

        container.addSubview(headerStack)
        container.addSubview(headerDivider)
        container.addSubview(scrollView)
        container.addSubview(footerStack)



        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 240),

            // Header: pinned to top
            headerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            headerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            // Header Divider
            headerDivider.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 14),
            headerDivider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            headerDivider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            // ScrollView: fills between header and footer
            scrollView.topAnchor.constraint(equalTo: headerDivider.bottomAnchor, constant: 8),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            scrollView.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -16),

            // Footer: pinned to bottom
            footerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            footerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            footerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),

            divider.widthAnchor.constraint(equalTo: footerStack.widthAnchor),
            settingsStack.widthAnchor.constraint(equalTo: footerStack.widthAnchor),
            settingsButton.heightAnchor.constraint(equalToConstant: 40),
            settingsButton.widthAnchor.constraint(equalToConstant: 140),



            // Profile list fills scroll view width
            profileListStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -8)
        ])

        return container
    }

    private func setupSidebarButton(_ button: SidebarIconButton, symbol: String) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        button.imagePosition = .imageOnly



        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    func setProfiles(_ profiles: [Profile], activeId: UUID) {
        self.activeProfileId = activeId
        profileListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        for profile in profiles {
            let isActive = (profile.id == activeId)
            let btn = ProfileButton(profile: profile, isActive: isActive)
            btn.target = self
            btn.action = #selector(handleProfileSelected(_:))
            profileListStack.addArrangedSubview(btn)
            btn.leadingAnchor.constraint(equalTo: profileListStack.leadingAnchor).isActive = true
            btn.trailingAnchor.constraint(equalTo: profileListStack.trailingAnchor).isActive = true
        }
        
        let activeProfile = profiles.first(where: { $0.id == activeId })
        duplicateProfileButton.isEnabled = true
        renameProfileButton.isEnabled = activeProfile?.isBuiltIn == false
        deleteProfileButton.isEnabled = activeProfile?.isBuiltIn == false
    }

    @objc private func handleProfileSelected(_ sender: ProfileButton) {
        delegate?.controlPanel(self, didSelectProfile: sender.profileId)
    }

    @objc private func handleAddProfile() {
        delegate?.controlPanelDidRequestAddProfile(self)
    }

    @objc private func handleDuplicateProfile() {
        guard let id = activeProfileId else { return }
        delegate?.controlPanel(self, didRequestDuplicateProfile: id)
    }

    @objc private func handleRenameProfile() {
        guard let id = activeProfileId else { return }
        delegate?.controlPanel(self, didRequestRenameProfile: id)
    }

    @objc private func handleDeleteProfile() {
        guard let id = activeProfileId else { return }
        delegate?.controlPanel(self, didRequestDeleteProfile: id)
    }

    @objc private func handleSettingsTapped() {
        delegate?.controlPanelDidRequestSettings(self)
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
        stack.spacing = 14

        stack.addArrangedSubview(profileTitleLabel)

        let sessionCard = makeSessionCard()
        stack.addArrangedSubview(sessionCard)

        let captureCard = makeCaptureCard()
        let scalingCard = makeScalingCard()
        let row1 = makeCardRow(left: captureCard, right: scalingCard)
        stack.addArrangedSubview(row1)

        let frameGenerationCard = makeFrameGenerationCard()
        let renderingCard = makeRenderingCard()
        let row2 = makeCardRow(left: frameGenerationCard, right: renderingCard)
        stack.addArrangedSubview(row2)

        contentView.addSubview(stack)

        // Pin stack to fill scroll content with explicit leading + trailing
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: clipView.topAnchor),
            contentView.bottomAnchor.constraint(greaterThanOrEqualTo: clipView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: clipView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            // Pin each child to fill the stack width
            sessionCard.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            sessionCard.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            row1.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            row1.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            row2.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            row2.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])

        return scrollView
    }

    private func makeSessionCard() -> NSView {
        let card = CardView(title: "Session")

        statusLabel.setContentHuggingPriority(.required, for: .vertical)
        statusLabel.alignment = .left
        statsLabel.alignment = .left

        // Fixed container: dot pinned to leading, label follows
        let statusContainer = NSView()
        statusContainer.translatesAutoresizingMaskIntoConstraints = false
        statusContainer.addSubview(statusDot)
        statusContainer.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusDot.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor),
            statusDot.centerYAnchor.constraint(equalTo: statusContainer.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 8),
            statusLabel.topAnchor.constraint(equalTo: statusContainer.topAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusContainer.trailingAnchor),
            statusContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 28)
        ])

        card.contentStack.addArrangedSubview(statusContainer)
        card.contentStack.addArrangedSubview(statsLabel)

        // Stretch items to fill card width
        statusContainer.leadingAnchor.constraint(equalTo: card.contentStack.leadingAnchor).isActive = true
        statusContainer.trailingAnchor.constraint(equalTo: card.contentStack.trailingAnchor).isActive = true
        statsLabel.leadingAnchor.constraint(equalTo: card.contentStack.leadingAnchor).isActive = true
        statsLabel.trailingAnchor.constraint(equalTo: card.contentStack.trailingAnchor).isActive = true

        card.setContentHuggingPriority(.required, for: .vertical)
        card.heightAnchor.constraint(equalToConstant: 120).isActive = true

        return card
    }

    private func makeFrameGenerationCard() -> NSView {
        let card = CardView(title: "Frame Generation", iconName: "film")

        let enabledRow = makeLabeledControlRow(label: "Enabled", control: frameGenerationSwitch, info: "Generates intermediate frames to raise output FPS; best at 30→60/90.")
        let modeRow = makeLabeledControlRow(label: "Mode", control: frameGenerationModeDropdown, info: "Sets the frame generation multiplier.")

        card.contentStack.addArrangedSubview(enabledRow)
        card.contentStack.addArrangedSubview(modeRow)

        // Pin rows to fill card width
        for row in [enabledRow, modeRow] {
            row.leadingAnchor.constraint(equalTo: card.contentStack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: card.contentStack.trailingAnchor).isActive = true
        }

        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        return card
    }

    private func makeScalingCard() -> NSView {
        let card = CardView(title: "Scaling", iconName: "plus.viewfinder")

        let typeRow = makeLabeledControlRow(label: "Type", control: upscalerDropdown, info: "Choose the upscaler implementation.")
        let factorRow = makeSliderRow(label: "Factor", slider: outputScaleSlider, valueLabel: outputScaleValueLabel)
        let matchRow = makeLabeledControlRow(label: "Match Resolution", control: matchOutputResolutionSwitch, info: "Resize source before scaling to match output.")
        let samplingRow = makeLabeledControlRow(label: "Sampling", control: samplingDropdown, info: "Resampling filter used during scaling.")
        let sharpRow = makeSliderRow(label: "Sharpness", slider: sharpnessSlider, valueLabel: sharpnessValueLabel, info: "Post-sharpening intensity.")

        let rows: [NSView] = [typeRow, factorRow, matchRow, samplingRow, sharpRow]
        for row in rows {
            card.contentStack.addArrangedSubview(row)
            row.leadingAnchor.constraint(equalTo: card.contentStack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: card.contentStack.trailingAnchor).isActive = true
        }

        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        return card
    }

    private func makeCaptureCard() -> NSView {
        let card = CardView(title: "Capture", iconName: "display")

        let modeRow = makeLabeledControlRow(label: "Mode", control: captureModeDropdown, info: "Select automatic, display, or window source.")
        let sourceRow = makeSourcePickerRow()
        let cursorRow = makeLabeledControlRow(label: "Show Cursor", control: captureCursorSwitch)
        let fpsRow = makeSliderRow(label: "Capture FPS", slider: captureFPSSlider, valueLabel: captureFPSValueLabel, info: "Capture cadence from the source.")
        let depthRow = makeSliderRow(label: "Queue Depth", slider: queueDepthSlider, valueLabel: queueDepthValueLabel, info: "Buffered frames to balance latency and stability.")

        let rows: [NSView] = [modeRow, sourceRow, cursorRow, fpsRow, depthRow]
        for row in rows {
            card.contentStack.addArrangedSubview(row)
            row.leadingAnchor.constraint(equalTo: card.contentStack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: card.contentStack.trailingAnchor).isActive = true
        }

        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        return card
    }

    private func makeRenderingCard() -> NSView {
        let card = CardView(title: "Rendering", iconName: "gearshape", headerAccessory: advancedToggleButton)

        advancedContentStack.translatesAutoresizingMaskIntoConstraints = false
        advancedContentStack.orientation = .vertical
        advancedContentStack.alignment = .leading
        advancedContentStack.spacing = 10
        advancedContentStack.isHidden = !isAdvancedVisible

        // Rendering Controls
        let dynRow = makeLabeledControlRow(label: "Dynamic Resolution", control: dynamicResolutionSwitch)
        let minRow = makeSliderRow(label: "Min Scale", slider: dynamicMinSlider, valueLabel: dynamicMinValueLabel)
        let maxRow = makeSliderRow(label: "Max Scale", slider: dynamicMaxSlider, valueLabel: dynamicMaxValueLabel)
        let fpsRow = makeSliderRow(label: "Target FPS", slider: targetFPSSlider, valueLabel: targetFPSValueLabel)

        advancedContentStack.addArrangedSubview(dynRow)
        advancedContentStack.addArrangedSubview(minRow)
        advancedContentStack.addArrangedSubview(maxRow)
        advancedContentStack.addArrangedSubview(fpsRow)
        
        card.contentStack.addArrangedSubview(advancedContentStack)

        // Pin advanced content to fill card width via leading+trailing
        advancedContentStack.leadingAnchor.constraint(equalTo: card.contentStack.leadingAnchor).isActive = true
        advancedContentStack.trailingAnchor.constraint(equalTo: card.contentStack.trailingAnchor).isActive = true
        // Pin each row inside advanced to fill
        for row in [dynRow, minRow, maxRow, fpsRow] {
            row.leadingAnchor.constraint(equalTo: advancedContentStack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: advancedContentStack.trailingAnchor).isActive = true
        }
        
        
        // Match Frame Generation card minimum height so they align on first launch
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        card.setContentHuggingPriority(.defaultHigh, for: .vertical)

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
        row.spacing = 16

        // Keep both cards same height so one doesn't vanish when the other expands
        left.heightAnchor.constraint(equalTo: right.heightAnchor).isActive = true

        return row
    }

    private func makeLabeledControlRow(label: String, control: NSView, info: String? = nil) -> NSView {
        let text = NSTextField(labelWithString: label)
        text.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        text.textColor = UITheme.body
        text.setContentHuggingPriority(.required, for: .horizontal)

        let titleStack = NSStackView(views: [text])
        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 6
        if let info {
            titleStack.addArrangedSubview(makeInfoIcon(title: label, tooltip: info))
        }

        let row = NSStackView(views: [titleStack, control])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func makeSliderRow(label: String, slider: NSSlider, valueLabel: NSTextField, info: String? = nil) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        title.textColor = UITheme.body

        valueLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        valueLabel.textColor = UITheme.title
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let titleStack = NSStackView(views: [title])
        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 6
        if let info {
            titleStack.addArrangedSubview(makeInfoIcon(title: label, tooltip: info))
        }

        let rowHeader = NSStackView(views: [titleStack, valueLabel])
        rowHeader.translatesAutoresizingMaskIntoConstraints = false
        rowHeader.orientation = .horizontal
        rowHeader.alignment = .centerY
        rowHeader.distribution = .fill
        rowHeader.spacing = 8

        slider.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [rowHeader, slider])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .vertical
        row.spacing = 3
        row.alignment = .leading

        // Pin header and slider to fill row width via leading+trailing
        rowHeader.leadingAnchor.constraint(equalTo: row.leadingAnchor).isActive = true
        rowHeader.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
        slider.leadingAnchor.constraint(equalTo: row.leadingAnchor).isActive = true
        slider.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true

        return row
    }

    private func makeSourcePickerRow() -> NSView {
        let row = NSStackView(views: [captureSourceDropdown, refreshSourcesButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        refreshSourcesButton.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    private func makeInfoIcon(title: String, tooltip: String) -> NSView {
        let icon = HoverInfoIcon(tooltip: tooltip)
        return icon
    }

    private func makeSecondaryButton(title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.bezelColor = NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.30, alpha: 1.0)
        button.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        return button
    }

    private func makeSecondaryIconButton(symbolName: String) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .rounded
        button.bezelColor = NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.30, alpha: 1.0)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: symbolName)
        button.imagePosition = .imageOnly
        button.contentTintColor = UITheme.body
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    private func syncDynamicControlsEnabledState() {
        let enabled = dynamicResolutionSwitch.state == .on
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
    private func handleCursorCaptureChanged() {
        guard !isApplyingValues else {
            return
        }
        delegate?.controlPanel(self, didToggleCursor: captureCursorSwitch.state == .on)
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
        delegate?.controlPanel(self, didToggleMatchOutputResolution: matchOutputResolutionSwitch.state == .on)
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
        delegate?.controlPanel(self, didToggleDynamicResolution: dynamicResolutionSwitch.state == .on)
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
        delegate?.controlPanel(self, didToggleFrameGeneration: frameGenerationSwitch.state == .on)
    }

    @objc
    private func handleAdvancedToggle() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            
            isAdvancedVisible.toggle()
            advancedContentStack.isHidden = !isAdvancedVisible
            
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            let symbolName = isAdvancedVisible ? "chevron.down" : "chevron.right"
            advancedToggleButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isAdvancedVisible ? "Hide" : "Show")?.withSymbolConfiguration(config)
            advancedToggleButton.contentTintColor = isAdvancedVisible ? UITheme.accent : UITheme.muted
            
            self.window?.layoutIfNeeded()
            self.layoutSubtreeIfNeeded()
        }
    }
}

private final class HoverInfoIcon: NSView {
    private let tooltipText: String
    private var popover: NSPopover?
    private var hoverTimer: Timer?
    private var trackingArea: NSTrackingArea?

    init(tooltip: String) {
        self.tooltipText = tooltip
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 16).isActive = true
        heightAnchor.constraint(equalToConstant: 16).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UITheme.muted
        ]
        let str = NSAttributedString(string: "ⓘ", attributes: attributes)
        let size = str.size()
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        str.draw(at: point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.showTooltip()
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hideTooltip()
    }

    private func showTooltip() {
        guard popover == nil else { return }

        let pop = NSPopover()
        pop.behavior = .semitransient
        pop.animates = true

        let vc = NSViewController()
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.18, alpha: 1.0).cgColor
        container.layer?.cornerRadius = 7

        let label = NSTextField(labelWithString: tooltipText)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = NSColor(white: 0.92, alpha: 1.0)
        label.cell?.wraps = true
        label.preferredMaxLayoutWidth = 250
        label.lineBreakMode = .byWordWrapping

        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        vc.view = container
        pop.contentViewController = vc
        pop.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        popover = pop
    }

    private func hideTooltip() {
        popover?.performClose(nil)
        popover = nil
    }
}
