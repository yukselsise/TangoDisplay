# Smart Auto-Gap Migration Design

**Date:** 2026-06-27
**Target:** TangoDisplay built-in player
**Source behavior:** TandaBuilder / MyLonga Auto-Gap

## Goal

Replace TangoDisplay's native auto-gap calculation and transition handling with the TandaBuilder/MyLonga smart-gap behavior. The built-in player must enforce the configured minimum perceived silence between automatically advancing tracks while preserving TangoDisplay's existing controls and exceptions.

## Locked behavior

- Preserve TangoDisplay's Auto-gap enable switch, `0.5...5.0` second target, first-track bypass, and per-track ignore option.
- Apply Smart Auto-Gap only to automatic track-to-track advancement. Manual next, previous, seek, direct play, and drop actions remain immediate.
- Define perceived silence as the current track's trailing intrinsic silence, plus injected silence, plus the next track's leading intrinsic silence.
- Calculate injected silence with:

  ```text
  injectedGap = max(0, targetGap - trailingSilence - leadingSilence)
  ```

- Example: target `5s`, trailing `1s`, leading `1s` produces `3s` injected silence.
- When intrinsic silence equals or exceeds the target, inject nothing.
- Do not introduce MyLonga's `0 = Off` or `16 = Auto-Stop` setting semantics.

## Architecture

### Smart-gap core

Add pure, reusable logic to `TangoDisplayCore`. It accepts target, trailing, and leading durations and returns a nonnegative injected duration. Inputs that are negative or non-finite are treated as zero so corrupt analysis cannot produce invalid frame counts.

This calculation is removed from `LocalPlayerSource`; the player consumes the core result instead of owning a second implementation.

### Silence analysis

Replace the current standalone analyzer behavior with the MyLonga measurement model:

- Read audio as non-interleaved Float32 samples through `AVAudioFile`.
- Build a peak envelope in 10 ms blocks, taking the maximum absolute sample across all channels.
- Treat blocks with peak `<= 4/255` as silent.
- Count consecutive silent blocks from the start and end.
- For an all-silent file, count its duration once as leading silence and return zero trailing silence, preventing double subtraction.
- Clamp measured durations to the decoded audio duration.
- Cache results by canonical file URL for the playback session.
- Analyze the current and next entries asynchronously before the next automatic transition.

The analyzer remains isolated from playback state. It returns only `silenceAtStart` and `silenceAtEnd`.

### Playback transition

`LocalPlayerSource` retains responsibility for AVAudioEngine scheduling and TangoDisplay-specific policy:

1. Resolve whether Auto-gap applies: enabled, not manually bypassed, entry does not ignore it, and first-track policy permits it.
2. Obtain the completed track's trailing silence and upcoming track's leading silence from prepared analysis.
3. Call the Smart Auto-Gap core calculation.
4. If the result is zero, advance without an added buffer.
5. Otherwise schedule a zero-filled `AVAudioPCMBuffer` for exactly the computed frame count, then advance after audible completion.

The silence-buffer callback uses `.dataPlayedBack`, not `.dataConsumed`, so transition state follows audible output. A schedule-generation token guards the callback. Stop, seek, manual skip, replacement, or device reconfiguration invalidates a pending transition.

Analysis must not begin on the real-time audio callback. Look-ahead work starts when the current entry is loaded. If analysis is unavailable or fails at transition time, that side's intrinsic silence is conservatively treated as zero; TangoDisplay injects more silence rather than undershooting the configured target.

### Existing UI and state

No user-facing setting migration is required. Existing `AppSettings`, `AutoGapPopoverView`, `PlayerSettingsView`, setlist indicators, `autoGapApplied`, `autoGapSkipped`, and `ignoresAutoGap` remain in place. Their backing playback state is updated when an injected buffer begins and when its audible playback completes or is cancelled.

## Removal and replacement scope

- Remove `LocalPlayerSource.computeAutoGapPadding`.
- Replace the current transition-time use of mutable `prevTrackSilenceAtEnd` and `nextTrackSilenceAtStart` with an explicit prepared transition result associated with current and next entry identities.
- Replace `.dataConsumed` on the injected silence buffer with `.dataPlayedBack`.
- Refactor or replace `AudioSilenceAnalyzer` so only the MyLonga-compatible 10 ms peak-envelope implementation remains.
- Do not alter ReplayGain, Audio Unit routing, fades, cortina handling, external music-player sources, or display transitions.

## State safety

Prepared analysis is valid only for the `(currentEntryID, nextEntryID)` pair that produced it. Reordering the setlist, removing a track, or selecting another entry invalidates the pair. This prevents stale silence values from being applied to a different transition.

The player clears `autoGapApplied` when the buffer completes audibly, when playback is cancelled, and when the relevant entry disappears. Failure to allocate or schedule the silent buffer falls back to immediate advancement without crashing.

## Tests

### Core calculation

- `target=5`, `trailing=1`, `leading=1` returns `3`.
- Intrinsic silence equal to target returns `0`.
- Intrinsic silence greater than target returns `0`.
- No intrinsic silence returns the full target.
- Negative and non-finite measurements cannot create negative or non-finite output.

### Silence measurement

Use synthetic PCM samples to cover:

- leading-only silence;
- trailing-only silence;
- silence at both ends;
- continuous tone;
- all-silent audio without double counting;
- audio shorter than one 10 ms block;
- stereo audio where either channel contains audible content;
- threshold boundary at `4/255`.

### Transition policy

Test the policy separately from AVAudioEngine scheduling:

- automatic advance applies calculated silence;
- disabled Auto-gap returns zero;
- ignored entry returns zero;
- first-track bypass returns zero;
- manual transitions bypass Smart Auto-Gap;
- stale current/next identity pairs are rejected.

### Verification

- Run the TangoDisplay core test runner.
- Build the complete TangoDisplay package.
- Perform a local two-track playback smoke test with known leading and trailing silence.
- Confirm manual skip is immediate and cancels a pending gap.
- Confirm setlist reorder during playback does not reuse stale analysis.
- Confirm the UI still exposes the existing range and exception controls unchanged.

## Acceptance criteria

- With a `5s` target, `1s` trailing silence, and `1s` leading silence, TangoDisplay injects `3s`.
- The measured perceived interval between audible content boundaries matches the target within one 10 ms analysis block plus audio-device scheduling tolerance.
- Intrinsic silence at or above the target never receives added silence.
- Existing TangoDisplay Auto-gap settings and per-track behavior remain available.
- No legacy native padding calculation remains active in the built-in playback path.
- Automatic completion follows audible playback, and user actions safely cancel pending transitions.

## Out of scope

Crossfading, waveform UI, persistent analysis across application launches, MyLonga Auto-Stop semantics, changing TangoDisplay's gap range, and Auto-gap support for external player sources.
