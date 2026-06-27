# Smart Auto-Gap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make TangoDisplay inject only the silence needed to reach the configured absolute perceived gap between automatically advancing tracks.

**Architecture:** Pure smart-gap arithmetic and PCM-envelope measurement live in `TangoDisplayCore`, where the existing lightweight test runner can exercise them. The AVFoundation actor decodes files and delegates measurement to the core, while `LocalPlayerSource` owns pair-identified look-ahead state and schedules the computed silent buffer with audible-completion semantics. Existing TangoDisplay settings and exception controls remain unchanged.

**Tech Stack:** Swift 5.9, AVFoundation/AVAudioEngine, Swift Package Manager, TangoDisplayCore, custom `TangoDisplayTests` runner.

---

## File map

- Create `Sources/TangoDisplayCore/Audio/SmartAutoGap.swift`: validated silence result, 10 ms peak-envelope measurement, and exact injected-gap calculation.
- Modify `Tests/TangoDisplayTests/TestRunner.swift`: unit coverage for arithmetic, PCM measurement, and pair/policy decisions.
- Modify `Sources/TangoDisplay/Services/AudioSilenceAnalyzer.swift`: AVAudioFile decoding and session cache around core measurement.
- Modify `Sources/TangoDisplay/Services/LocalPlayerSource.swift`: pair-bound look-ahead analysis, policy application, audible silent-buffer completion, and legacy-state removal.
- Reference `docs/superpowers/specs/2026-06-27-smart-auto-gap-design.md`: approved behavior and acceptance criteria.

### Task 1: Exact smart-gap arithmetic

**Files:**
- Create: `Sources/TangoDisplayCore/Audio/SmartAutoGap.swift`
- Modify: `Tests/TangoDisplayTests/TestRunner.swift`

- [ ] **Step 1: Add failing arithmetic tests**

Add before the main entry point:

```swift
func runSmartAutoGapCalculationTests() {
    suite("SmartAutoGap — injected silence") {
        test("5 target minus 1 trailing minus 1 leading is 3") {
            try expectEqual(SmartAutoGap.injectedDuration(target: 5, trailing: 1, leading: 1), 3)
        }
        test("intrinsic silence equal to target injects zero") {
            try expectEqual(SmartAutoGap.injectedDuration(target: 5, trailing: 2, leading: 3), 0)
        }
        test("intrinsic silence above target injects zero") {
            try expectEqual(SmartAutoGap.injectedDuration(target: 5, trailing: 4, leading: 4), 0)
        }
        test("no intrinsic silence injects full target") {
            try expectEqual(SmartAutoGap.injectedDuration(target: 5, trailing: 0, leading: 0), 5)
        }
        test("invalid measurements cannot create invalid output") {
            try expectEqual(SmartAutoGap.injectedDuration(target: 5, trailing: -1, leading: .nan), 5)
            try expectEqual(SmartAutoGap.injectedDuration(target: .infinity, trailing: 1, leading: 1), 0)
        }
    }
}
```

Call `runSmartAutoGapCalculationTests()` from the main entry point.

- [ ] **Step 2: Run the test runner and confirm red state**

Run: `swift run TangoDisplayTests`

Expected: compile failure containing `cannot find 'SmartAutoGap' in scope`.

- [ ] **Step 3: Implement the minimal calculation API**

Create `Sources/TangoDisplayCore/Audio/SmartAutoGap.swift`:

```swift
import Foundation

public enum SmartAutoGap {
    public static func injectedDuration(
        target: Double,
        trailing: Double,
        leading: Double
    ) -> Double {
        guard target.isFinite, target > 0 else { return 0 }
        let safeTrailing = trailing.isFinite ? max(0, trailing) : 0
        let safeLeading = leading.isFinite ? max(0, leading) : 0
        return max(0, target - safeTrailing - safeLeading)
    }
}
```

- [ ] **Step 4: Run tests and confirm green state**

Run: `swift run TangoDisplayTests`

Expected: all tests pass, including five `SmartAutoGap — injected silence` cases.

- [ ] **Step 5: Commit arithmetic**

```bash
git add Sources/TangoDisplayCore/Audio/SmartAutoGap.swift Tests/TangoDisplayTests/TestRunner.swift
git commit -m "feat: add exact smart auto-gap calculation"
```

