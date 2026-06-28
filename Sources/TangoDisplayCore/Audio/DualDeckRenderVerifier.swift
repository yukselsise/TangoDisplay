import AVFoundation

/// Pure-logic verification helpers that prove the smart-gap math (`SmartAutoGap`)
/// and the frame-domain schedule (`DualDeckSchedule`) agree on a single, concrete
/// PCM timeline. No audio I/O: every fixture here is a deterministic in-memory
/// sample array built from durations, and every check re-derives its expectation
/// from the *same* constants the production silence analyzer uses (the `4/255`
/// peak threshold and 10 ms block size baked into `SmartAutoGap.measureSilence`).
///
/// This type exists so Task 7's tests can build a fixture once and assert against
/// it from multiple angles (intrinsic-silence measurement, injected-duration math,
/// frame-domain schedule, and "cut discards the tail") without each test re-deriving
/// its own ad hoc sample arrays.
public enum DualDeckRenderVerifier {

    /// A deterministic PCM fixture for one deck's boundary region.
    ///
    /// `samples` is channel-major (`samples[channel][frame]`), matching the layout
    /// `SmartAutoGap.measureSilence` already expects.
    public struct Fixture: Equatable {
        public let samples: [[Float]]
        public let sampleRate: Double
        public let channelCount: Int

        public init(samples: [[Float]], sampleRate: Double) {
            self.samples = samples
            self.sampleRate = sampleRate
            self.channelCount = samples.count
        }

        public var frameCount: Int { samples.first?.count ?? 0 }
    }

    /// An audible sample value safely above the `4/255` silence threshold used
    /// throughout `SmartAutoGap`. `0` is used for silent frames.
    public static let audibleSampleValue: Float = 1.0

    /// Builds a fixture representing an outgoing track's trailing region: an
    /// audible "body" followed by `trailingSilence` seconds of true silence,
    /// optionally followed by a distinct "plugin tail" audible region appended
    /// *after* the silence (e.g. reverb/delay tail a plugin would still be
    /// emitting). The returned fixture's frame count therefore covers body +
    /// silence + tail, so callers can verify that cutting at the boundary frame
    /// discards the tail samples.
    ///
    /// - Parameters:
    ///   - bodySeconds: audible content before the trailing silence.
    ///   - trailingSilenceSeconds: true-silence region immediately preceding the cut.
    ///   - pluginTailSeconds: audible samples appended after the silence, modelling
    ///     content a plugin would still be producing if playback were not cut.
    public static func outgoingTrailingFixture(
        bodySeconds: Double,
        trailingSilenceSeconds: Double,
        pluginTailSeconds: Double = 0,
        sampleRate: Double,
        channelCount: Int
    ) -> Fixture {
        let bodyFrames = frameCount(forSeconds: bodySeconds, sampleRate: sampleRate)
        let silenceFrames = frameCount(forSeconds: trailingSilenceSeconds, sampleRate: sampleRate)
        let tailFrames = frameCount(forSeconds: pluginTailSeconds, sampleRate: sampleRate)
        let channel = Array(repeating: audibleSampleValue, count: bodyFrames)
            + Array(repeating: Float(0), count: silenceFrames)
            + Array(repeating: audibleSampleValue, count: tailFrames)
        return Fixture(samples: Array(repeating: channel, count: max(1, channelCount)), sampleRate: sampleRate)
    }

    /// Builds a fixture representing an incoming track's leading region:
    /// `leadingSilenceSeconds` of true silence followed by an audible body.
    public static func incomingLeadingFixture(
        leadingSilenceSeconds: Double,
        bodySeconds: Double,
        sampleRate: Double,
        channelCount: Int
    ) -> Fixture {
        let silenceFrames = frameCount(forSeconds: leadingSilenceSeconds, sampleRate: sampleRate)
        let bodyFrames = frameCount(forSeconds: bodySeconds, sampleRate: sampleRate)
        let channel = Array(repeating: Float(0), count: silenceFrames)
            + Array(repeating: audibleSampleValue, count: bodyFrames)
        return Fixture(samples: Array(repeating: channel, count: max(1, channelCount)), sampleRate: sampleRate)
    }

    /// Simulates a hard cut: returns only the samples at and after
    /// `cutAtFrame` are discarded — i.e. the portion of the fixture that
    /// survives playback once the deck is cut at that frame. Used to prove
    /// that whatever lies beyond `cutOutgoingAtFrame` (e.g. a plugin tail
    /// appended after trailing silence) is never rendered.
    public static func samplesSurvivingCut(_ fixture: Fixture, cutAtFrame: AVAudioFramePosition) -> [[Float]] {
        guard cutAtFrame > 0 else { return fixture.samples.map { _ in [] } }
        let limit = min(Int(cutAtFrame), fixture.frameCount)
        return fixture.samples.map { Array($0.prefix(limit)) }
    }

    /// Whether any sample in `samples` is audible under the same `4/255`
    /// threshold `SmartAutoGap.measureSilence` uses internally. Re-derives the
    /// threshold via a zero-leading/trailing-silence probe rather than
    /// duplicating the literal, so a future constant change here can't drift
    /// from the production value.
    public static func containsAudibleSample(_ samples: [[Float]], sampleRate: Double) -> Bool {
        let silence = SmartAutoGap.measureSilence(samples: samples, sampleRate: sampleRate)
        guard let frameCount = samples.map(\.count).min(), frameCount > 0 else { return false }
        let totalDuration = Double(frameCount) / sampleRate
        // Fully accounted for by leading+trailing silence only when the whole
        // buffer is silent (measureSilence reports the entire span as leading
        // in that case); anything else implies an audible block exists.
        return !(silence.leading >= totalDuration && silence.trailing == 0)
    }

    private static func frameCount(forSeconds seconds: Double, sampleRate: Double) -> Int {
        guard seconds.isFinite, seconds > 0, sampleRate.isFinite, sampleRate > 0 else { return 0 }
        return Int((seconds * sampleRate).rounded())
    }
}
