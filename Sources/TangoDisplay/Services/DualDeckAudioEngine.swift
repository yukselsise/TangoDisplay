import AVFoundation
import Foundation
import TangoDisplayCore
import TangoDisplayObjC

enum DualDeckAudioEngineError: LocalizedError {
    case graphMutationFailed(String)
    case graphInvariantFailed(String)

    var errorDescription: String? {
        switch self {
        case .graphMutationFailed(let reason):
            return "Dual-deck audio graph mutation failed: \(reason)"
        case .graphInvariantFailed(let reason):
            return "Dual-deck audio graph invariant failed: \(reason)"
        }
    }
}

/// Owns the process-lifetime two-deck output graph.
///
/// Normal preparation and promotion are intentionally absent from this type:
/// they operate on already-attached deck nodes and must never stop the engine or
/// reconnect the other deck. Only an output-device/configuration event may call
/// `rebuildOutputPath()`.
@MainActor
final class DualDeckAudioEngine {
    let engine: AVAudioEngine
    let deckA: PlaybackDeck
    let deckB: PlaybackDeck
    let commonMixer = AVAudioMixerNode()
    let balanceMixer = AVAudioMixerNode()
    let levelMeter: AudioLevelMeter

    private(set) var outputGraphRevision: UInt64 = 0

    var balance: Float {
        get { balanceMixer.pan }
        set { balanceMixer.pan = max(-1, min(1, newValue)) }
    }

    init(
        engine: AVAudioEngine = AVAudioEngine(),
        deckA: PlaybackDeck? = nil,
        deckB: PlaybackDeck? = nil
    ) throws {
        self.engine = engine
        self.deckA = deckA ?? PlaybackDeck(id: .a)
        self.deckB = deckB ?? PlaybackDeck(id: .b)

        try Self.safeAttach(commonMixer, to: engine)
        try Self.safeAttach(balanceMixer, to: engine)
        try self.deckA.attach(to: engine)
        try self.deckB.attach(to: engine)

        try Self.safeConnect(self.deckA.outputMixer, to: commonMixer, format: nil, in: engine)
        try Self.safeConnect(self.deckB.outputMixer, to: commonMixer, format: nil, in: engine)
        try Self.safeConnect(commonMixer, to: balanceMixer, format: nil, in: engine)
        try Self.safeConnect(balanceMixer, to: engine.mainMixerNode, format: nil, in: engine)

        // The tap stays on the common mixer while deck roles change.
        levelMeter = AudioLevelMeter(mixerNode: commonMixer)
        try assertStableGraph()
    }

    func startIfNeeded() throws {
        if !engine.isRunning { try engine.start() }
        try assertStableGraph(requireRunning: true)
    }

    /// Re-establishes only the shared output path after a genuine engine/device
    /// configuration change. Deck-internal graph preparation must not call this.
    func rebuildOutputPath() throws {
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }

        try Self.safeDisconnectOutput(deckA.outputMixer, in: engine)
        try Self.safeDisconnectOutput(deckB.outputMixer, in: engine)
        try Self.safeDisconnectOutput(commonMixer, in: engine)
        try Self.safeDisconnectOutput(balanceMixer, in: engine)

        try Self.safeConnect(deckA.outputMixer, to: commonMixer, format: nil, in: engine)
        try Self.safeConnect(deckB.outputMixer, to: commonMixer, format: nil, in: engine)
        try Self.safeConnect(commonMixer, to: balanceMixer, format: nil, in: engine)
        try Self.safeConnect(balanceMixer, to: engine.mainMixerNode, format: nil, in: engine)
        outputGraphRevision &+= 1

        if wasRunning { try engine.start() }
        try assertStableGraph(requireRunning: wasRunning)
    }

    func deck(_ id: DeckID) -> PlaybackDeck {
        id == .a ? deckA : deckB
    }

    /// Debug/test seam for proving promotion never mutates the output graph.
    func assertStableGraph(
        requireRunning: Bool = false,
        file: StaticString = #fileID,
        line: UInt = #line
    ) throws {
        if requireRunning && !engine.isRunning {
            assertionFailure("Dual-deck engine stopped during a normal graph operation", file: file, line: line)
            throw DualDeckAudioEngineError.graphInvariantFailed("the engine is not running")
        }
        let attached = engine.attachedNodes
        let required: [AVAudioNode] = [
            deckA.playerNode, deckA.eq, deckA.replayGainMixer, deckA.outputMixer,
            deckB.playerNode, deckB.eq, deckB.replayGainMixer, deckB.outputMixer,
            commonMixer, balanceMixer,
        ]
        guard required.allSatisfy({ candidate in
            attached.contains(where: { $0 === candidate })
        }) else {
            assertionFailure("Dual-deck graph lost an attached node", file: file, line: line)
            throw DualDeckAudioEngineError.graphInvariantFailed("an owned node is detached")
        }

        guard engine.outputConnectionPoints(for: deckA.outputMixer, outputBus: 0).contains(where: { $0.node === commonMixer }),
              engine.outputConnectionPoints(for: deckB.outputMixer, outputBus: 0).contains(where: { $0.node === commonMixer }),
              engine.outputConnectionPoints(for: commonMixer, outputBus: 0).contains(where: { $0.node === balanceMixer }),
              engine.outputConnectionPoints(for: balanceMixer, outputBus: 0).contains(where: { $0.node === engine.mainMixerNode }) else {
            assertionFailure("Dual-deck graph lost a stable output edge", file: file, line: line)
            throw DualDeckAudioEngineError.graphInvariantFailed("a shared output connection is missing")
        }
    }

    private static func safeAttach(_ node: AVAudioNode, to engine: AVAudioEngine) throws {
        var reason: NSString?
        guard TDTryAudioEngineAttach(engine, node, &reason) else {
            throw DualDeckAudioEngineError.graphMutationFailed(
                (reason as String?) ?? "NSException during attach"
            )
        }
    }

    private static func safeConnect(
        _ source: AVAudioNode,
        to destination: AVAudioNode,
        format: AVAudioFormat?,
        in engine: AVAudioEngine
    ) throws {
        var reason: NSString?
        guard TDTryAudioEngineConnect(engine, source, destination, format, &reason) else {
            throw DualDeckAudioEngineError.graphMutationFailed(
                (reason as String?) ?? "NSException during connect"
            )
        }
    }

    private static func safeDisconnectOutput(_ node: AVAudioNode, in engine: AVAudioEngine) throws {
        var reason: NSString?
        guard TDTryAudioEngineDisconnectOutput(engine, node, &reason) else {
            throw DualDeckAudioEngineError.graphMutationFailed(
                (reason as String?) ?? "NSException during disconnect"
            )
        }
    }
}
