import Foundation
import NaturalLanguage

final class TextParser {
    static let shared = TextParser()

    private init() {}

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
