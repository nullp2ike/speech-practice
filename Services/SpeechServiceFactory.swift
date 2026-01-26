import Foundation
import AVFoundation

/// Factory for creating appropriate speech synthesis services based on language and provider.
@MainActor
enum SpeechServiceFactory {
    /// Creates the appropriate speech service for the given language using the default provider.
    /// - Parameter language: BCP 47 language code (e.g., "en-US", "et-EE")
    /// - Returns: A speech synthesizing service appropriate for the language
    static func createService(for language: String) -> SpeechSynthesizing {
        createService(for: language, provider: PlaybackSettings.defaultProvider(for: language))
    }

    /// Creates the appropriate speech service for the given language and provider.
    /// - Parameters:
    ///   - language: BCP 47 language code (e.g., "en-US", "et-EE")
    ///   - provider: The TTS provider to use
    /// - Returns: A speech synthesizing service for the specified provider
    static func createService(for language: String, provider: TTSProvider) -> SpeechSynthesizing {
        switch provider {
        case .auto:
            // Deprecated: treat as language default for migration
            return createService(for: language, provider: PlaybackSettings.defaultProvider(for: language))

        case .tartuNLP:
            // TartuNLP only works for Estonian; fall back to iOS for other languages
            if TTSProvider.isEstonianLanguage(language) {
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

    /// Determines the effective provider to use, considering credentials availability and language.
    /// - Parameters:
    ///   - provider: The requested TTS provider
    ///   - language: The speech language
    ///   - hasAzureCredentials: Whether Azure credentials are configured
    /// - Returns: The effective provider (may differ based on constraints)
    static func effectiveProvider(_ provider: TTSProvider, language: String, hasAzureCredentials: Bool) -> TTSProvider {
        switch provider {
        case .auto:
            // Migrate deprecated .auto to language default
            return PlaybackSettings.defaultProvider(for: language)
        case .microsoft:
            // Fall back to language default if Microsoft is selected but not configured
            return hasAzureCredentials ? .microsoft : PlaybackSettings.defaultProvider(for: language)
        default:
            return provider
        }
    }

    /// Legacy overload for backwards compatibility (assumes non-Estonian language).
    static func effectiveProvider(_ provider: TTSProvider, hasAzureCredentials: Bool) -> TTSProvider {
        effectiveProvider(provider, language: "en-US", hasAzureCredentials: hasAzureCredentials)
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
        provider: TTSProvider = .ios
    ) -> Bool {
        guard let voiceIdentifier = voiceIdentifier else {
            return true // nil is always valid (uses default)
        }

        switch provider {
        case .auto:
            // Deprecated: treat as language default
            return isVoiceIdentifierValid(
                voiceIdentifier,
                for: language,
                provider: PlaybackSettings.defaultProvider(for: language)
            )

        case .tartuNLP:
            if TTSProvider.isEstonianLanguage(language) {
                // Estonian voices use simple IDs like "mari"
                return EstonianVoice.knownVoiceIds.contains(voiceIdentifier)
            } else {
                // TartuNLP for non-Estonian falls back to iOS, so check iOS voices
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
            // Azure voice identifiers contain locale format like "en-US-JennyNeural"
            return voiceIdentifier.contains("-")
        }
    }
}
