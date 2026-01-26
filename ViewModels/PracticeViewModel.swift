import Foundation
import SwiftUI
import AVFoundation

@MainActor
@Observable
final class PracticeViewModel {
    // MARK: - State

    private(set) var segments: [SpeechSegment] = []
    private(set) var currentSegmentIndex: Int = 0
    private(set) var isPlaying: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var isInPauseInterval: Bool = false
    private(set) var pauseTimeRemaining: TimeInterval = 0

    var settings: PlaybackSettings {
        didSet {
            settings.save()
        }
    }

    // MARK: - Dependencies

    let speech: Speech
    private let synthesizer: SpeechSynthesizerService
    private let textParser: TextParser

    private var pauseTask: Task<Void, Never>?

    // MARK: - Constants

    private static let pauseUpdateInterval: TimeInterval = 0.1

    // MARK: - Computed Properties

    var currentSegment: SpeechSegment? {
        guard currentSegmentIndex >= 0 && currentSegmentIndex < segments.count else {
            return nil
        }
        return segments[currentSegmentIndex]
    }

    var progress: Double {
        guard !segments.isEmpty else { return 0 }
        return Double(currentSegmentIndex + 1) / Double(segments.count)
    }

    var progressText: String {
        guard !segments.isEmpty else { return "0 / 0" }
        return "\(currentSegmentIndex + 1) / \(segments.count)"
    }

    var canGoBack: Bool {
        currentSegmentIndex > 0
    }

    var canGoForward: Bool {
        currentSegmentIndex < segments.count - 1
    }

    var playPauseIcon: String {
        if isPlaying && !isPaused {
            return "pause.fill"
        }
        return "play.fill"
    }

    // MARK: - Initialization

    init(speech: Speech) {
        self.speech = speech
        self.synthesizer = SpeechSynthesizerService()
        self.textParser = .shared
        self.settings = PlaybackSettings.load()

        parseSegments()
    }

    // MARK: - Setup

    private func parseSegments() {
        segments = textParser.parse(speech.content, granularity: settings.pauseGranularity)
        currentSegmentIndex = 0
    }

    private func syncStateFromSynthesizer() {
        isPlaying = synthesizer.isSpeaking || isInPauseInterval
        isPaused = synthesizer.isPaused
    }

    // MARK: - Playback Controls

    func play() {
        guard let segment = currentSegment else { return }

        HapticManager.shared.playLightImpact()

        synthesizer.speak(
            segment.text,
            rate: settings.rate,
            voice: settings.voice,
            onComplete: { [weak self] duration in
                self?.handleSegmentComplete(duration: duration)
            },
            onInterrupt: { [weak self] in
                self?.handleInterruption()
            }
        )

        isPlaying = true
    }

    private func handleInterruption() {
        isPaused = true
        HapticManager.shared.playLightImpact()
    }

    func pause() {
        cancelPauseInterval()
        synthesizer.pause()
        isPaused = true
        HapticManager.shared.playLightImpact()
    }

    func resume() {
        if isInPauseInterval {
            // Skip remaining pause and continue to next segment
            cancelPauseInterval()
            moveToNextSegmentAndPlay()
        } else {
            synthesizer.resume()
            isPaused = false
        }
        HapticManager.shared.playLightImpact()
    }

    func stop() {
        cancelPauseInterval()
        synthesizer.stop()
        isPlaying = false
        isPaused = false
        HapticManager.shared.playLightImpact()
    }

    func togglePlayPause() {
        if isPlaying {
            if isPaused || isInPauseInterval {
                resume()
            } else {
                pause()
            }
        } else {
            play()
        }
    }

    // MARK: - Navigation

    func goToNextSegment() {
        guard canGoForward else { return }
        cancelPauseInterval()
        synthesizer.stop()
        currentSegmentIndex += 1
        HapticManager.shared.playNavigationFeedback()

        if isPlaying {
            play()
        }
    }

    func goToPreviousSegment() {
        guard canGoBack else { return }
        cancelPauseInterval()
        synthesizer.stop()
        currentSegmentIndex -= 1
        HapticManager.shared.playNavigationFeedback()

        if isPlaying {
            play()
        }
    }

    func goToSegment(at index: Int) {
        guard index >= 0 && index < segments.count else { return }
        cancelPauseInterval()
        synthesizer.stop()
        currentSegmentIndex = index
        HapticManager.shared.playSelectionFeedback()

        if isPlaying {
            play()
        }
    }

    func restart() {
        stop()
        currentSegmentIndex = 0
        HapticManager.shared.playNavigationFeedback()
    }

    // MARK: - Settings

    func updateRate(_ rate: Float) {
        settings.setRate(rate)
        settings.save()
    }

    func updatePauseEnabled(_ enabled: Bool) {
        settings.pauseEnabled = enabled
        settings.save()
    }

    func updatePauseGranularity(_ granularity: SegmentType) {
        let wasPlaying = isPlaying
        stop()

        settings.pauseGranularity = granularity
        settings.save()

        parseSegments()

        if wasPlaying {
            play()
        }
    }

    func updateVoice(_ voiceIdentifier: String?) {
        settings.voiceIdentifier = voiceIdentifier
        settings.save()
    }

    // MARK: - Private Helpers

    private func handleSegmentComplete(duration: TimeInterval) {
        HapticManager.shared.playSegmentCompleteFeedback()

        if settings.pauseEnabled {
            startPauseInterval(duration: duration)
        } else {
            moveToNextSegmentAndPlay()
        }
    }

    private func startPauseInterval(duration: TimeInterval) {
        isInPauseInterval = true
        pauseTimeRemaining = duration

        // Capture all values at task creation to avoid race conditions
        let updateInterval = Self.pauseUpdateInterval
        let totalDuration = duration
        let steps = Int(totalDuration / updateInterval)

        pauseTask = Task { [weak self] in
            for i in 0..<steps {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(Int(updateInterval * 1000)))

                await MainActor.run {
                    guard let self = self, !Task.isCancelled else { return }
                    self.pauseTimeRemaining = totalDuration - (Double(i + 1) * updateInterval)
                }
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self = self else { return }
                self.isInPauseInterval = false
                self.pauseTimeRemaining = 0
                self.moveToNextSegmentAndPlay()
            }
        }
    }

    private func cancelPauseInterval() {
        pauseTask?.cancel()
        pauseTask = nil
        isInPauseInterval = false
        pauseTimeRemaining = 0
    }

    private func moveToNextSegmentAndPlay() {
        if canGoForward {
            currentSegmentIndex += 1
            play()
        } else {
            // Reached the end
            isPlaying = false
            HapticManager.shared.playHeavyImpact()
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        cancelPauseInterval()
        synthesizer.cleanup()
        isPlaying = false
        isPaused = false
    }
}
