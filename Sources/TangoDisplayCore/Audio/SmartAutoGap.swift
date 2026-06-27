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
