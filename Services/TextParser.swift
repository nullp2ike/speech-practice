import Foundation
import NaturalLanguage

final class TextParser {
    static let shared = TextParser()

    private init() {}

    /// Detects the dominant language of the given text.
    /// - Parameter text: The text to analyze (works best with 20+ characters)
    /// - Returns: A BCP 47 language code (e.g., "en-US") or nil if detection fails
    func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let detectedLanguage = recognizer.dominantLanguage else {
            return nil
        }

        // Map NLLanguage rawValue (base language code) to full BCP 47 codes used by the app
        // NLLanguage.rawValue returns codes like "en", "et", "de", etc.
        // Note: NLLanguageRecognizer often misidentifies Estonian as Finnish ("fi"),
        // so we map Finnish to Estonian as a workaround.
        let languageCode = detectedLanguage.rawValue

        switch languageCode {
        case "en": return "en-US"
        case "et", "fi": return "et-EE"  // Finnish often misdetected for Estonian
        case "de": return "de-DE"
        case "fr": return "fr-FR"
        case "es": return "es-ES"
        case "it": return "it-IT"
        case "pt": return "pt-BR"
        case "ja": return "ja-JP"
        case "zh": return "zh-CN"
        default: return nil
        }
    }

    func parse(_ text: String, granularity: SegmentType) -> [SpeechSegment] {
        switch granularity {
        case .sentence:
            return parseIntoSentences(text)
        case .paragraph:
            return parseIntoParagraphs(text)
        }
    }

    func parseIntoSentences(_ text: String) -> [SpeechSegment] {
        guard !text.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var segments: [SpeechSegment] = []

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentenceText = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentenceText.isEmpty {
                let segment = SpeechSegment(
                    text: sentenceText,
                    range: range,
                    type: .sentence
                )
                segments.append(segment)
            }
            return true
        }

        return segments
    }

    func parseIntoParagraphs(_ text: String) -> [SpeechSegment] {
        guard !text.isEmpty else { return [] }

        var segments: [SpeechSegment] = []
        var currentIndex = text.startIndex
        var paragraphStart: String.Index?

        while currentIndex < text.endIndex {
            let char = text[currentIndex]

            if char.isNewline {
                // End of a potential paragraph
                if let start = paragraphStart {
                    let range = start..<currentIndex
                    let paragraphText = String(text[range]).trimmingCharacters(in: .whitespaces)
                    if !paragraphText.isEmpty {
                        let segment = SpeechSegment(
                            text: paragraphText,
                            range: range,
                            type: .paragraph
                        )
                        segments.append(segment)
                    }
                    paragraphStart = nil
                }
            } else if !char.isWhitespace && paragraphStart == nil {
                // Start of a new paragraph
                paragraphStart = currentIndex
            }

            currentIndex = text.index(after: currentIndex)
        }

        // Handle last paragraph if text doesn't end with newline
        if let start = paragraphStart {
            let range = start..<currentIndex
            let paragraphText = String(text[range]).trimmingCharacters(in: .whitespaces)
            if !paragraphText.isEmpty {
                let segment = SpeechSegment(
                    text: paragraphText,
                    range: range,
                    type: .paragraph
                )
                segments.append(segment)
            }
        }

        return segments
    }
}
