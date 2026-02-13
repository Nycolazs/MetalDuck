import AppKit

enum MetalDuckIcon {
    static func make(size: CGFloat = 512) -> NSImage {
        if let bundled = loadBundledIcon(size: size) {
            return bundled
        }

        let imageSize = NSSize(width: size, height: size)
        let image = NSImage(size: imageSize)

        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: imageSize)

        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        func area(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(
                x: rect.minX + x * rect.width,
                y: rect.minY + y * rect.height,
                width: w * rect.width,
                height: h * rect.height
            )
        }

        // Background badge.
        let badge = NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04), xRadius: rect.width * 0.22, yRadius: rect.height * 0.22)
        let bg = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.18, alpha: 1.0), 0.0),
            (NSColor(calibratedRed: 0.13, green: 0.18, blue: 0.29, alpha: 1.0), 0.5),
            (NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.14, alpha: 1.0), 1.0)
        )
        bg?.draw(in: badge, angle: -90)

        // Soft floor shadow.
        let floorShadow = NSBezierPath(ovalIn: area(0.20, 0.17, 0.58, 0.16))
        NSColor(calibratedWhite: 0.02, alpha: 0.45).setFill()
        floorShadow.fill()

        // Duck body.
        let body = NSBezierPath()
        body.move(to: point(0.20, 0.43))
        body.curve(to: point(0.67, 0.43), controlPoint1: point(0.30, 0.29), controlPoint2: point(0.56, 0.29))
        body.curve(to: point(0.77, 0.56), controlPoint1: point(0.73, 0.44), controlPoint2: point(0.81, 0.50))
        body.curve(to: point(0.68, 0.67), controlPoint1: point(0.76, 0.63), controlPoint2: point(0.72, 0.69))
        body.curve(to: point(0.48, 0.70), controlPoint1: point(0.63, 0.67), controlPoint2: point(0.56, 0.71))
        body.curve(to: point(0.31, 0.66), controlPoint1: point(0.42, 0.70), controlPoint2: point(0.35, 0.69))
        body.curve(to: point(0.18, 0.54), controlPoint1: point(0.24, 0.62), controlPoint2: point(0.18, 0.58))
        body.curve(to: point(0.20, 0.43), controlPoint1: point(0.18, 0.50), controlPoint2: point(0.19, 0.46))
        body.close()

        let steel = NSGradient(colorsAndLocations:
            (NSColor(calibratedWhite: 0.93, alpha: 1.0), 0.0),
            (NSColor(calibratedWhite: 0.74, alpha: 1.0), 0.30),
            (NSColor(calibratedWhite: 0.56, alpha: 1.0), 0.55),
            (NSColor(calibratedWhite: 0.82, alpha: 1.0), 0.80),
            (NSColor(calibratedWhite: 0.48, alpha: 1.0), 1.0)
        )
        steel?.draw(in: body, angle: -35)

        // Wing plate.
        let wing = NSBezierPath(ovalIn: area(0.34, 0.45, 0.24, 0.17))
        let wingGradient = NSGradient(colorsAndLocations:
            (NSColor(calibratedWhite: 0.86, alpha: 0.96), 0.0),
            (NSColor(calibratedWhite: 0.63, alpha: 0.96), 1.0)
        )
        wingGradient?.draw(in: wing, angle: -30)

        // Duck head.
        let head = NSBezierPath(ovalIn: area(0.56, 0.56, 0.24, 0.24))
        let headGradient = NSGradient(colorsAndLocations:
            (NSColor(calibratedWhite: 0.95, alpha: 1.0), 0.0),
            (NSColor(calibratedWhite: 0.70, alpha: 1.0), 0.55),
            (NSColor(calibratedWhite: 0.52, alpha: 1.0), 1.0)
        )
        headGradient?.draw(in: head, angle: -35)

        // Beak with metallic copper.
        let beak = NSBezierPath()
        beak.move(to: point(0.73, 0.61))
        beak.curve(to: point(0.88, 0.59), controlPoint1: point(0.80, 0.64), controlPoint2: point(0.86, 0.63))
        beak.curve(to: point(0.88, 0.53), controlPoint1: point(0.90, 0.57), controlPoint2: point(0.90, 0.55))
        beak.curve(to: point(0.76, 0.52), controlPoint1: point(0.85, 0.50), controlPoint2: point(0.79, 0.50))
        beak.curve(to: point(0.73, 0.61), controlPoint1: point(0.74, 0.55), controlPoint2: point(0.73, 0.58))
        beak.close()

        let copper = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.30, alpha: 1.0), 0.0),
            (NSColor(calibratedRed: 0.86, green: 0.48, blue: 0.19, alpha: 1.0), 0.6),
            (NSColor(calibratedRed: 0.62, green: 0.29, blue: 0.11, alpha: 1.0), 1.0)
        )
        copper?.draw(in: beak, angle: -15)

        // Eye.
        let eye = NSBezierPath(ovalIn: area(0.69, 0.65, 0.038, 0.038))
        NSColor(calibratedWhite: 0.1, alpha: 1.0).setFill()
        eye.fill()
        let eyeSpec = NSBezierPath(ovalIn: area(0.703, 0.669, 0.012, 0.012))
        NSColor(calibratedWhite: 1.0, alpha: 0.9).setFill()
        eyeSpec.fill()

        // Strokes and glossy highlight.
        NSColor(calibratedWhite: 0.18, alpha: 0.9).setStroke()
        body.lineWidth = rect.width * 0.01
        wing.lineWidth = rect.width * 0.008
        head.lineWidth = rect.width * 0.009
        beak.lineWidth = rect.width * 0.008
        body.stroke()
        wing.stroke()
        head.stroke()
        beak.stroke()

        let gloss = NSBezierPath()
        gloss.move(to: point(0.26, 0.60))
        gloss.curve(to: point(0.55, 0.66), controlPoint1: point(0.35, 0.68), controlPoint2: point(0.50, 0.70))
        NSColor(calibratedWhite: 1.0, alpha: 0.32).setStroke()
        gloss.lineWidth = rect.width * 0.015
        gloss.lineCapStyle = .round
        gloss.stroke()

        let badgeStroke = NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04), xRadius: rect.width * 0.22, yRadius: rect.height * 0.22)
        NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
        badgeStroke.lineWidth = rect.width * 0.01
        badgeStroke.stroke()

        return image
    }

    private static func loadBundledIcon(size: CGFloat) -> NSImage? {
        guard let iconURL = Bundle.module.url(
            forResource: "AppIcon",
            withExtension: "png",
            subdirectory: "Assets"
        ),
        let image = NSImage(contentsOf: iconURL) else {
            return nil
        }

        image.size = NSSize(width: size, height: size)
        return image
    }
}
