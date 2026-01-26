import Foundation
import AVFoundation
import Combine

@MainActor
final class SpeechSynthesizerService: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentUtteranceProgress: Double = 0

    private var segmentStartTime: Date?
    private var onSegmentComplete: ((TimeInterval) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    /// Clears all callbacks and stops synthesis. Call this when the owning view disappears.
    func cleanup() {
        stop()
        onSegmentComplete = nil
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    func speak(
        _ text: String,
        rate: Float,
        voice: AVSpeechSynthesisVoice?,
        onComplete: @escaping (TimeInterval) -> Void
    ) {
        stop()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        segmentStartTime = Date()
        onSegmentComplete = onComplete

        synthesizer.speak(utterance)
        isSpeaking = true
        isPaused = false
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .immediate)
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        currentUtteranceProgress = 0
        segmentStartTime = nil
        onSegmentComplete = nil
    }

    func togglePlayPause() {
        if isPaused {
            resume()
        } else if isSpeaking {
            pause()
        }
    }

    // MARK: - Voice Selection

    static func availableVoices(for language: String? = nil) -> [AVSpeechSynthesisVoice] {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()

        if let language = language {
            return allVoices.filter { $0.language.hasPrefix(language.prefix(2)) }
        }

        return allVoices
    }

    static func defaultVoice(for language: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: language)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechSynthesizerService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            isSpeaking = true
            isPaused = false
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            let duration: TimeInterval
            if let startTime = segmentStartTime {
                duration = Date().timeIntervalSince(startTime)
            } else {
                duration = 0
            }

            isSpeaking = false
            isPaused = false
            currentUtteranceProgress = 0

            onSegmentComplete?(duration)
            onSegmentComplete = nil
            segmentStartTime = nil
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didPause utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            isPaused = true
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didContinue utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            isPaused = false
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            isSpeaking = false
            isPaused = false
            currentUtteranceProgress = 0
            onSegmentComplete = nil
            segmentStartTime = nil
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            let totalLength = utterance.speechString.count
            guard totalLength > 0 else { return }
            let progress = Double(characterRange.location + characterRange.length) / Double(totalLength)
            currentUtteranceProgress = progress
        }
    }
}
