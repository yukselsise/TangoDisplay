import Accelerate
import AVFoundation
import Foundation
import os

final class AudioLevelMeter: ObservableObject {

    @Published private(set) var leftLevel: Float = 0
    @Published private(set) var rightLevel: Float = 0
    @Published private(set) var leftPeak: Float = 0
    @Published private(set) var rightPeak: Float = 0
    @Published private(set) var leftClipped: Bool = false
    @Published private(set) var rightClipped: Bool = false

    // MARK: - Public API

    func resetClip() {
        leftClipped = false
        rightClipped = false
        leftPeakState = .holding(value: leftLevel, since: .now)
        rightPeakState = .holding(value: rightLevel, since: .now)
    }

    func reset() {
        rawLock.withLock { $0 = RawLevels() }
    }

    func reinstallTap() {
        if tapInstalled { mixerNode.removeTap(onBus: 0) }
        tapInstalled = false
        installTap()
    }

    // MARK: - Private types

    private struct RawLevels {
        var left: Float = 0
        var right: Float = 0
        var leftPeak: Float = 0
        var rightPeak: Float = 0
    }

    private enum PeakState {
        case holding(value: Float, since: Date)
        case decaying(from: Float, startedAt: Date)
    }

    // MARK: - Private state

    private static let holdDuration: TimeInterval = 2.0
    private static let decayDuration: TimeInterval = 1.5

    private let mixerNode: AVAudioMixerNode
    private let rawLock = OSAllocatedUnfairLock(initialState: RawLevels())
    private var displayTimer: Timer?
    private var tapInstalled = false

    private var leftPeakState: PeakState = .holding(value: 0, since: .distantPast)
    private var rightPeakState: PeakState = .holding(value: 0, since: .distantPast)

    // MARK: - Init / deinit

    init(mixerNode: AVAudioMixerNode) {
        self.mixerNode = mixerNode
        installTap()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    deinit {
        displayTimer?.invalidate()
        // Don't call removeTap here: the engine owns the tap and removes it when
        // deallocated. Calling removeTap risks crashing if the engine already removed
        // it during a reconfiguration before deinit ran.
    }

    // MARK: - Private

    private func installTap() {
        guard !tapInstalled else { return }
        mixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }
        tapInstalled = true
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = vDSP_Length(buffer.frameLength)
        guard frameCount > 0 else { return }
        let channelCount = Int(buffer.format.channelCount)

        var leftRMS: Float = 0
        var leftPeakMag: Float = 0
        vDSP_rmsqv(channelData[0], 1, &leftRMS, frameCount)
        vDSP_maxmgv(channelData[0], 1, &leftPeakMag, frameCount)

        var rightRMS: Float = 0
        var rightPeakMag: Float = 0
        if channelCount >= 2 {
            vDSP_rmsqv(channelData[1], 1, &rightRMS, frameCount)
            vDSP_maxmgv(channelData[1], 1, &rightPeakMag, frameCount)
        } else {
            rightRMS = leftRMS
            rightPeakMag = leftPeakMag
        }

        let snapshot = RawLevels(left: leftRMS, right: rightRMS, leftPeak: leftPeakMag, rightPeak: rightPeakMag)
        rawLock.withLock { $0 = snapshot }
    }

    private func updateDisplay() {
        let snapshot = rawLock.withLock { $0 }
        let now = Date()
        leftLevel = snapshot.left
        rightLevel = snapshot.right
        tick(rawPeak: snapshot.leftPeak,  displayPeak: &leftPeak,  state: &leftPeakState,  clipped: &leftClipped,  now: now)
        tick(rawPeak: snapshot.rightPeak, displayPeak: &rightPeak, state: &rightPeakState, clipped: &rightClipped, now: now)
    }

    private func tick(
        rawPeak: Float,
        displayPeak: inout Float,
        state: inout PeakState,
        clipped: inout Bool,
        now: Date
    ) {
        if rawPeak >= 1.0 { clipped = true }

        if rawPeak > displayPeak {
            displayPeak = rawPeak
            state = .holding(value: rawPeak, since: now)
            return
        }

        switch state {
        case .holding(_, let since):
            if now.timeIntervalSince(since) >= Self.holdDuration {
                state = .decaying(from: displayPeak, startedAt: now)
            }
        case .decaying(let from, let startedAt):
            let elapsed = now.timeIntervalSince(startedAt)
            let factor = Float(max(0.0, 1.0 - elapsed / Self.decayDuration))
            displayPeak = from * factor
            if displayPeak <= 0 {
                displayPeak = 0
                state = .holding(value: 0, since: .distantPast)
            }
        }
    }
}
