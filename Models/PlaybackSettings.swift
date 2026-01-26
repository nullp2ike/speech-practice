import Foundation
import AVFoundation

struct PlaybackSettings: Codable, Equatable, Sendable {
    var rate: Float
    var pauseEnabled: Bool
    var pauseGranularity: SegmentType
    var voiceIdentifier: String?

    static let minRate: Float = 0.1
    static let maxRate: Float = 1.0
    static let defaultRate: Float = AVSpeechUtteranceDefaultSpeechRate

    init(
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pauseEnabled: Bool = true,
        pauseGranularity: SegmentType = .sentence,
        voiceIdentifier: String? = nil
    ) {
        self.rate = min(max(rate, Self.minRate), Self.maxRate)
        self.pauseEnabled = pauseEnabled
        self.pauseGranularity = pauseGranularity
        self.voiceIdentifier = voiceIdentifier
    }

    var voice: AVSpeechSynthesisVoice? {
        if let identifier = voiceIdentifier {
            return AVSpeechSynthesisVoice(identifier: identifier)
        }
        return nil
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
