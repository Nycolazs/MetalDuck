import CoreGraphics
import Testing
@testable import MetalDuckKit

/// A 1512×982 pt screen at 2× with a 38 pt menu bar and a 70 pt Dock. Cocoa coordinates.
@Suite struct OverlayPlanTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let visible = CGRect(x: 0, y: 70, width: 1512, height: 874)

    private func plan(
        source: CGRect,
        output: PixelSize? = nil,
        placement: OutputPlacement = .overSource
    ) -> OverlayPlan {
        ScalePlan.overlayPlan(
            source: source,
            screenFrame: screen,
            visibleFrame: visible,
            backingScale: 2,
            output: output,
            placement: placement
        )
    }

    @Test func overSourceCoversTheWindowLessOnePointAtTheBottom() {
        let source = CGRect(x: 200, y: 200, width: 800, height: 600)
        let result = plan(source: source)
        #expect(result.frame == CGRect(x: 200, y: 201, width: 800, height: 599))
        #expect(!result.fillsScreen)
        // The picture shown is the window less its bottom strip, so it stays lined up.
        #expect(result.sourceCrop.minX == 0 && result.sourceCrop.minY == 0)
        #expect(result.sourceCrop.width == 1)
        #expect(abs(result.sourceCrop.height - 599.0 / 600.0) < 1e-9)
    }

    @Test func aWindowHalfOffTheRightEdgeShowsItsLeftHalf() {
        let source = CGRect(x: 1112, y: 200, width: 800, height: 600)
        let result = plan(source: source)
        #expect(result.frame.minX == 1112)
        #expect(result.frame.maxX == 1512)
        #expect(result.sourceCrop.minX == 0)
        #expect(abs(result.sourceCrop.width - 0.5) < 1e-9)
    }

    @Test func aWindowUnderTheDockLosesItsBottomFromThePicture() {
        // 100 pt of the window is below the visible area.
        let source = CGRect(x: 100, y: -30, width: 800, height: 600)
        let result = plan(source: source)
        #expect(result.frame.minY == 71)                 // Dock top, plus the one-point strip
        #expect(result.frame.maxY == 570)
        #expect(result.sourceCrop.minY == 0)             // the top of the picture is still shown
        #expect(abs(result.sourceCrop.height - 499.0 / 600.0) < 1e-9)
    }

    @Test func aFullScreenSourceIsCoveredWhereItIs() {
        // Full screen below a 38 pt notch strip.
        let source = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let result = plan(source: source)
        #expect(result.fillsScreen)
        #expect(result.frame == CGRect(x: 0, y: 1, width: 1512, height: 943))
    }

    @Test func fillDisplayCoversTheScreen() {
        let result = plan(source: CGRect(x: 300, y: 300, width: 640, height: 360), placement: .fillDisplay)
        #expect(result.frame == screen)
        #expect(result.fillsScreen)
        #expect(result.sourceCrop == OverlayPlan.wholePicture)
    }

    @Test func centredUsesTheOutputSizeInPoints() {
        // 1920×1080 px at 2× is 960×540 pt, centred between the menu bar and the Dock.
        let result = plan(
            source: CGRect(x: 0, y: 500, width: 640, height: 360),
            output: PixelSize(width: 1920, height: 1080),
            placement: .centered
        )
        #expect(result.frame.size == CGSize(width: 960, height: 540))
        #expect(result.frame.midX == visible.midX)
        #expect(abs(result.frame.midY - visible.midY) <= 0.5)
        #expect(!result.fillsScreen)
        #expect(result.sourceCrop == OverlayPlan.wholePicture)
    }

    @Test func centredLargerThanTheScreenShrinksToFitAndKeepsItsShape() {
        // 7680×4320 px is 3840×2160 pt: far too large. 16:9 inside 1512×982 is 1512×850.5.
        let result = plan(
            source: CGRect(x: 0, y: 500, width: 640, height: 360),
            output: PixelSize(width: 7680, height: 4320),
            placement: .centered
        )
        #expect(result.frame.width == 1512)
        #expect(abs(result.frame.height - 850) <= 1)
        #expect(screen.contains(result.frame))
    }

    @Test func centredAtTheScreenSizeCountsAsFillingIt() {
        let result = plan(
            source: CGRect(x: 0, y: 500, width: 640, height: 360),
            output: PixelSize(width: 3024, height: 1964),
            placement: .centered
        )
        #expect(result.fillsScreen)
        #expect(result.frame == screen)
    }

    @Test func theRenderSizeIsPlannedForTheWholePictureWhenPartIsShown() {
        // The overlay shows 599 of 600 rows: 2000×1198 px of a 2000×1200 capture. Planned
        // against the whole picture that is the capture's own size, so no scaler runs.
        let crop = CGRect(x: 0, y: 0, width: 1, height: 599.0 / 600.0)
        let whole = ScalePlan.drawable(PixelSize(width: 2000, height: 1198), showing: crop)
        #expect(whole == PixelSize(width: 2000, height: 1200))
    }
}
