import Testing
@testable import MetalDuckKit

@Suite struct ScalePlanTests {
    private let budget = PixelSize(width: 1920, height: 1080)

    private func size(_ width: Int, _ height: Int) -> PixelSize {
        PixelSize(width: width, height: height)
    }

    // MARK: Capture size

    @Test func automaticKeepsASmallSourceAtItsOwnSize() {
        #expect(ScalePlan.streamSize(native: size(1280, 720), requested: nil, budget: budget) == size(1280, 720))
    }

    @Test func automaticBringsALargeSourceDownToTheBudget() {
        let result = ScalePlan.streamSize(native: size(3840, 2160), requested: nil, budget: budget)
        #expect(result == size(1920, 1080))
    }

    @Test func automaticKeepsTheSourceShape() {
        let native = size(3456, 2234)
        let result = ScalePlan.streamSize(native: native, requested: nil, budget: budget)
        #expect(result.area <= budget.area + 4000)
        #expect(abs(result.aspect - native.aspect) < 0.01)
    }

    @Test func manualFitsInsideTheRequestWithTheSourceShape() {
        // A 16:10 source asked for 1280×720 keeps 16:10 and fits the height.
        #expect(ScalePlan.streamSize(native: size(2560, 1600), requested: size(1280, 720), budget: budget) == size(1152, 720))
        #expect(ScalePlan.streamSize(native: size(2560, 1440), requested: size(1280, 720), budget: budget) == size(1280, 720))
    }

    @Test func manualNeverCapturesMoreThanTheSourceHas() {
        #expect(ScalePlan.streamSize(native: size(1280, 720), requested: size(3840, 2160), budget: budget) == size(1280, 720))
    }

    @Test func sizesAreEven() {
        let result = ScalePlan.streamSize(native: size(1999, 1125), requested: size(1001, 999), budget: budget)
        #expect(result.width % 2 == 0)
        #expect(result.height % 2 == 0)
        #expect(result.width <= 1001)
    }

    @Test func aTinyRequestStopsAtTheSmallestWorkableSize() {
        let result = ScalePlan.streamSize(native: size(2560, 1440), requested: size(16, 16), budget: budget)
        #expect(result.width >= ScalePlan.minimumInput.width)
        #expect(result.height >= ScalePlan.minimumInput.height)
    }

    @Test func aSourceSmallerThanTheMinimumIsCapturedAsItIs() {
        #expect(ScalePlan.streamSize(native: size(100, 60), requested: nil, budget: budget) == size(100, 60))
    }

    @Test func dynamicScaleShrinksEachSide() {
        let result = ScalePlan.streamSize(native: size(1920, 1080), requested: nil, budget: budget, dynamicScale: 0.5)
        #expect(result == size(960, 540))
    }

    // MARK: Render size

    @Test func automaticRendersAtTheDrawableSize() {
        let result = ScalePlan.renderSize(input: size(1280, 720), requested: nil, drawable: size(2560, 1440), aspect: .fill)
        #expect(result == size(2560, 1440))
    }

    /// The overlay is one point shorter than the source. That must not start a scaler pass.
    @Test func aDrawableWithinOnePercentOfTheInputIsIdentity() {
        let input = size(2000, 1200)
        #expect(ScalePlan.renderSize(input: input, requested: nil, drawable: size(2000, 1198), aspect: .fill) == input)
        #expect(ScalePlan.renderSize(input: input, requested: nil, drawable: size(2000, 1198), aspect: .fit) == input)
    }

    @Test func aRequestAboveTheDrawableIsHeldToTheDrawable() {
        let result = ScalePlan.renderSize(input: size(1280, 720), requested: size(7680, 4320), drawable: size(2560, 1440), aspect: .fit)
        #expect(result == size(2560, 1440))
    }

    @Test func aRequestBelowTheDrawableIsRenderedAsAsked() {
        let result = ScalePlan.renderSize(input: size(1280, 720), requested: size(1920, 1080), drawable: size(3840, 2160), aspect: .fit)
        #expect(result == size(1920, 1080))
    }

    @Test func aspectModesOnAMismatchedOutput() {
        let input = size(1920, 1080)       // 16:9
        let drawable = size(1600, 1200)    // 4:3
        #expect(ScalePlan.renderSize(input: input, requested: nil, drawable: drawable, aspect: .fit) == size(1600, 900))
        #expect(ScalePlan.renderSize(input: input, requested: nil, drawable: drawable, aspect: .fill) == size(2133, 1200))
        #expect(ScalePlan.renderSize(input: input, requested: nil, drawable: drawable, aspect: .stretch) == size(1600, 1200))
    }

    @Test func metalFXOnlyScalesUp() {
        #expect(ScalePlan.canUpscale(from: size(1280, 720), to: size(2560, 1440)))
        #expect(!ScalePlan.canUpscale(from: size(1920, 1080), to: size(1600, 900)))
        #expect(!ScalePlan.canUpscale(from: size(1920, 1080), to: size(2133, 1000)))
        #expect(!ScalePlan.canUpscale(from: size(1920, 1080), to: size(1920, 1080)))
    }

    // MARK: Present

    @Test func presentScaleForEachAspectMode() {
        let picture = size(1920, 1080)     // 16:9
        let drawable = size(1600, 1200)    // 4:3, so the picture is wider than the drawable

        let fit = ScalePlan.presentScale(picture: picture, drawable: drawable, aspect: .fit)
        #expect(fit.x == 1)
        #expect(abs(fit.y - 0.75) < 0.001)          // bars above and below

        let fill = ScalePlan.presentScale(picture: picture, drawable: drawable, aspect: .fill)
        #expect(abs(fill.x - 1.3333) < 0.001)       // sides cropped
        #expect(fill.y == 1)

        let stretch = ScalePlan.presentScale(picture: picture, drawable: drawable, aspect: .stretch)
        #expect(stretch.x == 1 && stretch.y == 1)
    }

    @Test func presentScaleIsOneWhenShapesMatch() {
        for mode in AspectMode.allCases {
            let scale = ScalePlan.presentScale(picture: size(1280, 720), drawable: size(2560, 1440), aspect: mode)
            #expect(abs(scale.x - 1) < 0.0001 && abs(scale.y - 1) < 0.0001)
        }
    }
}
