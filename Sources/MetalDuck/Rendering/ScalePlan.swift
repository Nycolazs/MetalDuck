import CoreGraphics

/// A size in pixels.
struct PixelSize: Codable, Equatable, Hashable, Sendable {
    var width: Int
    var height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    var area: Int { width * height }
    var aspect: Double { Double(max(width, 1)) / Double(max(height, 1)) }
    var description: String { "\(width)×\(height)" }
}

/// How the picture is placed when its shape differs from the output's.
enum AspectMode: String, Codable, Equatable, CaseIterable, Sendable {
    /// All of the picture, with bars where the shapes differ.
    case fit = "Fit"
    /// No bars; the picture is cropped where the shapes differ.
    case fill = "Fill"
    /// All of the picture and no bars; the picture is distorted where the shapes differ.
    case stretch = "Stretch"
}

/// Where the scaled picture goes on screen.
enum OutputPlacement: String, Codable, Equatable, CaseIterable, Sendable {
    /// Exactly over the source, following it. Clicks land where the picture shows them.
    case overSource = "Over source"
    /// The output size, centred on the source's screen.
    case centered = "Centred"
    /// The whole screen the source is on.
    case fillDisplay = "Fill display"
}

/// Where the overlay sits, and which part of the source's picture it shows.
struct OverlayPlan: Equatable {
    /// In Cocoa screen coordinates (points, origin bottom left).
    var frame: CGRect
    /// The overlay covers a whole screen: it sits under the Dock and menu bar and joins
    /// the source's Space.
    var fillsScreen: Bool
    /// The part of the source's picture the overlay shows, as a share of it, origin top
    /// left. The whole picture is (0, 0, 1, 1).
    var sourceCrop: CGRect

    static let wholePicture = CGRect(x: 0, y: 0, width: 1, height: 1)
}

/// The sizes the pipeline works at. Pure arithmetic, kept apart from Metal and AppKit so
/// it can be tested: the capture stream's size, the size the scaler renders to, and how
/// that picture sits in the drawable.
enum ScalePlan {
    /// The capture service compares a 128×72 grid of points to spot repeated frames and
    /// cuts, and cannot below this size.
    static let minimumInput = PixelSize(width: 128, height: 72)

    /// The size to capture at.
    ///
    /// - `requested` nil (Automatic): the source's shape with at most `budget`'s pixel count.
    /// - `requested` set (Manual): the largest size with the source's shape that fits inside it.
    ///
    /// Never more pixels than the source has, since there is no more detail to capture.
    /// `dynamicScale` shrinks each side, for dynamic resolution.
    static func streamSize(
        native: PixelSize,
        requested: PixelSize?,
        budget: PixelSize,
        dynamicScale: Double = 1
    ) -> PixelSize {
        let nativeWidth = Double(max(native.width, 1))
        let nativeHeight = Double(max(native.height, 1))

        var scale: Double
        if let requested {
            scale = min(
                Double(max(requested.width, 1)) / nativeWidth,
                Double(max(requested.height, 1)) / nativeHeight
            )
        } else {
            scale = (Double(max(budget.area, 1)) / (nativeWidth * nativeHeight)).squareRoot()
        }
        scale = min(scale, 1) * min(max(dynamicScale, 0.1), 1)

        // Not below the smallest size the capture service can work with, unless the
        // source itself is smaller.
        let floorScale = min(1, max(
            Double(minimumInput.width) / nativeWidth,
            Double(minimumInput.height) / nativeHeight
        ))
        scale = max(scale, floorScale)

        return PixelSize(
            width: even(nativeWidth * scale, atMost: native.width),
            height: even(nativeHeight * scale, atMost: native.height)
        )
    }

    /// The size the scaler renders to, from a frame of `input` size.
    ///
    /// The picture is drawn into `drawable`. `requested` nil means "as large as the
    /// drawable". Nothing is rendered past the drawable: those pixels would be computed
    /// and thrown away. A result within 1% of the input is the input itself, so no scaler
    /// pass runs for nothing.
    static func renderSize(
        input: PixelSize,
        requested: PixelSize?,
        drawable: PixelSize,
        aspect: AspectMode
    ) -> PixelSize {
        let box = PixelSize(
            width: max(1, min(requested?.width ?? drawable.width, drawable.width)),
            height: max(1, min(requested?.height ?? drawable.height, drawable.height))
        )
        let scaleX = Double(box.width) / Double(max(input.width, 1))
        let scaleY = Double(box.height) / Double(max(input.height, 1))

        let size: PixelSize
        switch aspect {
        case .fit:
            let scale = min(scaleX, scaleY)
            size = PixelSize(width: rounded(Double(input.width) * scale), height: rounded(Double(input.height) * scale))
        case .fill:
            let scale = max(scaleX, scaleY)
            size = PixelSize(width: rounded(Double(input.width) * scale), height: rounded(Double(input.height) * scale))
        case .stretch:
            size = box
        }

        if isNearly(size.width, input.width), isNearly(size.height, input.height) {
            return input
        }
        return size
    }

    /// True when MetalFX can do the scaling: it only scales up.
    static func canUpscale(from input: PixelSize, to output: PixelSize) -> Bool {
        output.width >= input.width && output.height >= input.height && output != input
    }

