import CoreVideo
import Foundation
import Vision

// ScreenCaptureKit owns the buffer. OCR only reads it while this value retains it.
struct SubtitleImage: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
}

enum SubtitleOCR {
    static func recognize(_ image: SubtitleImage, language: String, wholeFrame: Bool) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [language]
        request.usesLanguageCorrection = true
        // Vision uses a bottom-left origin. Restrict OCR to the usual dialogue area.
        if !wholeFrame {
            request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 0.4)
        }
        try VNImageRequestHandler(cvPixelBuffer: image.pixelBuffer, orientation: .up).perform([request])

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
