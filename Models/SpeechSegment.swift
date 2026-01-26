import Foundation

struct SpeechSegment: Identifiable, Equatable, @unchecked Sendable {
    // Note: @unchecked is required because Range<String.Index> isn't Sendable,
    // but this struct is safe to send across concurrency domains since all
    // properties are immutable (let) and never mutated after initialization.
    let id: UUID
    let text: String
    let range: Range<String.Index>
    let type: SegmentType

    init(id: UUID = UUID(), text: String, range: Range<String.Index>, type: SegmentType) {
        self.id = id
        self.text = text
        self.range = range
        self.type = type
    }

    static func == (lhs: SpeechSegment, rhs: SpeechSegment) -> Bool {
        lhs.id == rhs.id
    }
}

enum SegmentType: String, CaseIterable, Codable, Sendable {
    case sentence
    case paragraph

    var displayName: String {
        switch self {
        case .sentence:
            return String(localized: "Sentence")
        case .paragraph:
            return String(localized: "Paragraph")
        }
    }
}
