import AVFoundation
import Foundation
import TangoDisplayCore

actor AudioSilenceAnalyzer {

    static let shared = AudioSilenceAnalyzer()

    private var cache: [URL: IntrinsicSilence] = [:]

    func analyze(url: URL) async -> IntrinsicSilence {
        let key = url.standardizedFileURL
        if let cached = cache[key] { return cached }
        guard let result = Self.analyzeFile(url: key) else { return .zero }
        cache[key] = result
        return result
    }

    func invalidate(url: URL) {
        cache.removeValue(forKey: url.standardizedFileURL)
    }

    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Private

    private static func analyzeFile(url: URL) -> IntrinsicSilence? {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) else { return nil }
        let format = file.processingFormat
        let capacity: AVAudioFrameCount = 32_768
        guard format.sampleRate > 0, file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var accumulator = SilenceAccumulator(sampleRate: format.sampleRate, channelCount: Int(format.channelCount))
        while file.framePosition < file.length {
            buffer.frameLength = 0
            guard (try? file.read(into: buffer, frameCount: capacity)) != nil,
                  buffer.frameLength > 0, let data = buffer.floatChannelData else { return nil }
            let frames = Int(buffer.frameLength)
            let samples = (0..<Int(format.channelCount)).map { channel in
                Array(UnsafeBufferPointer(start: data[channel], count: frames))
            }
            accumulator.append(samples: samples)
        }
        guard file.framePosition >= file.length else { return nil }
        return accumulator.finish()
    }
}
