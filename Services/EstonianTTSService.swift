import Foundation

/// TTS service for Estonian language using the TartuNLP API.
/// Implements the SpeechSynthesizing protocol for interoperability with the existing speech system.
@MainActor
@Observable
final class EstonianTTSService: SpeechSynthesizing {
    private let client = TartuNLPClient()
    private let audioPlayer = AudioPlayerService()

    private(set) var isSpeaking = false
    private(set) var isPaused = false
    /// Error message from TTS synthesis (API errors, network issues, etc.)
    private(set) var synthesisError: String?

    private var currentToken: SpeechCancellationToken?
    private var synthesisTask: Task<Void, Never>?

    /// In-memory cache for synthesized audio segments.
    /// Key: "\(text)_\(speaker)_\(speed)"
    private var audioCache: [String: CacheEntry] = [:]
    private var currentCacheSize: Int = 0
    private static let maxCacheEntries = 50
    /// Maximum cache size in bytes (10MB)
    private static let maxCacheSizeBytes = 10 * 1024 * 1024

    /// Cache entry with timestamp for LRU eviction.
    private struct CacheEntry {
        let data: Data
        var lastAccessTime: Date
    }

    // MARK: - Available Voices

    /// Cached Estonian voices from the API.
    private(set) var availableVoices: [EstonianVoice] = []

    /// Whether voices are currently being loaded.
    private(set) var isLoadingVoices = false

    /// Error message from loading voices, if any.
    private(set) var voicesLoadError: String?

    /// Fetches available Estonian voices from the TartuNLP API.
    func loadAvailableVoices() async {
        guard !isLoadingVoices else { return }

        isLoadingVoices = true
        voicesLoadError = nil

        do {
            availableVoices = try await client.fetchAvailableVoices()
        } catch is CancellationError {
            // Task was cancelled (e.g., view disappeared) - don't treat as error
            isLoadingVoices = false
            return
        } catch let error as TartuNLPError {
            // Check if the underlying error is a URL cancellation
            if case .networkError(let underlyingError) = error,
               (underlyingError as? URLError)?.code == .cancelled {
                // Request was cancelled - don't show error to user
                isLoadingVoices = false
                return
            }
            voicesLoadError = error.localizedDescription
            // Use default voices on error
            availableVoices = EstonianVoice.defaultVoices
        } catch {
            voicesLoadError = error.localizedDescription
            // Use default voices on error
            availableVoices = EstonianVoice.defaultVoices
        }

        isLoadingVoices = false
    }

    // MARK: - SpeechSynthesizing Protocol

    var audioErrorMessage: String? {
        synthesisError ?? audioPlayer.audioErrorMessage
    }

    @discardableResult
    func speak(
        _ text: String,
        rate: Float,
        voiceIdentifier: String?,
        onComplete: @escaping (TimeInterval) -> Void,
        onInterrupt: (() -> Void)? = nil
    ) -> SpeechCancellationToken {
        stop()

        let token = SpeechCancellationToken()
        currentToken = token
        synthesisError = nil

        let speaker = voiceIdentifier ?? EstonianVoice.defaultVoice.id
        let speed = TartuNLPClient.mapRateToSpeed(rate)

        isSpeaking = true
        isPaused = false

        synthesisTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                // Check cache first
                let cacheKey = self.makeCacheKey(text: text, speaker: speaker, speed: speed)
                let audioData: Data

                if var cachedEntry = self.audioCache[cacheKey] {
                    // Update last access time for LRU tracking
                    cachedEntry.lastAccessTime = Date()
                    self.audioCache[cacheKey] = cachedEntry
                    audioData = cachedEntry.data
                } else {
                    // Synthesize via API
                    guard !token.isCancelled else { return }
                    audioData = try await self.client.synthesize(text: text, speaker: speaker, speed: speed)

                    guard !token.isCancelled else { return }

                    // Cache the result
                    self.cacheAudio(data: audioData, forKey: cacheKey)
                }

                guard !token.isCancelled else { return }

                // Play the audio
                try self.audioPlayer.play(
                    data: audioData,
                    onComplete: { [weak self] duration in
                        guard let self = self else { return }
                        guard self.currentToken === token, !token.isCancelled else { return }

                        self.isSpeaking = false
                        self.isPaused = false
                        self.currentToken = nil
                        onComplete(duration)
                    },
                    onInterrupt: { [weak self] in
                        guard let self = self else { return }
                        guard self.currentToken === token, !token.isCancelled else { return }

                        self.isPaused = true
                        onInterrupt?()
                    }
                )
            } catch {
                guard !token.isCancelled else { return }

                self.synthesisError = error.localizedDescription
                self.isSpeaking = false
                self.isPaused = false
                self.currentToken = nil

                // Call onComplete with 0 duration to indicate failure
                onComplete(0)
            }
        }

        return token
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        audioPlayer.pause()
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        audioPlayer.resume()
        isPaused = false
    }

    func stop() {
        synthesisTask?.cancel()
        synthesisTask = nil
        currentToken?.cancel()
        currentToken = nil
        audioPlayer.stop()
        isSpeaking = false
        isPaused = false
    }

    func cancel(token: SpeechCancellationToken) {
        token.cancel()
        if currentToken === token {
            synthesisTask?.cancel()
            synthesisTask = nil
            audioPlayer.stop()
            isSpeaking = false
            isPaused = false
            currentToken = nil
        }
    }

    func cleanup() {
        stop()
        audioPlayer.cleanup()
        audioCache.removeAll()
        currentCacheSize = 0
    }

    // MARK: - Private Helpers

    private func makeCacheKey(text: String, speaker: String, speed: Float) -> String {
        "\(text)_\(speaker)_\(String(format: "%.2f", speed))"
    }

    private func cacheAudio(data: Data, forKey key: String) {
        // Evict oldest entries if cache exceeds entry count or memory limit (LRU eviction)
        while audioCache.count >= Self.maxCacheEntries ||
              (currentCacheSize + data.count > Self.maxCacheSizeBytes && !audioCache.isEmpty) {
            // Find the least recently used entry
            if let lruKey = audioCache.min(by: { $0.value.lastAccessTime < $1.value.lastAccessTime })?.key,
               let removed = audioCache.removeValue(forKey: lruKey) {
                currentCacheSize -= removed.data.count
            } else {
                break
            }
        }
        audioCache[key] = CacheEntry(data: data, lastAccessTime: Date())
        currentCacheSize += data.count
    }
}
