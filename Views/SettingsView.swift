import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PracticeViewModel
    @State private var showingHelp = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Playback") {
                    // Speed
                    VStack(alignment: .leading) {
                        Text("Speech Rate: \(String(format: "%.2f", viewModel.settings.rate))x")
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.settings.rate) },
                                set: { viewModel.updateRate(Float($0)) }
                            ),
                            in: Double(PlaybackSettings.minRate)...Double(PlaybackSettings.maxRate),
                            step: 0.05
                        )
                    }
                }

                Section {
                    Toggle("Enable Pause Mode", isOn: Binding(
                        get: { viewModel.settings.pauseEnabled },
                        set: { viewModel.updatePauseEnabled($0) }
                    ))

                    if viewModel.settings.pauseEnabled {
                        Picker("Pause After", selection: Binding(
                            get: { viewModel.settings.pauseGranularity },
                            set: { viewModel.updatePauseGranularity($0) }
                        )) {
                            ForEach(SegmentType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                    }
                } header: {
                    Text("Pause Mode")
                } footer: {
                    Text("When enabled, playback will pause after each segment for the same duration it took to read.")
                }

                ttsProviderSection

                voiceSection

                Section {
                    Button {
                        showingHelp = true
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - TTS Provider Section

    private var ttsProviderSection: some View {
        Section {
            TTSProviderPicker(
                selectedProvider: Binding(
                    get: { viewModel.settings.ttsProvider },
                    set: { viewModel.updateTTSProvider($0) }
                ),
                language: viewModel.speech.language,
                hasAzureCredentials: KeychainService.hasAzureCredentials()
            )

            if viewModel.settings.ttsProvider == .microsoft {
                NavigationLink {
                    AzureSettingsView(viewModel: viewModel)
                } label: {
                    HStack {
                        Text("Microsoft Azure Settings")
                        Spacer()
                        if !KeychainService.hasAzureCredentials() {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        } header: {
            Text("Text-to-Speech")
        } footer: {
            providerFooterText
        }
    }

    @ViewBuilder
    private var providerFooterText: some View {
        switch viewModel.effectiveProvider {
        case .auto:
            // Deprecated: should not appear, but handle gracefully
            Text("Using iOS built-in speech (offline).")
        case .tartuNLP:
            if viewModel.usesEstonianTTS {
                Text("Using TartuNLP for Estonian (free, requires internet).")
            } else {
                Text("TartuNLP only supports Estonian. Using iOS built-in speech instead.")
            }
        case .ios:
            Text("Using iOS built-in speech (offline).")
        case .microsoft:
            Text("Using Microsoft Azure neural voices (requires internet and API key).")
        }
    }

    // MARK: - Voice Section

    private var voiceSection: some View {
        Section("Voice") {
            switch viewModel.effectiveProvider {
            case .auto:
                // Deprecated: handle gracefully by showing iOS voice picker
                VoicePicker(
                    selectedVoiceIdentifier: Binding(
                        get: { viewModel.settings.voiceIdentifier },
                        set: { viewModel.updateVoice($0) }
                    ),
                    language: viewModel.speech.language
                )

            case .tartuNLP:
                if viewModel.usesEstonianTTS {
                    EstonianVoicePicker(
                        selectedVoiceIdentifier: Binding(
                            get: { viewModel.settings.voiceIdentifier },
                            set: { viewModel.updateVoice($0) }
                        ),
                        estonianService: viewModel.estonianTTSService
                    )
                } else {
                    // TartuNLP selected but not Estonian - show iOS voices
                    VoicePicker(
                        selectedVoiceIdentifier: Binding(
                            get: { viewModel.settings.voiceIdentifier },
                            set: { viewModel.updateVoice($0) }
                        ),
                        language: viewModel.speech.language
                    )
                }

            case .ios:
                VoicePicker(
                    selectedVoiceIdentifier: Binding(
                        get: { viewModel.settings.voiceIdentifier },
                        set: { viewModel.updateVoice($0) }
                    ),
                    language: viewModel.speech.language
                )

            case .microsoft:
                AzureVoicePicker(
                    selectedVoiceShortName: Binding(
                        get: { viewModel.settings.azureVoicePreference.voice(for: viewModel.speech.language) },
                        set: { viewModel.updateAzureVoice($0) }
                    ),
                    microsoftService: viewModel.microsoftTTSService
                )
            }
        }
    }
}

// MARK: - Voice Picker

struct VoicePicker: View {
    @Binding var selectedVoiceIdentifier: String?
    let language: String

    private var availableVoices: [AVSpeechSynthesisVoice] {
        SpeechSynthesizerService.availableVoices(for: language)
    }

    var body: some View {
        Picker("Voice", selection: $selectedVoiceIdentifier) {
            Text("Default").tag(nil as String?)

            ForEach(availableVoices, id: \.identifier) { voice in
                VoiceRow(voice: voice)
                    .tag(voice.identifier as String?)
            }
        }
    }
}

struct VoiceRow: View {
    let voice: AVSpeechSynthesisVoice

    var body: some View {
        HStack {
            Text(voice.name)
            if voice.quality == .enhanced {
                Text("Enhanced")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Estonian Voice Picker

struct EstonianVoicePicker: View {
    @Binding var selectedVoiceIdentifier: String?
    let estonianService: EstonianTTSService?

    var body: some View {
        if let service = estonianService {
            EstonianVoicePickerContent(
                selectedVoiceIdentifier: $selectedVoiceIdentifier,
                service: service
            )
        } else {
            Text("Estonian voices unavailable")
                .foregroundStyle(.secondary)
        }
    }
}

struct EstonianVoicePickerContent: View {
    @Binding var selectedVoiceIdentifier: String?
    let service: EstonianTTSService

    var body: some View {
        Group {
            if service.isLoadingVoices {
                HStack {
                    Text("Loading voices...")
                    Spacer()
                    ProgressView()
                }
            } else if let error = service.voicesLoadError {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Failed to load voices")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task {
                            await service.loadAvailableVoices()
                        }
                    }
                    .font(.caption)
                }
            } else {
                Picker("Voice", selection: $selectedVoiceIdentifier) {
                    Text("Default (Mari)").tag(nil as String?)

                    ForEach(service.availableVoices) { voice in
                        Text(voice.displayName).tag(voice.id as String?)
                    }
                }
            }
        }
        .task {
            if service.availableVoices.isEmpty && !service.isLoadingVoices {
                await service.loadAvailableVoices()
            }
        }
    }
}

#Preview {
    SettingsView(viewModel: PracticeViewModel(speech: Speech(title: "Test", content: "Test content.")))
}
