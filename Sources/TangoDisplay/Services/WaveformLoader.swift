import AVFoundation
import Foundation

actor WaveformLoader {

    struct WaveformData {
        let samples: [Float]   // normalised peak amplitude 0.0–1.0 per bucket
        let duration: Double   // seconds
    }

    static let shared = WaveformLoader()

    private var cache: [URL: WaveformData] = [:]

    func load(url: URL, buckets: Int = 500) async -> WaveformData? {
        if let cached = cache[url] { return cached }
        let data = Self.compute(url: url, buckets: buckets)
        if let data { cache[url] = data }
        return data
    }

    func invalidate(url: URL) {
        cache.removeValue(forKey: url)
    }

    // MARK: - Private

    private static func compute(url: URL, buckets: Int) -> WaveformData? {
        guard let file = try? AVAudioFile(forReading: url,
                                          commonFormat: .pcmFormatFloat32,
                                          interleaved: false) else { return nil }
        let totalFrames = file.length
        let sampleRate  = file.fileFormat.sampleRate
        guard totalFrames > 0, sampleRate > 0 else { return nil }

        let framesPerBucket = AVAudioFrameCount(max(1, Int64(totalFrames) / Int64(buckets)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: framesPerBucket) else { return nil }

        var samples = [Float]()
        samples.reserveCapacity(buckets)

        file.framePosition = 0
        while samples.count < buckets && file.framePosition < totalFrames {
            buffer.frameLength = 0
            guard (try? file.read(into: buffer, frameCount: framesPerBucket)) != nil,
                  buffer.frameLength > 0 else { break }
            samples.append(peakAmplitude(buffer: buffer))
        }

        // Normalise so the loudest bucket = 1.0
        let peak = samples.max() ?? 0
        if peak > 0 {
            for i in samples.indices { samples[i] /= peak }
        }

        return WaveformData(samples: samples, duration: Double(totalFrames) / sampleRate)
    }

    private static func peakAmplitude(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameCount   = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var peak: Float = 0
        for ch in 0..<channelCount {
            let ptr = channelData[ch]
            for i in 0..<frameCount {
                let abs = Swift.abs(ptr[i])
                if abs > peak { peak = abs }
            }
        }
        return peak
    }
}
