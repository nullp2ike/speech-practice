import SwiftUI

struct PracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PracticeViewModel
    @State private var showingSettings = false

    /// Maximum number of segments to show as individual progress dots.
    /// Beyond this threshold, a progress bar is shown instead for better UX.
    private static let maxProgressDots = 20

    init(speech: Speech) {
        _viewModel = State(initialValue: PracticeViewModel(speech: speech))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segments display
            segmentsView
                .frame(maxHeight: .infinity)

            Divider()

            // Progress indicator
            progressView
                .padding(.vertical, 12)

            Divider()

            // Controls
            controlsView
                .padding()
        }
        .navigationTitle(viewModel.speech.title.isEmpty ? "Practice" : viewModel.speech.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // MARK: - Segments View

    private var segmentsView: some View {
        Group {
            if viewModel.segments.isEmpty {
                emptySegmentsView
            } else {
                segmentsScrollView
            }
        }
    }

    private var emptySegmentsView: some View {
        ContentUnavailableView {
            Label("No Content", systemImage: "text.justify.left")
        } description: {
            Text("This speech has no content to practice. Add some text to get started.")
        }
    }

    private var segmentsScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(viewModel.segments.enumerated()), id: \.element.id) { index, segment in
                        SegmentView(
                            segment: segment,
                            isCurrent: index == viewModel.currentSegmentIndex,
                            isPrevious: index == viewModel.currentSegmentIndex - 1,
                            isNext: index == viewModel.currentSegmentIndex + 1
                        )
                        .id(segment.id)
                        .onTapGesture {
                            viewModel.goToSegment(at: index)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.currentSegmentIndex) { _, _ in
                if let segment = viewModel.currentSegment {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(segment.id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 8) {
            // Progress dots (use dots for small counts, progress bar for large)
            if viewModel.segments.count <= Self.maxProgressDots {
                progressDots
            } else {
                ProgressView(value: viewModel.progress)
                    .padding(.horizontal)
            }

            // Progress text
            HStack {
                Text(viewModel.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.isInPauseInterval {
                    Spacer()
                    Text("Pause: \(String(format: "%.1f", viewModel.pauseTimeRemaining))s")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<viewModel.segments.count, id: \.self) { index in
                Circle()
                    .fill(index == viewModel.currentSegmentIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .onTapGesture {
                        viewModel.goToSegment(at: index)
                    }
            }
        }
    }

    // MARK: - Controls View

    private var controlsView: some View {
        VStack(spacing: 16) {
            // Main playback controls
            HStack(spacing: 40) {
                // Previous
                Button {
                    viewModel.goToPreviousSegment()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Previous segment")
                .disabled(!viewModel.canGoBack)

                // Play/Pause
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: viewModel.playPauseIcon)
                        .font(.largeTitle)
                        .frame(width: 60, height: 60)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .accessibilityLabel(viewModel.isPlaying && !viewModel.isPaused ? "Pause" : "Play")

                // Next
                Button {
                    viewModel.goToNextSegment()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Next segment")
                .disabled(!viewModel.canGoForward)
            }

            // Speed slider
            HStack {
                Text("\(String(format: "%.1f", PlaybackSettings.minRate))x")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { Double(viewModel.settings.rate) },
                        set: { viewModel.updateRate(Float($0)) }
                    ),
                    in: Double(PlaybackSettings.minRate)...Double(PlaybackSettings.maxRate),
                    step: 0.05
                )

                Text("\(String(format: "%.1f", PlaybackSettings.maxRate))x")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Current speed indicator
            Text("Speed: \(String(format: "%.2f", viewModel.settings.rate))x")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Segment View

struct SegmentView: View {
    let segment: SpeechSegment
    let isCurrent: Bool
    let isPrevious: Bool
    let isNext: Bool

    var body: some View {
        Text(segment.text)
            .font(isCurrent ? .title3 : .body)
            .fontWeight(isCurrent ? .semibold : .regular)
            .foregroundStyle(foregroundStyle)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCurrent ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .animation(.easeInOut(duration: 0.2), value: isCurrent)
    }

    private var foregroundStyle: Color {
        if isCurrent {
            return .primary
        } else if isPrevious || isNext {
            return .secondary
        } else {
            return .secondary.opacity(0.6)
        }
    }

    private var backgroundColor: Color {
        if isCurrent {
            return Color.accentColor.opacity(0.1)
        }
        return Color(.secondarySystemBackground)
    }
}

#Preview {
    NavigationStack {
        PracticeView(speech: Speech(
            title: "Test Speech",
            content: "This is the first sentence. This is the second sentence. And here is the third one.\n\nThis is a new paragraph with more content to practice reading aloud."
        ))
    }
}
