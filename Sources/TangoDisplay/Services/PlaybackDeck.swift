import AVFoundation
import Foundation
import TangoDisplayCore
import TangoDisplayObjC

enum PlaybackDeckError: LocalizedError {
    case notAttached
    case notPrepared
    case stalePreparation
    case invalidStartingFrame
    case graphConnectionFailed(String)
    case graphMutationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAttached: return "Playback deck is not attached to an audio engine."
        case .notPrepared: return "Playback deck has no prepared track."
        case .stalePreparation: return "Playback deck preparation was superseded."
        case .invalidStartingFrame: return "The requested starting frame is outside the audio file."
        case .graphConnectionFailed(let reason): return "Playback deck graph connection failed: \(reason)"
        case .graphMutationFailed(let reason): return "Playback deck graph mutation failed: \(reason)"
        }
    }
}

/// One independently prepared side of the dual-deck player.
///
/// The legacy player remains authoritative until the coordinator and stable
/// output graph are introduced. In particular, this type never publishes UI
/// state and never opens an Audio Unit editor while preparing the standby side.
@MainActor
final class PlaybackDeck {
    let id: DeckID
    let playerNode = AVAudioPlayerNode()
    let eq = AVAudioUnitEQ(numberOfBands: 5)
    let replayGainMixer = AVAudioMixerNode()
    let outputMixer = AVAudioMixerNode()

    private(set) var entryID: UUID?
    private(set) var generation: Int = 0
    private(set) var audioFile: AVAudioFile?
    private(set) var processingFormat: AVAudioFormat?
    private(set) var pluginRuntimes: [AudioUnitPluginManager.DeckPluginRuntime] = []
    private(set) var pluginConfigurationID: UUID?

    private weak var engine: AVAudioEngine?
    private let pluginManager: AudioUnitPluginManager
    private var pluginSlots: [AudioUnitChainSlot]
    private var preparationTask: Task<Void, Error>?
    private var attachedOwnedNodes: [AVAudioNode] = []

    private struct OpenedAudioFile: @unchecked Sendable {
        let file: AVAudioFile
        let format: AVAudioFormat
    }

    init(
        id: DeckID,
        pluginManager: AudioUnitPluginManager = AudioUnitPluginManager(),
        pluginSlots: [AudioUnitChainSlot] = []
    ) {
        self.id = id
        self.pluginManager = pluginManager
        self.pluginSlots = pluginSlots
        configureEQ()
    }

    func updatePluginSlots(_ slots: [AudioUnitChainSlot]) {
        pluginSlots = slots
    }

    func attach(to engine: AVAudioEngine) throws {
        guard self.engine !== engine else { return }
        if let oldEngine = self.engine {
            detachOwnedNodes(from: oldEngine)
        }
        self.engine = engine
        attachedOwnedNodes.removeAll()
        do {
            for node in [playerNode, eq, replayGainMixer, outputMixer] {
                try safeAttach(engine, node)
                attachedOwnedNodes.append(node)
            }
        } catch {
            attachedOwnedNodes.reversed().forEach { safeDetach(engine, $0) }
            attachedOwnedNodes.removeAll()
            self.engine = nil
            throw error
        }
    }

    func prepare(
        entry: SetlistEntry,
        configuration: PluginChainConfiguration?,
        replayGain: Float
    ) async throws {
        guard let engine else { throw PlaybackDeckError.notAttached }
        cancel()
        generation &+= 1
        let requestedGeneration = generation
        let slots = pluginSlots
        let manager = pluginManager
        let url = entry.fileURL

        let task = Task<Void, Error> {
            let opened = try await Self.openAudioFile(at: url)
            try Task.checkCancellation()
            guard self.generation == requestedGeneration else {
                throw PlaybackDeckError.stalePreparation
            }
            let runtimes = try await manager.instantiateDeckChain(
                slots: slots,
                configuration: configuration
            )
            try Task.checkCancellation()
            guard self.generation == requestedGeneration else {
                throw PlaybackDeckError.stalePreparation
            }

            self.disconnectGraph(from: engine)
            self.detachPlugins(from: engine)
            var attached: [AudioUnitPluginManager.DeckPluginRuntime] = []
            do {
                for runtime in runtimes {
                    try self.safeAttach(engine, runtime.unit)
                    attached.append(runtime)
                }
                try self.connectGraph(
                    in: engine,
                    format: opened.format,
                    plugins: runtimes
                )
            } catch {
                self.rollbackPreparation(in: engine, attachedPlugins: attached)
                throw error
            }

            self.audioFile = opened.file
            self.processingFormat = opened.format
            self.entryID = entry.id
            self.pluginRuntimes = runtimes
            self.pluginConfigurationID = configuration?.id
            self.replayGainMixer.outputVolume = replayGain
        }
        preparationTask = task
        do {
            try await task.value
        } catch {
            if generation == requestedGeneration {
                rollbackPreparation(in: engine, attachedPlugins: pluginRuntimes)
            }
            throw error
        }
        if generation == requestedGeneration { preparationTask = nil }
    }

