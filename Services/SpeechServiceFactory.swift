import Foundation
import AVFoundation

/// Factory for creating appropriate speech synthesis services based on language and provider.
@MainActor
enum SpeechServiceFactory {
    /// Creates the appropriate speech service for the given language using auto provider selection.
    /// - Parameter language: BCP 47 language code (e.g., "en-US", "et-EE")
    /// - Returns: A speech synthesizing service appropriate for the language
    static func createService(for language: String) -> SpeechSynthesizing {
        createService(for: language, provider: .auto)
    }

    /// Creates the appropriate speech service for the given language and provider.
    /// - Parameters:
    ///   - language: BCP 47 language code (e.g., "en-US", "et-EE")
    ///   - provider: The TTS provider to use
    /// - Returns: A speech synthesizing service for the specified provider
    static func createService(for language: String, provider: TTSProvider) -> SpeechSynthesizing {
        switch provider {
        case .auto:
            // Auto mode: Estonian uses TartuNLP, others use iOS
            if isEstonianLanguage(language) {
                return EstonianTTSService()
            }
            return SpeechSynthesizerService()

        case .ios:
            // Always use iOS AVSpeech
            return SpeechSynthesizerService()

        case .microsoft:
            // Use Microsoft Azure TTS
            let service = MicrosoftTTSService()
            service.language = language
            return service
        }
    }

    /// Determines the effective provider to use, considering credentials availability.
    /// - Parameters:
    ///   - provider: The requested TTS provider
    ///   - hasAzureCredentials: Whether Azure credentials are configured
    /// - Returns: The effective provider (may differ if Microsoft is selected but not configured)
    static func effectiveProvider(_ provider: TTSProvider, hasAzureCredentials: Bool) -> TTSProvider {
        switch provider {
        case .microsoft:
            // Fall back to auto if Microsoft is selected but not configured
            return hasAzureCredentials ? .microsoft : .auto
        default:
            return provider
        }
    }

    /// Returns true if the given language uses the Estonian TTS service with auto provider.
    /// - Parameter language: BCP 47 language code
    /// - Returns: True if Estonian TTS will be used
    static func isEstonianLanguage(_ language: String) -> Bool {
        language.lowercased().hasPrefix("et")
    }

    /// Checks if a voice identifier is valid for the given language and provider.
    /// - Parameters:
    ///   - voiceIdentifier: The voice identifier to validate
    ///   - language: BCP 47 language code
    ///   - provider: The TTS provider being used
    /// - Returns: True if the voice identifier is compatible
    static func isVoiceIdentifierValid(
        _ voiceIdentifier: String?,
        for language: String,
        provider: TTSProvider = .auto
    ) -> Bool {
        guard let voiceIdentifier = voiceIdentifier else {
            return true // nil is always valid (uses default)
        }

        switch provider {
        case .auto:
            if isEstonianLanguage(language) {
                // Estonian voices use simple IDs like "mari"
                return EstonianVoice.knownVoiceIds.contains(voiceIdentifier)
            } else {
                // AVSpeech voices use full identifiers
                if EstonianVoice.knownVoiceIds.contains(voiceIdentifier) {
                    return false
                }
                return AVSpeechSynthesisVoice(identifier: voiceIdentifier) != nil
            }

        case .ios:
            // AVSpeech voices only
            if EstonianVoice.knownVoiceIds.contains(voiceIdentifier) {
                return false
            }
            return AVSpeechSynthesisVoice(identifier: voiceIdentifier) != nil

        case .microsoft:
            // Azure voices use shortName format like "en-US-JennyNeural"
            // Estonian and AVSpeech voices are not valid for Azure
            if EstonianVoice.knownVoiceIds.contains(voiceIdentifier) {
                return false
            }
            if AVSpeechSynthesisVoice(identifier: voiceIdentifier) != nil {
                return false
            }
            // Azure voice identifiers contain a dash and typically end with "Neural"
            return voiceIdentifier.contains("-") && voiceIdentifier.contains("-")
        }
    }
}