### Task 2: MyLonga-compatible silence measurement

**Files:**
- Modify: `Sources/TangoDisplayCore/Audio/SmartAutoGap.swift`
- Modify: `Tests/TangoDisplayTests/TestRunner.swift`

- [ ] **Step 1: Add failing synthetic PCM tests**

Add this suite to `TestRunner.swift` and call it from the main entry point:

```swift
func runSmartAutoGapMeasurementTests() {
    func repeated(_ value: Float, seconds: Double, rate: Double) -> [Float] {
        [Float](repeating: value, count: Int((seconds * rate).rounded()))
    }
    let rate = 1_000.0

    suite("SmartAutoGap — PCM silence measurement") {
        test("measures leading and trailing silence") {
            let channel = repeated(0, seconds: 1, rate: rate)
                + repeated(0.5, seconds: 2, rate: rate)
                + repeated(0, seconds: 1, rate: rate)
            let result = SmartAutoGap.measureSilence(samples: [channel], sampleRate: rate)
            try expect(abs(result.leading - 1) < 0.011)
            try expect(abs(result.trailing - 1) < 0.011)
        }
        test("continuous tone has no intrinsic silence") {
            let result = SmartAutoGap.measureSilence(
                samples: [repeated(0.5, seconds: 1, rate: rate)], sampleRate: rate)
            try expectEqual(result, .zero)
        }
        test("all-silent audio counts once at the start") {
            let result = SmartAutoGap.measureSilence(
                samples: [repeated(0, seconds: 1, rate: rate)], sampleRate: rate)
            try expect(abs(result.leading - 1) < 0.011)
            try expectEqual(result.trailing, 0)
        }
        test("audible content in either stereo channel breaks silence") {
            let left = repeated(0, seconds: 1, rate: rate)
            let right = repeated(0, seconds: 0.5, rate: rate)
                + repeated(0.5, seconds: 0.5, rate: rate)
            let result = SmartAutoGap.measureSilence(samples: [left, right], sampleRate: rate)
            try expect(abs(result.leading - 0.5) < 0.011)
            try expectEqual(result.trailing, 0)
        }
        test("threshold is inclusive at 4 over 255") {
            let boundary = Float(4.0 / 255.0)
            let result = SmartAutoGap.measureSilence(
                samples: [repeated(boundary, seconds: 0.02, rate: rate)
                    + repeated(boundary + 0.001, seconds: 0.02, rate: rate)],
                sampleRate: rate)
            try expect(abs(result.leading - 0.02) < 0.011)
        }
        test("sub-block audio remains bounded") {
            let result = SmartAutoGap.measureSilence(samples: [[0, 0, 0]], sampleRate: rate)
            try expect(result.leading <= 0.0031)
            try expectEqual(result.trailing, 0)
        }
    }
}
```

- [ ] **Step 2: Run tests and confirm missing API failure**

Run: `swift run TangoDisplayTests`

Expected: compile failures for `measureSilence` and `.zero`.

- [ ] **Step 3: Implement the 10 ms cross-channel peak envelope**

Add to `SmartAutoGap.swift`:

```swift
public struct IntrinsicSilence: Equatable, Sendable {
    public let leading: Double
    public let trailing: Double

    public init(leading: Double, trailing: Double) {
        self.leading = leading
        self.trailing = trailing
    }

    public static let zero = IntrinsicSilence(leading: 0, trailing: 0)
}

public extension SmartAutoGap {
    static func measureSilence(samples: [[Float]], sampleRate: Double) -> IntrinsicSilence {
        guard sampleRate.isFinite, sampleRate > 0,
              let first = samples.first, !first.isEmpty else { return .zero }
        let frameCount = samples.map(\.count).min() ?? 0
        guard frameCount > 0 else { return .zero }
        let blockFrames = max(1, Int((sampleRate * 0.01).rounded()))
        let threshold = Float(4.0 / 255.0)
        var silentFrames: [Int] = []
        var start = 0
        while start < frameCount {
            let end = min(start + blockFrames, frameCount)
            var peak: Float = 0
            for channel in samples {
                for index in start..<end { peak = max(peak, abs(channel[index])) }
            }
            silentFrames.append(peak <= threshold ? end - start : 0)
            start = end
        }
        var leadingFrames = 0
        for frames in silentFrames {
            guard frames > 0 else { break }
            leadingFrames += frames
        }
        if leadingFrames == frameCount {
            return IntrinsicSilence(leading: Double(frameCount) / sampleRate, trailing: 0)
        }
        var trailingFrames = 0
        for frames in silentFrames.reversed() {
            guard frames > 0 else { break }
            trailingFrames += frames
        }
        return IntrinsicSilence(
            leading: Double(leadingFrames) / sampleRate,
            trailing: Double(trailingFrames) / sampleRate
        )
    }
}
```

