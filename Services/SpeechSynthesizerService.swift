import Foundation
import AVFoundation
import ObjectiveC

// MARK: - Utterance Token Association

private var utteranceTokenKey: UInt8 = 0

private extension AVSpeechUtterance {
    /// Associates a cancellation token with this utterance for later verification
    var associatedToken: SpeechCancellationToken? {
        get {
            objc_getAssociatedObject(self, &utteranceTokenKey) as? SpeechCancellationToken
        }
        set {
            objc_setAssociatedObject(self, &utteranceTokenKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

// MARK: - Speech Cancellation Token

/// A token that allows cancellation of a speech synthesis operation.
/// The token can be checked for cancellation status and cancelled from outside the service.
final class SpeechCancellationToken: @unchecked Sendable {
    private var _isCancelled = false
    private let lock = NSLock()

    var isCancelled: Bool {
        lock.withLock { _isCancelled }
    }

    func cancel() {
        lock.withLock { _isCancelled = true }
    }
}

@MainActor
@Observable
final class SpeechSynthesizerService: NSObject {
    private let synthesizer = AVSpeechSynthesizer()

    private(set) var isSpeaking = false
    private(set) var isPaused = false
    private(set) var currentUtteranceProgress: Double = 0
    private(set) var audioSessionError: Error?

    private var segmentStartTime: Date?
    private var onSegmentComplete: ((TimeInterval) -> Void)?
    private var onInterruption: (() -> Void)?
    private var currentCancellationToken: SpeechCancellationToken?
    /// Token that was active when the current callbacks were registered.
    /// Used to verify that didFinish callbacks match the current speech operation.
    private var callbackToken: SpeechCancellationToken?

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
        observeAudioInterruptions()
    }

    /// Clears all callbacks and stops synthesis. Call this when the owning view disappears.
    func cleanup() {
        currentCancellationToken?.cancel()
        currentCancellationToken = nil
        callbackToken = nil
        stop()
        onSegmentComplete = nil
        onInterruption = nil
        NotificationCenter.default.removeObserver(self)
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            audioSessionError = nil
        } catch {
            audioSessionError = error
            print("Failed to configure audio session: \(error)")
        }
    }

    /// Returns a user-friendly message if there's an audio session error.
    var audioErrorMessage: String? {
        guard let error = audioSessionError else { return nil }
        return "Audio playback may not work properly: \(error.localizedDescription)"
    }

    private func observeAudioInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        Task { @MainActor in
            switch type {
            case .began:
                if isSpeaking && !isPaused {
                    pause()
                    onInterruption?()
                }
            case .ended:
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) && isPaused {
                        resume()
                    }
                }
            @unknown default:
                break
            }
        }
    }

    /// Speaks the given text with the specified rate and voice.
    /// - Parameters:
    ///   - text: The text to speak
    ///   - rate: Speech rate (0.1 to 1.0)
    ///   - voice: Optional voice to use
    ///   - onComplete: Called when speech finishes with the duration
    ///   - onInterrupt: Called when speech is interrupted
    /// - Returns: A cancellation token that can be used to cancel this specific speech operation
    @discardableResult
    func speak(
        _ text: String,
        rate: Float,
        voice: AVSpeechSynthesisVoice?,
        onComplete: @escaping (TimeInterval) -> Void,
        onInterrupt: (() -> Void)? = nil
    ) -> SpeechCancellationToken {
        stop()

        let token = SpeechCancellationToken()
        currentCancellationToken = token

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.associatedToken = token

        segmentStartTime = Date()
        onSegmentComplete = onComplete
        onInterruption = onInterrupt
        callbackToken = token

        synthesizer.speak(utterance)
        isSpeaking = true
        isPaused = false

        return token
    }

    /// Cancels the speech operation associated with the given token.
    /// If the token matches the current operation, the speech is stopped and callbacks are not called.
    func cancel(token: SpeechCancellationToken) {
        token.cancel()
        if currentCancellationToken === token {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            isPaused = false
            currentUtteranceProgress = 0
            segmentStartTime = nil
            onSegmentComplete = nil
            onInterruption = nil
            currentCancellationToken = nil
            callbackToken = nil
        }
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
        currentCancellationToken?.cancel()
        currentCancellationToken = nil
        callbackToken = nil
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
        // Capture the token associated with THIS utterance before entering async context
        let utteranceToken = utterance.associatedToken

        Task { @MainActor in
            // Verify this callback matches the current speech operation.
            // Race condition fix: When navigation happens during speech:
            // 1. Old speech is cancelled, new speech starts with new token
            // 2. Old didFinish callback may still fire (was already queued)
            // 3. By checking that the utterance's token matches callbackToken,
            //    we ensure old callbacks don't trigger new callback handlers
            guard let utteranceToken = utteranceToken,
                  let activeCallbackToken = callbackToken,
                  utteranceToken === activeCallbackToken,
                  !utteranceToken.isCancelled else {
                // This callback belongs to a cancelled/replaced speech operation
                // State will be managed by the new operation or cancel handler
                return
            }

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
            currentCancellationToken = nil
            callbackToken = nil
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
            currentCancellationToken = nil
            callbackToken = nil
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
