# Code Review: Speech Practice App

**Date:** 2026-01-26
**Reviewer:** Claude
**Codebase Version:** Initial implementation

## Summary

The codebase is well-structured with clear separation of concerns (MVVM). However, there are several issues ranging from bugs to potential improvements.

**Overall Assessment:** Solid foundation with a few bugs and improvements needed before production use.

---

## Critical Issues

### 1. ~~Bug: Paragraph parsing can fail with duplicate lines~~ FIXED

**File:** `Services/TextParser.swift`
**Severity:** Critical
**Type:** Bug
**Status:** ✅ FIXED (2026-01-26)

**Problem:** Using `range(of:)` to find a line would match the first occurrence. If the same text appeared multiple times, it could find the wrong range or skip lines entirely.

**Resolution:** Rewrote `parseIntoParagraphs()` to iterate through the string character by character, properly tracking paragraph start/end indices instead of searching for substrings.

---

### 2. ~~Bug: Speech list doesn't refresh after editing~~ FIXED

**File:** `Views/SpeechListView.swift`
**Severity:** Critical
**Type:** Bug
**Status:** ✅ FIXED (2026-01-26)

**Problem:** The list only fetched on `onAppear`. After editing a speech and returning, the list wouldn't reflect title/content changes until a full view reload.

**Resolution:** Replaced manual ViewModel fetch with SwiftData's `@Query` property wrapper for automatic updates. Removed `SpeechListViewModel` as it's no longer needed.

---

### 3. ~~Memory: Callback retained after view dismissal~~ FIXED

**File:** `Services/SpeechSynthesizerService.swift`
**Severity:** Critical
**Type:** Memory Management
**Status:** ✅ FIXED (2026-01-26)

**Problem:** The completion closure could reference a deallocated view model if the view was dismissed while speech was playing.

**Resolution:** Added `cleanup()` method to `SpeechSynthesizerService` that clears callbacks and stops synthesis. Updated `PracticeViewModel.cleanup()` to call `synthesizer.cleanup()`. Also removed unused `onUtteranceProgress` property.

---

## High Priority Issues

### 4. Thread safety: Combine subscriptions on @Observable

**File:** `ViewModels/PracticeViewModel.swift:87-99`
**Severity:** High
**Type:** Architecture

```swift
synthesizer.$isSpeaking
    .receive(on: DispatchQueue.main)
    .sink { [weak self] isSpeaking in
        self?.isPlaying = isSpeaking || (self?.isInPauseInterval ?? false)
    }
    .store(in: &cancellables)
```

**Problem:** Using Combine's `.sink` with `@Observable` is redundant and can cause issues. `@Observable` already provides automatic observation through Swift's observation system.

**Fix:** Remove Combine subscriptions and directly observe the synthesizer's properties, or refactor to use a callback-based approach.

---

### 5. Missing audio interruption handling

**File:** `Services/SpeechSynthesizerService.swift`
**Severity:** High
**Type:** Missing Feature

**Problem:** No handling for audio interruptions (phone calls, Siri, other apps). The app should observe `AVAudioSession.interruptionNotification` and pause/resume appropriately.

**Fix:** Add notification observer:
```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleInterruption),
    name: AVAudioSession.interruptionNotification,
    object: nil
)
```

---

### 6. Race condition in pause interval

**File:** `ViewModels/PracticeViewModel.swift:248-266`
**Severity:** High
**Type:** Concurrency Bug

```swift
pauseTask = Task { [weak self] in
    let steps = Int(duration * 10)
    for i in 0..<steps {
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(100))
        // ...
    }
}
```

**Problem:** The `pauseTask` uses `[weak self]` but the closure accesses `duration` after awaits. If granularity changes mid-pause, behavior is undefined.

**Fix:** Capture all needed values at task creation time and add proper cancellation checks.

---

## Medium Priority Issues

### 7. Inefficient: HapticManager creates new generators every call

**File:** `Services/HapticManager.swift:8-11`
**Severity:** Medium
**Type:** Performance

```swift
func playNavigationFeedback() {
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.prepare()
    generator.impactOccurred()
}
```

**Problem:** Creating a new generator each time is wasteful. Generators should be cached and `prepare()` called ahead of time for immediate feedback.

**Fix:**
```swift
final class HapticManager {
    static let shared = HapticManager()

    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    // ... cache other generators

    func playNavigationFeedback() {
        mediumImpact.impactOccurred()
    }
}
```

---

### 8. SwiftData: Missing index on frequently queried field

**File:** `Models/Speech.swift`
**Severity:** Medium
**Type:** Performance

**Problem:** The `updatedAt` field is used for sorting but lacks an index attribute, which will slow down queries as the dataset grows.

**Fix:**
```swift
@Attribute(.unique) var id: UUID
// Consider adding index for updatedAt if SwiftData supports it in future versions
```

---

### 9. Unnecessary double-save in settings

**File:** `ViewModels/PracticeViewModel.swift:203-206`
**Severity:** Medium
**Type:** Redundant Code

```swift
func updateRate(_ rate: Float) {
    settings.setRate(rate)
    settings.save()  // Also saves in didSet on line 19-21
}
```