    /// How the present pass scales its full-screen triangle so a `picture` lands in a
    /// `drawable` as the aspect mode asks. Above 1 on an axis crops that axis; below 1
    /// leaves bars on it.
    static func presentScale(picture: PixelSize, drawable: PixelSize, aspect: AspectMode) -> (x: Float, y: Float) {
        let ratio = Float(picture.aspect / drawable.aspect)
        switch aspect {
        case .stretch:
            return (1, 1)
        case .fill:
            return ratio > 1 ? (ratio, 1) : (1, 1 / ratio)
        case .fit:
            return ratio > 1 ? (1, 1 / ratio) : (ratio, 1)
        }
    }

    /// Where the overlay goes. All rectangles are Cocoa screen coordinates in points.
    ///
    /// Over the source, the overlay is the part of the source that is on screen, less a
    /// strip one point high at the bottom: macOS tells an app its window is hidden only
    /// when none of it shows, and browsers stop drawing then, which froze the very video
    /// being scaled. `sourceCrop` says which part of the picture that is, so the picture
    /// stays lined up with the window under it.
    static func overlayPlan(
        source: CGRect,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        backingScale: CGFloat,
        output: PixelSize?,
        placement: OutputPlacement
    ) -> OverlayPlan {
        switch placement {
        case .fillDisplay:
            return OverlayPlan(frame: screenFrame, fillsScreen: true, sourceCrop: OverlayPlan.wholePicture)

        case .centered:
            let scale = max(backingScale, 1)
            var size = output.map { CGSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale) }
                ?? source.size
            size.width = max(1, size.width)
            size.height = max(1, size.height)
            // Too large for the screen: shrink it, keeping its shape.
            let fit = min(1, screenFrame.width / size.width, screenFrame.height / size.height)
            size = CGSize(width: (size.width * fit).rounded(), height: (size.height * fit).rounded())
            if size.width >= screenFrame.width - 1, size.height >= screenFrame.height - 1 {
                return OverlayPlan(frame: screenFrame, fillsScreen: true, sourceCrop: OverlayPlan.wholePicture)
            }
            // Keep the menu bar and Dock clear when it fits between them.
            let area = size.width <= visibleFrame.width && size.height <= visibleFrame.height ? visibleFrame : screenFrame
            let frame = CGRect(
                x: (area.midX - size.width / 2).rounded(),
                y: (area.midY - size.height / 2).rounded(),
                width: size.width,
                height: size.height
            )
            return OverlayPlan(frame: frame, fillsScreen: false, sourceCrop: OverlayPlan.wholePicture)

        case .overSource:
            let fillsScreen = fills(source, screen: screenFrame)
            // A full-screen source is covered as it is. Anything else stays inside the
            // visible area, so the menu bar and Dock (and Force Quit) stay reachable.
            var frame = fillsScreen ? source : source.intersection(visibleFrame)
            if frame.isNull || frame.width < 1 || frame.height < 1 {
                frame = CGRect(x: source.minX, y: source.minY, width: max(1, source.width), height: max(1, source.height))
            }
            if frame.height > 2 {
                frame.origin.y += 1
                frame.size.height -= 1
            }
            guard source.width > 0, source.height > 0 else {
                return OverlayPlan(frame: frame, fillsScreen: fillsScreen, sourceCrop: OverlayPlan.wholePicture)
            }
            let crop = CGRect(
                x: (frame.minX - source.minX) / source.width,
                y: (source.maxY - frame.maxY) / source.height,
                width: frame.width / source.width,
                height: frame.height / source.height
            )
            return OverlayPlan(frame: frame, fillsScreen: fillsScreen, sourceCrop: crop)
        }
    }

    /// True when `rect` fills `screen`: full width, down to the bottom, and up to the top
    /// or to just under the notch strip. Apps stop at different heights there (Firefox
    /// leaves the menu bar's 37 pt, the notch itself is 32 pt), so allow up to 60 pt,
    /// which no ordinary window that fills the width reaches by accident.
    static func fills(_ rect: CGRect, screen: CGRect) -> Bool {
        let topGap = screen.maxY - rect.maxY
        return abs(rect.minX - screen.minX) <= 2 && abs(rect.width - screen.width) <= 4 &&
            abs(rect.minY - screen.minY) <= 2 && topGap >= -2 && topGap <= 60
    }

    /// The drawable the whole picture would need, when the overlay shows only `crop` of
    /// it: the render size is planned against this, so the visible part is not rendered
    /// smaller than the screen pixels it covers.
    static func drawable(_ drawable: PixelSize, showing crop: CGRect) -> PixelSize {
        PixelSize(
            width: rounded(Double(drawable.width) / Double(min(max(crop.width, 0.01), 1))),
            height: rounded(Double(drawable.height) / Double(min(max(crop.height, 0.01), 1)))
        )
    }

    private static func isNearly(_ a: Int, _ b: Int) -> Bool {
        abs(a - b) <= max(1, Int(Double(b) * 0.01))
    }

    private static func rounded(_ value: Double) -> Int {
        max(1, Int(value.rounded()))
    }

    /// The even number at or just below `value`, at least 2 and not above `limit`
    /// (video-sized surfaces are happier even). Rounds down so a requested size is never
    /// exceeded; the small allowance keeps 1079.999 from becoming 1078.
    private static func even(_ value: Double, atMost limit: Int) -> Int {
        var result = max(2, Int((value + 0.01) / 2) * 2)
        if result > limit {
            result = max(1, limit >= 2 ? limit - limit % 2 : limit)
        }
        return result
    }
}
