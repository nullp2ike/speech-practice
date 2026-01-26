import SwiftUI

/// Settings view for configuring Microsoft Azure TTS credentials.
struct AzureSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PracticeViewModel

    @State private var apiKey: String = ""
    @State private var selectedRegion: AzureRegion = .eastus
    @State private var isTestingConnection = false
    @State private var operationResult: OperationResult?
    @State private var showDeleteConfirmation = false
    /// Whether credentials exist in Keychain (updated on load/save/delete)
    @State private var credentialsExistInKeychain = false
    /// Whether to show the masked credential view (false when user wants to enter new key)
    @State private var showMaskedCredentials = false

    private var hasExistingCredentials: Bool {
        credentialsExistInKeychain
    }

    /// Placeholder shown when credentials exist but key hasn't been re-entered
    private static let maskedKeyPlaceholder = "••••••••••••••••"

    // MARK: - Help URLs
    // swiftlint:disable force_unwrapping
    private static let azureSignupURL = URL(string: "https://azure.microsoft.com/en-us/products/ai-services/text-to-speech")!
    private static let azurePortalURL = URL(string: "https://portal.azure.com/#view/Microsoft_Azure_ProjectOxford/CognitiveServicesHub/~/SpeechServices")!
    // swiftlint:enable force_unwrapping

    private enum OperationResult {
        case testSuccess(Int)   // Connection test passed, includes voice count
        case saveSuccess        // Credentials saved successfully
        case failure(String)    // Any error
    }

    var body: some View {
        NavigationStack {
            Form {
                credentialsSection
                connectionSection

                if hasExistingCredentials {
                    removeCredentialsSection
                }

                helpSection
            }
            .navigationTitle("Microsoft Azure TTS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadExistingCredentials()
            }
            .alert("Remove Credentials", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) {
                    removeCredentials()
                }
            } message: {
                Text("This will remove your Azure API credentials. You'll need to enter them again to use Microsoft TTS.")
            }
        }
    }

    // MARK: - Sections

    private var credentialsSection: some View {
        Section {
            if showMaskedCredentials {
                // Show masked placeholder when credentials exist but user hasn't started entering a new key
                HStack {
                    Text("API Key")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.maskedKeyPlaceholder)
                        .foregroundStyle(.secondary)
                }

                Button("Enter New API Key") {
                    showMaskedCredentials = false
                }
            } else {
                SecureField("API Key", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if credentialsExistInKeychain {
                    Button("Cancel", role: .cancel) {
                        apiKey = ""
                        showMaskedCredentials = true
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Picker("Region", selection: $selectedRegion) {
                ForEach(AzureRegion.allCases, id: \.self) { region in
                    Text(region.displayName).tag(region)
                }
            }
        } header: {
            Text("Azure Credentials")
        } footer: {
            if showMaskedCredentials {
                Text("Credentials are saved. Tap \"Enter New API Key\" to update.")
            } else {
                Text("Enter your Azure Speech Services API key and select your resource region.")
            }
        }
    }

    private var connectionSection: some View {
        Section {
            Button {
                testConnection()
            } label: {
                HStack {
                    Text("Test Connection")
                    Spacer()
                    if isTestingConnection {
                        ProgressView()
                    }
                }
            }
            .disabled((apiKey.isEmpty && !credentialsExistInKeychain) || isTestingConnection)

            if let result = operationResult {
                switch result {
                case .testSuccess(let voiceCount):
                    Label("Connected - \(voiceCount) voices available", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .saveSuccess:
                    Label("Credentials saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }

            Button {
                saveCredentials()
            } label: {
                Text("Save Credentials")
            }
            .disabled(apiKey.isEmpty && !credentialsExistInKeychain)
        }
    }

    private var removeCredentialsSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Text("Remove Credentials")
            }
        }
    }

    private var helpSection: some View {
        Section {
            Link(destination: Self.azureSignupURL) {
                Label("Get Azure Speech Services", systemImage: "link")
            }

            Link(destination: Self.azurePortalURL) {
                Label("Azure Portal - Speech Services", systemImage: "link")
            }
        } header: {
            Text("Help")
        } footer: {
            Text("You need an Azure account with a Speech Services resource to use Microsoft TTS.")
        }
    }

    // MARK: - Actions

    private func loadExistingCredentials() {
        // Only load the region, NOT the API key (security: avoid holding key in memory)
        if let credentials = KeychainService.loadAzureCredentials() {
            selectedRegion = credentials.region
            credentialsExistInKeychain = true
            showMaskedCredentials = true
        } else {
            credentialsExistInKeychain = false
            showMaskedCredentials = false
        }
    }

    private func testConnection() {
        // Determine which credentials to use for testing
        let credentialsToTest: AzureCredentials?
        if !apiKey.isEmpty {
            // Validate API key format before testing
            guard isValidAPIKey(apiKey) else {
                operationResult = .failure("Invalid API key format.")
                return
            }
            // User entered a new key - test with that
            credentialsToTest = AzureCredentials(apiKey: apiKey, region: selectedRegion)
        } else if credentialsExistInKeychain, let stored = KeychainService.loadAzureCredentials() {
            // No new key entered, but we have stored credentials - test with stored key but selected region
            credentialsToTest = AzureCredentials(apiKey: stored.apiKey, region: selectedRegion)
        } else {
            return
        }

        guard let credentials = credentialsToTest else { return }

        isTestingConnection = true
        operationResult = nil

        let client = AzureTTSClient(credentials: credentials)

        Task {
            do {
                let voiceCount = try await client.testConnection()
                operationResult = .testSuccess(voiceCount)
            } catch {
                operationResult = .failure(error.localizedDescription)
            }
            isTestingConnection = false
        }
    }

    /// Validates that an API key has a reasonable format for Azure.
    /// Azure keys are typically 32 hex characters, but some resource types use longer keys.
    private func isValidAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 32 && trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }
    }

    private func saveCredentials() {
        // Determine which credentials to save
        let credentialsToSave: AzureCredentials?
        if !apiKey.isEmpty {
            // Validate API key format before saving
            guard isValidAPIKey(apiKey) else {
                operationResult = .failure("Invalid API key format.")
                return
            }
            // User entered a new key - save with new key
            credentialsToSave = AzureCredentials(apiKey: apiKey, region: selectedRegion)
        } else if credentialsExistInKeychain, let stored = KeychainService.loadAzureCredentials() {
            // No new key entered, but we have stored credentials - update just the region
            credentialsToSave = AzureCredentials(apiKey: stored.apiKey, region: selectedRegion)
        } else {
            operationResult = .failure("Please enter an API key")
            return
        }

        guard let credentials = credentialsToSave else { return }

        do {
            try KeychainService.saveAzureCredentials(credentials)
            // Clear the entered key from memory after saving
            apiKey = ""
            credentialsExistInKeychain = true
            showMaskedCredentials = true
            operationResult = .saveSuccess
            // Notify view model that credentials changed
            viewModel.refreshAzureCredentials()
        } catch {
            operationResult = .failure("Failed to save: \(error.localizedDescription)")
        }
    }

    private func removeCredentials() {
        do {
            try KeychainService.deleteAzureCredentials()
            apiKey = ""
            selectedRegion = .eastus
            credentialsExistInKeychain = false
            showMaskedCredentials = false
            operationResult = nil
            // Notify view model that credentials were removed
            if viewModel.settings.ttsProvider == .microsoft {
                viewModel.updateTTSProvider(.auto)
            }
        } catch {
            operationResult = .failure("Failed to remove: \(error.localizedDescription)")
        }
    }
}

#Preview {
    AzureSettingsView(viewModel: PracticeViewModel(speech: Speech(title: "Test", content: "Test content.")))
}
