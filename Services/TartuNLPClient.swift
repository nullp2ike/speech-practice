import Foundation
import os.log

/// Represents a voice available from the TartuNLP TTS API.
struct EstonianVoice: Identifiable, Sendable {
    let id: String
    let name: String
    let displayName: String

    static let defaultVoice = EstonianVoice(id: "mari", name: "mari", displayName: "Mari")

    /// Default voices to use when API is unavailable.
    static let defaultVoices: [EstonianVoice] = [
        EstonianVoice(id: "mari", name: "mari", displayName: "Mari"),
        EstonianVoice(id: "tambet", name: "tambet", displayName: "Tambet"),
        EstonianVoice(id: "liivika", name: "liivika", displayName: "Liivika"),
        EstonianVoice(id: "kalev", name: "kalev", displayName: "Kalev")
    ]

    /// Known Estonian voice identifiers for validation.
    static let knownVoiceIds: Set<String> = ["mari", "tambet", "liivika", "kalev", "külli", "meelis", "albert", "indrek", "vesta", "peeter"]
}

/// Error types for TartuNLP API operations.
enum TartuNLPError: LocalizedError {
    case networkError(Error)
    case offline
    case invalidResponse
    case httpError(Int)
    case invalidAudioData

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .offline:
            return "Estonian speech requires an internet connection"
        case .invalidResponse:
            return "Invalid response from TTS server"
        case .httpError(let code):
            return "Server error (HTTP \(code))"
        case .invalidAudioData:
            return "Received invalid audio data"
        }
    }
}

private let tartuNLPLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeechPractice", category: "TartuNLPClient")

/// Client for the TartuNLP Estonian text-to-speech API.
/// API Documentation: https://api.tartunlp.ai/text-to-speech/v2
actor TartuNLPClient {
    private let baseURL = "https://api.tartunlp.ai/text-to-speech/v2"
    private let session: URLSession

    /// Cached list of available voices.
    private var cachedVoices: [EstonianVoice]?

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    /// Fetches the list of available Estonian voices from the API.
    /// - Returns: Array of available voices
    func fetchAvailableVoices() async throws -> [EstonianVoice] {
        if let cached = cachedVoices {
            return cached
        }

        guard let url = URL(string: baseURL) else {
            throw TartuNLPError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if isOfflineError(error) {
                throw TartuNLPError.offline
            }
            throw TartuNLPError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TartuNLPError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TartuNLPError.httpError(httpResponse.statusCode)
        }

        // Parse the response - expected to be a JSON object with voice info
        let voices = parseVoicesResponse(data)
        cachedVoices = voices
        return voices
    }

    /// Synthesizes text to audio using the TartuNLP API.
    /// - Parameters:
    ///   - text: The Estonian text to synthesize
    ///   - speaker: The voice/speaker to use (e.g., "mari")
    ///   - speed: Speed factor (0.5 to 2.0, where 1.0 is normal)
    /// - Returns: WAV audio data
    func synthesize(text: String, speaker: String, speed: Float) async throws -> Data {
        guard let url = URL(string: baseURL) else {
            throw TartuNLPError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": text,
            "speaker": speaker,
            "speed": speed
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if isOfflineError(error) {
                throw TartuNLPError.offline
            }
            throw TartuNLPError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TartuNLPError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TartuNLPError.httpError(httpResponse.statusCode)
        }

        // Verify we got audio data
        guard data.count > 44 else { // WAV header is at least 44 bytes
            throw TartuNLPError.invalidAudioData
        }

        return data
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

    private func parseVoicesResponse(_ data: Data) -> [EstonianVoice] {
        // The API returns voice information - parse it to extract available voices
        // If parsing fails, return default voices
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let speakers = json["speakers"] as? [String] {
                return speakers.map { speaker in
                    EstonianVoice(
                        id: speaker,
                        name: speaker,
                        displayName: speaker.capitalized
                    )
                }
            }
        } catch {
            tartuNLPLogger.warning("Failed to parse voices response: \(error.localizedDescription)")
        }

        // Return default voices if parsing fails
        return EstonianVoice.defaultVoices
    }

    /// Maps AVSpeech rate (0.1 - 1.0) to TartuNLP speed (0.5 - 2.0).
    /// Formula: tartuSpeed = 0.5 + ((avRate - 0.1) / 0.9) * 1.5
    static func mapRateToSpeed(_ avRate: Float) -> Float {
        let normalizedRate = (avRate - 0.1) / 0.9 // 0.0 to 1.0
        let tartuSpeed = 0.5 + normalizedRate * 1.5 // 0.5 to 2.0
        return min(max(tartuSpeed, 0.5), 2.0)
    }
}
