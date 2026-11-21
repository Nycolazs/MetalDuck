import CoreGraphics
import CoreMedia
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

    @Test func externalVideoFrameKeepsTimestampAndCanBeReadByOCR() throws {
        let image = try makeFrame()
        let timestamp = CMTime(value: 2, timescale: 30)
        let context = try MetalContext()
        let frame = try #require(CapturedFrame(
            pixelBuffer: image.pixelBuffer,
            timestamp: timestamp,
            targetRect: nil,
            context: context
        ))
        #expect(frame.targetRect == nil)
        #expect(frame.timestamp == timestamp)
        #expect(frame.texture.width == 960)
        #expect(frame.texture.height == 540)
        let result = try SubtitleOCR.recognize(frame.subtitleImage, language: "en", wholeFrame: false)
        #expect(result == "Open the gate")
    }

    private func makeFrame() throws -> SubtitleImage {
        let width = 960
        let height = 540
        var storage: CVPixelBuffer?
        let attributesForStorage = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributesForStorage, &storage)
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
