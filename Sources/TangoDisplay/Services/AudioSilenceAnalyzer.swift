import AVFoundation
import Foundation
import TangoDisplayCore

actor AudioSilenceAnalyzer {

    static let shared = AudioSilenceAnalyzer()

    private var cache: [URL: IntrinsicSilence] = [:]

    func analyze(url: URL) async -> IntrinsicSilence {
        let key = url.standardizedFileURL
        if let cached = cache[key] { return cached }
        let result = Self.analyzeFile(url: key)
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

    private static func analyzeFile(url: URL) -> IntrinsicSilence {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) else { return .zero }
        let format = file.processingFormat
        guard format.sampleRate > 0, file.length > 0, file.length <= AVAudioFramePosition(UInt32.max),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let data = buffer.floatChannelData else { return .zero }
        let frames = Int(buffer.frameLength)
        let samples = (0..<Int(format.channelCount)).map { channel in
            Array(UnsafeBufferPointer(start: data[channel], count: frames))
        }
        return SmartAutoGap.measureSilence(samples: samples, sampleRate: format.sampleRate)
    }
}
