import Foundation
import AVFoundation

/// Factory for creating appropriate speech synthesis services based on language.
@MainActor
enum SpeechServiceFactory {
    /// Creates the appropriate speech service for the given language.
    /// - Parameter language: BCP 47 language code (e.g., "en-US", "et-EE")
    /// - Returns: A speech synthesizing service appropriate for the language
    static func createService(for language: String) -> SpeechSynthesizing {
        if language.lowercased().hasPrefix("et") {
            return EstonianTTSService()
        }
        return SpeechSynthesizerService()
    }

    /// Returns true if the given language uses the Estonian TTS service.
    /// - Parameter language: BCP 47 language code
    /// - Returns: True if Estonian TTS will be used
    static func isEstonianLanguage(_ language: String) -> Bool {
        language.lowercased().hasPrefix("et")
    }

    /// Checks if a voice identifier is valid for the given language.
    /// Estonian uses simple IDs like "mari", while AVSpeech uses full identifiers.
    /// - Parameters:
    ///   - voiceIdentifier: The voice identifier to validate
    ///   - language: BCP 47 language code
    /// - Returns: True if the voice identifier is compatible with the language
    static func isVoiceIdentifierValid(_ voiceIdentifier: String?, for language: String) -> Bool {
        guard let voiceIdentifier = voiceIdentifier else {
            return true // nil is always valid (uses default)
        }

        if isEstonianLanguage(language) {
            // Estonian voices use simple IDs like "mari"
            return EstonianVoice.knownVoiceIds.contains(voiceIdentifier)
        } else {
            // AVSpeech voices use full identifiers like "com.apple.voice.compact.en-US.Samantha"
            // Estonian voice IDs are not valid for AVSpeech
            if EstonianVoice.knownVoiceIds.contains(voiceIdentifier) {
                return false
            }
            // Check if the voice actually exists in the system
            return AVSpeechSynthesisVoice(identifier: voiceIdentifier) != nil
        }
    }
}
