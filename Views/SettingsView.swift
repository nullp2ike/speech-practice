import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PracticeViewModel

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

                Section("Voice") {
                    VoicePicker(
                        selectedVoiceIdentifier: Binding(
                            get: { viewModel.settings.voiceIdentifier },
                            set: { viewModel.updateVoice($0) }
                        ),
                        language: viewModel.speech.language
                    )
                }

                Section {
                    Button("Restart from Beginning") {
                        viewModel.restart()
                        dismiss()
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
        .presentationDetents([.medium, .large])
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

#Preview {
    SettingsView(viewModel: PracticeViewModel(speech: Speech(title: "Test", content: "Test content.")))
}
