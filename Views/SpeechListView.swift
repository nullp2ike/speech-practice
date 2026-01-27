import SwiftUI
import SwiftData

struct SpeechToEdit: Hashable {
    let speech: Speech

    func hash(into hasher: inout Hasher) {
        hasher.combine(speech.id)
    }

    static func == (lhs: SpeechToEdit, rhs: SpeechToEdit) -> Bool {
        lhs.speech.id == rhs.speech.id
    }
}

struct SpeechListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Speech.updatedAt, order: .reverse) private var speeches: [Speech]
    @State private var searchText = ""
    @State private var showingNewSpeechSheet = false
    @State private var showingHelp = false
    @State private var navigationPath = NavigationPath()

    private var filteredSpeeches: [Speech] {
        if searchText.isEmpty {
            return speeches
        }
        return speeches.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if speeches.isEmpty {
                    emptyStateView
                } else if filteredSpeeches.isEmpty {
                    noSearchResultsView
                } else {
                    speechListContent
                }
            }
            .navigationTitle("Speeches")
            .navigationDestination(for: SpeechToEdit.self) { item in
                SpeechEditorView(speech: item.speech, navigationPath: $navigationPath)
            }
            .navigationDestination(for: Speech.self) { speech in
                SpeechDetailView(speech: speech)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewSpeechSheet = true
                        HapticManager.shared.playLightImpact()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search speeches")
            .sheet(isPresented: $showingNewSpeechSheet) {
                NewSpeechSheet { title in
                    let speech = createSpeech(title: title)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        navigationPath.append(SpeechToEdit(speech: speech))
                    }
                }
            }
            .sheet(isPresented: $showingHelp) {
                HelpView()
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Speeches", systemImage: "text.bubble")
        } description: {
            Text("Create your first speech to start practicing.")
        } actions: {
            Button("Create Speech") {
                showingNewSpeechSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var noSearchResultsView: some View {
        ContentUnavailableView.search(text: searchText)
    }

    private var speechListContent: some View {
        List {
            ForEach(filteredSpeeches) { speech in
                NavigationLink(value: speech) {
                    SpeechRowView(speech: speech)
                }
            }
            .onDelete(perform: deleteSpeeches)
        }
    }

    @discardableResult
    private func createSpeech(title: String) -> Speech {
        let speech = Speech(title: title.isEmpty ? "Untitled Speech" : title)
        modelContext.insert(speech)
        do {
            try modelContext.save()
        } catch {
            print("Failed to save new speech: \(error)")
        }
        HapticManager.shared.playLightImpact()
        return speech
    }

    private func deleteSpeeches(at offsets: IndexSet) {
        for index in offsets {
            let speech = filteredSpeeches[index]
            modelContext.delete(speech)
        }
        HapticManager.shared.playLightImpact()
    }
}

// MARK: - Speech Row View

struct SpeechRowView: View {
    let speech: Speech

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(speech.title.isEmpty ? "Untitled" : speech.title)
                .font(.headline)

            Text(speech.content.isEmpty ? "No content" : speech.content)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(speech.formattedEstimatedDuration)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New Speech Sheet

struct NewSpeechSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""

    let onCreate: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Speech Title") {
                    TextField("Enter title", text: $title)
                }
            }
            .navigationTitle("New Speech")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(title)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Speech Detail View

struct SpeechDetailView: View {
    let speech: Speech

    var body: some View {
        List {
            NavigationLink {
                SpeechEditorView(speech: speech)
            } label: {
                Label("Edit Speech", systemImage: "pencil")
            }

            NavigationLink {
                PracticeView(speech: speech)
            } label: {
                Label("Practice", systemImage: "play.fill")
            }

            Section("Info") {
                LabeledContent("Characters", value: "\(speech.content.count)")
                LabeledContent("Created", value: speech.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Modified", value: speech.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .navigationTitle(speech.title.isEmpty ? "Untitled" : speech.title)
    }
}

#Preview {
    SpeechListView()
        .modelContainer(for: Speech.self, inMemory: true)
}
