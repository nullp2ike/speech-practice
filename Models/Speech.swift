import Foundation
import SwiftData

@Model
class Speech {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var language: String

    static let maxContentLength = 10_000

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        language: String = "en-US"
    ) {
        self.id = id
        self.title = title
        self.content = String(content.prefix(Self.maxContentLength))
        self.createdAt = Date()
        self.updatedAt = Date()
        self.language = language
    }

    func updateContent(_ newContent: String) {
        content = String(newContent.prefix(Self.maxContentLength))
        updatedAt = Date()
    }

    func updateTitle(_ newTitle: String) {
        title = newTitle
        updatedAt = Date()
    }

    /// Average words per minute for speech duration estimates
    private static let wordsPerMinute = 150.0

    /// Estimated speech duration based on average speaking rate
    var estimatedDuration: TimeInterval {
        let wordCount = content.split(whereSeparator: \.isWhitespace).count
        return Double(wordCount) / Self.wordsPerMinute * 60.0
    }

    /// Formatted estimated duration string (e.g., "2 min", "1 hr 5 min")
    var formattedEstimatedDuration: String {
        let totalSeconds = Int(estimatedDuration)
        guard totalSeconds > 0 else { return "Empty" }

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return minutes > 0 ? "\(hours) hr \(minutes) min" : "\(hours) hr"
        } else if minutes > 0 {
            return seconds > 0 ? "\(minutes) min \(seconds) sec" : "\(minutes) min"
        } else {
            return "\(seconds) sec"
        }
    }
}
