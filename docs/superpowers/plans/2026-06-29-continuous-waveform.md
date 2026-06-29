# Continuous Waveform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render TangoDisplay's Waveform window as a continuous mirrored silhouette without changing playback behavior.

**Architecture:** Put width-aware peak downsampling in the pure core target and keep SwiftUI path construction local to the Waveform window. Preserve the existing loader cache and guard asynchronous results by the requested URL.

**Tech Stack:** Swift 5.9, SwiftUI Canvas, AVFoundation, TangoDisplayCore lightweight test runner.

---

### Task 1: Add peak downsampling

**Files:**
- Create: `Sources/TangoDisplayCore/Audio/WaveformEnvelope.swift`
- Modify: `Tests/TangoDisplayTests/TestRunner.swift`

- [ ] Add failing tests for empty input, invalid bucket counts, peak preservation, and exact output count.
- [ ] Run `swift run TangoDisplayTests` and confirm compilation fails because `WaveformEnvelope` does not exist.
- [ ] Implement `WaveformEnvelope.downsamplePeaks(_:buckets:)`.
- [ ] Run `swift run TangoDisplayTests` and confirm all tests pass.

### Task 2: Replace bars with a silhouette

**Files:**
- Modify: `Sources/TangoDisplay/Views/Control/WaveformWindowContent.swift`

- [ ] Make the waveform Canvas width-aware with `GeometryReader` and display scale.
- [ ] Construct one closed, vertically mirrored path from downsampled peaks.
- [ ] Fill the full shape dimly, clip an accent fill to clamped playback progress, and draw the playhead.
- [ ] Guard waveform-load completion with URL identity so stale results are discarded.

### Task 3: Verify and publish

- [ ] Run `swift run TangoDisplayTests`.
- [ ] Run `swift build -c release`.
- [ ] Review the diff for waveform-only scope.
- [ ] Commit, push the feature branch to `origin`, and open a pull request against `upstream/main`.
