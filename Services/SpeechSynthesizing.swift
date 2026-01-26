import Foundation

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

/// Protocol that defines speech synthesis capabilities.
/// Both AVSpeechSynthesizer-based and TartuNLP-based services implement this protocol.
@MainActor
protocol SpeechSynthesizing: AnyObject {
    /// Whether speech synthesis is currently active
    var isSpeaking: Bool { get }

    /// Whether speech synthesis is paused
    var isPaused: Bool { get }

    /// A user-friendly error message if there's an audio/playback issue
    var audioErrorMessage: String? { get }

    /// Speaks the given text with the specified rate and voice.
    /// - Parameters:
    ///   - text: The text to speak
    ///   - rate: Speech rate (0.1 to 1.0, using AVSpeech scale)
    ///   - voiceIdentifier: Optional voice identifier to use
    ///   - onComplete: Called when speech finishes with the duration
    ///   - onInterrupt: Called when speech is interrupted
    /// - Returns: A cancellation token that can be used to cancel this specific speech operation
    @discardableResult
    func speak(
        _ text: String,
        rate: Float,
        voiceIdentifier: String?,
        onComplete: @escaping (TimeInterval) -> Void,
        onInterrupt: (() -> Void)?
    ) -> SpeechCancellationToken

    /// Pauses the current speech
    func pause()

    /// Resumes paused speech
    func resume()

    /// Stops all speech synthesis
    func stop()

    /// Cancels the speech operation associated with the given token
    func cancel(token: SpeechCancellationToken)

    /// Clears all callbacks and stops synthesis. Call this when the owning view disappears.
    func cleanup()
}
