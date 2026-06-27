# Dual-Deck Smart Auto-Gap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace TangoDisplay's single mutable player graph with two independently prepared decks so automatic transitions enforce the configured perceived silence without post-gap loading latency.

**Architecture:** `PlaybackDeck` owns one independently formatted player, EQ, ReplayGain, and Audio Unit chain. A pure `DualDeckState` validates active/standby identities and generations; `LocalPlayerSource` prepares standby while active plays and commits one render timeline that cuts the outgoing plugin tail, renders calculated silence, and starts the prepared deck without stopping the engine.

**Tech Stack:** Swift 5.9, AVFoundation/AVAudioEngine, Audio Units, Combine, Swift Package Manager, TangoDisplayCore test runner.

---

## File map

- Create `Sources/TangoDisplayCore/Audio/DualDeckState.swift`: pure lifecycle and transition validation.
- Create `Sources/TangoDisplay/Services/PlaybackDeck.swift`: deck-owned nodes, file, gain, plugins, and scheduling.
- Create `Sources/TangoDisplay/Services/DualDeckAudioEngine.swift`: stable engine and shared output graph.
- Modify `Sources/TangoDisplay/Services/LocalPlayerSource.swift`: coordination, transport, policy, and UI state.
- Modify `Tests/TangoDisplayTests/TestRunner.swift`: state and timing-contract tests.

### Task 1: Dual-deck state machine

**Files:** Create `Sources/TangoDisplayCore/Audio/DualDeckState.swift`; modify `Tests/TangoDisplayTests/TestRunner.swift`.

- [ ] Add failing tests for A active/B empty, B preparing/ready, identity-matched transition commitment, promotion, reorder invalidation, stale callback rejection, stop-after rejection, and setting-revision invalidation.
- [ ] Run `swift run TangoDisplayTests`; expect missing `DualDeckState` compile errors.
- [ ] Implement `DeckID`, `DeckPhase`, `DeckSnapshot<ID>`, `DualDeckTransition<ID>`, and `DualDeckState<ID>`. Every callback must validate deck, entry identity, and generation.
- [ ] Run tests; expect zero failures.
- [ ] Commit: `git commit -am "feat: add dual-deck transition state machine"` after adding the new file.

Required contract:

```swift
var state = DualDeckState<String>()
state.activate(deck: .a, entryID: "current", generation: 1)
state.beginPreparation(deck: .b, entryID: "next", generation: 1)
state.markReady(deck: .b, entryID: "next", generation: 1)
let token = state.commitTransition(currentID: "current", nextID: "next", settingsRevision: 4)
try expect(state.promote(token!) == .b)
```

### Task 2: Independent PlaybackDeck

**Files:** Create `Sources/TangoDisplay/Services/PlaybackDeck.swift`; modify `Sources/TangoDisplay/Services/AudioUnitPluginManager.swift` and `LocalPlayerSource.swift`.

- [ ] Extract player node, EQ, ReplayGain mixer, file/format, generation, and plugin slot runtimes into `PlaybackDeck` while leaving legacy playback active.
- [ ] Give each deck independent Audio Unit instances and preset/configuration state. Standby preparation must never alter active-deck parameters or open plugin UI.
- [ ] Implement `attach`, async `prepare`, `schedule`, `cancel`, `hardCut`, and `resetForReuse` methods. `prepare` completes only after file, gain, and plugins are ready.
- [ ] Run `swift run TangoDisplayTests && swift build`; expect success.
- [ ] Commit `feat: isolate deck-owned playback and plugin state`.

```swift
@MainActor final class PlaybackDeck {
    let id: DeckID
    let playerNode: AVAudioPlayerNode
    let outputMixer: AVAudioMixerNode
    private(set) var entryID: UUID?
    func prepare(entry: SetlistEntry, configuration: PluginChainConfiguration?, replayGain: Float) async throws
    func schedule(startingFrame: AVAudioFramePosition, at time: AVAudioTime?) throws
    func cancel(); func hardCut(); func resetForReuse()
}
```

### Task 3: Stable two-deck engine graph

**Files:** Create `Sources/TangoDisplay/Services/DualDeckAudioEngine.swift`; modify `AudioLevelMeter.swift` and `LocalPlayerSource.swift`.

- [ ] Attach both decks to one stable common mixer and shared balance/output path. Let the common mixer convert each deck's source format.
- [ ] Keep `AudioLevelMeter` installed on the common mixer across promotions.
- [ ] Add Debug invariants proving normal prepare/promote paths leave the engine running and both deck outputs attached.
- [ ] Restrict graph rebuilds to output-device/configuration changes.
- [ ] Run `swift build`; expect success and no new warnings.
- [ ] Commit `feat: add stable dual-deck audio graph`.

### Task 4: Standby preparation

