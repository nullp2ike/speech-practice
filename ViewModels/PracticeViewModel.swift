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

    /// Error message to display when playback fails (e.g., network issues for Estonian TTS).
    private(set) var playbackError: String?

    // MARK: - Dependencies

    let speech: Speech
    private var synthesizer: SpeechSynthesizing
    private let textParser: TextParser

    private var pauseTask: Task<Void, Never>?
    private var currentSpeechToken: SpeechCancellationToken?

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

    /// The effective TTS provider being used (accounts for credential availability).
    var effectiveProvider: TTSProvider {
        SpeechServiceFactory.effectiveProvider(
            settings.ttsProvider,
            hasAzureCredentials: KeychainService.hasAzureCredentials()
        )
    }

    /// Returns true if the speech uses Estonian TTS (requires network).
    var usesEstonianTTS: Bool {
        effectiveProvider == .auto && SpeechServiceFactory.isEstonianLanguage(speech.language)
    }

    /// Returns true if the speech uses Microsoft Azure TTS.
    var usesMicrosoftTTS: Bool {
        effectiveProvider == .microsoft
    }

    /// Returns the Estonian TTS service if being used, nil otherwise.
    var estonianTTSService: EstonianTTSService? {
        synthesizer as? EstonianTTSService
    }

    /// Returns the Microsoft TTS service if being used, nil otherwise.
    var microsoftTTSService: MicrosoftTTSService? {
        synthesizer as? MicrosoftTTSService
    }

    // MARK: - Initialization

    init(speech: Speech) {
        self.speech = speech
        self.textParser = .shared

        // Load settings first to get provider preference
        let loadedSettings = PlaybackSettings.load()

        // Determine the effective provider
        let provider = SpeechServiceFactory.effectiveProvider(
            loadedSettings.ttsProvider,
            hasAzureCredentials: KeychainService.hasAzureCredentials()
        )

        // Create the appropriate synthesizer
        let createdSynthesizer = SpeechServiceFactory.createService(for: speech.language, provider: provider)

        // Now initialize stored properties
        self.settings = loadedSettings
        self.synthesizer = createdSynthesizer

        // Configure Microsoft TTS service if used
        if let microsoftService = synthesizer as? MicrosoftTTSService {
            microsoftService.language = speech.language
            microsoftService.preferredVoice = settings.azureVoicePreference.voice(for: speech.language)
        }

        // Clear voice identifier if it's incompatible with the current language/provider
        if !SpeechServiceFactory.isVoiceIdentifierValid(
            settings.voiceIdentifier,
            for: speech.language,
            provider: provider
        ) {
            settings.voiceIdentifier = nil
        }

        parseSegments()
    }

    // MARK: - Setup

    private func parseSegments() {
        segments = textParser.parse(speech.content, granularity: settings.pauseGranularity)
        currentSegmentIndex = 0
    }

    // MARK: - Playback Controls

    func play() {
        guard let segment = currentSegment else { return }

        HapticManager.shared.playLightImpact()

        // Clear any previous playback error
        playbackError = nil

        // Determine voice identifier based on provider
        let voiceIdentifier: String?
        if usesMicrosoftTTS {
            voiceIdentifier = settings.azureVoicePreference.voice(for: speech.language) ?? settings.voiceIdentifier
        } else {
            voiceIdentifier = settings.voiceIdentifier
        }

        currentSpeechToken = synthesizer.speak(
            segment.text,
            rate: settings.rate,
            voiceIdentifier: voiceIdentifier,
            onComplete: { [weak self] duration in
                guard let self = self else { return }
                // Check for errors from the synthesizer (handles async TTS errors)
                if duration == 0, let errorMessage = self.synthesizer.audioErrorMessage {
                    self.playbackError = errorMessage
                    self.isPlaying = false
                    return
                }
                self.handleSegmentComplete(duration: duration)
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
        cancelCurrentSpeech()
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
        navigateToSegment(currentSegmentIndex + 1)
    }

    func goToPreviousSegment() {
        guard canGoBack else { return }
        navigateToSegment(currentSegmentIndex - 1)
    }

    func goToSegment(at index: Int) {
        guard index >= 0 && index < segments.count else { return }
        navigateToSegment(index, hapticStyle: .selection)
    }

    private func navigateToSegment(_ index: Int, hapticStyle: HapticStyle = .navigation) {
        cancelPauseInterval()
        cancelCurrentSpeech()
        currentSegmentIndex = index

        switch hapticStyle {
        case .navigation:
            HapticManager.shared.playNavigationFeedback()
        case .selection:
            HapticManager.shared.playSelectionFeedback()
        }

        if isPlaying {
            play()
        }
    }

    private enum HapticStyle {
        case navigation
        case selection
    }

    /// Cancels the current speech operation using the cancellation token
    private func cancelCurrentSpeech() {
        if let token = currentSpeechToken {
            synthesizer.cancel(token: token)
            currentSpeechToken = nil
        } else {
            synthesizer.stop()
        }
    }

    func restart() {
        stop()
        currentSegmentIndex = 0
        HapticManager.shared.playNavigationFeedback()
    }

    func goToBeginning() {
        guard canGoBack else { return }
        navigateToSegment(0)
    }

    func goToEnd() {
        guard canGoForward else { return }
        navigateToSegment(segments.count - 1)
    }

    // MARK: - Settings

    func updateRate(_ rate: Float) {
        settings.setRate(rate)
        // didSet on settings handles save()
    }

    func updatePauseEnabled(_ enabled: Bool) {
        settings.pauseEnabled = enabled
        // didSet on settings handles save()
    }

    func updatePauseGranularity(_ granularity: SegmentType) {
        let wasPlaying = isPlaying
        stop()

        // Capture the current text position before re-parsing
        let currentTextPosition = currentSegment?.range.lowerBound

        settings.pauseGranularity = granularity
        // didSet on settings handles save()

        parseSegments()

        // Restore position by finding the segment that contains the previous position
        if let position = currentTextPosition {
            currentSegmentIndex = findSegmentIndex(containing: position) ?? 0
        }

        if wasPlaying {
            play()
        }
    }

    /// Finds the segment index that contains the given text position.
    private func findSegmentIndex(containing position: String.Index) -> Int? {
        for (index, segment) in segments.enumerated() {
            if segment.range.contains(position) || segment.range.lowerBound >= position {
                return index
            }
        }
        // If position is past all segments, return the last segment
        return segments.isEmpty ? nil : segments.count - 1
    }

    func updateVoice(_ voiceIdentifier: String?) {
        settings.voiceIdentifier = voiceIdentifier
        // didSet on settings handles save()
    }

    /// Updates the Azure voice preference for the current language.
    func updateAzureVoice(_ voiceShortName: String?) {
        settings.azureVoicePreference.setVoice(voiceShortName, for: speech.language)
        // Update the Microsoft TTS service if active
        if let microsoftService = microsoftTTSService {
            microsoftService.preferredVoice = voiceShortName
        }
        // didSet on settings handles save()
    }

    /// Updates the TTS provider and recreates the synthesizer.
    func updateTTSProvider(_ provider: TTSProvider) {
        let wasPlaying = isPlaying
        stop()

        settings.ttsProvider = provider
        // didSet on settings handles save()

        // Recreate the synthesizer with the new provider
        let effectiveProvider = SpeechServiceFactory.effectiveProvider(
            provider,
            hasAzureCredentials: KeychainService.hasAzureCredentials()
        )
        synthesizer = SpeechServiceFactory.createService(for: speech.language, provider: effectiveProvider)

        // Configure Microsoft TTS service if used
        if let microsoftService = synthesizer as? MicrosoftTTSService {
            microsoftService.language = speech.language
            microsoftService.preferredVoice = settings.azureVoicePreference.voice(for: speech.language)
        }

        // Clear voice identifier if incompatible with new provider
        if !SpeechServiceFactory.isVoiceIdentifierValid(
            settings.voiceIdentifier,
            for: speech.language,
            provider: effectiveProvider
        ) {
            settings.voiceIdentifier = nil
        }

        if wasPlaying {
            play()
        }
    }

    /// Refreshes Azure credentials and updates the synthesizer if using Microsoft TTS.
    func refreshAzureCredentials() {
        if let microsoftService = microsoftTTSService {
            microsoftService.refreshCredentials()
        } else if settings.ttsProvider == .microsoft && KeychainService.hasAzureCredentials() {
            // If Microsoft provider is selected and credentials are now available,
            // recreate the synthesizer
            updateTTSProvider(.microsoft)
        }
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

        // Capture values at task creation to avoid race conditions
        let updateInterval = Self.pauseUpdateInterval
        let totalDuration = duration
        let startTime = Date()

        pauseTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(updateInterval * 1000)))
                guard !Task.isCancelled else { return }

                // Calculate remaining time based on elapsed time from start for accuracy
                let elapsed = Date().timeIntervalSince(startTime)
                let remaining = totalDuration - elapsed

                if remaining <= 0 {
                    await MainActor.run {
                        guard let self = self else { return }
                        self.isInPauseInterval = false
                        self.pauseTimeRemaining = 0
                        self.moveToNextSegmentAndPlay()
                    }
                    return
                }

                await MainActor.run {
                    guard let self = self, !Task.isCancelled else { return }
                    self.pauseTimeRemaining = remaining
                }
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
        currentSpeechToken?.cancel()
        currentSpeechToken = nil
        synthesizer.cleanup()
        isPlaying = false
        isPaused = false
    }
}
