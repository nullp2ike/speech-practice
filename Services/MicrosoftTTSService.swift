import Foundation
import os.log

private let microsoftTTSLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeechPractice", category: "MicrosoftTTSService")

/// TTS service for Microsoft Azure Speech Service.
/// Implements the SpeechSynthesizing protocol for interoperability with the existing speech system.
@MainActor
@Observable
final class MicrosoftTTSService: SpeechSynthesizing {
    private var client: AzureTTSClient?
    private let audioPlayer = AudioPlayerService()

    private(set) var isSpeaking = false
    private(set) var isPaused = false
    /// Error message from TTS synthesis (API errors, network issues, etc.)
    private(set) var synthesisError: String?

    private var currentToken: SpeechCancellationToken?
    private var synthesisTask: Task<Void, Never>?

    /// In-memory cache for synthesized audio segments.
    /// Key: "\(text)_\(voice)_\(rate)"
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

    // MARK: - Configuration

    /// The language code for voice selection (e.g., "en-US", "et-EE")
    var language: String = "en-US"

    /// User's preferred voice for the current language
    var preferredVoice: String?

    // MARK: - Available Voices

    /// Cached Azure voices from the API.
    private(set) var availableVoices: [AzureVoice] = []

    /// Voices filtered for the current language.
    var voicesForCurrentLanguage: [AzureVoice] {
        let languageCode = String(language.prefix(2)).lowercased()
        return availableVoices.filter { voice in
            voice.languageCode.lowercased() == languageCode
        }
    }

    /// Voices filtered for the current language, sorted for display.
    /// Neural voices appear first, then sorted alphabetically by display name.
    var sortedVoicesForCurrentLanguage: [AzureVoice] {
        voicesForCurrentLanguage.sorted { voice1, voice2 in
            // Neural voices first
            if voice1.voiceType == "Neural" && voice2.voiceType != "Neural" {
                return true
            }
            if voice1.voiceType != "Neural" && voice2.voiceType == "Neural" {
                return false
            }
            // Then alphabetically by display name
            return voice1.displayName < voice2.displayName
        }
    }

    /// Whether voices are currently being loaded.
    private(set) var isLoadingVoices = false

    /// Error message from loading voices, if any.
    private(set) var voicesLoadError: String?

    /// Whether Azure credentials are configured.
    var isConfigured: Bool {
        client != nil
    }

    // MARK: - Initialization

    init() {
        loadCredentials()
    }

    /// Loads Azure credentials from Keychain and initializes the client.
    func loadCredentials() {
        if let credentials = KeychainService.loadAzureCredentials() {
            client = AzureTTSClient(credentials: credentials)
            microsoftTTSLogger.debug("Azure TTS client initialized with region: \(credentials.region.rawValue)")
        } else {
            client = nil
            availableVoices = []
            microsoftTTSLogger.debug("No Azure credentials found")
        }
    }

    /// Refreshes credentials from Keychain (call after saving new credentials).
    func refreshCredentials() {
        loadCredentials()
        // Clear cached voices to force reload with new credentials
        availableVoices = []
        voicesLoadError = nil
    }

    // MARK: - Voice Loading

    /// Fetches available voices from Azure TTS API.
    func loadAvailableVoices() async {
        guard let client = client else {
            voicesLoadError = AzureTTSError.missingCredentials.localizedDescription
            return
        }

        guard !isLoadingVoices else { return }

        isLoadingVoices = true
        voicesLoadError = nil

        do {
            availableVoices = try await client.fetchAvailableVoices()
            microsoftTTSLogger.info("Loaded \(self.availableVoices.count) Azure voices")
        } catch {
            voicesLoadError = error.localizedDescription
            microsoftTTSLogger.error("Failed to load Azure voices: \(error.localizedDescription)")
        }

        isLoadingVoices = false
    }

    /// Tests the Azure connection by fetching voices.
    /// - Returns: Number of available voices if successful
    func testConnection() async throws -> Int {
        guard let client = client else {
            throw AzureTTSError.missingCredentials
        }
        return try await client.testConnection()
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

        guard let client = client else {
            synthesisError = AzureTTSError.missingCredentials.localizedDescription
            onComplete(0)
            return token
        }

        // Determine voice to use
        let voiceName = voiceIdentifier ?? preferredVoice ?? defaultVoiceForLanguage()

        guard let voiceName = voiceName else {
            synthesisError = "No voice available for language: \(language)"
            onComplete(0)
            return token
        }

        isSpeaking = true
        isPaused = false

        synthesisTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                // Check cache first
                let cacheKey = self.makeCacheKey(text: text, voice: voiceName, rate: rate)
                let audioData: Data

                if var cachedEntry = self.audioCache[cacheKey] {
                    // Update last access time for LRU tracking
                    cachedEntry.lastAccessTime = Date()
                    self.audioCache[cacheKey] = cachedEntry
                    audioData = cachedEntry.data
                    microsoftTTSLogger.debug("Using cached audio for: \(text.prefix(30))...")
                } else {
                    // Synthesize via API
                    guard !token.isCancelled else { return }
                    audioData = try await client.synthesize(
                        text: text,
                        voiceName: voiceName,
                        rate: rate,
                        language: self.language
                    )

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

                microsoftTTSLogger.error("Azure TTS synthesis failed: \(error.localizedDescription)")

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

    private func defaultVoiceForLanguage() -> String? {
        // Find the first neural voice for the current language
        let languageCode = String(language.prefix(2)).lowercased()
        let matchingVoices = availableVoices.filter { voice in
            voice.languageCode.lowercased() == languageCode && voice.voiceType == "Neural"
        }

        // Prefer a female voice as default (common convention)
        if let femaleVoice = matchingVoices.first(where: { $0.gender == "Female" }) {
            return femaleVoice.shortName
        }

        return matchingVoices.first?.shortName
    }

    private func makeCacheKey(text: String, voice: String, rate: Float) -> String {
        // Use hash of text to avoid very long dictionary keys for long speeches
        let textHash = text.hashValue
        return "\(textHash)_\(voice)_\(String(format: "%.2f", rate))"
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
