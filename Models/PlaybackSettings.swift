import Foundation
import AVFoundation

struct PlaybackSettings: Equatable, Sendable {
    var rate: Float
    var pauseEnabled: Bool
    var pauseGranularity: SegmentType
    var voiceIdentifier: String?
    var ttsProvider: TTSProvider
    var azureVoicePreference: AzureVoicePreference
    /// Whether the user has explicitly selected a provider (vs using language default).
    var hasUserSelectedProvider: Bool

    static let minRate: Float = 0.1
    static let maxRate: Float = 1.0
    static let defaultRate: Float = AVSpeechUtteranceDefaultSpeechRate

    init(
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pauseEnabled: Bool = true,
        pauseGranularity: SegmentType = .sentence,
        voiceIdentifier: String? = nil,
        ttsProvider: TTSProvider = .ios,
        azureVoicePreference: AzureVoicePreference = AzureVoicePreference(),
        hasUserSelectedProvider: Bool = false
    ) {
        self.rate = min(max(rate, Self.minRate), Self.maxRate)
        self.pauseEnabled = pauseEnabled
        self.pauseGranularity = pauseGranularity
        self.voiceIdentifier = voiceIdentifier
        self.ttsProvider = ttsProvider
        self.azureVoicePreference = azureVoicePreference
        self.hasUserSelectedProvider = hasUserSelectedProvider
    }

    /// Returns the default provider for a given language.
    /// Estonian defaults to TartuNLP, others default to iOS.
    static func defaultProvider(for language: String) -> TTSProvider {
        TTSProvider.isEstonianLanguage(language) ? .tartuNLP : .ios
    }
}

// MARK: - Codable (with migration support)

extension PlaybackSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case rate, pauseEnabled, pauseGranularity, voiceIdentifier
        case ttsProvider, azureVoicePreference, hasUserSelectedProvider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRate = try container.decode(Float.self, forKey: .rate)
        self.rate = min(max(decodedRate, Self.minRate), Self.maxRate)
        self.pauseEnabled = try container.decode(Bool.self, forKey: .pauseEnabled)
        self.pauseGranularity = try container.decode(SegmentType.self, forKey: .pauseGranularity)
        self.voiceIdentifier = try container.decodeIfPresent(String.self, forKey: .voiceIdentifier)
        self.ttsProvider = try container.decode(TTSProvider.self, forKey: .ttsProvider)
        self.azureVoicePreference = try container.decodeIfPresent(AzureVoicePreference.self, forKey: .azureVoicePreference) ?? AzureVoicePreference()

        // Migration: older settings won't have this field.
        // If missing and provider is not .auto, treat as user-selected to preserve their choice.
        if let hasSelected = try container.decodeIfPresent(Bool.self, forKey: .hasUserSelectedProvider) {
            self.hasUserSelectedProvider = hasSelected
        } else {
            // Migration from old settings: if they had a specific provider (not .auto),
            // consider it user-selected to preserve their choice
            self.hasUserSelectedProvider = (ttsProvider != .auto)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rate, forKey: .rate)
        try container.encode(pauseEnabled, forKey: .pauseEnabled)
        try container.encode(pauseGranularity, forKey: .pauseGranularity)
        try container.encodeIfPresent(voiceIdentifier, forKey: .voiceIdentifier)
        try container.encode(ttsProvider, forKey: .ttsProvider)
        try container.encode(azureVoicePreference, forKey: .azureVoicePreference)
        try container.encode(hasUserSelectedProvider, forKey: .hasUserSelectedProvider)
    }
}

// MARK: - Voice Helpers

extension PlaybackSettings {
    var voice: AVSpeechSynthesisVoice? {
        if let identifier = voiceIdentifier {
            // Validate the voice identifier - it may become invalid if the voice is uninstalled
            if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
                return voice
            }
            // Voice not found - identifier is stale, return nil to use system default
            return nil
        }
        return nil
    }

    /// Returns true if the stored voice identifier is valid and available on the device.
    var isVoiceIdentifierValid: Bool {
        guard let identifier = voiceIdentifier else { return true }
        return AVSpeechSynthesisVoice(identifier: identifier) != nil
    }

    /// Clears the voice identifier if it's no longer valid (voice was uninstalled).
    mutating func validateAndClearInvalidVoice() {
        if let identifier = voiceIdentifier,
           AVSpeechSynthesisVoice(identifier: identifier) == nil {
            voiceIdentifier = nil
        }
    }

    mutating func setRate(_ newRate: Float) {
        rate = min(max(newRate, Self.minRate), Self.maxRate)
    }
}

// MARK: - Persistence

extension PlaybackSettings {
    private static let userDefaultsKey = "PlaybackSettings"

    static func load() -> PlaybackSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(PlaybackSettings.self, from: data) else {
            return PlaybackSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
