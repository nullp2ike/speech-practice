import Foundation

/// Available TTS providers for speech synthesis.
enum TTSProvider: String, Codable, CaseIterable, Sendable {
    /// Automatic selection: Estonian uses TartuNLP, others use iOS AVSpeech
    case auto
    /// iOS AVSpeech for all languages (offline capable)
    case ios
    /// Microsoft Azure TTS for all languages (requires API key and internet)
    case microsoft

    var displayName: String {
        switch self {
        case .auto:
            return "Automatic"
        case .ios:
            return "iOS (Offline)"
        case .microsoft:
            return "Microsoft Azure"
        }
    }

    var description: String {
        switch self {
        case .auto:
            return "Estonian uses TartuNLP, others use iOS"
        case .ios:
            return "Uses device voices, works offline"
        case .microsoft:
            return "High-quality neural voices, requires internet"
        }
    }
}

/// Azure region codes for the TTS API endpoint.
enum AzureRegion: String, Codable, CaseIterable, Sendable {
    case eastus = "eastus"
    case eastus2 = "eastus2"
    case westus = "westus"
    case westus2 = "westus2"
    case westus3 = "westus3"
    case centralus = "centralus"
    case northcentralus = "northcentralus"
    case southcentralus = "southcentralus"
    case westeurope = "westeurope"
    case northeurope = "northeurope"
    case uksouth = "uksouth"
    case ukwest = "ukwest"
    case francecentral = "francecentral"
    case germanywestcentral = "germanywestcentral"
    case switzerlandnorth = "switzerlandnorth"
    case swedencentral = "swedencentral"
    case norwayeast = "norwayeast"
    case eastasia = "eastasia"
    case southeastasia = "southeastasia"
    case japaneast = "japaneast"
    case japanwest = "japanwest"
    case koreacentral = "koreacentral"
    case australiaeast = "australiaeast"
    case brazilsouth = "brazilsouth"
    case canadacentral = "canadacentral"
    case centralindia = "centralindia"

    var displayName: String {
        switch self {
        case .eastus: return "East US"
        case .eastus2: return "East US 2"
        case .westus: return "West US"
        case .westus2: return "West US 2"
        case .westus3: return "West US 3"
        case .centralus: return "Central US"
        case .northcentralus: return "North Central US"
        case .southcentralus: return "South Central US"
        case .westeurope: return "West Europe"
        case .northeurope: return "North Europe"
        case .uksouth: return "UK South"
        case .ukwest: return "UK West"
        case .francecentral: return "France Central"
        case .germanywestcentral: return "Germany West Central"
        case .switzerlandnorth: return "Switzerland North"
        case .swedencentral: return "Sweden Central"
        case .norwayeast: return "Norway East"
        case .eastasia: return "East Asia"
        case .southeastasia: return "Southeast Asia"
        case .japaneast: return "Japan East"
        case .japanwest: return "Japan West"
        case .koreacentral: return "Korea Central"
        case .australiaeast: return "Australia East"
        case .brazilsouth: return "Brazil South"
        case .canadacentral: return "Canada Central"
        case .centralindia: return "Central India"
        }
    }
}

/// Credentials for Microsoft Azure Text-to-Speech API.
struct AzureCredentials: Codable, Equatable, Sendable {
    let apiKey: String
    let region: AzureRegion

    var endpoint: String {
        "https://\(region.rawValue).tts.speech.microsoft.com"
    }

    var voicesEndpoint: String {
        "\(endpoint)/cognitiveservices/voices/list"
    }

    var synthesisEndpoint: String {
        "\(endpoint)/cognitiveservices/v1"
    }
}

/// Represents a voice available from Microsoft Azure TTS.
struct AzureVoice: Identifiable, Codable, Equatable, Sendable {
    let shortName: String      // e.g., "en-US-JennyNeural"
    let displayName: String    // e.g., "Jenny"
    let localName: String      // Localized name
    let locale: String         // e.g., "en-US"
    let gender: String         // "Female" or "Male"
    let voiceType: String      // "Neural" or "Standard"

    var id: String { shortName }

    /// The language code without region (e.g., "en" from "en-US")
    var languageCode: String {
        String(locale.prefix(2))
    }

    /// Display string showing name and voice type
    var displayString: String {
        if voiceType == "Neural" {
            return "\(displayName) (Neural)"
        }
        return displayName
    }
}

/// User's preferred Azure voices per language.
struct AzureVoicePreference: Codable, Equatable, Sendable {
    /// Maps language code (e.g., "en", "et") to voice shortName
    var voicesByLanguage: [String: String]

    init(voicesByLanguage: [String: String] = [:]) {
        self.voicesByLanguage = voicesByLanguage
    }

    /// Gets the preferred voice for a language, if set.
    func voice(for language: String) -> String? {
        let languageCode = String(language.prefix(2)).lowercased()
        return voicesByLanguage[languageCode]
    }

    /// Sets the preferred voice for a language.
    mutating func setVoice(_ voiceShortName: String?, for language: String) {
        let languageCode = String(language.prefix(2)).lowercased()
        voicesByLanguage[languageCode] = voiceShortName
    }
}
