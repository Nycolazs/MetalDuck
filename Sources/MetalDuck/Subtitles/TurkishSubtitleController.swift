import Foundation
import Translation

@MainActor
final class TurkishSubtitleController {
    private var task: Task<Void, Never>?

    func stop() {
        task?.cancel()
        // Retain the task so a restart can wait for its in-flight OCR to finish.
    }

    @available(macOS 26, *)
    func start(
        language: String,
        region: CGRect,
        nextFrame: @escaping () -> (image: SubtitleImage, sequence: UInt64)?,
        show: @escaping (String) -> Void,
        report: @escaping (String) -> Void
    ) {
        stop()
        let previousTask = task
        task = Task {
            await previousTask?.value
            guard !Task.isCancelled else { return }

            let source = Locale.Language(identifier: language)
            let target = Locale.Language(identifier: "tr")
            let status = await LanguageAvailability().status(from: source, to: target)
            guard !Task.isCancelled else { return }
            switch status {
            case .installed:
                break
            case .supported:
                report("Türkçe altyazı için Sistem Ayarları → Genel → Dil ve Bölge → Çeviri Dilleri bölümünden kaynak dili ve Türkçeyi indirin.")
                return
            default:
                report("Apple Çeviri, bu kaynak dil ile Türkçe arasındaki çeviriyi desteklemiyor.")
                return
            }

            let session = TranslationSession(installedSource: source, target: target)
            var lastSequence: UInt64?
            var lastText = ""
            var cache: [String: String] = [:]

            while !Task.isCancelled {
                if let frame = nextFrame(), frame.sequence != lastSequence {
                    lastSequence = frame.sequence
                    do {
                        let worker = Task.detached(priority: .utility) {
                            try SubtitleOCR.recognize(frame.image, language: language, region: region)
                        }
                        let text = try await worker.value
                        try Task.checkCancellation()
                        if text != lastText {
                            if text.isEmpty {
                                show("")
                            } else if let cached = cache[text] {
                                show(cached)
                            } else {
                                let response = try await session.translate(text)
                                try Task.checkCancellation()
                                if cache.count >= 64 { cache.removeAll(keepingCapacity: true) }
                                cache[text] = response.targetText
                                show(response.targetText)
                            }
                            lastText = text
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        show("")
                        report("Türkçe altyazı işlenemedi. Çeviri dillerini kontrol edip yeniden deneyin.")
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}
