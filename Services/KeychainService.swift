import Foundation
import Security

/// Errors that can occur during Keychain operations.
enum KeychainError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case itemNotFound
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data for Keychain"
        case .decodingFailed:
            return "Failed to decode data from Keychain"
        case .itemNotFound:
            return "Item not found in Keychain"
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status: \(status)"
        }
    }
}

/// Service for securely storing sensitive data in the iOS Keychain.
/// Used primarily for storing Azure TTS API credentials.
enum KeychainService {
    private static let serviceName = Bundle.main.bundleIdentifier ?? "com.speechpractice"

    // MARK: - Azure Credentials Key

    private static let azureCredentialsKey = "azure_tts_credentials"

    // MARK: - Generic Operations

    /// Saves a Codable value to the Keychain.
    /// - Parameters:
    ///   - value: The value to save
    ///   - key: The key to associate with the value
    static func save<T: Codable>(_ value: T, forKey key: String) throws {
        let data = try JSONEncoder().encode(value)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        // Delete any existing item first
        SecItemDelete(query as CFDictionary)

        var newItem = query
        newItem[kSecValueData as String] = data

        let status = SecItemAdd(newItem as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Loads a Codable value from the Keychain.
    /// - Parameter key: The key associated with the value
    /// - Returns: The decoded value, or nil if not found
    static func load<T: Codable>(forKey key: String) throws -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.decodingFailed
            }
            return try JSONDecoder().decode(T.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Deletes a value from the Keychain.
    /// - Parameter key: The key associated with the value to delete
    static func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Azure Credentials Helpers

    /// Saves Azure TTS credentials to the Keychain.
    /// - Parameter credentials: The Azure credentials to save
    static func saveAzureCredentials(_ credentials: AzureCredentials) throws {
        try save(credentials, forKey: azureCredentialsKey)
    }

    /// Loads Azure TTS credentials from the Keychain.
    /// - Returns: The stored credentials, or nil if not configured
    static func loadAzureCredentials() -> AzureCredentials? {
        try? load(forKey: azureCredentialsKey)
    }

    /// Checks if Azure TTS credentials are stored in the Keychain.
    /// - Returns: True if credentials exist
    static func hasAzureCredentials() -> Bool {
        loadAzureCredentials() != nil
    }

    /// Removes Azure TTS credentials from the Keychain.
    static func deleteAzureCredentials() throws {
        try delete(forKey: azureCredentialsKey)
    }
}
