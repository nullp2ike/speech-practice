import Foundation
import AVFoundation

struct PlaybackSettings: Codable, Equatable, Sendable {
    var rate: Float
    var pauseEnabled: Bool
    var pauseGranularity: SegmentType
    var voiceIdentifier: String?
    var ttsProvider: TTSProvider
    var azureVoicePreference: AzureVoicePreference

    static let minRate: Float = 0.1
    static let maxRate: Float = 1.0
    static let defaultRate: Float = AVSpeechUtteranceDefaultSpeechRate

    init(
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pauseEnabled: Bool = true,
        pauseGranularity: SegmentType = .sentence,
        voiceIdentifier: String? = nil,
        ttsProvider: TTSProvider = .auto,
        azureVoicePreference: AzureVoicePreference = AzureVoicePreference()
    ) {
        self.rate = min(max(rate, Self.minRate), Self.maxRate)
        self.pauseEnabled = pauseEnabled
        self.pauseGranularity = pauseGranularity
        self.voiceIdentifier = voiceIdentifier
        self.ttsProvider = ttsProvider
        self.azureVoicePreference = azureVoicePreference
    }

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