**Files:** Modify `LocalPlayerSource.swift`, `DualDeckState.swift`, and `TestRunner.swift`.

- [ ] Add failing policy tests: real next unplayed entry, stop-after/performance suppression, reorder reuse/cancel, preparation failure, and setting changes without reopening B.
- [ ] Implement cancellable `prepareStandbyIfNeeded()`: open file, analyze silence, calculate ReplayGain, instantiate/apply deck-local plugins, then mark ready.
- [ ] Validate current, next, deck, and generation after every async boundary.
- [ ] Observe reorder/removal/plugin changes; retain B only when identity and configuration still match.
- [ ] Track `settingsRevision`; gap changes recompute an uncommitted timeline without reopening B.
- [ ] Run tests/build and commit `feat: prepare standby deck for exact transitions`.

### Task 5: Sample-accurate transition

**Files:** Modify `PlaybackDeck.swift`, `DualDeckAudioEngine.swift`, `LocalPlayerSource.swift`, `DualDeckState.swift`, and `TestRunner.swift`.

- [ ] Add failing pure tests for `DualDeckSchedule`: three seconds equals 144,000 frames at 48 kHz; zero padding; stale identity; changed setting revision; incoming-not-ready rejection.
- [ ] Before A drains, compute current Smart Auto-Gap padding and convert it to common-output frames.
- [ ] Anchor A's hard cut and B's start to one `AVAudioTime`: B starts at A decoded end plus injected frames. No file open, reconnect, ReplayGain, plugin configuration, or `engine.stop()` may occur after commitment.
- [ ] At B start, atomically promote UI/setlist state; discard A's plugin tail, reset A, and prepare it as new standby.
- [ ] If B is late, enter explicit degraded waiting state; after B becomes ready, render the deliberate gap and mark diagnostics non-exact.
- [ ] Remove post-gap `loadEntry`, `scheduleAutoGap`, and normal-transition graph reconnects.
- [ ] Run tests/build and use `rg` to prove legacy automatic-transition calls are absent.
- [ ] Commit `feat: schedule exact dual-deck smart gaps`.

```swift
struct DualDeckSchedule {
    let cutOutgoingAtFrame: AVAudioFramePosition
    let startIncomingAtFrame: AVAudioFramePosition
    let injectedFrames: AVAudioFrameCount
    let sampleRate: Double
}
```

### Task 6: Transport and cancellation

**Files:** Modify `LocalPlayerSource.swift`, `DualDeckState.swift`, and `TestRunner.swift`.

- [ ] Add failing tests for manual Next during prepare/gap, Previous, direct play, seek, stop, reorder/removal, device reset, stale A/B callbacks, and performance stop.
- [ ] Manual Next promotes ready B immediately without gap; otherwise prepares requested entry active.
- [ ] Seek affects active deck only and invalidates timeline. Stop invalidates both generations. Previous/direct play clears standby.
- [ ] Device recovery snapshots active identity/time, invalidates timelines, rebuilds shared output, and restores authoritative active state.
- [ ] Preserve volume, balance, elapsed/duration, played/paused state, first-track skip, Auto-gap indicators, plugin status, and next-track callbacks.
- [ ] Run tests/build and commit `feat: make transport dual-deck safe`.

### Task 7: Rendered boundary verification

**Files:** Create `Sources/TangoDisplayCore/Audio/DualDeckRenderVerifier.swift`; modify `TestRunner.swift`.

- [ ] Add deterministic PCM tests: target 5 with 1+1 intrinsic gives 3 injected and 5 perceived; intrinsic >= target gives zero; 44.1/48 kHz; mono/stereo; outgoing plugin-tail samples absent after cut.
- [ ] Implement pure fixture generation and audible-boundary detection using the same `4/255` threshold and 10 ms tolerance.
- [ ] Assert successful exact transitions have B prepared/scheduled before the deliberate gap completes.
- [ ] Run tests and commit `test: verify dual-deck audible gap boundaries`.

### Task 8: Final verification

**Files:** Verify existing settings and control views; no planned UI edits.

- [ ] Run `swift package clean`, `swift run TangoDisplayTests`, `swift build`, `git diff --check`, and `git status --short`.
- [ ] Audit that normal transitions never stop the engine or load/configure B after commitment.
- [ ] Confirm enable, `0.5...5`, first-track skip, per-entry ignore, and indicators remain.
- [ ] Record common output and test a real device: known 5/1/1 fixture, differing formats/channels, differing ReplayGain, plugin tail on A, plugin on B, manual Next, reorder, seek, and device change.
- [ ] Require measured last-audible-A to first-audible-B interval within 10 ms plus render tolerance.
- [ ] Report exact test count, build result, transition logs, recorded gap, plugin-tail result, and hardware limitations. Never claim exact timing without recorded-output evidence.
