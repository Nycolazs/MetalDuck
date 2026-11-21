import AppKit
import CoreImage

@MainActor
enum SubtitleRegionPicker {
    static func select(in frame: SubtitleImage, initialRegion: CGRect?, on screen: NSScreen?) -> CGRect? {
        let source = CIImage(cvPixelBuffer: frame.pixelBuffer)
        guard let image = CIContext().createCGImage(source, from: source.extent) else { return nil }
        let available = screen?.visibleFrame.size ?? CGSize(width: 1000, height: 700)
        let scale = min(950 / source.extent.width, available.width * 0.85 / source.extent.width,
                        available.height * 0.72 / source.extent.height)
        let size = CGSize(width: source.extent.width * scale, height: source.extent.height * scale)
        let preview = RegionPreview(image: image, size: size, region: initialRegion)
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.title = "OCR alanını sürükleyerek seç · Esc ile iptal"
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.contentView = preview
        panel.delegate = preview
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(preview)
        let response = NSApplication.shared.runModal(for: panel)
        panel.orderOut(nil)
        return response == .OK ? preview.region : nil
    }
}

@MainActor
private final class RegionPreview: NSView, NSWindowDelegate {
    let image: NSImage
    var region: CGRect?
    private var origin: CGPoint?

    init(image: CGImage, size: CGSize, region: CGRect?) {
        self.image = NSImage(cgImage: image, size: size)
        self.region = region
        super.init(frame: CGRect(origin: .zero, size: size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
        guard let region else { return }
        let selected = CGRect(x: region.minX * bounds.width, y: region.minY * bounds.height,
                              width: region.width * bounds.width, height: region.height * bounds.height)
        let shade = NSBezierPath(rect: bounds)
        shade.appendRect(selected)
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.56).setFill()
        shade.fill()
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selected)
        border.lineWidth = 2
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        origin = normalizedPoint(event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin else { return }
        let end = normalizedPoint(event)
        region = CGRect(x: min(origin.x, end.x), y: min(origin.y, end.y),
                        width: abs(end.x - origin.x), height: abs(end.y - origin.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard let region, region.width * bounds.width >= 8, region.height * bounds.height >= 8 else { return }
        NSApplication.shared.stopModal(withCode: .OK)
    }

    override func cancelOperation(_ sender: Any?) {
        NSApplication.shared.stopModal(withCode: .cancel)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelOperation(nil)
        return false
    }

    private func normalizedPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x / bounds.width, 0), 1),
                       y: min(max(point.y / bounds.height, 0), 1))
    }
}
