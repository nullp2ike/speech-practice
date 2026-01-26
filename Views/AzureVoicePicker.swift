import SwiftUI

/// Voice picker for Microsoft Azure TTS voices.
struct AzureVoicePicker: View {
    @Binding var selectedVoiceShortName: String?
    let microsoftService: MicrosoftTTSService?

    var body: some View {
        if let service = microsoftService {
            AzureVoicePickerContent(
                selectedVoiceShortName: $selectedVoiceShortName,
                service: service
            )
        } else {
            Text("Microsoft TTS not configured")
                .foregroundStyle(.secondary)
        }
    }
}

struct AzureVoicePickerContent: View {
    @Binding var selectedVoiceShortName: String?
    let service: MicrosoftTTSService

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
            } else if service.voicesForCurrentLanguage.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No voices for this language")
                        .foregroundStyle(.secondary)
                    if service.availableVoices.isEmpty {
                        Button("Load Voices") {
                            Task {
                                await service.loadAvailableVoices()
                            }
                        }
                        .font(.caption)
                    }
                }
            } else {
                Picker("Voice", selection: $selectedVoiceShortName) {
                    Text("Default").tag(nil as String?)

                    ForEach(service.sortedVoicesForCurrentLanguage) { voice in
                        AzureVoiceRow(voice: voice)
                            .tag(voice.shortName as String?)
                    }
                }
            }
        }
        .task {
            if service.availableVoices.isEmpty && !service.isLoadingVoices && service.isConfigured {
                await service.loadAvailableVoices()
            }
        }
    }
}

struct AzureVoiceRow: View {
    let voice: AzureVoice

    var body: some View {
        HStack {
            Text(voice.displayName)
            if voice.voiceType == "Neural" {
                Text("Neural")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    Form {
        Section("Voice") {
            AzureVoicePicker(
                selectedVoiceShortName: .constant(nil),
                microsoftService: nil
            )
        }
    }
}
