import CoreImage
import CoreVideo
import Foundation
import Vision

// ScreenCaptureKit owns the buffer. OCR only reads it while this value retains it.
struct SubtitleImage: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
}

enum SubtitleOCR {
    private static let context = CIContext()

    static func recognize(_ image: SubtitleImage, language: String, region: CGRect) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [language]
        request.usesLanguageCorrection = true
        let source = CIImage(cvPixelBuffer: image.pixelBuffer)
        let extent = source.extent
        let selection = CGRect(
            x: extent.minX + region.minX * extent.width,
            y: extent.minY + region.minY * extent.height,
            width: region.width * extent.width,
            height: region.height * extent.height
        )
        // Round inward so Vision never receives pixels beyond the selected area.
        let crop = CGRect(x: ceil(selection.minX), y: ceil(selection.minY),
                          width: floor(selection.maxX) - ceil(selection.minX),
                          height: floor(selection.maxY) - ceil(selection.minY)).intersection(extent)
        guard !crop.isEmpty, let pixels = context.createCGImage(source, from: crop) else { return "" }
        try VNImageRequestHandler(cgImage: pixels, orientation: .up).perform([request])

        return (request.results ?? [])
            .compactMap { observation -> (text: String, bounds: CGRect)? in
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= 0.35,
                      candidate.string.contains(where: \.isLetter) else { return nil }
                return (candidate.string, observation.boundingBox)
            }
            .sorted {
                let firstRow = Int(($0.bounds.midY * 100).rounded())
                let secondRow = Int(($1.bounds.midY * 100).rounded())
                if firstRow == secondRow { return $0.bounds.minX < $1.bounds.minX }
                return firstRow > secondRow
            }
            .prefix(6)
            .map(\.text)
            .joined(separator: "\n")
    }
}