**Problem:** The `settings` property already has a `didSet` that calls `save()`, causing double saves to UserDefaults.

**Fix:** Remove the explicit `save()` call from update methods since `didSet` handles it:
```swift
func updateRate(_ rate: Float) {
    settings.setRate(rate)
    // didSet will call save() automatically
}
```

---

### 10. Empty state shows when searching with no results

**File:** `Views/SpeechListView.swift:12`
**Severity:** Medium
**Type:** UX Bug

```swift
if viewModel.speeches.isEmpty {
    emptyStateView
}
```

**Problem:** Should check `filteredSpeeches.isEmpty` and differentiate between "No results" for search vs "No speeches" for empty state.

**Fix:**
```swift
if viewModel.speeches.isEmpty {
    emptyStateView  // "No speeches yet"
} else if viewModel.filteredSpeeches.isEmpty {
    noSearchResultsView  // "No results for 'query'"
} else {
    speechListContent
}
```

---

## Low Priority / Code Quality

### 11. Unused property

**File:** `Services/SpeechSynthesizerService.swift:15`
**Severity:** Low
**Type:** Dead Code

```swift
private var onUtteranceProgress: ((Double) -> Void)?
```

**Problem:** This property is declared but never assigned or used.

**Fix:** Remove the unused property.

---

### 12. Magic numbers

**File:** `ViewModels/PracticeViewModel.swift:249`
**Severity:** Low
**Type:** Code Quality

```swift
let steps = Int(duration * 10) // Update every 0.1 seconds
```

**Problem:** Magic number should be a named constant for clarity and maintainability.

**Fix:**
```swift
private static let pauseUpdateInterval: TimeInterval = 0.1

let steps = Int(duration / Self.pauseUpdateInterval)
```

---

### 13. Inconsistent error handling

**Files:** Multiple ViewModels
**Severity:** Low
**Type:** Error Handling

```swift
try? modelContext.save()
```

**Problem:** Some operations use `try?` silently. Failed saves should at least be logged or shown to the user.

**Fix:**
```swift
do {
    try modelContext.save()
} catch {
    print("Failed to save: \(error)")
    // Consider showing user-facing error
}
```

---

### 14. displayName should be localized

**File:** `Models/SpeechSegment.swift:25-31`
**Severity:** Low
**Type:** Localization

```swift
var displayName: String {
    switch self {
    case .sentence: return "Sentence"
    case .paragraph: return "Paragraph"
    }
}
```

**Problem:** Hardcoded English strings should use localization.

**Fix:**
```swift
var displayName: String {
    switch self {
    case .sentence: return String(localized: "Sentence")
    case .paragraph: return String(localized: "Paragraph")
    }
}
```

---

### 15. Missing accessibility labels

**File:** `Views/PracticeView.swift:129-156`
**Severity:** Low
**Type:** Accessibility

**Problem:** Navigation buttons lack accessibility labels for VoiceOver users.

**Fix:**
```swift
Button {
    viewModel.goToPreviousSegment()
} label: {
    Image(systemName: "backward.fill")
        .font(.title2)
}
.accessibilityLabel("Previous segment")
.disabled(!viewModel.canGoBack)
```

---

## Suggestions for Future Improvement

### 16. Consider using SwiftData's @Query

Instead of manual fetch in ViewModel, use `@Query` directly in the view for automatic updates:

```swift
struct SpeechListView: View {
    @Query(sort: \Speech.updatedAt, order: .reverse)
    var speeches: [Speech]
    // ...
}
```

---

### 17. Add Sendable conformance

`SpeechSegment` and `PlaybackSettings` should conform to `Sendable` for safe concurrent access:

```swift
struct SpeechSegment: Identifiable, Equatable, Sendable {
    // ...
}
```

---

### 18. Consider cancellation token for speech

Allow cancelling speech synthesis with proper cleanup instead of relying solely on `stop()`. This would provide better control over the synthesis lifecycle.

---

## What's Good

- Clean MVVM architecture with proper separation of concerns
- Good use of `@Observable` macro for iOS 17+
- Proper `@MainActor` isolation for UI-related code
- Comprehensive haptic feedback throughout the app
- Character limit enforcement at model level
- Localization-ready structure with `.xcstrings` file
- Good use of `NLTokenizer` for accurate sentence parsing
- Well-organized file structure following conventions
- SwiftData integration for persistence
- Dark mode support via system theme

---

## Issue Summary

| Severity | Count | Fixed |
|----------|-------|-------|
| Critical | 3 | ✅ 3 |
| High | 3 | 0 |
| Medium | 4 | 0 |
| Low | 5 | 0 |
| Suggestions | 3 | 0 |
| **Total** | **18** | **3** |

---

## Recommended Priority for Fixes

1. ~~Fix paragraph parsing bug (#1)~~ ✅ DONE
2. ~~Fix speech list refresh issue (#2)~~ ✅ DONE
3. ~~Fix memory management for callbacks (#3)~~ ✅ DONE
4. Add audio interruption handling (#5)
5. Remove redundant Combine subscriptions (#4)
6. Fix race condition in pause interval (#6)
7. Fix empty state vs no search results (#10)
8. Address remaining medium/low issues
