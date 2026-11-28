import AppKit

/// Width and height in pixels, typed in, with a menu of common sizes.
///
/// A value is committed on Return, on leaving a field, or on picking from the menu, never
/// on each keystroke: changing the input size reconfigures the capture stream.
@MainActor
final class ResolutionField: NSView {
    static let presets: [PixelSize] = [
        PixelSize(width: 1280, height: 720),
        PixelSize(width: 1600, height: 900),
        PixelSize(width: 1920, height: 1080),
        PixelSize(width: 2560, height: 1440),
        PixelSize(width: 3840, height: 2160)
    ]
    private static let limits = 16...16384

    var onCommit: ((PixelSize) -> Void)?

    var size: PixelSize {
        didSet { showSize() }
    }

    var isEnabled = true {
        didSet {
            widthField.isEnabled = isEnabled
            heightField.isEnabled = isEnabled
            presetButton.isEnabled = isEnabled
            timesLabel.textColor = isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
            presetButton.alphaValue = isEnabled ? 1 : 0.4
        }
    }

    private let widthField = ResolutionField.makeField()
    private let heightField = ResolutionField.makeField()
    private let timesLabel = GlassLabel.make("×", font: GlassFont.body, color: .secondaryLabelColor)
    private let presetButton = GlassActionButton(title: nil, symbol: "chevron.down", style: .neutral, symbolSize: 10, height: 24)

    init(size: PixelSize, accessibilityName: String) {
        self.size = size
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        for field in [widthField, heightField] {
            field.target = self
            field.action = #selector(commitFields)
        }
        widthField.setAccessibilityLabel("\(accessibilityName) width in pixels")
        heightField.setAccessibilityLabel("\(accessibilityName) height in pixels")
        presetButton.setAccessibilityLabel("\(accessibilityName) presets")
        presetButton.toolTip = "Common sizes"
        presetButton.target = self
        presetButton.action = #selector(showPresets)
        presetButton.widthAnchor.constraint(equalToConstant: 26).isActive = true

        let stack = NSStackView(views: [widthField, timesLabel, heightField, presetButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        showSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makeField() -> NSTextField {
        let field = NSTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = GlassFont.value
        field.alignment = .right
        field.bezelStyle = .roundedBezel
        field.controlSize = .small
        field.usesSingleLineMode = true
        field.cell?.sendsActionOnEndEditing = true
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: limits.lowerBound)
        formatter.maximum = NSNumber(value: limits.upperBound)
        field.formatter = formatter
        field.widthAnchor.constraint(equalToConstant: 58).isActive = true
        return field
    }

    private func showSize() {
        widthField.integerValue = size.width
        heightField.integerValue = size.height
    }

    @objc private func commitFields() {
        let typed = PixelSize(
            width: min(max(widthField.integerValue, Self.limits.lowerBound), Self.limits.upperBound),
            height: min(max(heightField.integerValue, Self.limits.lowerBound), Self.limits.upperBound)
        )
        commit(typed)
    }

    private func commit(_ newSize: PixelSize) {
        guard newSize != size else {
            showSize()
            return
        }
        size = newSize
        onCommit?(newSize)
    }

    @objc private func showPresets() {
        let menu = NSMenu()
        for preset in Self.presets {
            menu.addItem(item(title: "\(preset.width) × \(preset.height)", size: preset))
        }
        if let screen = window?.screen ?? NSScreen.main {
            let pixels = screen.convertRectToBacking(screen.frame).size
            let native = PixelSize(width: Int(pixels.width.rounded()), height: Int(pixels.height.rounded()))
            menu.addItem(.separator())
            menu.addItem(item(title: "This display (\(native.width) × \(native.height))", size: native))
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: presetButton.bounds.height + 4), in: presetButton)
    }

    private func item(title: String, size: PixelSize) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(pickPreset(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = [size.width, size.height]
        item.state = size == self.size ? .on : .off
        return item
    }

    @objc private func pickPreset(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [Int], values.count == 2 else { return }
        commit(PixelSize(width: values[0], height: values[1]))
    }
}
