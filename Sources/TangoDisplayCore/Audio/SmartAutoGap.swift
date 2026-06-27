public struct IntrinsicSilence: Equatable, Sendable {
    public let leading: Double
    public let trailing: Double

    public init(leading: Double, trailing: Double) {
        self.leading = leading
        self.trailing = trailing
    }

    public static let zero = IntrinsicSilence(leading: 0, trailing: 0)
}

public enum SmartAutoGap {
    public static func measureSilence(
        samples: [[Float]],
        sampleRate: Double
    ) -> IntrinsicSilence {
        guard sampleRate.isFinite, sampleRate > 0, !samples.isEmpty,
              let frameCount = samples.map(\.count).min(), frameCount > 0 else {
            return .zero
        }

        let blockFrames = max(1, Int((sampleRate * 0.01).rounded()))
        let threshold = Float(4.0 / 255.0)
        var silentBlockFrames: [Int] = []
        var blockStart = 0

        while blockStart < frameCount {
            let blockEnd = min(blockStart + blockFrames, frameCount)
            var peak: Float = 0
            for channel in samples {
                for frame in blockStart..<blockEnd {
                    peak = max(peak, abs(channel[frame]))
                }
            }
            silentBlockFrames.append(peak <= threshold ? blockEnd - blockStart : 0)
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
