import SwiftUI

/// Picker for selecting the TTS provider.
struct TTSProviderPicker: View {
    @Binding var selectedProvider: TTSProvider
    let language: String
    let hasAzureCredentials: Bool

    /// Providers available for the current language.
    private var availableProviders: [TTSProvider] {
        TTSProvider.availableCases(for: language)
    }

    var body: some View {
        Picker("TTS Provider", selection: $selectedProvider) {
            ForEach(availableProviders, id: \.self) { provider in
                ProviderRow(provider: provider, hasCredentials: hasAzureCredentials)
                    .tag(provider)
            }
        }
    }
}

private struct ProviderRow: View {
    let provider: TTSProvider
    let hasCredentials: Bool

    var body: some View {
        HStack {
            Text(provider.displayName)
            if provider == .microsoft && !hasCredentials {
                Text("(Not configured)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Not configured")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var accessibilityLabelText: String {
        if provider == .microsoft && !hasCredentials {
            return "\(provider.displayName), not configured"
        }
        return provider.displayName
    }
}

#Preview("English") {
    Form {
        TTSProviderPicker(
            selectedProvider: .constant(.ios),
            language: "en-US",
            hasAzureCredentials: false
        )
    }
}

#Preview("Estonian") {
    Form {
        TTSProviderPicker(
            selectedProvider: .constant(.tartuNLP),
            language: "et-EE",
            hasAzureCredentials: false
        )
    }
}