- [ ] **Step 4: Run all core tests**

Run: `swift run TangoDisplayTests`

Expected: all tests pass, including six PCM measurement cases.

- [ ] **Step 5: Commit measurement**

```bash
git add Sources/TangoDisplayCore/Audio/SmartAutoGap.swift Tests/TangoDisplayTests/TestRunner.swift
git commit -m "feat: measure intrinsic silence for smart gaps"
```

### Task 3: Replace file analyzer internals

**Files:**
- Modify: `Sources/TangoDisplay/Services/AudioSilenceAnalyzer.swift`

- [ ] **Step 1: Make the analyzer return the core type and decode full multichannel PCM**

Replace the private overview scanner with this actor shape:

```swift
import AVFoundation
import Foundation
import TangoDisplayCore

actor AudioSilenceAnalyzer {
    static let shared = AudioSilenceAnalyzer()
    private var cache: [URL: IntrinsicSilence] = [:]

    func analyze(url: URL) async -> IntrinsicSilence {
        let key = url.standardizedFileURL
        if let cached = cache[key] { return cached }
        let result = Self.analyzeFile(url: key)
        cache[key] = result
        return result
    }

    func invalidate(url: URL) { cache.removeValue(forKey: url.standardizedFileURL) }
    func clearCache() { cache.removeAll() }

    private static func analyzeFile(url: URL) -> IntrinsicSilence {
        guard let file = try? AVAudioFile(forReading: url) else { return .zero }
        let format = file.processingFormat
        guard format.sampleRate > 0, file.length > 0,
              file.length <= AVAudioFramePosition(UInt32.max),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(file.length)
              ), (try? file.read(into: buffer)) != nil,
              let data = buffer.floatChannelData else { return .zero }
        let frames = Int(buffer.frameLength)
        let samples = (0..<Int(format.channelCount)).map { channel in
            Array(UnsafeBufferPointer(start: data[channel], count: frames))
        }
        return SmartAutoGap.measureSilence(samples: samples, sampleRate: format.sampleRate)
    }
}
```

This deliberately removes the old RMS-named peak helper, 10-second scan limit, mono conversion, and duplicate threshold implementation.

- [ ] **Step 2: Compile the complete package**

Run: `swift build`

Expected: failures only in `LocalPlayerSource.swift` for renamed result fields (`silenceAtStart`/`silenceAtEnd`), proving the analyzer replacement is wired to the application target.

- [ ] **Step 3: Commit analyzer replacement together with Task 4**

Do not commit a known compile failure. Keep this change staged locally until Task 4 restores the application build.

### Task 4: Bind analysis to the correct track pair and replace native scheduling

**Files:**
- Modify: `Sources/TangoDisplayCore/Audio/SmartAutoGap.swift`
- Modify: `Tests/TangoDisplayTests/TestRunner.swift`
- Modify: `Sources/TangoDisplay/Services/LocalPlayerSource.swift`
- Modify: `Sources/TangoDisplay/Services/AudioSilenceAnalyzer.swift`

- [ ] **Step 1: Add failing pair-identity tests**

First add tests that construct a `PreparedAutoGap(currentID: "A", nextID: "B", trailing: 1, leading: 1)`, assert the matching pair returns `3` for a `5` second target, and assert a reordered/mismatched next ID returns `nil`. Run `swift run TangoDisplayTests` and expect a missing `PreparedAutoGap` compile failure.

- [ ] **Step 2: Implement pair identity validation**

Add to the core file:

