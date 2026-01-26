# Code Review: Estonian TTS Implementation

## Overall Assessment
The implementation is well-structured and follows the existing codebase patterns. The protocol-based abstraction is clean and the separation of concerns is good. However, there are several issues ranging from bugs to improvements.

---

## Critical Issues

### 1. ~~Cache eviction is not LRU~~ FIXED
**File:** `EstonianTTSService.swift:188-196`

```swift
private func cacheAudio(data: Data, forKey key: String) {
    if audioCache.count >= Self.maxCacheEntries {
        // Simple eviction: remove a random entry
        if let firstKey = audioCache.keys.first {
            audioCache.removeValue(forKey: firstKey)
        }
    }
    audioCache[key] = data
}
```

Dictionary key ordering is undefined in Swift. This removes an arbitrary entry, not the oldest. For a speech app where users navigate back, this could evict recently-used segments.

**Recommendation:** Use an ordered cache with timestamps or an `NSCache` with cost limits.

**Fix:** Implemented proper LRU eviction using a `CacheEntry` struct with `lastAccessTime` timestamp. The cache now evicts the least recently used entry by finding the entry with the oldest access time.

---

### 2. ~~Error not updated asynchronously~~ FIXED
**File:** `PracticeViewModel.swift:129-132`

```swift
// Check for errors from the synthesizer
if let errorMessage = synthesizer.audioErrorMessage {
    playbackError = errorMessage
}
```

For Estonian TTS, errors occur asynchronously during the API call, but this check happens synchronously immediately after `speak()` returns. The error won't be captured here.

**Recommendation:** The error is correctly set via `onComplete(0)` path in `EstonianTTSService`, but the `audioErrorMessage` check is misleading and should be removed, or errors should be propagated through a callback.

**Fix:** Moved the error check into the `onComplete` callback where it correctly handles async errors. When `duration == 0` (indicating failure), the error message is now captured from `synthesizer.audioErrorMessage`.

---

## Medium Issues

### 3. ~~Default voices duplicated in two places~~ FIXED
**Files:** `TartuNLPClient.swift` and `EstonianTTSService.swift`

The same fallback voices are defined in both `parseVoicesResponse()` (lines 169-174) and `loadAvailableVoices()` (lines 46-51).

**Recommendation:** Extract to a single source of truth, e.g., a static property on `EstonianVoice`.

**Fix:** Added `EstonianVoice.defaultVoices` static property as the single source of truth. Both `parseVoicesResponse()` and `loadAvailableVoices()` now reference this property.

---

### 4. ~~Missing `onInterruption` cleanup~~ FIXED
**File:** `AudioPlayerService.swift:136`

```swift
func stop() {
    ...
    onComplete = nil
    onInterrupt = nil  // Good
}
```

This is correct, but `onInterrupt` is never called during `stop()`. If audio is playing and `stop()` is called, the caller doesn't know it was interrupted vs completed.

**Fix:** Modified `stop()` to call `onInterrupt` when audio was actively playing. This allows callers to distinguish between natural completion (`onComplete`) and programmatic stop/interruption (`onInterrupt`).

---

### 5. ~~Voice identifier mismatch between services~~ FIXED

Estonian voices use IDs like `"mari"`, while AVSpeech uses identifiers like `"com.apple.voice.compact.en-US.Samantha"`. If a user switches a speech's language from Estonian to English, the saved `voiceIdentifier` will be invalid.

**Recommendation:** Clear `voiceIdentifier` when language changes, or store voice identifiers per-language.

**Fix:** Added `SpeechServiceFactory.isVoiceIdentifierValid(_:for:)` to validate voice identifiers against the current language. Added `EstonianVoice.knownVoiceIds` to identify Estonian voice IDs. `PracticeViewModel.init` now clears the voice identifier if it's incompatible with the speech's language.

---

## Low Priority Issues

### 6. Unused method
**File:** `SpeechSynthesizerService.swift:199-205`

```swift
func togglePlayPause() {
    if isPaused {
        resume()
    } else if isSpeaking {
        pause()
    }
}
```

This method exists on `SpeechSynthesizerService` but isn't part of the `SpeechSynthesizing` protocol and isn't used. It's duplicated in `PracticeViewModel`.

**Recommendation:** Remove it or add to protocol if needed.

---

### 7. Print statements for debugging
**Files:** `TartuNLPClient.swift:165`, `AudioPlayerService.swift:37,172`

```swift
print("Failed to parse voices response: \(error)")
print("AudioPlayerService: Failed to configure audio session: \(error)")
```

Production code should use `os.Logger` for structured logging.

---

### 8. `syncStateFromSynthesizer()` is never called
**File:** `PracticeViewModel.swift:102-105`

```swift
private func syncStateFromSynthesizer() {
    isPlaying = synthesizer.isSpeaking || isInPauseInterval
    isPaused = synthesizer.isPaused
}
```

This method is defined but never invoked.

**Recommendation:** Remove dead code.

---

### 9. Error banner retry doesn't clear error first
**File:** `PracticeView.swift:67-68`

```swift
Button {
    viewModel.play() // Retry
}
```

While `play()` does clear `playbackError`, it would be clearer to show a loading state during retry.

---

### 10. Potential memory issue with large audio cache

With 50 cached WAV segments, memory usage could be significant (WAV is uncompressed). A 10-second segment at 22kHz mono is ~440KB.

**Recommendation:** Consider adding a memory limit instead of just entry count, or use file-based caching.

---

## Style/Consistency Issues

### 11. Inconsistent error property naming

- `SpeechSynthesizerService`: `audioSessionError` (Error) + `audioErrorMessage` (String?)
- `AudioPlayerService`: `audioSessionError` (Error) + `audioErrorMessage` (String?)
- `EstonianTTSService`: `playbackError` (String?) + `audioErrorMessage` (computed)

**Recommendation:** Standardize naming across services.

---

## What's Done Well

1. **Clean protocol abstraction** - `SpeechSynthesizing` enables easy swapping of TTS backends
2. **Proper cancellation handling** - Token-based cancellation prevents stale callbacks
3. **Good error types** - `TartuNLPError` has descriptive, user-friendly messages
4. **Offline detection** - Properly detects and reports network issues
5. **Audio session handling** - Both services properly configure audio sessions and handle interruptions
6. **Factory pattern** - Clean separation of service creation logic
7. **Rate mapping** - Correct formula for converting between rate scales

---

## Summary

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 2 | **All Fixed** |
| Medium | 3 | **All Fixed** |
| Low | 5 | Open |

The implementation is functional and well-architected. ~~The critical issues around cache eviction and async error handling should be addressed.~~ Critical issues have been resolved. Medium priority issues (duplicate defaults, missing interruption notification, voice identifier mismatch) have also been resolved.
