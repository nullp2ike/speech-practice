import SwiftUI
import SwiftData

struct SpeechEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: SpeechEditorViewModel

    init(speech: Speech) {
        _viewModel = State(initialValue: SpeechEditorViewModel(speech: speech))
    }

    var body: some View {
        Form {
            Section("Title") {
                TextField("Speech title", text: $viewModel.title)
            }

            Section {
                TextEditor(text: Binding(
                    get: { viewModel.content },
                    set: { viewModel.updateContent($0) }
                ))
                .frame(minHeight: 300)
                .font(.body)
            } header: {
                Text("Content")
            } footer: {
                HStack {
                    Text(viewModel.characterCountText)
                        .foregroundStyle(viewModel.isAtCharacterLimit ? .red : .secondary)

                    Spacer()

                    if viewModel.isAtCharacterLimit {
                        Text("Character limit reached")
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Language") {
                LanguagePicker(selectedLanguage: Binding(
                    get: { viewModel.speech.language },
                    set: { viewModel.speech.language = $0 }
                ))
            }
        }
        .navigationTitle("Edit Speech")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.save()
                    dismiss()
                }
            }
        }
        .onAppear {
            viewModel.setup(modelContext: modelContext)
        }
    }
}

// MARK: - Language Picker

struct LanguagePicker: View {
    @Binding var selectedLanguage: String

    private let languages = [
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("et-EE", "Estonian"),
        ("de-DE", "German"),
        ("fr-FR", "French"),
        ("es-ES", "Spanish"),
        ("it-IT", "Italian"),
        ("pt-BR", "Portuguese (Brazil)"),
        ("ja-JP", "Japanese"),
        ("zh-CN", "Chinese (Simplified)"),
    ]

    var body: some View {
        Picker("Language", selection: $selectedLanguage) {
            ForEach(languages, id: \.0) { code, name in
                Text(name).tag(code)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SpeechEditorView(speech: Speech(title: "Test Speech", content: "This is some test content for the speech editor preview."))
    }
    .modelContainer(for: Speech.self, inMemory: true)
}
