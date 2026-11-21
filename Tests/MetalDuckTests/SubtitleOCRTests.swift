import CoreGraphics
import CoreText
import CoreVideo
import Testing
@testable import MetalDuck

struct SubtitleOCRTests {
    @Test func dialogueAreaIgnoresTextAtTop() throws {
        let image = try makeFrame()
        let result = try SubtitleOCR.recognize(image, language: "en", wholeFrame: false)
        #expect(result.contains("Open the gate"))
        #expect(!result.contains("Quest updated"))
    }

    @Test func wholeFrameIncludesTextInReadingOrder() throws {
        let image = try makeFrame()
        let result = try SubtitleOCR.recognize(image, language: "en", wholeFrame: true)
        #expect(result == "Quest updated\nOpen the gate")
    }

    private func makeFrame() throws -> SubtitleImage {
        let width = 960
        let height = 540
        var storage: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &storage)
        #expect(status == kCVReturnSuccess)
        let buffer = try #require(storage)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = try #require(CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        ))
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let attributes: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, 44, nil),
            kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)
        ]
        for (text, y) in [("Quest updated", 410.0), ("Open the gate", 75.0)] {
            let line = CTLineCreateWithAttributedString(
                CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
            )
            context.textPosition = CGPoint(x: 200, y: y)
            CTLineDraw(line, context)
        }
        context.flush()
        return SubtitleImage(pixelBuffer: buffer)
    }
}
