import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class SpeechEditorViewModel {
    var speech: Speech
    var title: String
    var content: String

    private var modelContext: ModelContext?
    private var hasChanges: Bool {
        title != speech.title || content != speech.content
    }

    var characterCount: Int {
        content.count
    }

    var characterLimit: Int {
        Speech.maxContentLength
    }

    var isAtCharacterLimit: Bool {
        characterCount >= characterLimit
    }

    var characterCountText: String {
        "\(characterCount) / \(characterLimit)"
    }

    init(speech: Speech) {
        self.speech = speech
        self.title = speech.title
        self.content = speech.content
    }

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func save() {
        guard hasChanges else { return }

        speech.updateTitle(title)
        speech.updateContent(content)

        if let modelContext {
            do {
                try modelContext.save()
            } catch {
                print("Failed to save speech: \(error)")
            }
        }

        HapticManager.shared.playLightImpact()
    }

    func updateContent(_ newContent: String) {
        if newContent.count <= characterLimit {
            content = newContent
        } else {
            content = String(newContent.prefix(characterLimit))
            HapticManager.shared.playErrorFeedback()
        }
    }

    func revertChanges() {
        title = speech.title
        content = speech.content
    }
}
