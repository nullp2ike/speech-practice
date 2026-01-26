import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class SpeechEditorViewModel {
    var speech: Speech
    var title: String
    var content: String
    var language: String

    private var modelContext: ModelContext?
    private var languageDetectionTask: Task<Void, Never>?
    private var hasChanges: Bool {
        title != speech.title || content != speech.content || language != speech.language
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
        self.language = speech.language
    }

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func save() {
        guard hasChanges else { return }

        speech.updateTitle(title)
        speech.updateContent(content)
        speech.language = language

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

        // Debounced language detection
        languageDetectionTask?.cancel()
        languageDetectionTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            // Need enough text for reliable detection
            guard content.count >= 20 else { return }

            if let detectedLanguage = TextParser.shared.detectLanguage(content),
               detectedLanguage != language {
                language = detectedLanguage
            }
        }
    }

    func revertChanges() {
        title = speech.title
        content = speech.content
        language = speech.language
    }
}
