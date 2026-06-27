# Dual-Deck Smart Auto-Gap Design

**Date:** 2026-06-28
**Target:** TangoDisplay built-in player
**Extends:** `2026-06-27-smart-auto-gap-design.md`

## Goal

Guarantee the configured absolute perceived silence between automatically advancing tracks, including transitions across different audio formats, ReplayGain values, and per-track Audio Unit configurations. Eliminate uncontrolled file-open, graph-reconnect, callback, and plugin-setup latency from the measured track-to-track interval.

## Locked decisions

- Replace the single mutable playback graph with two independently prepared playback decks feeding one stable output mixer.
- Each deck owns its file format, player node, EQ, ReplayGain stage, and Audio Unit instances/configuration.
- At the current track's audible end, cut the outgoing deck and its Audio Unit tail immediately. Reverb, echo, and other plugin tails do not extend the transition or count toward intrinsic silence.
- Preserve TangoDisplay's existing Auto-gap enable switch, `0.5...5.0` second range, first-track bypass, and per-track ignore option.
- Smart Auto-Gap applies to automatic track-to-track advancement. Manual transport actions remain immediate.
- Never label or treat an approximate fallback as exact Smart Auto-Gap.

## Timing contract

For each automatic transition:

```text
injectedGap = max(0, targetGap - currentTrailingSilence - nextLeadingSilence)
```

The output timeline is:

```text
last audible sample of deck A
-> deck A and its plugin tail are cut
-> injectedGap of digital silence
-> first decoded sample of deck B
-> deck B's intrinsic leading silence
-> first audible sample of deck B
```

The measured interval between the last audible sample of A and first audible sample of B must equal `targetGap` within one 10 ms analysis block plus output-device render tolerance.

Opening B's file, configuring its format, applying ReplayGain, instantiating Audio Units, and loading presets happen before the timeline is committed. None of that work counts toward the injected or perceived gap.

## Architecture

### PlaybackDeck

Introduce a focused `PlaybackDeck` object. Each instance owns:

- one `AVAudioPlayerNode`;
- one EQ stage;
- one ReplayGain stage;
- its own Audio Unit chain and runtime state;
- the loaded `AVAudioFile` and processing format;
- scheduled frame range, generation, and entry identity;
- prepared silence analysis and plugin configuration identity.

Decks expose preparation, scheduling, cancellation, seeking, and teardown through explicit methods. They do not choose setlist entries or mutate application playback state.

### Stable output graph

Deck A and Deck B feed a stable common mixer/output path. Format conversion occurs at each deck's connection into the common mixer, allowing adjacent mono/stereo and different-sample-rate files without stopping the main engine. Balance, master volume, output-device routing, metering, and the final output remain shared.

The engine is rebuilt only for genuine output-device or engine-configuration changes, not normal track transitions.

### Deck coordinator

`LocalPlayerSource` becomes the coordinator rather than the owner of one mutable track graph. It tracks:

- active and standby deck;
- current and prepared-next setlist entry identities;
- transition generation;
- deck preparation status;
- committed transition timeline;
- UI-facing elapsed time and playback state.

While A plays, the coordinator prepares B for the actual next unplayed entry. Reorder or removal invalidates B unless its entry identity still matches current adjacency.

### Plugin isolation

Each deck has independent Audio Unit instances and preset/configuration state. Preparing B must not change A's sound. At the transition boundary, A's deck output is silenced and stopped; its effect tail is discarded. B is already configured and begins on the committed render timeline.

Plugins that cannot be instantiated or configured on B follow the existing track/plugin failure policy before a transition is committed. The coordinator never begins an exact transition with a partially prepared deck.

### Analysis

Retain the bounded streaming 10 ms peak-envelope analyzer and exact padding calculation already implemented in `TangoDisplayCore`. Analysis belongs to deck preparation and is cached by canonical file URL. Failed or incomplete analysis is not cached.

## Transition flow

1. Load A and start playback.
2. Resolve the real next unplayed entry and prepare it on B: file, format, ReplayGain, Audio Units, presets, and silence analysis.
3. Observe Auto-gap settings until the transition is committed. A setting change invalidates and recomputes the pending timeline without reopening B.
4. When A approaches its scheduled end and B is ready, compute the current `injectedGap` and schedule the deck boundary against one render timeline.
5. At A's decoded end, hard-cut A and its plugin tail.
6. Keep both deck outputs silent for `injectedGap`.
7. Start B exactly at the end of that injected interval.
8. Atomically promote B to active application state and recycle A as the next standby deck.