```swift
public struct PreparedAutoGap<ID: Equatable & Sendable>: Equatable, Sendable {
    public let currentID: ID
    public let nextID: ID
    public let trailing: Double
    public let leading: Double

    public init(currentID: ID, nextID: ID, trailing: Double, leading: Double) {
        self.currentID = currentID
        self.nextID = nextID
        self.trailing = trailing
        self.leading = leading
    }

    public func injectedDuration(currentID: ID, nextID: ID, target: Double) -> Double? {
        guard self.currentID == currentID, self.nextID == nextID else { return nil }
        return SmartAutoGap.injectedDuration(target: target, trailing: trailing, leading: leading)
    }
}
```

Run `swift run TangoDisplayTests` again. Expected: matching and stale-pair tests pass.

- [ ] **Step 3: Replace mutable unscoped auto-gap state**

In `LocalPlayerSource`, replace:

```swift
private var prevTrackSilenceAtEnd: Double = 0
private var nextTrackSilenceAtStart: Double = 0
```

with:

```swift
private var preparedAutoGap: PreparedAutoGap<UUID>?
private var autoGapAnalysisTask: Task<Void, Never>?
```

Cancel the task and clear `preparedAutoGap` in `stop()`, `stopTrack()`, engine configuration changes, and before every new `loadEntry` preparation.

- [ ] **Step 4: Add pair-bound look-ahead preparation**

Add:

```swift
private func prepareAutoGap(current: SetlistEntry) {
    autoGapAnalysisTask?.cancel()
    preparedAutoGap = nil
    guard let next = setlist.firstUnplayed(after: current.id) else { return }
    let currentID = current.id
    let nextID = next.id
    let currentURL = current.fileURL
    let nextURL = next.fileURL
    autoGapAnalysisTask = Task { [weak self] in
        let currentSilence = await AudioSilenceAnalyzer.shared.analyze(url: currentURL)
        guard !Task.isCancelled else { return }
        let nextSilence = await AudioSilenceAnalyzer.shared.analyze(url: nextURL)
        guard !Task.isCancelled else { return }
        await MainActor.run { [weak self] in
            guard let self,
                  self.currentEntryID == currentID,
                  self.setlist.firstUnplayed(after: currentID)?.id == nextID else { return }
            self.preparedAutoGap = PreparedAutoGap(
                currentID: currentID,
                nextID: nextID,
                trailing: currentSilence.trailing,
                leading: nextSilence.leading
            )
        }
    }
}
```

Call it after `currentEntryID = entry.id` in `loadEntry`. Remove the old background `Task` that assigns unscoped silence doubles.

- [ ] **Step 5: Move inter-track gap insertion to automatic completion**

Change `handleTrackEnd` to resolve the next unplayed entry and call a new `advanceAutomatically(from:to:)`. Keep `skipNextImmediate()` as the manual bypass path.

```swift
private func handleTrackEnd(generation: Int) {
    guard generation == scheduleGeneration,
          let currentID = currentEntryID,
          let current = setlist.entries.first(where: { $0.id == currentID }) else { return }
    guard let next = setlist.firstUnplayed(after: currentID) else {
        skipNextImmediate()
        return
    }
    advanceAutomatically(from: current, to: next)
}

private func advanceAutomatically(from current: SetlistEntry, to next: SetlistEntry) {
    let bypass = !settings.autoGapEnabled
        || next.ignoresAutoGap
    let padding = bypass ? 0 : preparedAutoGap?
        .injectedDuration(currentID: current.id, nextID: next.id, target: settings.autoGapDuration)
        ?? settings.autoGapDuration
    guard padding > 0 else { skipNextImmediate(); return }
    scheduleAutoGap(seconds: padding, nextEntryID: next.id)
}
```

Preserve the existing product interpretation that `ignoresAutoGap` belongs to the entry receiving the gap. `autoGapIgnoreFirstTrack` applies only to initial playback and therefore is not consulted for later track-to-track transitions.

- [ ] **Step 6: Schedule silence with audible completion and generation cancellation**

Add:

```swift
private func scheduleAutoGap(seconds: Double, nextEntryID: UUID) {
    scheduleGeneration += 1
    let generation = scheduleGeneration
    guard let format = audioFile?.processingFormat else { skipNextImmediate(); return }
    let frames = AVAudioFrameCount(max(1, (seconds * format.sampleRate).rounded()))
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
        skipNextImmediate()
        return
    }
    buffer.frameLength = frames
    currentPaddingFrames = frames
    silencePending = true
    setlist.setAutoGapApplied(id: nextEntryID, applied: true)
    playerNode.scheduleBuffer(buffer, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
        DispatchQueue.main.async {
            guard let self, self.scheduleGeneration == generation else { return }
            self.currentPaddingFrames = 0
            self.silencePending = false
            self.setlist.setAutoGapApplied(id: nextEntryID, applied: false)
            self.skipNextImmediate()
        }
    }
    if !playerNode.isPlaying { playerNode.play() }
}
```

