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
}
