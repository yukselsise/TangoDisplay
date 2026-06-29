import Foundation

public enum WaveformEnvelope {
    /// Returns one absolute peak per interval. When more buckets than source
    /// values are requested, source peaks are repeated without interpolation.
    public static func downsamplePeaks(_ samples: [Float], buckets: Int) -> [Float] {
        guard buckets > 0 else { return [] }
        guard !samples.isEmpty else { return Array(repeating: 0, count: buckets) }

        if buckets >= samples.count {
            return (0..<buckets).map { bucket in
                let sourceIndex = min(samples.count - 1, bucket * samples.count / buckets)
                return abs(samples[sourceIndex])
            }
        }

        return (0..<buckets).map { bucket in
            let start = bucket * samples.count / buckets
            let end = max(start + 1, (bucket + 1) * samples.count / buckets)
            return samples[start..<min(end, samples.count)]
                .reduce(0) { max($0, abs($1)) }
        }
    }
}