    func schedule(startingFrame: AVAudioFramePosition = 0, at time: AVAudioTime? = nil) throws {
        guard let audioFile else { throw PlaybackDeckError.notPrepared }
        guard startingFrame >= 0, startingFrame < audioFile.length else {
            throw PlaybackDeckError.invalidStartingFrame
        }
        outputMixer.outputVolume = 1
        let remaining = audioFile.length - startingFrame
        guard remaining <= AVAudioFramePosition(AVAudioFrameCount.max) else {
            // AVAudioPlayerNode's segment API is UInt32-limited. Long files are
            // scheduled whole when playback starts at zero.
            if startingFrame == 0 {
                playerNode.scheduleFile(audioFile, at: time)
                return
            }
            throw PlaybackDeckError.invalidStartingFrame
        }
        playerNode.scheduleSegment(
            audioFile,
            startingFrame: startingFrame,
            frameCount: AVAudioFrameCount(remaining),
            at: time
        )
    }

    func cancel() {
        preparationTask?.cancel()
        preparationTask = nil
        playerNode.stop()
        generation &+= 1
    }

    /// Stops the player node immediately, intentionally discarding plugin tail.
    func hardCut() {
        playerNode.stop()
        outputMixer.outputVolume = 0
    }

    func resetForReuse() {
        cancel()
        if let engine {
            disconnectGraph(from: engine)
            detachPlugins(from: engine)
        }
        clearPreparedIdentity()
        outputMixer.outputVolume = 1
        replayGainMixer.outputVolume = 1
    }

    private func configureEQ() {
        let frequencies: [Float] = [60, 250, 1_000, 4_000, 12_000]
        let types: [AVAudioUnitEQFilterType] = [.lowShelf, .parametric, .parametric, .parametric, .highShelf]
        for (index, band) in eq.bands.enumerated() {
            band.filterType = types[index]
            band.frequency = frequencies[index]
            band.bandwidth = 1
            band.gain = 0
            band.bypass = false
        }
    }

    private func connectGraph(
        in engine: AVAudioEngine,
        format: AVAudioFormat,
        plugins: [AudioUnitPluginManager.DeckPluginRuntime]
    ) throws {
        try safeConnect(engine, playerNode, eq, format)
        try safeConnect(engine, eq, replayGainMixer, format)
        let pluginFormat = format.channelCount < 2
            ? AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2)
            : format
        var previous: AVAudioNode = replayGainMixer
        for runtime in plugins {
            if let pluginFormat {
                try runtime.unit.auAudioUnit.inputBusses[0].setFormat(pluginFormat)
            }
            try safeConnect(engine, previous, runtime.unit, pluginFormat)
            previous = runtime.unit
        }
        try safeConnect(engine, previous, outputMixer, pluginFormat)
    }

    private func safeConnect(
        _ engine: AVAudioEngine,
        _ source: AVAudioNode,
        _ destination: AVAudioNode,
        _ format: AVAudioFormat?
    ) throws {
        var reason: NSString?
        guard TDTryAudioEngineConnect(engine, source, destination, format, &reason) else {
            throw PlaybackDeckError.graphConnectionFailed(
                (reason as String?) ?? "NSException during connect"
            )
        }
    }

    private nonisolated static func openAudioFile(at url: URL) async throws -> OpenedAudioFile {
        try await Task.detached(priority: .userInitiated) {
            let file = try AVAudioFile(forReading: url)
            return OpenedAudioFile(file: file, format: file.processingFormat)
        }.value
    }

    private func safeAttach(_ engine: AVAudioEngine, _ node: AVAudioNode) throws {
        var reason: NSString?
        guard TDTryAudioEngineAttach(engine, node, &reason) else {
            throw PlaybackDeckError.graphMutationFailed((reason as String?) ?? "NSException during attach")
        }
    }

    private func safeDetach(_ engine: AVAudioEngine, _ node: AVAudioNode) {
        var reason: NSString?
        _ = TDTryAudioEngineDetach(engine, node, &reason)
    }

    private func rollbackPreparation(
        in engine: AVAudioEngine,
        attachedPlugins: [AudioUnitPluginManager.DeckPluginRuntime]
    ) {
        disconnectGraph(from: engine)
        for runtime in attachedPlugins {
            engine.disconnectNodeOutput(runtime.unit)
            safeDetach(engine, runtime.unit)
        }
        pluginRuntimes.removeAll()
        clearPreparedIdentity()
        replayGainMixer.outputVolume = 1
        outputMixer.outputVolume = 1
    }

    private func disconnectGraph(from engine: AVAudioEngine) {
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(eq)
        engine.disconnectNodeOutput(replayGainMixer)
        pluginRuntimes.forEach { engine.disconnectNodeOutput($0.unit) }
        engine.disconnectNodeOutput(outputMixer)
    }

    private func detachPlugins(from engine: AVAudioEngine) {
        pluginRuntimes.forEach { safeDetach(engine, $0.unit) }
        pluginRuntimes.removeAll()
    }

    private func detachOwnedNodes(from engine: AVAudioEngine) {
        disconnectGraph(from: engine)
        detachPlugins(from: engine)
        attachedOwnedNodes.reversed().forEach { safeDetach(engine, $0) }
        attachedOwnedNodes.removeAll()
    }

    private func clearPreparedIdentity() {
        audioFile = nil
        processingFormat = nil
        entryID = nil
        pluginConfigurationID = nil
    }
}
