public struct IntrinsicSilence: Equatable, Sendable {
    public let leading: Double
    public let trailing: Double

    public init(leading: Double, trailing: Double) {
        self.leading = leading
        self.trailing = trailing
    }

    public static let zero = IntrinsicSilence(leading: 0, trailing: 0)
}

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

public struct PendingAutoGapIdentity<ID: Equatable & Sendable>: Equatable, Sendable {
    public let currentID: ID
    public let nextID: ID
    public let generation: Int
    public init(currentID: ID, nextID: ID, generation: Int) {
        self.currentID = currentID; self.nextID = nextID; self.generation = generation
    }
    public func matches(currentID: ID, nextID: ID?, generation: Int) -> Bool {
        self.currentID == currentID && self.nextID == nextID && self.generation == generation
    }
}

public enum SmartAutoGapTransitionPolicy {
    public static func shouldSchedule(enabled: Bool, ignored: Bool, automatic: Bool, willStop: Bool) -> Bool {
        enabled && !ignored && automatic && !willStop
    }
}

public struct SilenceAccumulator: Sendable {
    private let sampleRate: Double
    private let channelCount: Int
    private let blockFrames: Int
    private var framesInBlock = 0
    private var blockPeak: Float = 0
    private var blockHasInvalid = false
    private var totalFrames = 0
    private var leadingFrames = 0
    private var trailingFrames = 0
    private var foundAudible = false

    public init(sampleRate: Double, channelCount: Int) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        let rounded = (sampleRate * 0.01).rounded()
        self.blockFrames = rounded.isFinite && rounded > 0 && rounded < Double(Int.max) ? max(1, Int(rounded)) : 1
    }

    public mutating func append(samples: [[Float]]) {
        guard sampleRate.isFinite, sampleRate > 0, channelCount > 0,
              samples.count == channelCount, let count = samples.map(\.count).min() else { return }
        for frame in 0..<count {
            for channel in 0..<channelCount {
                let value = samples[channel][frame]
                if value.isFinite { blockPeak = max(blockPeak, abs(value)) } else { blockHasInvalid = true }
            }
            framesInBlock += 1
            totalFrames += 1
            if framesInBlock == blockFrames { completeBlock() }
        }
    }

    public mutating func finish() -> IntrinsicSilence {
        if framesInBlock > 0 { completeBlock() }
        guard totalFrames > 0 else { return .zero }
        if !foundAudible { return IntrinsicSilence(leading: Double(totalFrames) / sampleRate, trailing: 0) }
        return IntrinsicSilence(leading: Double(leadingFrames) / sampleRate, trailing: Double(trailingFrames) / sampleRate)
    }

    private mutating func completeBlock() {
        let silent = !blockHasInvalid && blockPeak <= Float(4.0 / 255.0)
        if silent {
            if foundAudible { trailingFrames += framesInBlock } else { leadingFrames += framesInBlock }
        } else {
            foundAudible = true
            trailingFrames = 0
        }
        framesInBlock = 0; blockPeak = 0; blockHasInvalid = false
    }
}

public enum SmartAutoGap {
    /// Measures consecutive silent blocks at the beginning and end of PCM samples.
    /// Unequal channel arrays are measured only through their shortest shared frame count.
    public static func measureSilence(
        samples: [[Float]],
        sampleRate: Double
    ) -> IntrinsicSilence {
        guard sampleRate.isFinite, sampleRate > 0, !samples.isEmpty,
              let frameCount = samples.map(\.count).min(), frameCount > 0 else {
            return .zero
        }

        let roundedBlockFrames = (sampleRate * 0.01).rounded()
        guard roundedBlockFrames.isFinite, roundedBlockFrames < Double(Int.max) else {
            return .zero
        }
        let blockFrames = max(1, Int(roundedBlockFrames))
        let threshold = Float(4.0 / 255.0)
        var silentBlockFrames: [Int] = []
        var blockStart = 0

        while blockStart < frameCount {
            let blockEnd = blockStart + min(blockFrames, frameCount - blockStart)
            var peak: Float = 0
            var containsNonFiniteSample = false
            for channel in samples {
                for frame in blockStart..<blockEnd {
                    let sample = channel[frame]
                    if !sample.isFinite {
                        containsNonFiniteSample = true
                        break
                    }
                    peak = max(peak, abs(sample))
                }
                if containsNonFiniteSample { break }
            }
            let isSilent = !containsNonFiniteSample && peak <= threshold
            silentBlockFrames.append(isSilent ? blockEnd - blockStart : 0)
            blockStart = blockEnd
        }

        var leadingFrames = 0
        for silentFrames in silentBlockFrames {
            guard silentFrames > 0 else { break }
            leadingFrames += silentFrames
        }
        if leadingFrames == frameCount {
            return IntrinsicSilence(leading: Double(leadingFrames) / sampleRate, trailing: 0)
        }

        var trailingFrames = 0
        for silentFrames in silentBlockFrames.reversed() {
            guard silentFrames > 0 else { break }
            trailingFrames += silentFrames
        }
        return IntrinsicSilence(
            leading: Double(leadingFrames) / sampleRate,
            trailing: Double(trailingFrames) / sampleRate
        )
    }

    public static func injectedDuration(
        target: Double,
        trailing: Double,
        leading: Double
    ) -> Double {
        guard target.isFinite, target > 0 else { return 0 }

        let safeTrailing = trailing.isFinite && trailing > 0 ? trailing : 0
        let safeLeading = leading.isFinite && leading > 0 ? leading : 0
        return max(0, target - safeTrailing - safeLeading)
    }
}
