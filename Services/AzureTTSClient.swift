import Foundation
import os.log

/// Error types for Azure TTS API operations.
enum AzureTTSError: LocalizedError {
    case networkError(Error)
    case offline
    case invalidResponse
    case httpError(Int, String?)
    case invalidAudioData
    case missingCredentials
    case invalidCredentials
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .offline:
            return "Microsoft TTS requires an internet connection"
        case .invalidResponse:
            return "Invalid response from Azure TTS"
        case .httpError(let code, let message):
            if let message = message {
                return "Azure error (HTTP \(code)): \(message)"
            }
            return "Azure error (HTTP \(code))"
        case .invalidAudioData:
            return "Received invalid audio data from Azure"
        case .missingCredentials:
            return "Azure API credentials not configured"
        case .invalidCredentials:
            return "Invalid API key or region"
        case .quotaExceeded:
            return "Monthly quota exceeded. Check your Azure subscription."
        }
    }
}

private let azureTTSLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeechPractice", category: "AzureTTSClient")

/// Client for Microsoft Azure Text-to-Speech API.
/// API Documentation: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech
actor AzureTTSClient {
    /// MP3 format at 24kHz, 48kbps mono - good balance of quality and file size for speech.
    /// See: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech#audio-outputs
    private static let audioOutputFormat = "audio-24khz-48kbitrate-mono-mp3"

    /// Minimum expected size for valid MP3 audio data in bytes.
    /// MP3 files have headers (ID3 tags, frame headers) that typically exceed 100 bytes.
    /// A response smaller than this likely indicates an error message rather than audio.
    private static let minimumAudioDataSize = 100

    private let session: URLSession
    private let credentials: AzureCredentials

    /// Cached list of available voices.
    private var cachedVoices: [AzureVoice]?

    init(credentials: AzureCredentials) {
        self.credentials = credentials

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    /// Fetches the list of available voices from Azure TTS.
    /// - Returns: Array of available voices
    func fetchAvailableVoices() async throws -> [AzureVoice] {
        if let cached = cachedVoices {
            return cached
        }

        guard let url = URL(string: credentials.voicesEndpoint) else {
            throw AzureTTSError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if isOfflineError(error) {
                throw AzureTTSError.offline
            }
            throw AzureTTSError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AzureTTSError.invalidResponse
        }

        try handleHTTPError(httpResponse.statusCode, data: data)

        let voices = try parseVoicesResponse(data)
        cachedVoices = voices
        return voices
    }

    /// Synthesizes text to audio using Azure TTS.
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - voiceName: The voice shortName to use (e.g., "en-US-JennyNeural")
    ///   - rate: Speech rate in AVSpeech scale (0.1 to 1.0)
    ///   - language: The language code (e.g., "en-US")
    /// - Returns: Audio data in MP3 format
    func synthesize(text: String, voiceName: String, rate: Float, language: String) async throws -> Data {
        guard let url = URL(string: credentials.synthesisEndpoint) else {
            throw AzureTTSError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.audioOutputFormat, forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-RequestId")

        let ssml = generateSSML(text: text, voiceName: voiceName, rate: rate, language: language)
        request.httpBody = ssml.data(using: .utf8)

        azureTTSLogger.debug("Synthesizing with voice: \(voiceName), rate: \(rate)")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if isOfflineError(error) {
                throw AzureTTSError.offline
            }
            throw AzureTTSError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AzureTTSError.invalidResponse
        }

        try handleHTTPError(httpResponse.statusCode, data: data)

        // Verify we got audio data, not an error response
        guard data.count > Self.minimumAudioDataSize else {
            throw AzureTTSError.invalidAudioData
        }

        return data
    }

    /// Tests the connection to Azure TTS by fetching voices.
    /// - Returns: Number of available voices if successful
    func testConnection() async throws -> Int {
        // Clear cache to force a fresh request
        cachedVoices = nil
        let voices = try await fetchAvailableVoices()
        return voices.count
    }

    /// Clears the cached voices list.
    func clearCache() {
        cachedVoices = nil
    }

    // MARK: - Private Helpers

    private func isOfflineError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && (
            nsError.code == NSURLErrorNotConnectedToInternet ||
            nsError.code == NSURLErrorNetworkConnectionLost ||
            nsError.code == NSURLErrorDataNotAllowed
        )
    }

    private func handleHTTPError(_ statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200...299:
            return // Success
        case 401, 403:
            throw AzureTTSError.invalidCredentials
        case 429:
            throw AzureTTSError.quotaExceeded
        default:
            let message = String(data: data, encoding: .utf8)
            throw AzureTTSError.httpError(statusCode, message)
        }
    }

    private func parseVoicesResponse(_ data: Data) throws -> [AzureVoice] {
        struct APIVoice: Decodable {
            let ShortName: String
            let DisplayName: String
            let LocalName: String
            let Locale: String
            let Gender: String
            let VoiceType: String
        }

        let decoder = JSONDecoder()
        let apiVoices = try decoder.decode([APIVoice].self, from: data)

        return apiVoices.map { voice in
            AzureVoice(
                shortName: voice.ShortName,
                displayName: voice.DisplayName,
                localName: voice.LocalName,
                locale: voice.Locale,
                gender: voice.Gender,
                voiceType: voice.VoiceType
            )
        }
    }

    /// Generates SSML markup for speech synthesis.
    private func generateSSML(text: String, voiceName: String, rate: Float, language: String) -> String {
        let prosodyRate = mapRateToProsodyRate(rate)
        let escapedText = escapeXML(text)

        return """
        <speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="\(language)">
            <voice name="\(voiceName)">
                <prosody rate="\(prosodyRate)">
                    \(escapedText)
                </prosody>
            </voice>
        </speak>
        """
    }

    /// Maps AVSpeech rate (0.1 - 1.0) to Azure prosody rate percentage.
    /// Delegates to the static method for implementation.
    private func mapRateToProsodyRate(_ avRate: Float) -> String {
        Self.mapRateToProsodyRate(avRate)
    }

    /// Escapes special XML characters in text.
    private func escapeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Maps AVSpeech rate (0.1 - 1.0) to Azure prosody rate percentage.
    /// - Parameter avRate: AVSpeech rate where 0.1 = slowest, 0.5 = default, 1.0 = fastest
    /// - Returns: Azure prosody rate string (e.g., "-50%", "0%", "+100%")
    ///
    /// Mapping:
    /// - AVSpeech 0.1 (slowest) -> "-50%"
    /// - AVSpeech 0.5 (default) -> "0%" (normal)
    /// - AVSpeech 1.0 (fastest) -> "+100%"
    static func mapRateToProsodyRate(_ avRate: Float) -> String {
        let percentage: Int
        if avRate <= 0.5 {
            let normalized = (avRate - 0.1) / 0.4
            percentage = Int(-50 + normalized * 50)
        } else {
            let normalized = (avRate - 0.5) / 0.5
            percentage = Int(normalized * 100)
        }

        if percentage >= 0 {
            return "+\(percentage)%"
        }
        return "\(percentage)%"
    }
}
