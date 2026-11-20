// Generates the app icon and the DMG installer background from the silver logo.
//
//   swift scripts/generate_brand_assets.swift
//
// Inputs:  Designs/MetalDuck_Logo_Silver.png (transparent silver duck)
// Outputs: Sources/MetalDuck/Assets/AppIcon.png       (1024 px, used in-app)
//          Sources/MetalDuck/Assets/AppIcon.icns      (bundle icon)
//          Designs/DMG/{light,dark}/background.png and @2x (660 x 400 pt installer window)

import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let logoURL = root.appendingPathComponent("Designs/MetalDuck_Logo_Silver.png")
let assetsDir = root.appendingPathComponent("Sources/MetalDuck/Assets")
let dmgDir = root.appendingPathComponent("Designs/DMG")

guard let logoImage = NSImage(contentsOf: logoURL),
      let logo = logoImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Missing logo at \(logoURL.path)")
}

// MARK: - Helpers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func makeContext(width: Int, height: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    return ctx
}

func writePNG(_ ctx: CGContext, to url: URL, pointsPerInch: CGFloat = 72) {
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: CGFloat(image.width) * 72 / pointsPerInch,
                      height: CGFloat(image.height) * 72 / pointsPerInch)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path.replacingOccurrences(of: root.path + "/", with: ""))")
}

/// Apple-style continuous-corner rounded square (superellipse, n = 5).
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n: CGFloat = 5
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c >= 0 ? 1 : -1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s >= 0 ? 1 : -1) * pow(abs(s), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func linearGradient(_ ctx: CGContext, _ colors: [CGColor], _ locations: [CGFloat], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radialGradient(_ ctx: CGContext, _ colors: [CGColor], center: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// Draws the logo so its visible content (not the transparent margin) fills `width`, centred on `center`.
func drawLogo(_ ctx: CGContext, center: CGPoint, width: CGFloat, shadow: (CGFloat, CGFloat, CGFloat)? = nil) {
    // Visible content of the 760 px source spans x 8...751, y 54...705.
    let contentW: CGFloat = 744, contentCX: CGFloat = 379.5, contentCY: CGFloat = 379.5
    let scale = width / contentW
    let w = CGFloat(logo.width) * scale, h = CGFloat(logo.height) * scale
    let origin = CGPoint(x: center.x - contentCX * scale, y: center.y - (CGFloat(logo.height) - contentCY) * scale)
    ctx.saveGState()
    if let (dy, blur, alpha) = shadow {
        ctx.setShadow(offset: CGSize(width: 0, height: -dy), blur: blur, color: rgb(0x000000, alpha))
    }
    ctx.draw(logo, in: CGRect(x: origin.x, y: origin.y, width: w, height: h))
    ctx.restoreGState()
}

func drawText(_ ctx: CGContext, _ text: String, font: NSFont, color: NSColor, center: CGPoint, kern: CGFloat = 0) {
    let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    let line = CTLineCreateWithAttributedString(attr)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.saveGState()
    ctx.textPosition = CGPoint(x: center.x - bounds.width / 2 - bounds.minX,
                               y: center.y - (bounds.height / 2 + bounds.minY))
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// MARK: - App icon

func renderIcon(size: Int) -> CGContext {
    let ctx = makeContext(width: size, height: size)
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824 pt body inside a 1024 canvas, leaving room for the shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.45))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0x16191E))
    ctx.fillPath()
    ctx.restoreGState()

    // Graphite body.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    linearGradient(ctx, [rgb(0x3A4049), rgb(0x22262C), rgb(0x0E1013)], [0, 0.55, 1],
                   from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
    // Soft top light and a faint warm floor reflection.
    radialGradient(ctx, [rgb(0xFFFFFF, 0.14), rgb(0xFFFFFF, 0)], center: CGPoint(x: 512, y: 980), radius: 620)
    radialGradient(ctx, [rgb(0xFF9A3C, 0.10), rgb(0xFF9A3C, 0)], center: CGPoint(x: 512, y: 60), radius: 520)
    ctx.restoreGState()

    // Hairline rim: bright at the top, fading toward the bottom.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setLineWidth(4)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    linearGradient(ctx, [rgb(0xFFFFFF, 0.28), rgb(0xFFFFFF, 0.04)], [0, 1],
                   from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
    ctx.restoreGState()

    // The silver duck.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    drawLogo(ctx, center: CGPoint(x: 512, y: 508), width: 620, shadow: (14, 30, 0.6))
    ctx.restoreGState()

    return ctx
}

