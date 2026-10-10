import AppKit

enum MetalDuckIcon {
    static func make(size: CGFloat = 512) -> NSImage {
        if let bundled = loadBundledIcon(size: size) {
            return bundled
        }

        // Simple placeholder fallback if asset is missing.
        let imageSize = NSSize(width: size, height: size)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: imageSize)
        let badge = NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04), xRadius: rect.width * 0.22, yRadius: rect.height * 0.22)
        NSColor.windowBackgroundColor.setFill()
        badge.fill()

        return image
    }

    private static func loadBundledIcon(size: CGFloat) -> NSImage? {
        guard let bundle = Bundle.safeModule else {
            return nil
        }

        // SPM flattens the Assets directory in the final bundle.
        let resourceName = "AppIcon"
        let resourceExtension = "png"

        let iconURL = bundle.url(forResource: resourceName, withExtension: resourceExtension)
            ?? bundle.url(forResource: resourceName, withExtension: resourceExtension, subdirectory: "Assets")

        guard let url = iconURL, let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.size = NSSize(width: size, height: size)
        return image
    }
}
