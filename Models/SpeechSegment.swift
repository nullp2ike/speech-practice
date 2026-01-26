import Foundation

struct SpeechSegment: Identifiable, Equatable {
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

enum SegmentType: String, CaseIterable, Codable {
    case sentence
    case paragraph

    var displayName: String {
        switch self {
        case .sentence:
            return "Sentence"
        case .paragraph:
            return "Paragraph"
        }
    }
}