let iconPNG = assetsDir.appendingPathComponent("AppIcon.png")
writePNG(renderIcon(size: 1024), to: iconPNG)

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MetalDuck-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(renderIcon(size: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(renderIcon(size: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"), pointsPerInch: 144)
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", assetsDir.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")
try? FileManager.default.removeItem(at: iconset)
print("wrote Sources/MetalDuck/Assets/AppIcon.icns")

// MARK: - DMG background
//
// Window content is 660 x 400 pt. Finder places the icons (128 pt) at the
// positions set in scripts/create_release.sh; keep these numbers in sync.

let dmgSize = CGSize(width: 660, height: 400)
let appIconCenter = CGPoint(x: 170, y: 190)      // top-left origin, as Finder uses
let appsIconCenter = CGPoint(x: 490, y: 190)

/// Colours for one look of the installer window.
struct DMGTheme {
    let name: String
    let base: [UInt32]            // top, middle, bottom
    let glow: (UInt32, CGFloat)   // soft light from the top
    let tile: (UInt32, CGFloat)   // pixel field colour and peak opacity
    let platform: UInt32
    /// Opacity of the tile at its top (behind the icon) and bottom (behind the name).
    let platformAlpha: (CGFloat, CGFloat)
    let platformStroke: (UInt32, CGFloat)
    let arrow: UInt32
    let title: NSColor
    let body: NSColor
    let caption: NSColor
    let logoShadow: CGFloat
}

let darkTheme = DMGTheme(
    name: "dark",
    base: [0x2B3037, 0x1A1D22, 0x111316], glow: (0xFFFFFF, 0.07), tile: (0xFFFFFF, 0.06),
    // Finder draws the file names in black on a custom background, so the tile
    // must be light where the name sits. It fades toward the top so it stays
    // quiet behind the icon instead of competing with it.
    platform: 0x9AA1AB, platformAlpha: (0.10, 0.90), platformStroke: (0xFFFFFF, 0.10),
    arrow: 0xD8DDE3,
    title: NSColor(white: 0.95, alpha: 1), body: NSColor(white: 0.88, alpha: 1), caption: NSColor(white: 0.55, alpha: 1),
    logoShadow: 0.5)

let lightTheme = DMGTheme(
    name: "light",
    base: [0xFBFBFC, 0xF0F2F4, 0xE2E5E9], glow: (0xFFFFFF, 0.8), tile: (0x1E2228, 0.05),
    platform: 0xFFFFFF, platformAlpha: (0.85, 0.95), platformStroke: (0x000000, 0.06),
    arrow: 0x2E333A,
    title: NSColor(white: 0.11, alpha: 1), body: NSColor(white: 0.18, alpha: 1), caption: NSColor(white: 0.48, alpha: 1),
    logoShadow: 0.35)

func renderBackground(scale: CGFloat, theme: DMGTheme) -> CGContext {
    let ctx = makeContext(width: Int(dmgSize.width * scale), height: Int(dmgSize.height * scale))
    ctx.scaleBy(x: scale, y: scale)
    let W = dmgSize.width, H = dmgSize.height
    func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: H - p.y) }

    linearGradient(ctx, theme.base.map { rgb($0) }, [0, 0.6, 1],
                   from: CGPoint(x: 0, y: H), to: CGPoint(x: 0, y: 0))
    radialGradient(ctx, [rgb(theme.glow.0, theme.glow.1), rgb(theme.glow.0, 0)],
                   center: CGPoint(x: W / 2, y: H + 40), radius: 420)
    radialGradient(ctx, [rgb(0xFF9A3C, 0.06), rgb(0xFF9A3C, 0)], center: CGPoint(x: W / 2, y: -60), radius: 360)

    // Pixel field on the left that dissolves to the right, echoing the logo.
    let tile: CGFloat = 14
    var seed: UInt64 = 0x5EED
    func rand() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((seed >> 33) % 10_000) / 10_000
    }
    var y: CGFloat = 0
    while y < H {
        var x: CGFloat = 0
        while x < W {
            let fade = max(0, 1 - x / (W * 0.62))
            if rand() < fade * 0.55 {
                let alpha = theme.tile.1 * (0.2 + fade * rand())
                ctx.setFillColor(rgb(theme.tile.0, alpha))
                ctx.addPath(CGPath(roundedRect: CGRect(x: x + 1, y: y + 1, width: tile - 2, height: tile - 2),
                                   cornerWidth: 2, cornerHeight: 2, transform: nil))
                ctx.fillPath()
            }
            x += tile
        }
        y += tile
    }

    // Header: mark + wordmark.
    drawLogo(ctx, center: flip(CGPoint(x: 268, y: 52)), width: 30, shadow: (1, 3, theme.logoShadow))
    drawText(ctx, "MetalDuck", font: .systemFont(ofSize: 20, weight: .semibold),
             color: theme.title, center: flip(CGPoint(x: 340, y: 52)), kern: 0.2)

    // Platforms under the two icons and their names.
    for c in [appIconCenter, appsIconCenter] {
        let p = flip(c)
        let rect = CGRect(x: p.x - 92, y: p.y - 104, width: 184, height: 184)
        let path = CGPath(roundedRect: rect, cornerWidth: 34, cornerHeight: 34, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        linearGradient(ctx, [rgb(theme.platform, theme.platformAlpha.0), rgb(theme.platform, theme.platformAlpha.0 + (theme.platformAlpha.1 - theme.platformAlpha.0) * 0.45),
                             rgb(theme.platform, theme.platformAlpha.1)], [0, 0.55, 1],
                       from: CGPoint(x: 0, y: rect.maxY), to: CGPoint(x: 0, y: rect.minY))
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.setStrokeColor(rgb(theme.platformStroke.0, theme.platformStroke.1))
        ctx.setLineWidth(1)
        ctx.strokePath()
    }

    // Pixel arrow: scattered tiles that assemble into a chevron, like the duck.
    let arrowCenter = flip(CGPoint(x: 330, y: 190))
    let cell: CGFloat = 8
    let pattern = [
        "........#...",
        "........##..",
        "#..#.######.",
        ".#.#.#######",
        "..#.#.#####.",
        "........##..",
        "........#...",
    ]
    for (row, line) in pattern.enumerated() {
        for (col, ch) in line.enumerated() where ch == "#" {
            let t = CGFloat(col) / CGFloat(line.count - 1)
            let x = arrowCenter.x + (CGFloat(col) - CGFloat(line.count) / 2) * cell
            let y = arrowCenter.y + (CGFloat(pattern.count) / 2 - CGFloat(row) - 1) * cell
            ctx.setFillColor(rgb(theme.arrow, 0.2 + 0.75 * t))
            ctx.addPath(CGPath(roundedRect: CGRect(x: x + 0.75, y: y + 0.75, width: cell - 1.5, height: cell - 1.5),
                               cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
            ctx.fillPath()
        }
    }

    // Instructions.
    drawText(ctx, "Drag MetalDuck to Applications to install", font: .systemFont(ofSize: 14, weight: .medium),
             color: theme.body, center: flip(CGPoint(x: 330, y: 330)))
    drawText(ctx, "Version 1.3.1  ·  Requires Apple silicon and macOS 15 or later",
             font: .systemFont(ofSize: 11, weight: .regular),
             color: theme.caption, center: flip(CGPoint(x: 330, y: 356)))

    return ctx
}

// Designs/DMG/<theme>/background.png and @2x. create_release.sh picks one with DMG_THEME.
for theme in [lightTheme, darkTheme] {
    let dir = dmgDir.appendingPathComponent(theme.name)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    writePNG(renderBackground(scale: 1, theme: theme), to: dir.appendingPathComponent("background.png"))
    writePNG(renderBackground(scale: 2, theme: theme), to: dir.appendingPathComponent("background@2x.png"), pointsPerInch: 144)
}
