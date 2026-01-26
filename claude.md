# Speech Practice App

An iOS app that helps users practice speeches by reading text aloud with configurable pacing and navigation.

## Tech Stack

- **UI**: SwiftUI (iOS 17+)
- **Persistence**: SwiftData
- **Speech**: AVFoundation (AVSpeechSynthesizer)
- **Language**: Swift 5.9+
- **Architecture**: MVVM

## Core Features

### 1. Speech Input
- Text editor for entering speech text (up to 10,000 characters)
- Character count display
- Save/load speeches with SwiftData

### 2. Text-to-Speech Playback
- Uses AVSpeechSynthesizer for reading text aloud
- Configurable speech rate (0.1 to 1.0, default 0.5)
- Voice selection from available system voices
- Support for multiple languages (starting with English)

### 3. Pause Mode
- After reading each segment, pause for the same duration it took to read
- Configurable granularity: pause after each **sentence** or **paragraph**
- Toggle to enable/disable pause mode

### 4. Navigation
- Skip forward/backward between segments (sentences or paragraphs)
- Visual indicator of current segment and progress
- Tap on text to jump to specific segment

### 5. Additional Features
- Dark mode support (automatic system theme)
- Haptic feedback for navigation and state changes
- Localization-ready structure for future languages (Estonian, etc.)

## Project Structure

```
speech-practice/
├── SpeechPracticeApp.swift       # App entry point
├── Models/
│   ├── Speech.swift              # SwiftData model for saved speeches
│   ├── SpeechSegment.swift       # Represents a sentence or paragraph
│   └── PlaybackSettings.swift    # User preferences for playback
├── Views/
│   ├── ContentView.swift         # Main navigation
│   ├── SpeechListView.swift      # List of saved speeches
│   ├── SpeechEditorView.swift    # Create/edit speech text
│   ├── PracticeView.swift        # Main practice screen
│   └── SettingsView.swift        # Playback settings
├── ViewModels/
│   ├── SpeechListViewModel.swift
│   ├── SpeechEditorViewModel.swift
│   └── PracticeViewModel.swift   # Core playback logic
├── Services/
│   ├── SpeechSynthesizer.swift   # Wraps AVSpeechSynthesizer
│   ├── TextParser.swift          # Splits text into segments
│   └── HapticManager.swift       # Haptic feedback
├── Resources/
│   └── Localizable.xcstrings     # Localization strings
└── Extensions/
    └── String+Parsing.swift      # Text parsing utilities
```

## Data Models

### Speech (SwiftData)
```swift
@Model
class Speech {
    var id: UUID
    var title: String
    var content: String          // Up to 10,000 characters
    var createdAt: Date
    var updatedAt: Date
    var language: String         // BCP 47 code, e.g., "en-US"
}
```

### SpeechSegment
```swift
struct SpeechSegment: Identifiable {
    let id: UUID
    let text: String
    let range: Range<String.Index>  // Position in original text
    let type: SegmentType           // .sentence or .paragraph
}

enum SegmentType {
    case sentence
    case paragraph
}
```

### PlaybackSettings
```swift
struct PlaybackSettings {
    var rate: Float              // 0.1 to 1.0 (AVSpeechUtteranceDefaultSpeechRate = 0.5)
    var pauseEnabled: Bool       // Enable echo pause
    var pauseGranularity: SegmentType  // Pause after sentence or paragraph
    var voiceIdentifier: String? // Selected voice, nil = default
}
```

## Key Implementation Details

### Text Parsing
Use NLTokenizer for accurate sentence/paragraph detection:
```swift
import NaturalLanguage

func parseIntoSentences(_ text: String) -> [SpeechSegment] {
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    // Enumerate tokens and create segments
}

func parseIntoParagraphs(_ text: String) -> [SpeechSegment] {
    // Split by newlines, filter empty
    text.components(separatedBy: .newlines)
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}
```

### Speech Synthesis
```swift
class SpeechSynthesizer: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    @Published var isSpeaking = false
    @Published var currentSegmentIndex: Int = 0

    func speak(_ segment: SpeechSegment, rate: Float, voice: AVSpeechSynthesisVoice?) {
        let utterance = AVSpeechUtterance(string: segment.text)
        utterance.rate = rate
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    // Implement AVSpeechSynthesizerDelegate for completion callbacks
}
```

### Pause Duration Calculation
Track the time from speech start to completion, then pause for the same duration:
```swift
var segmentStartTime: Date?

func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                       didFinish utterance: AVSpeechUtterance) {
    guard let startTime = segmentStartTime else { return }
    let duration = Date().timeIntervalSince(startTime)

    if settings.pauseEnabled {
        Task {
            try await Task.sleep(for: .seconds(duration))
            await moveToNextSegment()
        }
    } else {
        moveToNextSegment()
    }
}
```

### Haptic Feedback
```swift
class HapticManager {
    static let shared = HapticManager()

    func playNavigationFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    func playSegmentCompleteFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}
```

## UI Guidelines

### Practice View Layout
```
┌─────────────────────────────────┐
│  [Back]    Title         [⚙️]   │  <- Navigation bar
├─────────────────────────────────┤
│                                 │
│  Previous segment (dimmed)      │
│                                 │
│  ┌─────────────────────────┐   │
│  │ CURRENT SEGMENT         │   │  <- Highlighted, larger text
│  │ (being read aloud)      │   │
│  └─────────────────────────┘   │
│                                 │
│  Next segment (dimmed)          │
│                                 │
├─────────────────────────────────┤
│  ○○○●○○○○○                      │  <- Progress dots
├─────────────────────────────────┤
│  [⏮️]   [⏸️ / ▶️]   [⏭️]        │  <- Controls
│         0.5x ━━━●━━━ 1.0x       │  <- Speed slider
└─────────────────────────────────┘
```

### Accessibility
- VoiceOver support for all controls
- Dynamic Type for text sizing
- Sufficient color contrast in both light/dark modes

## Localization

Structure for future language support:
- Use String Catalogs (Localizable.xcstrings) for UI strings
- Store speech language preference per Speech model
- Voice selection filtered by language

Future languages planned:
- Estonian (et-EE)
- Additional languages as needed

## Testing Strategy

### Unit Tests
- TextParser: sentence/paragraph splitting accuracy
- PlaybackSettings: validation of rate bounds
- Speech model: character limit enforcement

### UI Tests
- Navigation flow through all screens
- Playback controls interaction
- Settings persistence

### Manual Testing Checklist
- [ ] Create speech with 10,000 characters
- [ ] Test pause mode with both sentence and paragraph granularity
- [ ] Verify speed slider affects playback rate
- [ ] Test forward/backward navigation during playback
- [ ] Verify haptic feedback triggers
- [ ] Test dark mode appearance
- [ ] Test with different system voices

## Performance Considerations

- Lazy parsing: only parse visible segments initially
- Limit to 10,000 characters enforced at input level
- Use MainActor for UI updates from speech callbacks
- Efficient SwiftData queries with proper indexing on `updatedAt`

## Error Handling

- Handle AVSpeechSynthesizer failures gracefully
- Show user-friendly messages when no voices available
- Validate text length before saving
- Handle interruptions (phone calls, etc.) by pausing playback
