import Foundation
import AVFoundation
import os.log

private let audioPlayerLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeechPractice", category: "AudioPlayerService")

/// Service for playing WAV audio data using AVAudioPlayer.
/// Tracks playback duration and handles interruptions.
@MainActor
@Observable
final class AudioPlayerService: NSObject {
    private var audioPlayer: AVAudioPlayer?

    private(set) var isPlaying = false
    private(set) var isPaused = false
    private(set) var audioSessionError: Error?

    private var playbackStartTime: Date?
    private var pausedTime: TimeInterval = 0
    private var onComplete: ((TimeInterval) -> Void)?
    private var onInterrupt: (() -> Void)?

    override init() {
        super.init()
        configureAudioSession()
        observeAudioInterruptions()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            audioSessionError = nil
        } catch {
            audioSessionError = error
            audioPlayerLogger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

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
                if isPlaying && !isPaused {
                    pause()
                    onInterrupt?()
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

    /// Plays the given audio data.
    /// - Parameters:
    ///   - data: WAV audio data to play
    ///   - onComplete: Called when playback finishes with the actual duration
    ///   - onInterrupt: Called when playback is interrupted
    func play(
        data: Data,
        onComplete: @escaping (TimeInterval) -> Void,
        onInterrupt: (() -> Void)? = nil
    ) throws {
        stop()

        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()

        self.onComplete = onComplete
        self.onInterrupt = onInterrupt
        self.playbackStartTime = Date()
        self.pausedTime = 0

        audioPlayer?.play()
        isPlaying = true
        isPaused = false
    }

    func pause() {
        guard isPlaying, !isPaused, let player = audioPlayer else { return }

        // Track how much time has elapsed
        if let startTime = playbackStartTime {
            pausedTime += Date().timeIntervalSince(startTime)
        }

        player.pause()
        isPaused = true
    }

    func resume() {
        guard isPaused, let player = audioPlayer else { return }

        playbackStartTime = Date() // Reset start time for tracking
        player.play()
        isPaused = false
    }

    func stop() {
        let wasPlaying = isPlaying && !isPaused
        let interruptHandler = onInterrupt

        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        isPaused = false
        playbackStartTime = nil
        pausedTime = 0
        onComplete = nil
        onInterrupt = nil

        // Notify caller that playback was interrupted (not completed naturally)
        if wasPlaying {
            interruptHandler?()
        }
    }

    func cleanup() {
        stop()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayerService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            let duration: TimeInterval
            if let startTime = playbackStartTime {
                duration = pausedTime + Date().timeIntervalSince(startTime)
            } else {
                duration = player.duration
            }

            let completionHandler = onComplete

            isPlaying = false
            isPaused = false
            playbackStartTime = nil
            pausedTime = 0
            onComplete = nil
            onInterrupt = nil

            completionHandler?(duration)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            audioPlayerLogger.error("Decode error: \(error?.localizedDescription ?? "unknown")")
            // Treat decode error as completion with 0 duration
            let completionHandler = onComplete

            isPlaying = false
            isPaused = false
            playbackStartTime = nil
            pausedTime = 0
            onComplete = nil
            onInterrupt = nil

            completionHandler?(0)
        }
    }
}