If B is not ready when A ends, stop A and report a preparing/waiting transition state. Once B becomes ready, begin the deliberate injected interval and then B. Preparation time is not counted as target silence and is not reported as an exact transition. This is degraded error handling, not the normal Smart Auto-Gap path.

## Transport and mutation behavior

- **Manual Next:** cancel any committed automatic transition, hard-cut A, and start prepared B immediately. If B is not ready, use the existing loading state without adding Auto-gap.
- **Previous/direct play:** cancel both pending preparation and timeline, prepare the requested entry as active, and rebuild the standby candidate.
- **Seek:** affect only the active deck and invalidate the current transition timeline; standby preparation may be retained only if adjacency is unchanged.
- **Stop:** cancel both decks and every callback generation.
- **Setlist reorder/removal:** compare the prepared identity with the new next unplayed identity. Reuse only an exact match; otherwise cancel and prepare the new B.
- **Output-device change:** invalidate the shared render timeline, re-establish the stable output graph, then reschedule from authoritative active-deck state.
- **Performance/stop-after:** do not prepare or schedule an automatic transition that policy says must stop.

All delayed callbacks validate deck identity, current/next entry identity, and transition generation before mutating state.

## Existing UI and settings

No Auto-gap UI migration is introduced. Existing settings and indicators remain. Initial first-track preroll remains a startup behavior rather than a track-to-track Smart Auto-Gap transition; its existing skip control remains functional.

`autoGapApplied` indicates a committed injected interval, not background analysis or deck preparation. It is cleared on completion, cancellation, reorder, stop, seek, or device reset.

## Error handling

- File-open, decode, or plugin-preparation failures occur before timeline commitment and use existing skip/alert policy.
- A standby deck is never promoted unless its entry identity still matches actual adjacency.
- Partial analysis returns conservative uncached failure; it does not fabricate silence measurements.
- Late preparation enters an explicit degraded waiting path. It cannot claim exact timing.
- Allocation or scheduling failure cancels the committed transition and surfaces playback failure rather than silently extending the target.

## Testing

### Pure and state-machine tests

- Smart-gap arithmetic and invalid measurements.
- Streaming silence analysis across chunk boundaries.
- Deck lifecycle: empty, preparing, ready, scheduled, active, recycling, failed.
- Current/next/deck/generation identity validation.
- Setting changes before and after timeline commitment.
- Manual transport, stop-after, reorder, removal, seek, and device-reset cancellation.
- Stale callbacks cannot mutate a newer deck or transition.

### Audio integration tests

Generate deterministic PCM fixtures and capture the common mixer's rendered output:

- target `5s`, A trailing `1s`, B leading `1s`: injected `3s`, perceived `5s`;
- intrinsic silence equal to or greater than target: injected `0`;
- adjacent 44.1 kHz and 48 kHz files;
- mono-to-stereo and stereo-to-mono;
- different ReplayGain values;
- empty, identical, and different per-track plugin configurations;
- plugin tail on A is cut at A's decoded end;
- Auto-gap disabled and per-track ignored transitions;
- manual Next during a committed gap;
- reorder and removal while B is ready or scheduled.

Tests assert that B is fully prepared and scheduled before the injected interval completes. No successful exact transition may call file-open, graph-reconnect, or plugin-configuration work after the gap has begun.

### Verification

- Run the complete TangoDisplay test runner and package build.
- Confirm the engine does not stop/reconnect during ordinary automatic transitions.
- Record common-output audio for two known files and measure audible boundaries.
- Repeat on a real output device with different-format tracks and enabled per-track plugins.
- Confirm existing Auto-gap controls and indicators remain unchanged.

## Acceptance criteria

- Automatic transitions meet the configured perceived-silence target within 10 ms analysis resolution plus output render tolerance.
- Exact timing holds across supported file formats, ReplayGain values, and per-track Audio Unit configurations.
- Outgoing plugin tails are cut at the decoded track end.
- No file loading, graph rebuilding, ReplayGain calculation, or plugin preparation occurs between the end of injected silence and B's scheduled start.
- Auto-gap setting changes made before timeline commitment affect the upcoming transition.
- Manual and policy-driven stops do not receive an automatic gap.
- Existing TangoDisplay settings and UI behavior remain available.
- Degraded late-preparation behavior is visible and never represented as exact Smart Auto-Gap.

## Out of scope

Crossfading, preserving outgoing plugin tails, changing the Auto-gap range, external music-player sources, persistent waveform UI, and redesigning setlist presentation.
