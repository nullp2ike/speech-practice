import Foundation
import NaturalLanguage

extension String {
    /// Returns the number of sentences in the string
    var sentenceCount: Int {
        guard !isEmpty else { return 0 }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = self
        var count = 0
        tokenizer.enumerateTokens(in: startIndex..<endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    /// Returns the number of paragraphs in the string
    var paragraphCount: Int {
        components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    /// Truncates the string to a maximum length with ellipsis
    func truncated(to maxLength: Int, addEllipsis: Bool = true) -> String {
        guard count > maxLength else { return self }
        let truncated = prefix(maxLength)
        return addEllipsis ? "\(truncated)..." : String(truncated)
    }

    /// Returns the word count
    var wordCount: Int {
        let words = components(separatedBy: .whitespacesAndNewlines)
        return words.filter { !$0.isEmpty }.count
    }

    /// Estimates reading time in seconds based on average reading speed
    func estimatedReadingTime(wordsPerMinute: Int = 150) -> TimeInterval {
        let words = Double(wordCount)
        let minutes = words / Double(wordsPerMinute)
        return minutes * 60
    }
}
