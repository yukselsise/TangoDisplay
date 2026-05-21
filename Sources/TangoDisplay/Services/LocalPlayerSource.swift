import AVFoundation
import AppKit
import Combine
import CoreAudioKit
import Foundation
import OSLog
import TangoDisplayCore

final class LocalPlayerSource: NSObject, ObservableObject, MusicPlayerSource {

    // MARK: - MusicPlayerSource callbacks

    var onTrackUpdate: ((Track?, PlayerState) -> Void)?
    var onPlaylistUpdate: ((tracks: [Track], currentIndex: Int)?) -> Void = { _ in }
    var onNextTrackUpdate: ((Track?) -> Void)?
    var onWatchdogChanged: ((Bool) -> Void)?
    var supportsPlaylist: Bool { true }
    var isTransportControllable: Bool { true }

    // MARK: - Observable playback state (for PlayerControlsView)

    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentEntryID: UUID?
    @Published private(set) var isCurrentEntryMarkedAsPlayed: Bool = false
    @Published private(set) var isActivePlaying: Bool = false

    var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = max(0, min(1, newValue)) }
    }

    private var _balance: Float = 0
    var balance: Float {
        get { _balance }
        set { _balance = max(-1, min(1, newValue)); applyBalance(_balance) }
    }

    // MARK: - Diagnostics

    @Published private(set) var replayGainStatus: String = ""

    // MARK: - Private — audio engine

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 5)
    private let replayGainMixer = AVAudioMixerNode()
    private let balanceMixer = AVAudioMixerNode()
    private var audioFile: AVAudioFile?
    private var seekOffset: Double = 0

    // MARK: - Level meter

    private(set) var levelMeter: AudioLevelMeter!

    // MARK: - Private — state

    let setlist: SetlistManager
    private let settings: AppSettings
    private var timeObserverTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var earlyMarkedEntryIDs: Set<UUID> = []
    private var scheduleGeneration: Int = 0

    // MARK: - Private — Audio Unit plugin

    private let pluginManager = AudioUnitPluginManager()
    private var activeAudioUnitPlugin: AVAudioUnit?
    private var pluginLoadTask: Task<Void, Never>?
    private var pluginLoadGeneration: Int = 0
    @Published private(set) var audioUnitPluginStatus: AudioUnitPluginStatus = .noPluginSelected
    private var pluginWindow: NSWindow?

    // MARK: - Private — auto-gap

    private var currentPaddingFrames: AVAudioFrameCount = 0
    private var prevTrackSilenceAtEnd: Double = 0   // populated by background analysis of the track that just played
    private var nextTrackSilenceAtStart: Double = 0 // populated by background analysis of the upcoming track
    private var audioStartSampleTime: AVAudioFramePosition = 0
    private var silencePending: Bool = false

    // MARK: - Private — loudness analysis

    private var inFlightAnalysisURLs = Set<URL>()
    private let loudnessCache = LoudnessAnalysisCache.shared

    // MARK: - Init

    init(setlist: SetlistManager, settings: AppSettings, volume: Float = 1.0) {
        self.setlist = setlist
        self.settings = settings
        super.init()
        setupAudioEngine()
        levelMeter = AudioLevelMeter(mixerNode: audioEngine.mainMixerNode)
        playerNode.volume = max(0, min(1, volume))
        applyOutputDevice(settings.builtInOutputDeviceUID)
        applyEQGains(settings.eqGains)
        _balance = max(-1, min(1, settings.builtInBalance))
        applyBalance(_balance)
    }

    // MARK: - Audio engine setup

    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        audioEngine.attach(eq)
        audioEngine.attach(replayGainMixer)
        audioEngine.attach(balanceMixer)
        connectAudioGraph(format: nil)

        let frequencies: [Float]          = [60, 250, 1000, 4000, 12000]
        let filterTypes: [AVAudioUnitEQFilterType] = [.lowShelf, .parametric, .parametric, .parametric, .highShelf]
        for (i, band) in eq.bands.enumerated() {
            band.filterType = filterTypes[i]
            band.frequency  = frequencies[i]
            band.bandwidth  = 1.0
            band.gain       = 0.0
            band.bypass     = false
        }

        try? audioEngine.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )
    }

    @objc private func handleEngineConfigChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.audioFile != nil {
                self.connectAudioGraph(format: self.audioFile?.processingFormat)
            }
            // Engine is already stopped by the system when this notification fires, so it is
            // safe to set the output device property before restarting — this re-asserts the
            // user's chosen device so a plug event (e.g. headphones) doesn't silently redirect audio.
            if let audioUnit = self.audioEngine.outputNode.audioUnit {
                self.setOutputDeviceProperty(audioUnit: audioUnit, uid: self.settings.builtInOutputDeviceUID)
            }
            do {
                try self.audioEngine.start()
                self.levelMeter.reinstallTap()
                self.applyBalance(self._balance)
                if self.audioFile != nil {
                    self.seekTo(self.elapsed)
                    if self.isActivePlaying { self.playerNode.play() }
                }
            } catch {
                os_log(.error, "TangoDisplay: engine restart failed: %{public}@", error.localizedDescription)
            }
        }
    }

    private func applyOutputDevice(_ uid: String) {
        guard let audioUnit = audioEngine.outputNode.audioUnit else { return }
        let wasPlaying = isActivePlaying
        let savedElapsed = elapsed
        // CoreAudio requires the engine to be stopped before changing the output device.
        if audioEngine.isRunning {
            playerNode.stop()
            audioEngine.stop()
        }
        setOutputDeviceProperty(audioUnit: audioUnit, uid: uid)
        do {
            try audioEngine.start()
            levelMeter.reinstallTap()
            if audioFile != nil {
                seekTo(savedElapsed)
                if wasPlaying { playerNode.play() }
            }
        } catch {
            os_log(.error, "TangoDisplay: applyOutputDevice engine restart failed: %{public}@", error.localizedDescription)
        }
    }

    private func setOutputDeviceProperty(audioUnit: AudioUnit, uid: String) {
        if uid.isEmpty {
            // Restore default device by reading system default
            var defaultID = AudioDeviceID(0)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &defaultID)
            AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &defaultID, size)
        } else if var deviceID = AudioDeviceManager.audioDeviceID(forUID: uid) {
            AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &deviceID,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        }
    }

    private func applyEQGains(_ gains: [Float]) {
        for (i, band) in eq.bands.enumerated() where i < gains.count {
            band.gain = gains[i]
        }
    }

    private func applyBalance(_ pan: Float) {
        balanceMixer.pan = pan
    }

    private func applyReplayGain(for entry: SetlistEntry) {
        let rgSettings = ReplayGainSettings(
            mode: settings.replayGainMode,
            preampDb: Double(settings.replayGainPreampDb),
            preventClipping: settings.replayGainPreventClipping,
            targetLoudnessLufs: Double(settings.replayGainTargetLufs)
        )
        let info = entry.track.replayGainInfo
        let cacheKey = loudnessCacheKey(for: entry)
        let rawAnalysis = cacheKey.flatMap { loudnessCache.result(for: $0) }

        // Recalculate gain from cached integrated loudness if target has changed since analysis
        let analysis: LoudnessAnalysisResult? = rawAnalysis.map { cached in
            guard cached.targetLoudnessLufs != rgSettings.targetLoudnessLufs else { return cached }
            let newGainDb = rgSettings.targetLoudnessLufs - cached.integratedLoudnessLufs
            return LoudnessAnalysisResult(
                filePath: cached.filePath, fileSize: cached.fileSize,
                modifiedDate: cached.modifiedDate, duration: cached.duration,
                integratedLoudnessLufs: cached.integratedLoudnessLufs,
                calculatedReplayGainDb: newGainDb,
                targetLoudnessLufs: rgSettings.targetLoudnessLufs,
                samplePeak: cached.samplePeak, truePeak: cached.truePeak,
                analysedAt: cached.analysedAt
            )
        }

        let result = calculateReplayGain(info: info, analysis: analysis, settings: rgSettings)
        replayGainMixer.outputVolume = result.linearGain

        let analysisInFlight = inFlightAnalysisURLs.contains(entry.fileURL)
        replayGainStatus = replayGainStatusString(result: result, settings: rgSettings,
                                                   analysisInFlight: analysisInFlight)

        if settings.replayGainMode == .auto,
           info?.trackGainDb == nil,
           analysis == nil {
            queueLoudnessAnalysis(for: entry, isCurrentTrack: true)
        }
    }

    private func replayGainStatusString(result: ReplayGainCalculationResult,
                                         settings: ReplayGainSettings,
                                         analysisInFlight: Bool) -> String {
        guard settings.mode != .off else { return "" }
        switch result.source {
        case .none:
            if analysisInFlight { return "ReplayGain: Analysing…" }
            return settings.mode == .album ? "ReplayGain: No album metadata" : "ReplayGain: No metadata"
        case .metadataTrack:
            let suffix = result.clippingProtectionApplied ? " (clipping limited)" : ""
            return String(format: "ReplayGain: Track %+.1f dB\(suffix)", result.gainDb ?? 0)
        case .metadataAlbum:
            let suffix = result.clippingProtectionApplied ? " (clipping limited)" : ""
            return String(format: "ReplayGain: Album %+.1f dB\(suffix)", result.gainDb ?? 0)
        case .analysed:
            let lufsStr = result.integratedLoudnessLufs.map { String(format: " · %.1f LUFS", $0) } ?? ""
            let suffix = result.clippingProtectionApplied ? " (clipping limited)" : ""
            return String(format: "ReplayGain: Auto %+.1f dB\(lufsStr)\(suffix)", result.gainDb ?? 0)
        }
    }

    private static func analysisStatusForError(_ error: Error) -> String {
        if error is CancellationError { return "ReplayGain: Cancelled" }
        switch error as? LoudnessAnalysisError {
        case .cannotOpenFile:    return "ReplayGain: Cannot read file"
        case .unsupportedFormat: return "ReplayGain: Unsupported format"
        case .insufficientData:  return "ReplayGain: Insufficient audio"
        case .none:              return "ReplayGain: Analysis failed"
        }
    }

    private func queueLoudnessAnalysis(for entry: SetlistEntry, isCurrentTrack: Bool) {
        let url = entry.fileURL
        guard !inFlightAnalysisURLs.contains(url) else { return }
        inFlightAnalysisURLs.insert(url)
        if isCurrentTrack { replayGainStatus = "ReplayGain: Analysing…" }

        let entryID = entry.id
        let targetLufs = Double(settings.replayGainTargetLufs)
        let cache = loudnessCache

        Task.detached(priority: .background) { [weak self] in
            let analysisResult: LoudnessAnalysisResult?
            let errorStatus: String?
            do {
                analysisResult = try await LoudnessAnalyzer.shared.analyse(
                    url: url, targetLoudnessLufs: targetLufs)
                errorStatus = nil
            } catch {
                analysisResult = nil
                errorStatus = LocalPlayerSource.analysisStatusForError(error)
            }

            if let result = analysisResult { cache.store(result) }

            let succeeded = analysisResult != nil
            let failStatus = errorStatus
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.inFlightAnalysisURLs.remove(url)               // always runs
                guard self.currentEntryID == entryID else { return }
                if let currentEntry = self.setlist.entries.first(where: { $0.id == entryID }) {
                    self.applyReplayGain(for: currentEntry)         // re-reads cache or falls through
                }
                if !succeeded, let status = failStatus {
                    self.replayGainStatus = status
                }
            }
        }
    }

    private func preAnalyseIfNeeded(_ entry: SetlistEntry) {
        guard settings.replayGainMode == .auto,
              entry.track.replayGainInfo?.trackGainDb == nil else { return }
        if let key = loudnessCacheKey(for: entry),
           loudnessCache.result(for: key) != nil { return }
        queueLoudnessAnalysis(for: entry, isCurrentTrack: false)
    }

    private func loudnessCacheKey(for entry: SetlistEntry) -> LoudnessAnalysisCacheKey? {
        let path = entry.fileURL.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attrs[.size] as? Int64,
              let modDate = attrs[.modificationDate] as? Date else { return nil }
        return LoudnessAnalysisCacheKey(filePath: path, fileSize: fileSize, modifiedDate: modDate)
    }

    private func reapplyReplayGainIfLoaded() {
        guard let id = currentEntryID,
              let entry = setlist.entries.first(where: { $0.id == id }) else {
            replayGainStatus = ""
            return
        }
        applyReplayGain(for: entry)
    }

    // MARK: - MusicPlayerSource lifecycle

    func start() {
        setupObservers()
        reportCurrentState()
        reportPlaylist()
        initializePluginStatus()
    }

    func stop() {
        pluginLoadTask?.cancel()
        pluginLoadTask = nil
        pluginWindow?.close()
        pluginWindow = nil
        currentEntryID = nil
        isCurrentEntryMarkedAsPlayed = false
        isActivePlaying = false
        replayGainStatus = ""
        replayGainMixer.outputVolume = 1.0
        inFlightAnalysisURLs.removeAll()
        playerNode.stop()
        audioEngine.stop()
        levelMeter.reset()
        audioFile = nil
        elapsed = 0
        duration = 0
        currentPaddingFrames = 0
        silencePending = false
        audioStartSampleTime = 0
        prevTrackSilenceAtEnd = 0
        nextTrackSilenceAtStart = 0
        teardownObservers()
    }

    func pollNow() {
        reportCurrentState()
        reportPlaylist()
    }

    func triggerPlaylistFetch() {
        reportPlaylist()
    }

    func fetchArtwork(for track: Track) async -> NSImage? {
        guard let url = URL(string: track.persistentID), url.isFileURL else { return nil }
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.metadata) else { return nil }
        let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork)
        guard let item = items.first,
              let data = try? await item.load(.dataValue) else { return nil }
        return NSImage(data: data)
    }

    // MARK: - Transport controls

    func play() {
        if let id = currentEntryID, earlyMarkedEntryIDs.contains(id) || currentEntryIsPlayed() {
            skipNext()
            return
        }
        if audioFile == nil {
            // Prefer currentEntryID if set (e.g. pause() advanced it to the next track);
            // fall back to first non-played entry for a fresh start.
            let entry: SetlistEntry?
            if let id = currentEntryID {
                entry = setlist.entries.first(where: { $0.id == id })
            } else {
                entry = setlist.entries.first(where: { $0.state != .played })
            }
            guard let entry else { return }
            loadEntry(entry)
            playerNode.play()
            isActivePlaying = true
        } else if let id = currentEntryID {
            setlist.markPlaying(id: id)
            seekTo(0) { [weak self] in
                self?.playerNode.play()
                self?.isActivePlaying = true
            }
        }
        reportCurrentState()
    }

    func pause() {
        scheduleGeneration += 1
        playerNode.stop()
        isActivePlaying = false
        if let id = currentEntryID, !earlyMarkedEntryIDs.contains(id), !currentEntryIsPlayed() {
            setlist.markPaused(id: id)
            seekTo(0)
            elapsed = 0
            reportCurrentState()
        } else if let id = currentEntryID, let nextEntry = setlist.firstUnplayed(after: id) {
            audioFile = nil
            seekOffset = 0
            currentEntryID = nextEntry.id
            elapsed = 0
            duration = nextEntry.duration ?? 0
            reportCurrentState()
            reportPlaylist()
            onNextTrackUpdate?(setlist.entry(after: nextEntry.id)?.track)
        } else {
            audioFile = nil
            seekOffset = 0
            currentEntryID = nil
            elapsed = 0
            duration = 0
            reportCurrentState()
            reportPlaylist()
            onNextTrackUpdate?(nil)
        }
    }

    func stopTrack() {
        if let id = currentEntryID, !earlyMarkedEntryIDs.contains(id), !currentEntryIsPlayed() {
            setlist.markQueued(id: id)
        }
        scheduleGeneration += 1
        currentEntryID = nil
        isCurrentEntryMarkedAsPlayed = false
        isActivePlaying = false
        replayGainStatus = ""
        playerNode.stop()
        audioFile = nil
        elapsed = 0
        duration = 0
        seekOffset = 0
        currentPaddingFrames = 0
        silencePending = false
        audioStartSampleTime = 0
        prevTrackSilenceAtEnd = 0
        nextTrackSilenceAtStart = 0
        reportCurrentState()
        reportPlaylist()
        onNextTrackUpdate?(nil)
    }

    func skipNext() {
        guard let id = currentEntryID else { play(); return }
        let shouldStop = (id == setlist.stopAfterEntryID)
        setlist.markPlayed(id: id)
        if shouldStop { setlist.stopAfterEntryID = nil }
        if !shouldStop, let next = setlist.firstUnplayed(after: id) {
            loadEntry(next)
            playerNode.play()
            isActivePlaying = true
            reportCurrentState()
        } else {
            currentEntryID = nil
            isActivePlaying = false
            replayGainStatus = ""
            playerNode.stop()
            audioFile = nil
            elapsed = 0
            duration = 0
            seekOffset = 0
            reportCurrentState()
            reportPlaylist()
            onNextTrackUpdate?(nil)
        }
    }

    func skipNextImmediate() {
        guard let id = currentEntryID else { play(); return }
        let shouldStop = (id == setlist.stopAfterEntryID)
        setlist.markPlayed(id: id)
        if shouldStop { setlist.stopAfterEntryID = nil }
        if !shouldStop, let next = setlist.firstUnplayed(after: id) {
            loadEntry(next, bypassAutoGap: true)
            playerNode.play()
            isActivePlaying = true
            reportCurrentState()
        } else {
            currentEntryID = nil
            isActivePlaying = false
            replayGainStatus = ""
            playerNode.stop()
            audioFile = nil
            elapsed = 0
            duration = 0
            seekOffset = 0
            reportCurrentState()
            reportPlaylist()
            onNextTrackUpdate?(nil)
        }
    }

    func skipPrevious() {
        if elapsed > 3 {
            seek(to: 0)
            return
        }
        guard let id = currentEntryID else { return }
        if let prev = setlist.entry(before: id) {
            let wasPlaying = isActivePlaying
            loadEntry(prev)
            if wasPlaying { playerNode.play(); isActivePlaying = true; reportCurrentState() }
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: Double) {
        seekTo(seconds)
    }

    // MARK: - Jump to a specific entry (double-click in SetlistView)

    func jumpTo(_ entry: SetlistEntry) {
        loadEntry(entry)
        playerNode.play()
        isActivePlaying = true
        reportCurrentState()
    }

    // MARK: - Private: seek implementation

    private func seekTo(_ seconds: Double, completion: (() -> Void)? = nil) {
        guard let file = audioFile else { completion?(); return }
        let sampleRate = file.fileFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, seconds) * sampleRate)
        let totalFrames = file.length
        guard startFrame < totalFrames else { completion?(); return }
        let frameCount = AVAudioFrameCount(totalFrames - startFrame)
        let wasPlaying = playerNode.isPlaying
        playerNode.stop()
        seekOffset = seconds
        elapsed = seconds
        currentPaddingFrames = 0
        silencePending = false
        audioStartSampleTime = 0
        scheduleGeneration += 1
        let gen = scheduleGeneration
        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount,
                                   at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.handleTrackEnd(generation: gen) }
        }
        if wasPlaying { playerNode.play() }
        completion?()
    }

    // MARK: - Private: entry loading

    private func loadEntry(_ entry: SetlistEntry, bypassAutoGap: Bool = false) {
        earlyMarkedEntryIDs.remove(entry.id)
        isCurrentEntryMarkedAsPlayed = false
        playerNode.stop()
        scheduleGeneration += 1
        let gen = scheduleGeneration
        do {
            let file = try AVAudioFile(forReading: entry.fileURL)
            audioFile = file
            seekOffset = 0
            elapsed = 0
            duration = Double(file.length) / file.fileFormat.sampleRate
            // scheduleFile requires the file format to exactly match the output bus format.
            // Stop the engine before reconnecting so the graph is in a clean state; a mono
            // AIFF scheduled against the stereo-defaulted startup connection produces silence.
            audioEngine.stop()
            connectAudioGraph(format: file.processingFormat)
            try audioEngine.start()
            levelMeter.reinstallTap()
            applyReplayGain(for: entry)

            // Pre-warm loudness analysis for the next track so it's cached before it starts.
            if let nextEntry = setlist.entry(after: entry.id) {
                preAnalyseIfNeeded(nextEntry)
            }

            // Auto-gap: schedule silence before the file if needed.
            // nextTrackSilenceAtStart is pre-populated by the background analysis from the previous track's loadEntry.
            currentPaddingFrames = 0
            silencePending = false
            audioStartSampleTime = 0
            let isFirstTrack = setlist.entries.first?.id == entry.id
                && !setlist.entries.contains(where: { $0.state == .played })
            var autoGapApplied = false
            var autoGapSkipped = false
            if !bypassAutoGap && !entry.ignoresAutoGap && settings.autoGapEnabled {
                if settings.autoGapIgnoreFirstTrack && isFirstTrack {
                    autoGapSkipped = true
                } else {
                    let padding = computeAutoGapPadding(
                        prevSilenceAtEnd: prevTrackSilenceAtEnd,
                        nextSilenceAtStart: nextTrackSilenceAtStart,
                        minimumSilence: settings.autoGapDuration
                    )
                    if padding > 0 {
                        let frames = AVAudioFrameCount(padding * file.fileFormat.sampleRate)
                        silencePending = true
                        let entryID = entry.id
                        playerNode.scheduleBuffer(
                            makeSilenceBuffer(format: file.processingFormat, frameCount: frames),
                            completionCallbackType: .dataConsumed
                        ) { [weak self] _ in
                            DispatchQueue.main.async {
                                guard let self,
                                      let nodeTime = self.playerNode.lastRenderTime,
                                      nodeTime.isSampleTimeValid,
                                      let pt = self.playerNode.playerTime(forNodeTime: nodeTime) else { return }
                                self.audioStartSampleTime = pt.sampleTime
                                self.silencePending = false
                                self.setlist.setAutoGapApplied(id: entryID, applied: false)
                            }
                        }
                        currentPaddingFrames = frames
                        autoGapApplied = true
                    }
                }
            }
            setlist.setAutoGapApplied(id: entry.id, applied: autoGapApplied)
            setlist.setAutoGapSkipped(id: entry.id, skipped: autoGapSkipped)
            prevTrackSilenceAtEnd = 0
            nextTrackSilenceAtStart = 0

            playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async { self?.handleTrackEnd(generation: gen) }
            }

            // Analyze current track's end-silence and pre-warm next track's start-silence in background.
            let currentURL = entry.fileURL
            let nextURL = setlist.entry(after: entry.id)?.fileURL
            Task { [weak self] in
                let result = await AudioSilenceAnalyzer.shared.analyze(url: currentURL)
                let nextStart: Double
                if let nextURL {
                    let nextResult = await AudioSilenceAnalyzer.shared.analyze(url: nextURL)
                    nextStart = nextResult.silenceAtStart
                } else {
                    nextStart = 0
                }
                await MainActor.run { [weak self] in
                    self?.prevTrackSilenceAtEnd = result.silenceAtEnd
                    self?.nextTrackSilenceAtStart = nextStart
                }
            }
        } catch {
            os_log(.error, "TangoDisplay: failed to load %{public}@: %{public}@",
                   entry.fileURL.path, error.localizedDescription)
            audioFile = nil
        }
        currentEntryID = entry.id
        setlist.markPlaying(id: entry.id)
        reportCurrentState()
        reportPlaylist()
        onNextTrackUpdate?(setlist.entry(after: entry.id)?.track)
    }

    private func handleTrackEnd(generation: Int) {
        guard generation == scheduleGeneration else { return }
        skipNext()
    }

    private func computeAutoGapPadding(
        prevSilenceAtEnd: Double,
        nextSilenceAtStart: Double,
        minimumSilence: Double
    ) -> Double {
        guard minimumSilence > 0 else { return 0 }
        let existing = prevSilenceAtEnd + nextSilenceAtStart
        return max(0, minimumSilence - existing)
    }

    private func makeSilenceBuffer(format: AVAudioFormat, frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer {
        // AVAudioPCMBuffer is zero-initialized, so this is already silent.
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buf.frameLength = frameCount
        return buf
    }

    private func currentEntryIsPlayed() -> Bool {
        guard let id = currentEntryID else { return false }
        return setlist.entries.first(where: { $0.id == id })?.state == .played
    }

    // MARK: - Private: audio graph

    private func connectAudioGraph(format: AVAudioFormat?) {
        audioEngine.disconnectNodeOutput(playerNode)
        audioEngine.disconnectNodeOutput(eq)
        audioEngine.disconnectNodeOutput(replayGainMixer)
        if let plugin = activeAudioUnitPlugin {
            audioEngine.disconnectNodeOutput(plugin)
        }
        audioEngine.disconnectNodeOutput(balanceMixer)

        audioEngine.connect(playerNode, to: eq, format: format)
        audioEngine.connect(eq, to: replayGainMixer, format: format)

        let usePlugin = settings.audioUnitPluginEnabled
            && !settings.audioUnitPluginBypassed
            && activeAudioUnitPlugin != nil
        if usePlugin, let plugin = activeAudioUnitPlugin {
            audioEngine.connect(replayGainMixer, to: plugin, format: format)
            audioEngine.connect(plugin, to: balanceMixer, format: format)
        } else {
            audioEngine.connect(replayGainMixer, to: balanceMixer, format: format)
        }

        audioEngine.connect(balanceMixer, to: audioEngine.mainMixerNode, format: format)
    }

    private func rewireGraphSafely() {
        let wasPlaying = isActivePlaying
        let savedElapsed = elapsed
        let format = audioFile?.processingFormat

        playerNode.stop()
        audioEngine.stop()
        connectAudioGraph(format: format)

        do {
            try audioEngine.start()
        } catch {
            // Plugin caused engine start failure (e.g. format incompatibility). Fall back to safe graph.
            os_log(.error, "TangoDisplay: engine start failed with plugin, falling back: %{public}@",
                   error.localizedDescription)
            let name = settings.selectedAudioUnitPlugin?.name ?? ""
            let failedPlugin = activeAudioUnitPlugin
            activeAudioUnitPlugin = nil
            audioUnitPluginStatus = .failed(name, reason: error.localizedDescription)
            connectAudioGraph(format: format)
            try? audioEngine.start()
            if let plugin = failedPlugin {
                audioEngine.detach(plugin)
            }
        }

        levelMeter.reinstallTap()
        applyBalance(_balance)
        if audioFile != nil {
            seekTo(savedElapsed)
            if wasPlaying { playerNode.play() }
        }
    }

    // MARK: - Audio Unit plugin actions

    func selectAudioUnitPlugin(_ selection: AudioUnitPluginSelection) {
        pluginLoadTask?.cancel()
        pluginLoadTask = nil
        closePluginWindow()
        detachActivePlugin()
        settings.selectedAudioUnitPlugin = selection
        if settings.audioUnitPluginEnabled {
            startPluginLoad(selection)
        } else {
            audioUnitPluginStatus = .disabled
        }
    }

    func enableAudioUnitPlugin() {
        settings.audioUnitPluginEnabled = true
        guard let selection = settings.selectedAudioUnitPlugin else {
            audioUnitPluginStatus = .noPluginSelected
            return
        }
        if activeAudioUnitPlugin != nil {
            audioUnitPluginStatus = settings.audioUnitPluginBypassed
                ? .bypassed(selection.name) : .active(selection.name)
            rewireGraphSafely()
        } else {
            startPluginLoad(selection)
        }
    }

    func disableAudioUnitPlugin() {
        settings.audioUnitPluginEnabled = false
        audioUnitPluginStatus = .disabled
        rewireGraphSafely()
    }

    func bypassAudioUnitPlugin(_ bypassed: Bool) {
        settings.audioUnitPluginBypassed = bypassed
        if let name = settings.selectedAudioUnitPlugin?.name {
            audioUnitPluginStatus = bypassed ? .bypassed(name) : .active(name)
        }
        rewireGraphSafely()
    }

    func removeAudioUnitPlugin() {
        pluginLoadTask?.cancel()
        pluginLoadTask = nil
        closePluginWindow()
        detachActivePlugin()
        settings.selectedAudioUnitPlugin = nil
        settings.audioUnitPluginEnabled = false
        settings.audioUnitPluginBypassed = false
        audioUnitPluginStatus = .noPluginSelected
        rewireGraphSafely()
    }

    func openPluginWindow() {
        guard let avUnit = activeAudioUnitPlugin else { return }
        if let existing = pluginWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        avUnit.auAudioUnit.requestViewController { [weak self] viewController in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let vc = viewController else {
                    self.audioUnitPluginStatus = .failed(
                        self.settings.selectedAudioUnitPlugin?.name ?? "",
                        reason: "Plugin editor unavailable")
                    return
                }
                let window = NSWindow(contentViewController: vc)
                window.title = self.settings.selectedAudioUnitPlugin?.name ?? "Plugin"
                window.styleMask = [.titled, .closable, .resizable]
                window.isReleasedWhenClosed = false
                window.makeKeyAndOrderFront(nil)
                self.pluginWindow = window
            }
        }
    }

    func closePluginWindow() {
        pluginWindow?.close()
        pluginWindow = nil
    }

    // MARK: - Private: plugin internals

    private func initializePluginStatus() {
        guard let selection = settings.selectedAudioUnitPlugin else {
            audioUnitPluginStatus = .noPluginSelected
            return
        }
        guard settings.audioUnitPluginEnabled else {
            audioUnitPluginStatus = .disabled
            return
        }
        // Plugin already live from a previous session cycle — no need to reload.
        if activeAudioUnitPlugin != nil {
            audioUnitPluginStatus = settings.audioUnitPluginBypassed
                ? .bypassed(selection.name) : .active(selection.name)
            return
        }
        if pluginManager.isAvailable(selection) {
            startPluginLoad(selection)
        } else {
            audioUnitPluginStatus = .unavailable(selection.name)
        }
    }

    private func startPluginLoad(_ selection: AudioUnitPluginSelection) {
        pluginLoadTask?.cancel()
        pluginLoadGeneration += 1
        let gen = pluginLoadGeneration
        audioUnitPluginStatus = .loading(selection.name)
        pluginLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let avUnit = try await pluginManager.instantiate(selection)
                await MainActor.run { [weak self] in
                    guard let self, self.pluginLoadGeneration == gen else {
                        // Load became stale (user changed selection or removed plugin while loading).
                        return
                    }
                    self.audioEngine.attach(avUnit)
                    self.activeAudioUnitPlugin = avUnit
                    self.audioUnitPluginStatus = .active(selection.name)
                    self.rewireGraphSafely()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.pluginLoadGeneration == gen else { return }
                    self.audioUnitPluginStatus = .failed(selection.name, reason: error.localizedDescription)
                    // Graph already on safe path (no plugin was attached).
                }
            }
        }
    }

    private func detachActivePlugin() {
        guard let plugin = activeAudioUnitPlugin else { return }
        // Disconnect before detach so the engine does not hold a reference to the node.
        audioEngine.disconnectNodeOutput(plugin)
        audioEngine.detach(plugin)
        activeAudioUnitPlugin = nil
    }

    // MARK: - Private: observers

    private func setupObservers() {
        timeObserverTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.updateTime() }

        settings.$builtInOutputDeviceUID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] uid in self?.applyOutputDevice(uid) }
            .store(in: &cancellables)

        settings.$eqBand0Gain.sink { [weak self] v in self?.eq.bands[0].gain = v }.store(in: &cancellables)
        settings.$eqBand1Gain.sink { [weak self] v in self?.eq.bands[1].gain = v }.store(in: &cancellables)
        settings.$eqBand2Gain.sink { [weak self] v in self?.eq.bands[2].gain = v }.store(in: &cancellables)
        settings.$eqBand3Gain.sink { [weak self] v in self?.eq.bands[3].gain = v }.store(in: &cancellables)
        settings.$eqBand4Gain.sink { [weak self] v in self?.eq.bands[4].gain = v }.store(in: &cancellables)

        settings.$builtInBalance
            .dropFirst()
            .sink { [weak self] v in self?.balance = v }
            .store(in: &cancellables)

        // receive(on: DispatchQueue.main) defers the sink to the next run-loop cycle so that
        // the @Published property (which fires in willSet) is fully committed before we read it.
        settings.$replayGainMode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reapplyReplayGainIfLoaded() }
            .store(in: &cancellables)
        settings.$replayGainPreampDb
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reapplyReplayGainIfLoaded() }
            .store(in: &cancellables)
        settings.$replayGainPreventClipping
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reapplyReplayGainIfLoaded() }
            .store(in: &cancellables)
        settings.$replayGainTargetLufs
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reapplyReplayGainIfLoaded() }
            .store(in: &cancellables)

        setlist.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                guard let self else { return }
                // Remove early-mark for entries removed from setlist or explicitly unmarked as played.
                let playedIDs = Set(entries.filter { $0.state == .played }.map(\.id))
                self.earlyMarkedEntryIDs.formIntersection(playedIDs)
                if let id = self.currentEntryID, !self.earlyMarkedEntryIDs.contains(id) {
                    self.isCurrentEntryMarkedAsPlayed = false
                }
                if let id = self.currentEntryID,
                   !entries.contains(where: { $0.id == id }) {
                    self.currentEntryID = nil
                    self.isActivePlaying = false
                    self.replayGainStatus = ""
                    self.playerNode.stop()
                    self.audioFile = nil
                    self.elapsed = 0
                    self.duration = 0
                    self.seekOffset = 0
                    self.reportCurrentState()
                    self.reportPlaylist()
                    self.onNextTrackUpdate?(nil)
                }
                if let id = self.currentEntryID, self.audioFile == nil,
                   let entry = entries.first(where: { $0.id == id }),
                   let d = entry.duration, d != self.duration {
                    self.duration = d
                }
                if let id = self.currentEntryID, self.audioFile == nil, !self.isActivePlaying,
                   entries.first(where: { $0.id == id })?.state == .played {
                    if let next = self.setlist.firstUnplayed(after: id) {
                        self.currentEntryID = next.id
                        self.elapsed = 0
                        self.duration = next.duration ?? 0
                        self.reportCurrentState()
                        self.reportPlaylist()
                        self.onNextTrackUpdate?(self.setlist.entry(after: next.id)?.track)
                    } else {
                        self.currentEntryID = nil
                        self.elapsed = 0
                        self.duration = 0
                        self.reportCurrentState()
                        self.reportPlaylist()
                        self.onNextTrackUpdate?(nil)
                    }
                }
                if self.currentEntryID == nil, self.audioFile == nil,
                   let firstQueued = entries.first(where: { $0.state == .queued }) {
                    self.currentEntryID = firstQueued.id
                    self.elapsed = 0
                    self.duration = firstQueued.duration ?? 0
                    self.reportCurrentState()
                    self.reportPlaylist()
                    self.onNextTrackUpdate?(self.setlist.entry(after: firstQueued.id)?.track)
                }
                // A reorder may have inserted a queued track before our queued-but-not-yet-loaded
                // current entry. Promote the new first-queued entry to be the current one.
                if let id = self.currentEntryID, self.audioFile == nil, !self.isActivePlaying,
                   entries.first(where: { $0.id == id })?.state == .queued,
                   let firstQueued = entries.first(where: { $0.state == .queued }),
                   firstQueued.id != id {
                    self.currentEntryID = firstQueued.id
                    self.elapsed = 0
                    self.duration = firstQueued.duration ?? 0
                    self.reportCurrentState()
                    self.reportPlaylist()
                    self.onNextTrackUpdate?(self.setlist.entry(after: firstQueued.id)?.track)
                }
                // Always report so AppState recalculates tanda position on any entries
                // change, including pure reorders that don't trigger any branch above.
                self.reportPlaylist()
            }
            .store(in: &cancellables)
    }

    private func teardownObservers() {
        timeObserverTimer = nil
        cancellables.removeAll()
    }

    // MARK: - Private: time update

    private func updateTime() {
        guard isActivePlaying,
              let file = audioFile,
              let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }

        guard !silencePending else { elapsed = 0; return }
        let sampleRate = file.fileFormat.sampleRate
        guard sampleRate > 0 else { return }
        let audioFrames = max(0, playerTime.sampleTime - audioStartSampleTime)
        let newElapsed = seekOffset + Double(audioFrames) / sampleRate
        elapsed = max(0, min(newElapsed, duration))
        duration = Double(file.length) / sampleRate

        if !settings.markAsPlayedAfterCompletion,
           let id = currentEntryID,
           !earlyMarkedEntryIDs.contains(id),
           duration > 0,
           elapsed >= Double(settings.markAsPlayedAfterSeconds) {
            earlyMarkedEntryIDs.insert(id)
            isCurrentEntryMarkedAsPlayed = true
            setlist.markPlayed(id: id)
            reportPlaylist()
        }
    }

    // MARK: - Private: state reporting

    private func reportCurrentState() {
        guard let id = currentEntryID,
              let entry = setlist.entries.first(where: { $0.id == id })
        else {
            isActivePlaying = false
            onTrackUpdate?(nil, .stopped)
            return
        }
        let state: PlayerState = isActivePlaying ? .playing : .paused
        onTrackUpdate?(entry.track, state)
    }

    private func reportPlaylist() {
        let entries = setlist.entries
        guard !entries.isEmpty else { onPlaylistUpdate(nil); return }
        let tracks = entries.map { $0.track }
        let idx = entries.firstIndex(where: { $0.id == currentEntryID }) ?? 0
        onPlaylistUpdate((tracks: tracks, currentIndex: idx))
    }
}