Remove inter-track preroll scheduling from `loadEntry`, remove `computeAutoGapPadding` and `makeSilenceBuffer`, and keep `audioStartSampleTime` only if elapsed-time reporting still requires it. Any cancellation path must clear the next entry's `autoGapApplied` flag before discarding the prepared pair.

- [ ] **Step 7: Preserve the existing first-track option with smart measurement**

When `loadEntry` is loading the first setlist entry before any entry is played, analyze that entry and schedule its initial buffer only when Auto-gap is enabled, the entry does not ignore Auto-gap, and `autoGapIgnoreFirstTrack == false`. Calculate it as:

```swift
let initialPadding = SmartAutoGap.injectedDuration(
    target: settings.autoGapDuration,
    trailing: 0,
    leading: firstSilence.leading
)
```

Use the same `.dataPlayedBack` scheduling helper and generation guard as inter-track gaps. When `autoGapIgnoreFirstTrack == true`, set `autoGapSkipped` for the first entry and schedule no initial buffer. This preserves the current control while using smart rather than fixed initial padding.

- [ ] **Step 8: Run tests and build**

Run:

```bash
swift run TangoDisplayTests
swift build
```

Expected: test runner reports zero failures; package build ends with `Build complete!`.

- [ ] **Step 9: Confirm legacy logic is absent**

Run:

```bash
rg -n "computeAutoGapPadding|prevTrackSilenceAtEnd|nextTrackSilenceAtStart|completionCallbackType: \.dataConsumed" Sources/TangoDisplay
```

Expected: no matches in the Auto-Gap path.

- [ ] **Step 10: Commit integrated playback behavior**

```bash
git add Sources/TangoDisplayCore/Audio/SmartAutoGap.swift Tests/TangoDisplayTests/TestRunner.swift Sources/TangoDisplay/Services/AudioSilenceAnalyzer.swift Sources/TangoDisplay/Services/LocalPlayerSource.swift
git commit -m "feat: integrate smart auto-gap playback transitions"
```

### Task 5: User-visible verification and regression audit

**Files:**
- Verify: `Sources/TangoDisplay/Settings/AppSettings.swift`
- Verify: `Sources/TangoDisplay/Views/Control/AutoGapPopoverView.swift`
- Verify: `Sources/TangoDisplay/Views/Control/PlayerSettingsView.swift`
- Verify: `Sources/TangoDisplay/Views/Control/SetlistView.swift`

- [ ] **Step 1: Confirm existing settings remain unchanged**

Run:

```bash
rg -n "autoGapEnabled|autoGapDuration|autoGapIgnoreFirstTrack|ignoresAutoGap|0\.5\.\.\.5" Sources/TangoDisplay
```

Expected: separate enable switch, `0.5...5` slider, first-track option, and per-entry ignore option remain present.

- [ ] **Step 2: Run clean verification**

Run:

```bash
swift package clean
swift run TangoDisplayTests
swift build
git diff --check
git status --short
```

Expected: all tests pass; build succeeds; no whitespace errors; status contains only intentional plan or implementation changes.

- [ ] **Step 3: Launch and perform the real playback smoke test**

Use two local test files with known `1s` trailing and `1s` leading silence. Set target to `5s`, enable Auto-gap, and play through automatic advancement.

Acceptance checks:

- audible-content boundary measures approximately `5s` (within 10 ms analysis resolution plus device scheduling tolerance);
- injected silent-buffer duration is `3s`;
- intrinsic silence totaling `>= 5s` injects no buffer;
- manual Next advances immediately during a pending gap;
- Stop and seek cancel the pending transition;
- reordering the next setlist entry does not reuse stale analysis;
- first-track and per-track ignore indicators retain their current UI behavior.

- [ ] **Step 4: Record verification evidence in the handoff**

Report exact test counts, build result, test-file silence durations, measured perceived gap, and any manual checks that require the user's audio hardware. Do not claim exact real playback behavior from unit tests alone.
