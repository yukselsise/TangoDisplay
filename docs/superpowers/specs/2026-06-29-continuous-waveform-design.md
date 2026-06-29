# Continuous Waveform Design

## Goal

Replace the Waveform window's vertical bars with the continuous mirrored silhouette used by Abrazo while preserving TangoDisplay's playback and track-transition behavior.

## Design

Waveform decoding and caching remain owned by `WaveformLoader`. A pure `WaveformEnvelope.downsamplePeaks` helper in `TangoDisplayCore` reduces cached samples to the physical pixel width of the Canvas. The SwiftUI view builds one closed path from the upper peak contour and its lower mirror, fills the unplayed silhouette dimly, clips an accent fill to playback progress, and overlays the existing playhead.

The view draws no synthetic waveform. Existing loading and no-track states remain intact. URL identity checks prevent an obsolete asynchronous result from replacing the waveform for a newer track.

## Verification

Core tests cover peak-preserving downsampling, empty input, invalid bucket counts, and requested output size. The full lightweight test runner and a release build must pass before publication.
