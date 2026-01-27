import SwiftUI

// MARK: - Help Topic Models

struct HelpSubtopic: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let content: LocalizedStringKey
}

struct HelpTopic: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let iconName: String
    let content: LocalizedStringKey
    let subtopics: [HelpSubtopic]

    init(title: LocalizedStringKey, iconName: String, content: LocalizedStringKey, subtopics: [HelpSubtopic] = []) {
        self.title = title
        self.iconName = iconName
        self.content = content
        self.subtopics = subtopics
    }
}

// MARK: - Help View

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let helpTopics: [HelpTopic] = [
        HelpTopic(
            title: "Getting Started",
            iconName: "star",
            content: "help.gettingStarted.content"
        ),
        HelpTopic(
            title: "Playback Controls",
            iconName: "play.circle",
            content: "help.playbackControls.content"
        ),
        HelpTopic(
            title: "Speech Rate",
            iconName: "gauge.with.needle",
            content: "help.speechRate.content"
        ),
        HelpTopic(
            title: "Pause Mode",
            iconName: "pause.circle",
            content: "help.pauseMode.content"
        ),
        HelpTopic(
            title: "Segments & Granularity",
            iconName: "text.alignleft",
            content: "help.segments.content"
        ),
        HelpTopic(
            title: "Text-to-Speech Providers",
            iconName: "waveform",
            content: "help.ttsProviders.content",
            subtopics: [
                HelpSubtopic(
                    title: "iOS (Offline)",
                    content: "help.ttsProviders.ios.content"
                ),
                HelpSubtopic(
                    title: "TartuNLP",
                    content: "help.ttsProviders.tartuNLP.content"
                ),
                HelpSubtopic(
                    title: "Microsoft Azure",
                    content: "help.ttsProviders.azure.content"
                )
            ]
        ),
        HelpTopic(
            title: "Voice Selection",
            iconName: "person.wave.2",
            content: "help.voiceSelection.content"
        ),
        HelpTopic(
            title: "Microsoft Azure Setup",
            iconName: "cloud",
            content: "help.azureSetup.content",
            subtopics: [
                HelpSubtopic(
                    title: "help.azureSetup.createAccount.title",
                    content: "help.azureSetup.createAccount.content"
                ),
                HelpSubtopic(
                    title: "help.azureSetup.createResource.title",
                    content: "help.azureSetup.createResource.content"
                ),
                HelpSubtopic(
                    title: "help.azureSetup.getApiKey.title",
                    content: "help.azureSetup.getApiKey.content"
                ),
                HelpSubtopic(
                    title: "help.azureSetup.configureApp.title",
                    content: "help.azureSetup.configureApp.content"
                )
            ]
        ),
        HelpTopic(
            title: "Language Detection",
            iconName: "globe",
            content: "help.languageDetection.content"
        ),
        HelpTopic(
            title: "Tips & Best Practices",
            iconName: "lightbulb",
            content: "help.tips.content",
            subtopics: [
                HelpSubtopic(
                    title: "help.tips.startSlow.title",
                    content: "help.tips.startSlow.content"
                ),
                HelpSubtopic(
                    title: "help.tips.usePauseMode.title",
                    content: "help.tips.usePauseMode.content"
                ),
                HelpSubtopic(
                    title: "help.tips.practiceChunks.title",
                    content: "help.tips.practiceChunks.content"
                ),
                HelpSubtopic(
                    title: "help.tips.reviewRegularly.title",
                    content: "help.tips.reviewRegularly.content"
                )
            ]
        )
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(helpTopics) { topic in
                    Section {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(topic.content)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if !topic.subtopics.isEmpty {
                                    ForEach(topic.subtopics) { subtopic in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(subtopic.title)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Text(subtopic.content)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        } label: {
                            Label(topic.title, systemImage: topic.iconName)
                        }
                        .accessibilityHint("Double tap to expand or collapse")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    HelpView()
}
