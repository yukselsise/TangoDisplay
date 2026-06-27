import AVFoundation
import Foundation
import TangoDisplayCore

enum PlaybackDeckError: LocalizedError {
    case notAttached
    case notPrepared
    case stalePreparation
    case invalidStartingFrame

    var errorDescription: String? {
        switch self {
        case .notAttached: return "Playback deck is not attached to an audio engine."
        case .notPrepared: return "Playback deck has no prepared track."
        case .stalePreparation: return "Playback deck preparation was superseded."
        case .invalidStartingFrame: return "The requested starting frame is outside the audio file."
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

    func attach(to engine: AVAudioEngine) {
        guard self.engine !== engine else { return }
        if let oldEngine = self.engine {
            detachOwnedNodes(from: oldEngine)
        }
        self.engine = engine
        [playerNode, eq, replayGainMixer, outputMixer].forEach { engine.attach($0) }
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
            let file = try AVAudioFile(forReading: url)
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
            for runtime in runtimes { engine.attach(runtime.unit) }
            try self.connectGraph(
                in: engine,
                format: file.processingFormat,
                plugins: runtimes
            )

            self.audioFile = file
            self.processingFormat = file.processingFormat
            self.entryID = entry.id
            self.pluginRuntimes = runtimes
            self.pluginConfigurationID = configuration?.id
            self.replayGainMixer.outputVolume = replayGain
        }
        preparationTask = task
        do {
            try await task.value
        } catch {
            if generation == requestedGeneration { clearPreparedIdentity() }
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
        engine.connect(playerNode, to: eq, format: format)
        engine.connect(eq, to: replayGainMixer, format: format)
        let pluginFormat = format.channelCount < 2
            ? AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2)
            : format
        var previous: AVAudioNode = replayGainMixer
        for runtime in plugins {
            if let pluginFormat {
                try runtime.unit.auAudioUnit.inputBusses[0].setFormat(pluginFormat)
            }
            engine.connect(previous, to: runtime.unit, format: pluginFormat)
            previous = runtime.unit
        }
        engine.connect(previous, to: outputMixer, format: pluginFormat)
    }

    private func disconnectGraph(from engine: AVAudioEngine) {
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(eq)
        engine.disconnectNodeOutput(replayGainMixer)
        pluginRuntimes.forEach { engine.disconnectNodeOutput($0.unit) }
        engine.disconnectNodeOutput(outputMixer)
    }

    private func detachPlugins(from engine: AVAudioEngine) {
        pluginRuntimes.forEach { engine.detach($0.unit) }
        pluginRuntimes.removeAll()
    }

    private func detachOwnedNodes(from engine: AVAudioEngine) {
        disconnectGraph(from: engine)
        detachPlugins(from: engine)
        [playerNode, eq, replayGainMixer, outputMixer].forEach { engine.detach($0) }
    }

    private func clearPreparedIdentity() {
        audioFile = nil
        processingFormat = nil
        entryID = nil
        pluginConfigurationID = nil
    }
}
