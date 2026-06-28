import AVFoundation
import AppKit
import Combine
import CoreAudioKit
import Foundation
import OSLog
import TangoDisplayCore
import TangoDisplayObjC

// `@MainActor`: this class was already only ever constructed/used from the main
// thread in practice (flagged as a latent gap in Task 3's review). The Task 5
// migration to `DualDeckAudioEngine`/`PlaybackDeck` — both `@MainActor`-isolated
// — makes that assumption load-bearing everywhere, not just at the one
// `MainActor.assumeIsolated` seam Task 4 used for standby prep. Annotating here
// makes the existing real-world constraint explicit and checked by the
// compiler instead of asserted ad hoc.
@MainActor
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
    @Published private(set) var isActivePlaying: Bool = false {
        didSet {
            guard isActivePlaying != oldValue else { return }
            // ponytail: idle-sleep assertion only, not a full power-source watcher — battery's
            // shorter idle-sleep timeout was suspending playback mid-track on unplug.
            if isActivePlaying {
                sleepAssertionToken = ProcessInfo.processInfo.beginActivity(
                    options: .idleSystemSleepDisabled,
                    reason: "TangoDisplay setlist playback"
                )
            } else if let token = sleepAssertionToken {
                ProcessInfo.processInfo.endActivity(token)
                sleepAssertionToken = nil
            }
        }
    }
    private var sleepAssertionToken: NSObjectProtocol?

    var volume: Float {
        get { activeDeck.playerNode.volume }
        set { activeDeck.playerNode.volume = max(0, min(1, newValue)) }
    }

    private var _balance: Float = 0
    var balance: Float {
        get { _balance }
        set { _balance = max(-1, min(1, newValue)); applyBalance(_balance) }
    }

    // MARK: - Diagnostics

    @Published private(set) var replayGainStatus: String = ""
    @Published private(set) var hogModeConflict: Bool = false
    @Published private(set) var hogDeviceStolenAlert: Bool = false
    @Published private(set) var isChangingDevice: Bool = false

    // MARK: - Private — audio engine
    //
    // `DualDeckAudioEngine` is the sole live output owner (Task 5 migration).
    // The legacy single-deck `audioEngine`/`playerNode`/`eq`/`replayGainMixer`/
    // `balanceMixer` graph has been retired; transport, seek, output-device
    // switching, ReplayGain, and EQ all target `activeDeck` (deck A or B,
    // whichever `dualDeckState.activeDeck` currently is). `audioFile`/`audioFile`
    // tracking still lives here for now (seek math, duration) — it always
    // mirrors `activeDeck.audioFile`.

    /// Force-unwrapped: constructed in `init`, and every later use happens
    /// after `init` returns. A construction failure is a fatal startup error —
    /// there is no fallback output path once the legacy graph is retired.
    private var dualDeckAudioEngine: DualDeckAudioEngine!
    private var audioFile: AVAudioFile?
    private var seekOffset: Double = 0

    /// The currently audible deck. Manual transport (Task 6 will generalize
    /// this to dual-deck-aware promote-without-gap semantics) and automatic
    /// transitions both resolve through this single accessor so there is one
    /// place that defines "the deck the user is listening to right now."
    private var activeDeck: PlaybackDeck {
        dualDeckAudioEngine.deck(dualDeckState.activeDeck ?? .a)
    }

    private var standbyDeck: PlaybackDeck {
        dualDeckAudioEngine.deck((dualDeckState.activeDeck ?? .a).other)
    }

    // MARK: - Level meter

    var levelMeter: AudioLevelMeter { dualDeckAudioEngine.levelMeter }

    // MARK: - Private — state

    let setlist: SetlistManager
    private let settings: AppSettings
    private let configStore: PluginConfigurationStore

    // Snapshot of chain state captured just before the first per-track config is applied.
    // Restored when the next unassigned track (with no default config) plays.
    private var preConfigSnapshot: PreConfigSnapshot? = nil

    private struct PreConfigSnapshot {
        let chainEnabled: Bool
        let chainBypassed: Bool
        let slotStates: [PluginSlotState]
    }
    private var timeObserverTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var earlyMarkedEntryIDs: Set<UUID> = []
    private var scheduleGeneration: Int = 0
    private var hoggedDeviceUID: String? = nil
    private let audioDeviceQueue = DispatchQueue(label: "com.tangodisplay.audio-device", qos: .userInitiated)

    // MARK: - Private — Audio Unit plugin chain

    private let pluginManager = AudioUnitPluginManager()

    private final class SlotRuntime {
        var avUnit: AVAudioUnit?
        var status: AudioUnitPluginStatus = .noPluginSelected
        var presetManager: AudioUnitPresetManager?
        var availablePresets: [AudioUnitPreset] = []
        var activePresetID: UUID? = nil
        var pluginWindow: NSWindow?
        var pluginWindowVC: PluginWindowViewController?
        var paramObserverTree: AUParameterTree?
        var paramObserverToken: AUParameterObserverToken?
        var currentPresetObservation: NSKeyValueObservation?
        var loadGeneration: Int = 0
        var loadTask: Task<Void, Never>?
        var isApplyingPreset: Bool = false
    }

    private var slotRuntimes: [UUID: SlotRuntime] = [:]
    @Published private(set) var audioUnitPluginStatus: AudioUnitPluginStatus = .noPluginSelected
    @Published private(set) var slotStatuses: [UUID: AudioUnitPluginStatus] = [:]
    @Published private(set) var slotPresets: [UUID: [AudioUnitPreset]] = [:]
    @Published private(set) var slotActivePresetIDs: [UUID: UUID] = [:]

    // MARK: - Private — auto-gap

    private var currentPaddingFrames: AVAudioFrameCount = 0
    private var preparedAutoGap: PreparedAutoGap<UUID>?
    private var autoGapAnalysisTask: Task<Void, Never>?
    private var noGapPreparedForGeneration: Int?
    private var audioStartSampleTime: AVAudioFramePosition = 0
    private var silencePending: Bool = false

    /// Set once a transition has been committed (`DualDeckSchedule.commit`
    /// returned non-nil and `renderTransition`/`promote` ran) for the current
    /// `scheduleGeneration`, so `handleTrackEnd` and a second commit attempt
    /// both know the handoff already happened and must not double-fire.
    private var committedTransitionGeneration: Int?
    /// Set while waiting for a late standby deck B (degraded-waiting fallback).
    /// `handleTrackEnd` checks this so the "no automatic transition applies"
    /// branches don't also fire while a wait is already in flight.
    private var degradedWaitingForGeneration: Int?
    private var degradedWaitingTask: Task<Void, Never>?

    // MARK: - Private — dual-deck standby preparation
    //
    // Deck B preparation runs ahead of an exact transition: it opens the next
    // unplayed entry's file, analyses silence, calculates ReplayGain, and
    // instantiates deck-local plugins on `dualDeckAudioEngine`'s standby
    // (non-legacy) deck. None of this is wired into live playback yet — the
    // legacy single-deck path above remains the sole audible output owner.
    // `dualDeckState` exists purely to validate async work against
    // current/next/deck/generation so a stale callback can never corrupt state.

    private var dualDeckState = DualDeckState<UUID>()
    private var standbyPreparationToken: StandbyPreparationToken<UUID>?
    private var standbyDeckPreparationToken: DeckPreparationToken<UUID>?
    private var standbyPreparationTask: Task<Void, Never>?
    private(set) var settingsRevision: UInt64 = 0

    // MARK: - Private — loudness analysis

    private var inFlightAnalysisURLs = Set<URL>()
    private let loudnessCache = LoudnessAnalysisCache.shared

    // MARK: - Init

    init(setlist: SetlistManager, settings: AppSettings, configStore: PluginConfigurationStore, volume: Float = 1.0) {
        self.setlist = setlist
        self.settings = settings
        self.configStore = configStore
        super.init()
        do {
            dualDeckAudioEngine = try DualDeckAudioEngine()
        } catch {
            // Fatal: there is no fallback output path once the legacy single-deck
            // graph is retired. Surface loudly rather than silently play nothing.
            os_log(.fault, "TangoDisplay: dual-deck graph setup failed: %{public}@", error.localizedDescription)
            fatalError("TangoDisplay: dual-deck graph setup failed: \(error.localizedDescription)")
        }
        setupAudioEngine()
        // No deck is the user-audible "active" one until the first `loadEntry`-equivalent
        // call; `activeDeck` defaults to deck A via `dualDeckState.activeDeck ?? .a` until
        // then, so pre-playback setup (volume/output device/EQ/balance) below lands on deck A.
        activeDeck.playerNode.volume = max(0, min(1, volume))
        applyOutputDevice(settings.builtInOutputDeviceUID)
        applyEQGains(settings.eqGains)
        _balance = max(-1, min(1, settings.builtInBalance))
        applyBalance(_balance)
    }

    // MARK: - Audio engine setup

    private func setupAudioEngine() {
        for deck in [dualDeckAudioEngine.deckA, dualDeckAudioEngine.deckB] {
            for (i, band) in deck.eq.bands.enumerated() {
                let frequencies: [Float] = [60, 250, 1000, 4000, 12000]
                let filterTypes: [AVAudioUnitEQFilterType] = [.lowShelf, .parametric, .parametric, .parametric, .highShelf]
                band.filterType = filterTypes[i]
                band.frequency  = frequencies[i]
                band.bandwidth  = 1.0
                band.gain       = 0.0
                band.bypass     = false
            }
        }
        try? dualDeckAudioEngine.startIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: dualDeckAudioEngine.engine
        )
    }

    @objc private func handleEngineConfigChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cancelAutoGapPreparation()
            // Invalidate any pending dataPlayedBack callbacks so the system-forced engine stop
            // (e.g. headphone removal on System Default) doesn't spuriously fire handleTrackEnd → skipNext().
            self.scheduleGeneration += 1
            // Graph rewire must happen with engine stopped; engine is already stopped when this fires.
            if self.audioFile != nil {
                self.reconnectLegacyPluginChain(format: self.audioFile?.processingFormat)
            }

            // Capture all state before leaving the main thread.
            guard let audioUnit = self.dualDeckAudioEngine.engine.outputNode.audioUnit else { return }
            let uid = self.settings.builtInOutputDeviceUID
            let hogEnabled = self.settings.builtInHogMode
            let wasPlaying = self.isActivePlaying
            let savedElapsed = self.elapsed

            // Dispatch blocking CoreAudio work off the main thread to avoid a UI spinner.
            self.audioDeviceQueue.async { [weak self] in
                guard let self else { return }

                // Re-assert the user's chosen output device before restarting.
                self.setOutputDeviceProperty(audioUnit: audioUnit, uid: uid)

                // Detect hog-mode theft by another process.
                let deviceStolenByOther: Bool
                if !uid.isEmpty && !hogEnabled {
                    let owner = AudioDeviceManager.hogOwner(forUID: uid)
                    deviceStolenByOther = owner != -1 && owner != getpid()
                } else {
                    deviceStolenByOther = false
                }

                if deviceStolenByOther && wasPlaying {
                    DispatchQueue.main.async { self.activeDeck.playerNode.stop() }
                }

                do {
                    try self.dualDeckAudioEngine.startIfNeeded()
                } catch {
                    os_log(.error, "TangoDisplay: engine restart failed: %{public}@", error.localizedDescription)
                }

                DispatchQueue.main.async {
                    if deviceStolenByOther {
                        self.hogModeConflict = true
                        if wasPlaying {
                            self.isActivePlaying = false
                            self.reportCurrentState()
                            self.hogDeviceStolenAlert = true
                            // Pulse back to false so future interruptions can re-trigger the alert.
                            DispatchQueue.main.async { self.hogDeviceStolenAlert = false }
                        }
                    } else {
                        self.recoverActiveDeckAfterDeviceChange(wasPlaying: wasPlaying, savedElapsed: savedElapsed)
                    }
                }
            }
        }
    }

    private func applyOutputDevice(_ uid: String) {
        // Fast pre-check on the calling thread — if another process owns the hog, leave the
        // engine on its current device so play continues to work without hanging.
        if !uid.isEmpty {
            let owner = AudioDeviceManager.hogOwner(forUID: uid)
            if owner != -1 && owner != getpid() {
                hogModeConflict = true
                os_log(.error, "TangoDisplay: device %{public}@ is hogged by pid %d", uid, owner)
                return
            }
        }
        hogModeConflict = false

        // Capture values on the calling thread (main) before dispatching blocking work.
        guard let audioUnit = dualDeckAudioEngine.engine.outputNode.audioUnit else { return }
        let wasPlaying = isActivePlaying
        let savedElapsed = elapsed
        let hogEnabled = settings.builtInHogMode
        let engine = dualDeckAudioEngine.engine
        // Invalidate any pending dataPlayedBack callbacks before stopping the player node,
        // so the stop doesn't spuriously fire handleTrackEnd → skipNext().
        scheduleGeneration += 1

        isChangingDevice = true

        audioDeviceQueue.async { [weak self] in
            guard let self else { return }

            // Release hog on the previous device.
            if let prev = self.hoggedDeviceUID {
                AudioDeviceManager.releaseHogMode(forUID: prev)
                self.hoggedDeviceUID = nil
            }

            // CoreAudio stop/start can block — must be off the main thread.
            if engine.isRunning {
                DispatchQueue.main.sync { self.activeDeck.playerNode.stop() }
                engine.stop()
            }

            self.setOutputDeviceProperty(audioUnit: audioUnit, uid: uid)

            do {
                try engine.start()

                // Acquire hog mode on the audio queue (CoreAudio property set).
                if hogEnabled && !uid.isEmpty {
                    if AudioDeviceManager.acquireHogMode(forUID: uid) {
                        self.hoggedDeviceUID = uid
                        DispatchQueue.main.async { self.hogModeConflict = false }
                    } else {
                        DispatchQueue.main.async { self.hogModeConflict = true }
                        os_log(.error, "TangoDisplay: failed to acquire hog mode on %{public}@", uid)
                    }
                }

                // AVAudioEngine player ops, output-path rebuild, and tap reinstall
                // must be on main (all @MainActor-isolated).
                DispatchQueue.main.async {
                    self.recoverActiveDeckAfterDeviceChange(wasPlaying: wasPlaying, savedElapsed: savedElapsed)
                    self.isChangingDevice = false
                }
            } catch {
                os_log(.error, "TangoDisplay: applyOutputDevice engine restart failed: %{public}@",
                       error.localizedDescription)
                DispatchQueue.main.async { self.isChangingDevice = false }
            }
        }
    }

    private func applyHogMode(enabled: Bool, deviceUID: String) {
        // Must be called from audioDeviceQueue. All @Published writes dispatch back to main.
        if let prev = hoggedDeviceUID {
            AudioDeviceManager.releaseHogMode(forUID: prev)
            hoggedDeviceUID = nil
        }
        guard enabled, !deviceUID.isEmpty else {
            let conflict: Bool
            if !deviceUID.isEmpty {
                let owner = AudioDeviceManager.hogOwner(forUID: deviceUID)
                conflict = owner != -1 && owner != getpid()
            } else {
                conflict = false
            }
            DispatchQueue.main.async { self.hogModeConflict = conflict }
            return
        }
        if AudioDeviceManager.acquireHogMode(forUID: deviceUID) {
            hoggedDeviceUID = deviceUID
            DispatchQueue.main.async { self.hogModeConflict = false }
        } else {
            DispatchQueue.main.async { self.hogModeConflict = true }
            os_log(.error, "TangoDisplay: failed to acquire hog mode on device %{public}@", deviceUID)
        }
    }

    deinit {
        let uid = hoggedDeviceUID
        audioDeviceQueue.async {
            if let uid { AudioDeviceManager.releaseHogMode(forUID: uid) }
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

    /// Applies EQ to both decks — EQ is a per-engine output setting, not a
    /// per-track one, so both decks must always carry identical gains; a
    /// promotion must never reveal a flat EQ on the newly active deck.
    private func applyEQGains(_ gains: [Float]) {
        for deck in [dualDeckAudioEngine.deckA, dualDeckAudioEngine.deckB] {
            for (i, band) in deck.eq.bands.enumerated() where i < gains.count {
                band.gain = gains[i]
            }
        }
    }

    private func applyBalance(_ pan: Float) {
        dualDeckAudioEngine.balance = pan
    }

    private func setEQBandGain(_ index: Int, _ gain: Float) {
        for deck in [dualDeckAudioEngine.deckA, dualDeckAudioEngine.deckB] {
            deck.eq.bands[index].gain = gain
        }
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
        var finalGain = result.linearGain
        let cortinaCutDb = settings.cortinaVolumeReductionDb
        if cortinaCutDb < 0 {
            let detector = settings.makeDetector()
            if detector.isCortina(genre: entry.track.genre) {
                finalGain *= Float(pow(10.0, cortinaCutDb / 20.0))
            }
        }
        activeDeck.replayGainMixer.outputVolume = finalGain

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

    private nonisolated static func analysisStatusForError(_ error: Error) -> String {
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
        cancelAutoGapPreparation()
        cancelStandbyPreparation()
        for runtime in slotRuntimes.values {
            runtime.loadTask?.cancel()
            runtime.loadTask = nil
            runtime.pluginWindow?.close()
            runtime.pluginWindow = nil
            runtime.pluginWindowVC = nil
        }
        currentEntryID = nil
        isCurrentEntryMarkedAsPlayed = false
        isActivePlaying = false
        replayGainStatus = ""
        activeDeck.replayGainMixer.outputVolume = 1.0
        inFlightAnalysisURLs.removeAll()
        // Stop both deck nodes before invalidating identity — after `cancelAll`
        // the `activeDeck` accessor resets to deck A, so resolve "the audible
        // deck" while it is still authoritative.
        dualDeckAudioEngine.deckA.playerNode.stop()
        dualDeckAudioEngine.deckB.playerNode.stop()
        // Stop invalidates both decks' generations so no in-flight callback can
        // resurrect playback state after the stop.
        dualDeckState.cancelAll()
        dualDeckAudioEngine.engine.stop()
        levelMeter.reset()
        audioFile = nil
        elapsed = 0
        duration = 0
        currentPaddingFrames = 0
        silencePending = false
        audioStartSampleTime = 0
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
        // The topmost not-yet-played entry always wins. If a reorder dragged a queued track
        // above the currently loaded/paused entry, discard the stale load and start the top one
        // — the paused entry reverts to a normal queued track (its pause position is dropped).
        if let id = currentEntryID, audioFile != nil,
           let firstUnplayed = setlist.entries.first(where: { $0.state != .played }),
           firstUnplayed.id != id {
            setlist.markQueued(id: id)
            activeDeck.playerNode.stop()
            audioFile = nil
            seekOffset = 0
            elapsed = 0
            currentEntryID = firstUnplayed.id
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
            activeDeck.playerNode.play()
            isActivePlaying = true
        } else if let id = currentEntryID {
            setlist.markPlaying(id: id)
            seekTo(0) { [weak self] in
                self?.activeDeck.playerNode.play()
                self?.isActivePlaying = true
            }
        }
        reportCurrentState()
    }

    func pause() {
        cancelPendingAutoGapBuffer()
        scheduleGeneration += 1
        activeDeck.playerNode.stop()
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
        cancelAutoGapPreparation()
        cancelStandbyPreparation()
        if let id = currentEntryID, !earlyMarkedEntryIDs.contains(id), !currentEntryIsPlayed() {
            setlist.markQueued(id: id)
        }
        scheduleGeneration += 1
        currentEntryID = nil
        isCurrentEntryMarkedAsPlayed = false
        isActivePlaying = false
        replayGainStatus = ""
        // Stop both deck nodes while the active deck is still authoritative, then
        // invalidate both generations so no in-flight callback resurrects state.
        dualDeckAudioEngine.deckA.playerNode.stop()
        dualDeckAudioEngine.deckB.playerNode.stop()
        dualDeckState.cancelAll()
        audioFile = nil
        elapsed = 0
        duration = 0
        seekOffset = 0
        currentPaddingFrames = 0
        silencePending = false
        audioStartSampleTime = 0
        reportCurrentState()
        reportPlaylist()
        onNextTrackUpdate?(nil)
    }

    /// Manual Next (user-pressed). Dual-deck-aware: if the standby deck is already
    /// prepared for exactly the next unplayed entry, promote it immediately with
    /// NO injected smart-gap (the gapless fast path). Otherwise load the next entry
    /// fresh on the active deck — no assumption that B is reusable. A stop-after /
    /// performance-stop boundary or an empty queue stops instead.
    func skipNext() {
        guard let id = currentEntryID else { play(); return }
        let finishedEntry = setlist.entries.first(where: { $0.id == id })
        let stopForPerformance = (finishedEntry?.isPerformance == true) && settings.stopAfterEachPerformanceTrack
        let willStop = (id == setlist.stopAfterEntryID) || stopForPerformance
        let next = setlist.firstUnplayed(after: id)
        let standbyID = standbyDeck.id

        let decision = TransportPolicy.manualNext(
            nextID: next?.id, willStop: willStop,
            standbyPhase: dualDeckState[standbyID].phase,
            standbyEntryID: dualDeckState[standbyID].entryID
        )

        switch decision {
        case .promoteStandby:
            guard let next, isActivePlaying else {
                // Promotion needs the active deck running for a sample-accurate
                // anchor; if paused, fall through to a fresh load.
                fallthrough
            }
            // Gapless immediate promotion of the prepared standby. The commit path
            // marks the outgoing entry played and advances all UI/callback state.
            setlist.markPlayed(id: id)
            if id == setlist.stopAfterEntryID { setlist.stopAfterEntryID = nil }
            let committed = attemptCommitTransition(
                currentID: id, next: next, injectedSeconds: 0,
                generation: scheduleGeneration, cutImmediately: true
            )
            if !committed {
                // Standby raced out of readiness between the decision and the
                // commit (e.g. a reorder invalidated it) — load fresh instead.
                loadEntry(next, bypassAutoGap: true)
                activeDeck.playerNode.play()
                isActivePlaying = true
                reportCurrentState()
            }
        case .loadFresh:
            guard let next else { fallthrough }
            setlist.markPlayed(id: id)
            if id == setlist.stopAfterEntryID { setlist.stopAfterEntryID = nil }
            loadEntry(next, bypassAutoGap: true)
            activeDeck.playerNode.play()
            isActivePlaying = true
            reportCurrentState()
        case .stop:
            setlist.markPlayed(id: id)
            if id == setlist.stopAfterEntryID { setlist.stopAfterEntryID = nil }
            cancelStandbyPreparation()
            currentEntryID = nil
            isActivePlaying = false
            replayGainStatus = ""
            activeDeck.playerNode.stop()
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
        let finishedEntry = setlist.entries.first(where: { $0.id == id })
        let stopForPerformance = (finishedEntry?.isPerformance == true) && settings.stopAfterEachPerformanceTrack
        let shouldStop = (id == setlist.stopAfterEntryID) || stopForPerformance
        setlist.markPlayed(id: id)
        if id == setlist.stopAfterEntryID { setlist.stopAfterEntryID = nil }
        if !shouldStop, let next = setlist.firstUnplayed(after: id) {
            loadEntry(next, bypassAutoGap: true)
            activeDeck.playerNode.play()
            isActivePlaying = true
            reportCurrentState()
        } else {
            currentEntryID = nil
            isActivePlaying = false
            replayGainStatus = ""
            activeDeck.playerNode.stop()
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
            // Direct jump to an arbitrary entry: the standby prepared for whatever
            // followed the *old* current entry is no longer relevant.
            clearStandbyForJump()
            let wasPlaying = isActivePlaying
            loadEntry(prev)
            if wasPlaying { activeDeck.playerNode.play(); isActivePlaying = true; reportCurrentState() }
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: Double) {
        // A seek moves the active deck's decoded position, invalidating any
        // committed/uncommitted smart-gap timeline (which was anchored to the old
        // frame positions). The standby deck's prepared file is untouched —
        // seeking only affects the active deck.
        if TransportPolicy.seekInvalidatesTimeline() {
            committedTransitionGeneration = nil
            cancelDegradedWaiting()
            _ = dualDeckState.invalidateTimelinesPreservingActive()
        }
        seekTo(seconds)
    }

    // MARK: - Jump to a specific entry (double-click in SetlistView)

    func jumpTo(_ entry: SetlistEntry) {
        // Direct play of an arbitrary entry clears the prepared standby.
        clearStandbyForJump()
        loadEntry(entry)
        activeDeck.playerNode.play()
        isActivePlaying = true
        reportCurrentState()
    }

    /// Cancels the prepared standby deck when the user jumps to an arbitrary
    /// destination (Previous / direct play). `loadEntry` re-establishes the
    /// correct standby for the new current entry via `prepareAutoGap`.
    private func clearStandbyForJump() {
        guard TransportPolicy.jumpClearsStandby() else { return }
        cancelStandbyPreparation()
    }

    func retryOutputDevice() {
        applyOutputDevice(settings.builtInOutputDeviceUID)
    }

    /// Device recovery (output-device change / disconnect / engine config change).
    /// Snapshots the active deck's identity and elapsed time, invalidates any
    /// committed/uncommitted dual-deck timeline (its frame anchors are meaningless
    /// once the output path is torn down and rebuilt), rebuilds the shared output
    /// path via `DualDeckAudioEngine.rebuildOutputPath()` (Task 3's reserved
    /// routine), then restores the active deck to its prior position and play
    /// state. The standby deck is reset and re-prepared from the restored active
    /// entry afterwards, since its prior preparation was anchored to the old graph.
    private func recoverActiveDeckAfterDeviceChange(wasPlaying: Bool, savedElapsed: Double) {
        // Snapshot the authoritative active entry before any invalidation.
        let activeEntryID = currentEntryID
        // Invalidate timelines while the active deck is still authoritative.
        cancelStandbyPreparation()
        committedTransitionGeneration = nil
        cancelDegradedWaiting()
        _ = dualDeckState.invalidateTimelinesPreservingActive()

        // Rebuild the shared output path (stops/restarts the engine internally).
        do {
            try dualDeckAudioEngine.rebuildOutputPath()
        } catch {
            os_log(.error, "TangoDisplay: rebuildOutputPath failed: %{public}@", error.localizedDescription)
            // Fall back to a plain restart so audio isn't left dead.
            try? dualDeckAudioEngine.startIfNeeded()
        }

        // Restore authoritative active-deck state.
        levelMeter.reinstallTap()
        applyBalance(_balance)
        if audioFile != nil {
            seekTo(savedElapsed)
            if wasPlaying { activeDeck.playerNode.play() }
        }
        // Re-prepare the standby for the restored active entry.
        if activeEntryID != nil { prepareStandbyIfNeeded() }
    }

    // MARK: - Private: seek implementation

    private func seekTo(_ seconds: Double, completion: (() -> Void)? = nil) {
        cancelPendingAutoGapBuffer()
        guard let file = audioFile else { completion?(); return }
        let sampleRate = file.fileFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, seconds) * sampleRate)
        let totalFrames = file.length
        guard startFrame < totalFrames else { completion?(); return }
        let frameCount = AVAudioFrameCount(totalFrames - startFrame)
        let wasPlaying = activeDeck.playerNode.isPlaying
        activeDeck.playerNode.stop()
        seekOffset = seconds
        elapsed = seconds
        currentPaddingFrames = 0
        silencePending = false
        audioStartSampleTime = 0
        scheduleGeneration += 1
        let gen = scheduleGeneration
        activeDeck.playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount,
                                   at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.handleTrackEnd(generation: gen) }
        }
        if wasPlaying { activeDeck.playerNode.play() }
        completion?()
    }

    // MARK: - Private: entry loading

    private func loadEntry(_ entry: SetlistEntry, bypassAutoGap: Bool = false) {
        cancelAutoGapPreparation()
        earlyMarkedEntryIDs.remove(entry.id)
        isCurrentEntryMarkedAsPlayed = false
        activeDeck.playerNode.stop()
        scheduleGeneration += 1
        let gen = scheduleGeneration
        committedTransitionGeneration = nil
        cancelDegradedWaiting()
        noGapPreparedForGeneration = bypassAutoGap ? gen : nil
        do {
            let file = try AVAudioFile(forReading: entry.fileURL)
            audioFile = file
            seekOffset = 0
            elapsed = 0
            duration = Double(file.length) / file.fileFormat.sampleRate
            // scheduleFile requires the file format to exactly match the output bus format.
            // `PlaybackDeck.prepare()` (Tasks 2/4) already reconnects a deck's internal chain
            // edges without stopping the shared engine — only the legacy/output-device-rebuild
            // paths stop it. Follow the same pattern here: reconnect only `activeDeck`'s
            // internal chain (its own nodes plus the legacy plugin-editor splice), never the
            // shared `commonMixer`/`balanceMixer` output path, and never stop the engine.
            //
            // Manual loads (play/jumpTo/skipPrevious/skipNext's no-next-entry fallback) still
            // run this synchronous open-and-schedule path against `activeDeck` rather than the
            // async `PlaybackDeck.prepare()`/standby machinery — Task 6 will generalize manual
            // transport to dual-deck-aware promote-without-gap semantics. For now this is the
            // minimal correct behavior: it only ever touches the currently active deck, same as
            // the legacy single-deck path did.
            try activeDeck.connectForManualLoad(format: file.processingFormat)
            reconnectLegacyPluginChain(format: file.processingFormat)
            try dualDeckAudioEngine.startIfNeeded()
            levelMeter.reinstallTap()
            applyReplayGain(for: entry)

            // Pre-warm loudness analysis for the next track so it's cached before it starts.
            if let nextEntry = setlist.entry(after: entry.id) {
                preAnalyseIfNeeded(nextEntry)
            }

            currentPaddingFrames = 0
            silencePending = false
            audioStartSampleTime = 0
            let isFirstTrack = setlist.entries.first?.id == entry.id
                && !setlist.entries.contains(where: { $0.state == .played })
            var autoGapSkipped = false
            var initialAutoGapApplied = false
            if !bypassAutoGap && !entry.ignoresAutoGap && settings.autoGapEnabled {
                if settings.autoGapIgnoreFirstTrack && isFirstTrack {
                    autoGapSkipped = true
                } else if isFirstTrack {
                    // Preserve the existing first-track lead-in without delaying playback on
                    // asynchronous file analysis. Pair transitions below use measured silence.
                    let frameValue = (settings.autoGapDuration * file.processingFormat.sampleRate).rounded()
                    if frameValue.isFinite, frameValue > 0, frameValue <= Double(UInt32.max) {
                        let frames = AVAudioFrameCount(frameValue)
                        if let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) {
                            buffer.frameLength = frames
                            currentPaddingFrames = frames
                            silencePending = true
                            initialAutoGapApplied = true
                            activeDeck.playerNode.scheduleBuffer(buffer, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                                DispatchQueue.main.async {
                                    guard let self, self.scheduleGeneration == gen else { return }
                                    self.currentPaddingFrames = 0
                                    self.silencePending = false
                                    self.setlist.setAutoGapApplied(id: entry.id, applied: false)
                                }
                            }
                        }
                    }
                }
            }
            setlist.setAutoGapApplied(id: entry.id, applied: initialAutoGapApplied)
            setlist.setAutoGapSkipped(id: entry.id, skipped: autoGapSkipped)

            activeDeck.playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async { self?.handleTrackEnd(generation: gen) }
            }

            // Make the loaded deck the `DualDeckState` active deck. Without this,
            // `commitTransition`/`promote` (which guard on `activeDeck`) can never
            // fire — so neither the manual-Next gapless promotion below nor the
            // automatic exact-gap transition could ever engage. `activate` resets
            // the *other* (standby) deck's state; that's fine here because
            // `cancelAutoGapPreparation()` at the top already cancelled any
            // in-flight standby, and `prepareAutoGap` below re-establishes it.
            let loadedDeckID = dualDeckState.activeDeck ?? .a
            dualDeckState.activate(
                deck: loadedDeckID, entryID: entry.id,
                generation: dualDeckState[loadedDeckID].generation &+ 1
            )

        } catch {
            os_log(.error, "TangoDisplay: failed to load %{public}@: %{public}@",
                   entry.fileURL.path, error.localizedDescription)
            audioFile = nil
        }
        currentEntryID = entry.id
        prepareAutoGap(current: entry)
        setlist.markPlaying(id: entry.id)
        applyPerTrackPluginConfiguration(for: entry)
        reportCurrentState()
        reportPlaylist()
        onNextTrackUpdate?(setlist.entry(after: entry.id)?.track)
    }

    /// Fires when `activeDeck`'s scheduled file finishes playing back. Under the
    /// dual-deck design this should normally never be reached for an automatic
    /// transition — `commitAndRenderTransition` anchors B's start before A's
    /// audible end, so the handoff already happened. This remains as the
    /// degraded-waiting fallback's last resort and the "no automatic transition
    /// applies" path (manual stop-after / ignored / disabled gap).
    private func handleTrackEnd(generation: Int) {
        guard generation == scheduleGeneration,
              let currentID = currentEntryID,
              let current = setlist.entries.first(where: { $0.id == currentID }) else { return }
        if degradedWaitingForGeneration == generation { return }
        let stopForPerformance = current.isPerformance && settings.stopAfterEachPerformanceTrack
        guard currentID != setlist.stopAfterEntryID, !stopForPerformance,
              let next = setlist.firstUnplayed(after: currentID) else {
            skipNextImmediate()
            return
        }
        if noGapPreparedForGeneration == generation {
            skipNextImmediate()
            return
        }
        guard SmartAutoGapTransitionPolicy.shouldSchedule(
            enabled: settings.autoGapEnabled, ignored: next.ignoresAutoGap,
            automatic: true, willStop: false
        ) else {
            skipNextImmediate()
            return
        }
        // A's audible end arrived before B became ready and before a transition was
        // committed (standby preparation was slower than the track, or this is the
        // very first track after launch). Enter the degraded-waiting fallback: wait
        // for B, then render the gap with diagnostics marked non-exact instead of
        // silently losing the gap or stalling forever.
        enterDegradedWaiting(currentID: currentID, next: next, generation: generation)
    }

    private func prepareAutoGap(current: SetlistEntry) {
        autoGapAnalysisTask?.cancel()
        preparedAutoGap = nil
        prepareStandbyIfNeeded()
        guard let next = setlist.firstUnplayed(after: current.id) else { return }
        let currentID = current.id
        let nextID = next.id
        autoGapAnalysisTask = Task { [weak self] in
            let currentSilence = await AudioSilenceAnalyzer.shared.analyze(url: current.fileURL)
            guard !Task.isCancelled else { return }
            let nextSilence = await AudioSilenceAnalyzer.shared.analyze(url: next.fileURL)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.currentEntryID == currentID,
                      self.setlist.firstUnplayed(after: currentID)?.id == nextID else { return }
                self.preparedAutoGap = PreparedAutoGap(
                    currentID: currentID, nextID: nextID,
                    trailing: currentSilence.trailing, leading: nextSilence.leading
                )
                self.queuePreparedAutoGapIfEligible(currentID: currentID, nextID: nextID)
            }
        }
    }

    // MARK: - Private — dual-deck standby preparation

    /// Prepares the standby deck (deck B while deck A plays the legacy single-deck
    /// path) ahead of an exact transition to the real next unplayed entry. Cancels
    /// any in-flight preparation, observes reorder/removal/plugin changes, and
    /// validates current/next/deck/generation after every async boundary so a
    /// stale callback can never corrupt `dualDeckState`. Does not touch the
    /// audible legacy graph.
    private func prepareStandbyIfNeeded() {
        guard let dualDeckAudioEngine else { return }
        guard let currentID = currentEntryID,
              let current = setlist.entries.first(where: { $0.id == currentID }) else {
            cancelStandbyPreparation()
            return
        }
        guard let next = setlist.firstUnplayed(after: currentID) else {
            cancelStandbyPreparation()
            return
        }
        let willStop = currentID == setlist.stopAfterEntryID
            || (current.isPerformance && settings.stopAfterEachPerformanceTrack)
        guard StandbyPreparationPolicy.shouldPrepare(willStop: willStop) else {
            cancelStandbyPreparation()
            return
        }

        let standbyDeckID = dualDeckState.activeDeck?.other ?? .b
        let nextConfigID = next.pluginConfigurationID ?? configStore.defaultConfigurationID

        // Reuse the already-ready standby deck when its identity and plugin
        // configuration still match the freshly observed next entry.
        if let token = standbyPreparationToken,
           token.matchesIdentity(deck: standbyDeckID, currentID: currentID, nextID: next.id, generation: token.generation),
           StandbyReusePolicy.canReuse(
               preparedNextID: token.nextID,
               preparedPluginConfigurationID: token.pluginConfigurationID,
               observedNextID: next.id,
               observedPluginConfigurationID: nextConfigID
           ) {
            return
        }

        cancelStandbyPreparation()

        guard let preparationToken = dualDeckState.beginPreparation(deck: standbyDeckID, entryID: next.id) else {
            return
        }
        standbyDeckPreparationToken = preparationToken
        let token = StandbyPreparationToken<UUID>(
            deck: standbyDeckID,
            currentID: currentID,
            nextID: next.id,
            generation: preparationToken.generation,
            settingsRevision: settingsRevision,
            pluginConfigurationID: nextConfigID
        )
        standbyPreparationToken = token
        let configuration = nextConfigID.flatMap { configStore.configuration(id: $0) }
        let deck = dualDeckAudioEngine.deck(standbyDeckID)

        standbyPreparationTask = Task { [weak self] in
            guard let self else { return }
            let stillValid: () -> Bool = { [weak self] in
                guard let self else { return false }
                return self.dualDeckState.matches(
                    deck: token.deck, entryID: token.nextID, generation: token.generation, phase: .preparing
                ) && self.currentEntryID == token.currentID
                    && self.setlist.firstUnplayed(after: token.currentID)?.id == token.nextID
            }
            let replayGain = await self.calculateStandbyReplayGain(for: next)
            guard !Task.isCancelled, stillValid() else { return }
            let nextSilence = await AudioSilenceAnalyzer.shared.analyze(url: next.fileURL)
            guard !Task.isCancelled, stillValid() else { return }
            if let current = self.standbyPreparationToken,
               current.matchesIdentity(deck: token.deck, currentID: token.currentID, nextID: token.nextID, generation: token.generation) {
                self.standbyPreparationToken?.leadingSilence = nextSilence.leading
            }
            do {
                try await deck.prepare(entry: next, configuration: configuration, replayGain: replayGain)
            } catch {
                guard stillValid() else { return }
                os_log(.error, "TangoDisplay: standby deck preparation failed: %{public}@", error.localizedDescription)
                _ = self.dualDeckState.markFailed(preparationToken)
                if self.standbyDeckPreparationToken == preparationToken {
                    self.standbyDeckPreparationToken = nil
                    self.standbyPreparationToken = nil
                }
                return
            }
            guard stillValid() else { return }
            _ = self.dualDeckState.markReady(preparationToken)
            // Silence analysis (in `prepareAutoGap`) and standby readiness (here)
            // resolve independently and in no particular order. If analysis
            // already finished while this deck was still preparing, this is the
            // only place that retries the commit — without it, a transition
            // would wait for `handleTrackEnd`'s degraded-waiting fallback even
            // though B was actually ready in time.
            self.queuePreparedAutoGapIfEligible(currentID: token.currentID, nextID: token.nextID)
        }
    }

    /// Cancels any in-flight standby preparation and resets deck B's policy state.
    /// Does not reopen or recycle the deck's file unless preparation had advanced
    /// past `.empty` — recycling is left to the transition/promotion path.
    private func cancelStandbyPreparation() {
        standbyPreparationTask?.cancel()
        standbyPreparationTask = nil
        if let token = standbyDeckPreparationToken {
            dualDeckState.cancel(deck: token.deck)
        }
        standbyDeckPreparationToken = nil
        standbyPreparationToken = nil
    }

    /// Recomputes the uncommitted timeline for a gap-only settings change
    /// (auto-gap duration/enabled/first-track or stop-after-performance) without
    /// reopening deck B's file. Bumps `settingsRevision` so `DualDeckState.promote`
    /// can detect and discard a stale committed transition, then re-evaluates
    /// standby eligibility purely from policy — the already-opened file, analysed
    /// silence, and instantiated plugins are untouched.
    private func handleGapSettingsRevisionChange() {
        settingsRevision &+= 1
        if let token = standbyPreparationToken {
            standbyPreparationToken = StandbyPreparationToken(
                deck: token.deck, currentID: token.currentID, nextID: token.nextID,
                generation: token.generation, settingsRevision: settingsRevision,
                pluginConfigurationID: token.pluginConfigurationID,
                leadingSilence: token.leadingSilence
            )
        }
        prepareStandbyIfNeeded()
    }

    private func calculateStandbyReplayGain(for entry: SetlistEntry) async -> Float {
        let rgSettings = ReplayGainSettings(
            mode: settings.replayGainMode,
            preampDb: Double(settings.replayGainPreampDb),
            preventClipping: settings.replayGainPreventClipping,
            targetLoudnessLufs: Double(settings.replayGainTargetLufs)
        )
        let info = entry.track.replayGainInfo
        let cacheKey = loudnessCacheKey(for: entry)
        let analysis = cacheKey.flatMap { loudnessCache.result(for: $0) }
        let result = calculateReplayGain(info: info, analysis: analysis, settings: rgSettings)
        var finalGain = result.linearGain
        let cortinaCutDb = settings.cortinaVolumeReductionDb
        if cortinaCutDb < 0, settings.makeDetector().isCortina(genre: entry.track.genre) {
            finalGain *= Float(pow(10.0, cortinaCutDb / 20.0))
        }
        return finalGain
    }

    /// Once silence analysis resolves (or standby readiness changes), attempt the
    /// sample-accurate commit. This is the primary automatic-transition path —
    /// it runs well before A's audible end, anchoring B's start to A's decoded
    /// end frame on the common-output clock. Replaces the legacy
    /// `scheduleAutoGap` silence-buffer-then-`skipNextImmediate()` mechanism.
    private func queuePreparedAutoGapIfEligible(currentID: UUID, nextID: UUID) {
        let generation = scheduleGeneration
        guard committedTransitionGeneration != generation,
              noGapPreparedForGeneration != generation,
              self.currentEntryID == currentID,
              let current = setlist.entries.first(where: { $0.id == currentID }),
              let next = setlist.firstUnplayed(after: currentID), next.id == nextID else { return }
        let willStop = currentID == setlist.stopAfterEntryID
            || (current.isPerformance && settings.stopAfterEachPerformanceTrack)
        guard SmartAutoGapTransitionPolicy.shouldSchedule(
            enabled: settings.autoGapEnabled, ignored: next.ignoresAutoGap,
            automatic: true, willStop: willStop
        ) else {
            noGapPreparedForGeneration = generation
            return
        }
        let padding = preparedAutoGap?.injectedDuration(
            currentID: currentID, nextID: nextID, target: settings.autoGapDuration
        ) ?? settings.autoGapDuration
        attemptCommitTransition(currentID: currentID, next: next, injectedSeconds: padding, generation: generation)
    }

    /// Computes the frame-domain `DualDeckSchedule`, anchors A's cut and B's
    /// start to it via `renderTransition`, and atomically promotes UI/setlist
    /// state. No-op (returns without side effects) when the standby deck isn't
    /// `.ready` yet, the identity is stale, or the gap-only settings revision
    /// advanced past what standby preparation captured — those cases fall
    /// through to `handleTrackEnd`'s degraded-waiting path when A's audible end
    /// actually arrives.
    ///
    /// Everything expensive (file open, ReplayGain, plugin instantiation) has
    /// already happened in `prepareStandbyIfNeeded` (Task 4). The one
    /// documented exception is the legacy plugin-editor chain's connection
    /// point, which `reconnectLegacyPluginChainAfterPromotion()` moves at the
    /// promotion instant — see that method's doc comment.
    @discardableResult
    private func attemptCommitTransition(
        currentID: UUID, next: SetlistEntry, injectedSeconds: Double, generation: Int,
        cutImmediately: Bool = false
    ) -> Bool {
        let outgoing = dualDeckState.activeDeck ?? .a
        guard committedTransitionGeneration != generation,
              let file = audioFile,
              let nodeTime = activeDeck.playerNode.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = activeDeck.playerNode.playerTime(forNodeTime: nodeTime)
        else { return false }
        let incoming = outgoing.other
        let incomingPhase = dualDeckState[incoming].phase
        let sampleRate = dualDeckAudioEngine.commonSampleRate
        guard sampleRate.isFinite, sampleRate > 0 else { return false }

        let transition = dualDeckState.commitTransition(
            currentID: currentID, nextID: next.id, settingsRevision: settingsRevision
        )
        // Manual Next (`cutImmediately`) anchors the cut at the active deck's
        // *current* decoded frame — the outgoing track is abandoned now — instead
        // of its natural end. With `injectedSeconds == 0` the incoming deck then
        // starts on that same frame: a gapless, immediate promotion of the
        // already-prepared standby. Automatic transitions cut at the decoded end.
        let decodedEndFrame: AVAudioFramePosition
        if cutImmediately {
            decodedEndFrame = playerTime.sampleTime
        } else {
            let remainingFrames = max(0, file.length - playerTime.sampleTime)
            decodedEndFrame = playerTime.sampleTime + remainingFrames
        }

        guard let schedule = DualDeckSchedule.commit(
            transition: transition,
            currentID: currentID, nextID: next.id,
            incomingPhase: incomingPhase,
            liveSettingsRevision: settingsRevision,
            injectedSeconds: injectedSeconds,
            decodedEndFrame: decodedEndFrame,
            sampleRate: sampleRate
        ) else {
            // Reject and discard the uncommitted transition snapshot (if any was
            // created above); standby remains `.ready`/`.preparing` and is left
            // for the next attempt (a later silence-analysis resolution, or
            // `handleTrackEnd`'s degraded-waiting fallback if A's audible end
            // arrives first). `promote` with a deliberately-stale settingsRevision
            // is `DualDeckState`'s documented way to discard a committed
            // transition without disturbing deck phases.
            if let transition { _ = dualDeckState.promote(transition, settingsRevision: transition.settingsRevision &+ 1) }
            return false
        }

        // Bumped before `renderTransition` so the completion handler captures the
        // generation that will own the promoted deck's `dataPlayedBack` callback —
        // `completePromotion` below reuses this same value rather than bumping
        // again, so there is exactly one generation for "the incoming deck is now
        // current."
        scheduleGeneration += 1
        let newGeneration = scheduleGeneration
        do {
            try dualDeckAudioEngine.renderTransition(
                outgoing: outgoing, incoming: incoming,
                schedule: schedule, outgoingNow: nodeTime, outgoingNowFrame: playerTime.sampleTime,
                onIncomingPlaybackCompleted: { [weak self] _ in
                    DispatchQueue.main.async { self?.handleTrackEnd(generation: newGeneration) }
                }
            )
        } catch {
            os_log(.error, "TangoDisplay: renderTransition failed: %{public}@", error.localizedDescription)
            return false
        }

        guard let token = transition, dualDeckState.promote(token, settingsRevision: settingsRevision) != nil else {
            return false
        }
        committedTransitionGeneration = generation
        completePromotion(to: next, schedule: schedule, generation: newGeneration)
        return true
    }

    /// Atomically promotes UI/setlist state right after `renderTransition`
    /// armed the incoming deck and cut the outgoing one. Discards the outgoing
    /// deck's plugin tail (already done by `hardCut` inside `renderTransition`),
    /// resets it, and starts preparing it as the new standby — mirroring what
    /// `loadEntry` used to do, but with no file open/reconnect/RG/plugin work
    /// happening here: that was all done ahead of time by Task 4's standby prep.
    private func completePromotion(to next: SetlistEntry, schedule: DualDeckSchedule, generation: Int) {
        let outgoingDeck = standbyDeck // After promote(), the old active deck is now standby-side.
        let outgoingID = currentEntryID
        noGapPreparedForGeneration = nil
        cancelDegradedWaiting()
        setlist.setAutoGapApplied(id: next.id, applied: schedule.injectedFrames > 0)

        if let outgoingID, !earlyMarkedEntryIDs.contains(outgoingID), !currentEntryIsPlayed() {
            setlist.markPlayed(id: outgoingID)
        }
        earlyMarkedEntryIDs.remove(next.id)
        isCurrentEntryMarkedAsPlayed = false
        currentEntryID = next.id
        audioFile = activeDeck.audioFile
        seekOffset = 0
        elapsed = 0
        duration = activeDeck.audioFile.map { Double($0.length) / $0.fileFormat.sampleRate } ?? (next.duration ?? 0)
        currentPaddingFrames = 0
        silencePending = false
        audioStartSampleTime = 0
        preparedAutoGap = nil
        autoGapAnalysisTask?.cancel()
        standbyPreparationToken = nil
        standbyDeckPreparationToken = nil

        // `renderTransition` already armed and started the incoming deck's
        // player node (`scheduleStart`/`play(at:)`, with the `dataPlayedBack`
        // completion routed to `handleTrackEnd(generation:)` for this same
        // `generation`) — nothing further to schedule here.

        reconnectLegacyPluginChainAfterPromotion()
        setlist.markPlaying(id: next.id)
        applyPerTrackPluginConfiguration(for: next)
        // Cosmetic only: the incoming deck's `replayGainMixer.outputVolume` was
        // already set correctly during Task 4 standby prep (`calculateStandbyReplayGain`).
        // This re-applies the identical value and refreshes `replayGainStatus`'s
        // UI string (which prep doesn't update) — not a post-commitment gain
        // recalculation, just a label refresh plus a no-op volume write.
        applyReplayGain(for: next)
        // Pre-warm loudness analysis for the entry two tracks ahead, mirroring
        // `loadEntry`'s pre-warm so auto-mode ReplayGain is cached before that
        // entry becomes current instead of showing "Analysing…".
        if let twoAhead = setlist.entry(after: next.id) {
            preAnalyseIfNeeded(twoAhead)
        }
        applyOutgoingDeckTailReset(outgoingDeck)
        reportCurrentState()
        reportPlaylist()
        onNextTrackUpdate?(setlist.entry(after: next.id)?.track)
        prepareAutoGap(current: next)
    }

    /// Resets the just-demoted deck (discarding its plugin tail — already cut
    /// by `renderTransition`'s `hardCut`) so it's a clean, reusable standby
    /// candidate. `prepareStandbyIfNeeded` (called from `prepareAutoGap` above)
    /// will prepare it with the entry after `next`.
    private func applyOutgoingDeckTailReset(_ deck: PlaybackDeck) {
        do {
            try deck.resetForReuse()
        } catch {
            os_log(.error, "TangoDisplay: outgoing deck reset failed: %{public}@", error.localizedDescription)
        }
    }

    /// Late-B fallback: A's audible end arrived before a transition committed.
    /// Enters an explicit waiting state (no audio plays — this is the
    /// "deliberate gap" the user would have heard anyway, just rendered after
    /// the fact instead of pre-anchored) and renders the transition the moment
    /// B becomes ready.
    ///
    /// Diagnostics note: `SetlistEntry`/`SetlistManager` currently has no
    /// "exact vs. degraded gap" field — only `autoGapApplied`/`autoGapSkipped`.
    /// This path is, by definition, the non-exact case (the legacy
    /// silence-buffer fallback's equivalent), but there is nowhere to record
    /// that distinctly today. Flagged here for a future diagnostics field
    /// rather than added speculatively.
    private func enterDegradedWaiting(currentID: UUID, next: SetlistEntry, generation: Int) {
        guard degradedWaitingForGeneration != generation else { return }
        degradedWaitingTask?.cancel()
        degradedWaitingForGeneration = generation
        setlist.setAutoGapApplied(id: next.id, applied: true)
        let nextID = next.id
        degradedWaitingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard self.degradedWaitingForGeneration == generation,
                      self.currentEntryID == currentID,
                      self.setlist.firstUnplayed(after: currentID)?.id == nextID else { return }
                if self.dualDeckState[self.standbyDeck.id].phase == .ready
                    || self.dualDeckState[self.standbyDeck.id].phase == .scheduled {
                    let padding = self.preparedAutoGap?.injectedDuration(
                        currentID: currentID, nextID: nextID, target: self.settings.autoGapDuration
                    ) ?? self.settings.autoGapDuration
                    let committed = self.attemptCommitTransition(
                        currentID: currentID, next: next, injectedSeconds: padding, generation: generation
                    )
                    if committed {
                        self.degradedWaitingForGeneration = nil
                    } else {
                        // Standby flipped to ready but commit still failed (e.g. a
                        // settings-revision race) — fall back to the immediate
                        // advance rather than waiting forever.
                        self.degradedWaitingForGeneration = nil
                        self.skipNextImmediate()
                    }
                    return
                }
                if self.dualDeckState[self.standbyDeck.id].phase == .failed {
                    self.degradedWaitingForGeneration = nil
                    self.skipNextImmediate()
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    private func cancelDegradedWaiting() {
        degradedWaitingTask?.cancel()
        degradedWaitingTask = nil
        degradedWaitingForGeneration = nil
    }

    private func cancelPendingAutoGapBuffer() {
        if silencePending {
            if let currentEntryID {
                setlist.setAutoGapApplied(id: currentEntryID, applied: false)
            }
        }
        // A degraded wait or an already-committed-but-not-yet-promoted gap may
        // have marked the *next* entry's gap as applied; clear it the same way
        // the legacy silence-buffer cancellation did.
        if degradedWaitingForGeneration != nil, let nextID = preparedAutoGap?.nextID {
            setlist.setAutoGapApplied(id: nextID, applied: false)
        }
        currentPaddingFrames = 0
        silencePending = false
        noGapPreparedForGeneration = nil
        committedTransitionGeneration = nil
        cancelDegradedWaiting()
    }

    private func cancelAutoGapPreparation() {
        autoGapAnalysisTask?.cancel()
        autoGapAnalysisTask = nil
        cancelPendingAutoGapBuffer()
        preparedAutoGap = nil
    }

    private func currentEntryIsPlayed() -> Bool {
        guard let id = currentEntryID else { return false }
        return setlist.entries.first(where: { $0.id == id })?.state == .played
    }

    // MARK: - Private: audio graph

    private func liveChainUnits() -> [(slot: AudioUnitChainSlot, unit: AVAudioUnit)] {
        guard settings.audioUnitPluginEnabled, !settings.audioUnitPluginBypassed else { return [] }
        return settings.audioUnitPluginChain.compactMap { slot in
            guard slot.isEnabled,
                  let runtime = slotRuntimes[slot.id],
                  let unit = runtime.avUnit else { return nil }
            return (slot, unit)
        }
    }

    // MARK: - Plugin chain configuration capture / apply

    func captureChainConfiguration() -> [PluginSlotState] {
        settings.audioUnitPluginChain.compactMap { slot in
            guard let runtime = slotRuntimes[slot.id],
                  let unit = runtime.avUnit,
                  let fullState = unit.auAudioUnit.fullState,
                  let encoded = try? AUStateCodec.encode(fullState)
            else { return nil }
            return PluginSlotState(
                slotID: slot.id,
                componentType: slot.selection.componentType,
                componentSubType: slot.selection.componentSubType,
                componentManufacturer: slot.selection.componentManufacturer,
                auState: encoded,
                isEnabled: slot.isEnabled
            )
        }
    }

    func applyChainConfiguration(_ config: PluginChainConfiguration) {
        for slotState in config.slotStates {
            guard let runtime = slotRuntimes[slotState.slotID],
                  let unit = runtime.avUnit else { continue }
            applySlotState(slotState, to: unit, runtime: runtime)
            setSlotEnabled(id: slotState.slotID, enabled: slotState.isEnabled)
        }
    }

    /// Switches the legacy plugin-editor chain's per-slot state to the entry's
    /// assigned configuration (or restores the pre-configuration snapshot when
    /// none is assigned). Shared by `loadEntry` (manual transport) and
    /// `completePromotion` (automatic dual-deck transition) — this chain's
    /// lifecycle is independent of which deck happens to be audible.
    private func applyPerTrackPluginConfiguration(for entry: SetlistEntry) {
        let resolvedConfigID = entry.pluginConfigurationID ?? configStore.defaultConfigurationID
        if let configID = resolvedConfigID, let config = configStore.configuration(id: configID) {
            if preConfigSnapshot == nil {
                preConfigSnapshot = PreConfigSnapshot(
                    chainEnabled: settings.audioUnitPluginEnabled,
                    chainBypassed: settings.audioUnitPluginBypassed,
                    slotStates: captureChainConfiguration()
                )
            }
            if !settings.audioUnitPluginEnabled { enableAudioUnitPlugin() }
            applyChainConfiguration(config)
        } else if let snapshot = preConfigSnapshot {
            restorePreConfigSnapshot(snapshot)
            preConfigSnapshot = nil
        }
    }

    private func restorePreConfigSnapshot(_ snapshot: PreConfigSnapshot) {
        for slotState in snapshot.slotStates {
            guard let runtime = slotRuntimes[slotState.slotID],
                  let unit = runtime.avUnit else { continue }
            applySlotState(slotState, to: unit, runtime: runtime)
            setSlotEnabled(id: slotState.slotID, enabled: slotState.isEnabled)
        }
        if snapshot.chainBypassed != settings.audioUnitPluginBypassed {
            bypassAudioUnitPlugin(snapshot.chainBypassed)
        }
        if snapshot.chainEnabled != settings.audioUnitPluginEnabled {
            if snapshot.chainEnabled { enableAudioUnitPlugin() } else { disableAudioUnitPlugin() }
        }
    }

    private func applySlotState(_ slotState: PluginSlotState, to unit: AVAudioUnit, runtime: SlotRuntime) {
        guard let fullState = try? AUStateCodec.decode(slotState.auState) else { return }
        runtime.isApplyingPreset = true
        unit.auAudioUnit.fullState = fullState
        runtime.activePresetID = nil
        slotActivePresetIDs.removeValue(forKey: slotState.slotID)
        updateSlotPresetName(slotId: slotState.slotID, name: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak runtime] in
            runtime?.isApplyingPreset = false
        }
    }

    /// Splices the legacy, session-long-lived plugin-editor chain
    /// (`slotRuntimes`) between `activeDeck.pluginChainTail` (this deck's own
    /// `replayGainMixer`, or the end of its `prepare()`-instantiated plugins)
    /// and `activeDeck.outputMixer`.
    ///
    /// Task 5 decision (Option C): this chain deliberately keeps its existing
    /// one-AU-instance-per-session lifecycle (`slotRuntimes`/`PluginWindowViewController`,
    /// reconfigured via `fullState`/presets per track) rather than being unified
    /// with `PlaybackDeck.pluginRuntimes`'s prepare-time instantiation. It is
    /// re-targeted at whichever deck is currently active. Only `activeDeck`'s own
    /// nodes are touched — never the shared `commonMixer`/`balanceMixer` output
    /// path, and never `engine.stop()`.
    ///
    /// KNOWN LIMITATION: at promotion, this chain's connection points must move
    /// from the outgoing deck to the incoming deck — see `reconnectLegacyPluginChainAfterPromotion()`,
    /// called from the transition path. That reconnect happens at the promotion
    /// instant, not ahead of commitment, which is a real exception to "everything
    /// expensive happens before commitment" for this one chain. The deck's own
    /// `pluginRuntimes` (Task 4's standby-prepared plugins) are unaffected and
    /// remain fully pre-attached.
    private func reconnectLegacyPluginChain(format: AVAudioFormat?) {
        let deck = activeDeck
        for runtime in slotRuntimes.values {
            if let unit = runtime.avUnit {
                dualDeckAudioEngine.engine.disconnectNodeOutput(unit)
            }
        }

        // AU plugins often don't support mono. Upmix to stereo here so replayGainMixer
        // (AVAudioMixerNode) does the channel conversion before the plugin chain sees any data.
        let pluginFormat: AVAudioFormat? = {
            guard let fmt = format, fmt.channelCount < 2 else { return format }
            return AVAudioFormat(standardFormatWithSampleRate: fmt.sampleRate, channels: 2)
        }()

        var prev: AVAudioNode = deck.pluginChainTail
        var failedSlots: [(id: UUID, reason: String)] = []
        for (slot, unit) in liveChainUnits() {
            if let fmt = pluginFormat {
                do {
                    try unit.auAudioUnit.inputBusses[0].setFormat(fmt)
                } catch {
                    os_log(.error, "TangoDisplay: plugin '%{public}@' rejected format; disabling: %{public}@",
                           slot.selection.name, error.localizedDescription)
                    failedSlots.append((id: slot.id, reason: error.localizedDescription))
                    continue
                }
            }
            var connectReason: NSString?
            if TDTryAudioEngineConnect(dualDeckAudioEngine.engine, prev, unit, pluginFormat, &connectReason) {
                prev = unit
            } else {
                let msg = (connectReason as String?) ?? "NSException during connect"
                os_log(.error, "TangoDisplay: plugin '%{public}@' connect threw exception; disabling: %{public}@",
                       slot.selection.name, msg)
                failedSlots.append((id: slot.id, reason: msg))
            }
        }
        for (id, reason) in failedSlots {
            markSlotFailed(id: id, reason: reason)
        }
        do {
            try deck.pointOutputMixer(at: prev, format: pluginFormat)
        } catch {
            os_log(.error, "TangoDisplay: failed to point %{public}@'s output mixer at the plugin chain: %{public}@",
                   String(describing: deck.id), error.localizedDescription)
        }
    }

    /// Moves the legacy plugin-editor chain's connection point from the
    /// outgoing deck to the newly-promoted incoming deck. Called once, right
    /// after `DualDeckState.promote` flips `activeDeck` — see the known
    /// limitation noted on `reconnectLegacyPluginChain`.
    private func reconnectLegacyPluginChainAfterPromotion() {
        reconnectLegacyPluginChain(format: audioFile?.processingFormat)
    }

    private func rewireGraphSafely() {
        let wasPlaying = isActivePlaying
        let savedElapsed = elapsed
        let format = audioFile?.processingFormat

        activeDeck.playerNode.stop()
        reconnectLegacyPluginChain(format: format)

        // If a plugin in the live chain breaks the deck's internal connection
        // (e.g. format incompatibility), drop slots from the end of the live
        // chain one at a time and retry — this preserves the working portion of
        // the chain. Unlike the legacy single-deck engine, this no longer needs
        // a full `engine.stop()/start()`: only `activeDeck`'s internal edges and
        // the legacy chain's splice point are touched.
        var attempts = liveChainUnits().count + 1
        while attempts > 0 {
            if dualDeckAudioEngine.engine.isRunning { break }
            do {
                try dualDeckAudioEngine.startIfNeeded()
                break
            } catch {
                let live = liveChainUnits()
                guard let last = live.last else {
                    os_log(.error, "TangoDisplay: engine start failed with no live plugins: %{public}@",
                           error.localizedDescription)
                    try? dualDeckAudioEngine.startIfNeeded()
                    break
                }
                os_log(.error, "TangoDisplay: engine start failed; disabling slot %{public}@: %{public}@",
                       last.slot.selection.name, error.localizedDescription)
                markSlotFailed(id: last.slot.id, reason: error.localizedDescription)
                reconnectLegacyPluginChain(format: format)
            }
            attempts -= 1
        }

        levelMeter.reinstallTap()
        applyBalance(_balance)
        if audioFile != nil {
            seekTo(savedElapsed)
            if wasPlaying { activeDeck.playerNode.play() }
        }
        recomputeChainStatus()
    }

    private func markSlotFailed(id: UUID, reason: String) {
        guard let runtime = slotRuntimes[id] else { return }
        let name = settings.audioUnitPluginChain.first(where: { $0.id == id })?.selection.name ?? ""
        runtime.status = .failed(name, reason: reason)
        slotStatuses[id] = runtime.status
        if let unit = runtime.avUnit {
            dualDeckAudioEngine.engine.disconnectNodeOutput(unit)
            dualDeckAudioEngine.engine.detach(unit)
        }
        teardownSlotObservers(runtime)
        runtime.avUnit = nil
    }

    // MARK: - Audio Unit chain actions

    /// Append a plugin to the chain. No-op if the chain is already at the max.
    @discardableResult
    func addPluginSlot(_ selection: AudioUnitPluginSelection) -> UUID? {
        guard settings.audioUnitPluginChain.count < AudioUnitChainSlot.maxSlots else { return nil }
        let slot = AudioUnitChainSlot(selection: selection, isEnabled: true)
        settings.audioUnitPluginChain.append(slot)
        slotRuntimes[slot.id] = SlotRuntime()
        slotStatuses[slot.id] = .loading(selection.name)
        if settings.audioUnitPluginEnabled {
            startSlotLoad(slot)
        } else {
            slotStatuses[slot.id] = .disabled
        }
        recomputeChainStatus()
        return slot.id
    }

    /// Replace what's loaded in an existing slot. Preserves the slot's id and position.
    func replacePluginSlot(id: UUID, with selection: AudioUnitPluginSelection) {
        guard let index = settings.audioUnitPluginChain.firstIndex(where: { $0.id == id }) else { return }
        tearDownSlot(id: id, detachAVUnit: true)
        var updated = settings.audioUnitPluginChain[index]
        updated.selection = selection
        updated.lastUsedPresetName = nil
        settings.audioUnitPluginChain[index] = updated
        slotRuntimes[id] = SlotRuntime()
        if settings.audioUnitPluginEnabled {
            startSlotLoad(updated)
        } else {
            slotStatuses[id] = .disabled
        }
        rewireGraphSafely()
    }

    func removePluginSlot(id: UUID) {
        tearDownSlot(id: id, detachAVUnit: true)
        slotRuntimes.removeValue(forKey: id)
        slotStatuses.removeValue(forKey: id)
        slotPresets.removeValue(forKey: id)
        slotActivePresetIDs.removeValue(forKey: id)
        settings.audioUnitPluginChain.removeAll { $0.id == id }
        rewireGraphSafely()
    }

    func moveSlot(from source: Int, to destination: Int) {
        var chain = settings.audioUnitPluginChain
        guard source >= 0, source < chain.count,
              destination >= 0, destination <= chain.count,
              source != destination else { return }
        let item = chain.remove(at: source)
        let target = destination > source ? destination - 1 : destination
        chain.insert(item, at: min(target, chain.count))
        settings.audioUnitPluginChain = chain
        rewireGraphSafely()
    }

    func setSlotEnabled(id: UUID, enabled: Bool) {
        guard let index = settings.audioUnitPluginChain.firstIndex(where: { $0.id == id }) else { return }
        settings.audioUnitPluginChain[index].isEnabled = enabled
        rewireGraphSafely()
        recomputeChainStatus()
    }

    func enableAudioUnitPlugin() {
        settings.audioUnitPluginEnabled = true
        // Kick off any slots that didn't load yet.
        for slot in settings.audioUnitPluginChain where slotRuntimes[slot.id]?.avUnit == nil {
            startSlotLoad(slot)
        }
        rewireGraphSafely()
    }

    func disableAudioUnitPlugin() {
        settings.audioUnitPluginEnabled = false
        rewireGraphSafely()
        recomputeChainStatus()
    }

    func bypassAudioUnitPlugin(_ bypassed: Bool) {
        settings.audioUnitPluginBypassed = bypassed
        rewireGraphSafely()
        recomputeChainStatus()
    }

    func openPluginWindow(slotId: UUID) {
        guard let runtime = slotRuntimes[slotId], let avUnit = runtime.avUnit else { return }
        if let existing = runtime.pluginWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let title = settings.audioUnitPluginChain.first(where: { $0.id == slotId })?.selection.name ?? "Plugin"
        avUnit.auAudioUnit.requestViewController { [weak self] viewController in
            DispatchQueue.main.async {
                guard let self, let runtime = self.slotRuntimes[slotId] else { return }
                guard let vc = viewController else {
                    runtime.status = .failed(title, reason: "Plugin editor unavailable")
                    self.slotStatuses[slotId] = runtime.status
                    self.recomputeChainStatus()
                    return
                }
                let wrapper = PluginWindowViewController(pluginVC: vc, player: self, slotId: slotId)
                // Force loadView/viewDidLoad so wrapper.view is sized.
                _ = wrapper.view
                let initialSize: NSSize = wrapper.view.frame.size != .zero
                    ? wrapper.view.frame.size
                    : NSSize(width: 600, height: 400)

                let window = NSWindow(
                    contentRect: NSRect(origin: .zero, size: initialSize),
                    styleMask: [.titled, .closable, .resizable, .miniaturizable],
                    backing: .buffered,
                    defer: false
                )
                window.title = title
                // Each plugin window stays standalone — never auto-merged into a
                // tab group (which would also disable the resize handle). A
                // unique tabbingIdentifier means even if macOS tries to group,
                // there's no other window it could group with.
                window.tabbingMode = .disallowed
                window.tabbingIdentifier = "tangodisplay.plugin.\(slotId.uuidString)"
                window.isRestorable = false
                // Bypass `contentViewController = wrapper` deliberately: that
                // setter binds the window's content size to the VC's
                // preferredContentSize, which silently overrides manual resize
                // and our own setContentSize calls. Setting contentView
                // directly keeps the window freely resizable. We then hold the
                // wrapper VC strongly in SlotRuntime since the window doesn't.
                window.contentView = wrapper.view
                window.contentMinSize = NSSize(width: 200, height: 100)
                window.contentMaxSize = NSSize(width: 4096, height: 4096)
                window.isReleasedWhenClosed = false
                window.center()
                window.makeKeyAndOrderFront(nil)
                // Defensive: if macOS somehow grouped us anyway, break out.
                if window.tabGroup != nil {
                    window.moveTabToNewWindow(nil)
                }
                runtime.pluginWindow = window
                runtime.pluginWindowVC = wrapper
            }
        }
    }

    func closePluginWindow(slotId: UUID) {
        slotRuntimes[slotId]?.pluginWindow?.close()
        slotRuntimes[slotId]?.pluginWindow = nil
        slotRuntimes[slotId]?.pluginWindowVC = nil
    }

    // MARK: - Presets (per slot)

    func applyPreset(_ preset: AudioUnitPreset, toSlot slotId: UUID) {
        guard let runtime = slotRuntimes[slotId],
              let avUnit = runtime.avUnit,
              let manager = runtime.presetManager else { return }
        runtime.isApplyingPreset = true
        do {
            try manager.applyPreset(preset, to: avUnit, originator: runtime.paramObserverToken)
            runtime.activePresetID = preset.id
            slotActivePresetIDs[slotId] = preset.id
            updateSlotPresetName(slotId: slotId, name: preset.name)
        } catch {
            os_log(.error, "TangoDisplay: applyPreset failed: %{public}@", error.localizedDescription)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak runtime] in
            runtime?.isApplyingPreset = false
        }
    }

    func saveCurrentAsPreset(named name: String, forSlot slotId: UUID) throws {
        guard let runtime = slotRuntimes[slotId],
              let avUnit = runtime.avUnit,
              let manager = runtime.presetManager else { return }
        let preset = try manager.savePreset(name: name, from: avUnit)
        let all = manager.factoryPresets(for: avUnit) + manager.userPresets()
        runtime.availablePresets = all
        runtime.activePresetID = preset.id
        slotPresets[slotId] = all
        slotActivePresetIDs[slotId] = preset.id
        updateSlotPresetName(slotId: slotId, name: preset.name)
    }

    func deletePreset(_ preset: AudioUnitPreset, fromSlot slotId: UUID) throws {
        guard let runtime = slotRuntimes[slotId],
              let avUnit = runtime.avUnit,
              let manager = runtime.presetManager else { return }
        try manager.deletePreset(preset)
        let all = manager.factoryPresets(for: avUnit) + manager.userPresets()
        runtime.availablePresets = all
        slotPresets[slotId] = all
        if runtime.activePresetID == preset.id {
            runtime.activePresetID = nil
            slotActivePresetIDs.removeValue(forKey: slotId)
            updateSlotPresetName(slotId: slotId, name: nil)
        }
    }

    private func updateSlotPresetName(slotId: UUID, name: String?) {
        guard let index = settings.audioUnitPluginChain.firstIndex(where: { $0.id == slotId }) else { return }
        settings.audioUnitPluginChain[index].lastUsedPresetName = name
    }

    // MARK: - Private: chain internals

    private func initializePluginStatus() {
        guard !settings.audioUnitPluginChain.isEmpty else {
            audioUnitPluginStatus = .noPluginSelected
            return
        }
        for slot in settings.audioUnitPluginChain {
            if slotRuntimes[slot.id] == nil {
                slotRuntimes[slot.id] = SlotRuntime()
            }
            if !settings.audioUnitPluginEnabled {
                slotStatuses[slot.id] = .disabled
                continue
            }
            if slotRuntimes[slot.id]?.avUnit != nil { continue }
            if pluginManager.isAvailable(slot.selection) {
                startSlotLoad(slot)
            } else {
                slotStatuses[slot.id] = .unavailable(slot.selection.name)
            }
        }
        recomputeChainStatus()
    }

    private func startSlotLoad(_ slot: AudioUnitChainSlot) {
        let runtime = slotRuntimes[slot.id] ?? SlotRuntime()
        slotRuntimes[slot.id] = runtime
        runtime.loadTask?.cancel()
        runtime.loadGeneration += 1
        let gen = runtime.loadGeneration
        let slotId = slot.id
        let selection = slot.selection
        runtime.status = .loading(selection.name)
        slotStatuses[slotId] = runtime.status
        recomputeChainStatus()

        runtime.loadTask = Task { [weak self, weak runtime] in
            guard let self else { return }
            do {
                let avUnit = try await pluginManager.instantiate(selection)
                await MainActor.run { [weak self, weak runtime] in
                    guard let self, let runtime,
                          runtime.loadGeneration == gen,
                          self.settings.audioUnitPluginChain.contains(where: { $0.id == slotId })
                    else { return }
                    self.dualDeckAudioEngine.engine.attach(avUnit)
                    runtime.avUnit = avUnit
                    runtime.status = .active(selection.name)
                    self.slotStatuses[slotId] = runtime.status

                    let manager = AudioUnitPresetManager(for: selection)
                    runtime.presetManager = manager
                    let all = manager.factoryPresets(for: avUnit) + manager.userPresets()
                    runtime.availablePresets = all
                    self.slotPresets[slotId] = all

                    self.installSlotObservers(slotId: slotId, runtime: runtime, avUnit: avUnit)

                    // Apply the track's assigned configuration (or default), falling back to last-used preset.
                    var appliedConfig = false
                    if let entryID = self.currentEntryID,
                       let entry = self.setlist.entries.first(where: { $0.id == entryID }) {
                        let resolvedID = entry.pluginConfigurationID ?? self.configStore.defaultConfigurationID
                        if let configID = resolvedID,
                           let config = self.configStore.configuration(id: configID),
                           let slotState = config.slotStates.first(where: { $0.slotID == slotId }) {
                            self.applySlotState(slotState, to: avUnit, runtime: runtime)
                            appliedConfig = true
                        }
                    }

                    if !appliedConfig {
                        // Restore last-used preset for this slot.
                        let savedName = self.settings.audioUnitPluginChain
                            .first(where: { $0.id == slotId })?.lastUsedPresetName
                        if let savedName, let match = all.first(where: { $0.name == savedName }) {
                            runtime.isApplyingPreset = true
                            try? manager.applyPreset(match, to: avUnit, originator: runtime.paramObserverToken)
                            runtime.activePresetID = match.id
                            self.slotActivePresetIDs[slotId] = match.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak runtime] in
                                runtime?.isApplyingPreset = false
                            }
                        }
                    }

                    self.rewireGraphSafely()
                }
            } catch {
                await MainActor.run { [weak self, weak runtime] in
                    guard let self, let runtime, runtime.loadGeneration == gen else { return }
                    runtime.status = .failed(selection.name, reason: error.localizedDescription)
                    self.slotStatuses[slotId] = runtime.status
                    self.recomputeChainStatus()
                }
            }
        }
    }

    private func installSlotObservers(slotId: UUID, runtime: SlotRuntime, avUnit: AVAudioUnit) {
        if let tree = avUnit.auAudioUnit.parameterTree {
            runtime.paramObserverTree = tree
            runtime.paramObserverToken = tree.token(byAddingParameterObserver: { [weak self, weak runtime] _, _ in
                DispatchQueue.main.async {
                    guard let self, let runtime, !runtime.isApplyingPreset else { return }
                    runtime.activePresetID = nil
                    self.slotActivePresetIDs.removeValue(forKey: slotId)
                    self.updateSlotPresetName(slotId: slotId, name: nil)
                }
            })
        }
        // KVO on currentPreset catches V2 AU UIs (e.g. AUGraphicEQ "Flat") that bypass the parameter tree.
        runtime.currentPresetObservation = avUnit.auAudioUnit.observe(\.currentPreset, options: [.new]) {
            [weak self, weak runtime] _, _ in
            DispatchQueue.main.async {
                guard let self, let runtime, !runtime.isApplyingPreset else { return }
                runtime.activePresetID = nil
                self.slotActivePresetIDs.removeValue(forKey: slotId)
                self.updateSlotPresetName(slotId: slotId, name: nil)
            }
        }
    }

    private func teardownSlotObservers(_ runtime: SlotRuntime) {
        if let tree = runtime.paramObserverTree, let token = runtime.paramObserverToken {
            tree.removeParameterObserver(token)
        }
        runtime.paramObserverTree = nil
        runtime.paramObserverToken = nil
        runtime.currentPresetObservation = nil
    }

    private func tearDownSlot(id: UUID, detachAVUnit: Bool) {
        guard let runtime = slotRuntimes[id] else { return }
        runtime.loadTask?.cancel()
        runtime.loadTask = nil
        runtime.pluginWindow?.close()
        runtime.pluginWindow = nil
        runtime.pluginWindowVC = nil
        teardownSlotObservers(runtime)
        if detachAVUnit, let unit = runtime.avUnit {
            dualDeckAudioEngine.engine.disconnectNodeOutput(unit)
            dualDeckAudioEngine.engine.detach(unit)
        }
        runtime.avUnit = nil
        runtime.presetManager = nil
        runtime.availablePresets = []
        runtime.activePresetID = nil
        slotPresets.removeValue(forKey: id)
        slotActivePresetIDs.removeValue(forKey: id)
    }

    private func recomputeChainStatus() {
        let chain = settings.audioUnitPluginChain
        guard !chain.isEmpty else {
            audioUnitPluginStatus = .noPluginSelected
            return
        }
        if !settings.audioUnitPluginEnabled {
            audioUnitPluginStatus = .disabled
            return
        }
        // Surface a failure if any slot is broken.
        if let failed = chain.compactMap({ slot -> (String, String)? in
            if case .failed(let n, let r) = slotStatuses[slot.id] ?? .noPluginSelected {
                return (n, r)
            }
            return nil
        }).first {
            audioUnitPluginStatus = .failed(failed.0, reason: failed.1)
            return
        }
        if settings.audioUnitPluginBypassed {
            audioUnitPluginStatus = .bypassed(chainSummaryName(chain))
            return
        }
        // Loading wins over active so the UI shows progress.
        if chain.contains(where: { if case .loading = slotStatuses[$0.id] ?? .noPluginSelected { return true } else { return false } }) {
            audioUnitPluginStatus = .loading(chainSummaryName(chain))
            return
        }
        audioUnitPluginStatus = .active(chainSummaryName(chain))
    }

    private func chainSummaryName(_ chain: [AudioUnitChainSlot]) -> String {
        if chain.count == 1 { return chain[0].selection.name }
        return "\(chain.count) plugins"
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

        settings.$builtInHogMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                let uid = self.settings.builtInOutputDeviceUID
                self.isChangingDevice = true
                self.audioDeviceQueue.async {
                    self.applyHogMode(enabled: enabled, deviceUID: uid)
                    DispatchQueue.main.async { self.isChangingDevice = false }
                }
            }
            .store(in: &cancellables)

        // Applied to both decks (see `applyEQGains`) so a promotion never reveals a flat EQ.
        settings.$eqBand0Gain.sink { [weak self] v in self?.setEQBandGain(0, v) }.store(in: &cancellables)
        settings.$eqBand1Gain.sink { [weak self] v in self?.setEQBandGain(1, v) }.store(in: &cancellables)
        settings.$eqBand2Gain.sink { [weak self] v in self?.setEQBandGain(2, v) }.store(in: &cancellables)
        settings.$eqBand3Gain.sink { [weak self] v in self?.setEQBandGain(3, v) }.store(in: &cancellables)
        settings.$eqBand4Gain.sink { [weak self] v in self?.setEQBandGain(4, v) }.store(in: &cancellables)

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
        settings.$cortinaVolumeReductionDb
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
                    self.activeDeck.playerNode.stop()
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
                // A reorder, removal, or per-entry plugin-configuration change may have
                // invalidated the standby deck's identity; re-evaluate and reuse or cancel.
                self.prepareStandbyIfNeeded()
            }
            .store(in: &cancellables)

        // Gap-only setting changes recompute the uncommitted timeline without
        // reopening deck B's file — only `settingsRevision` advances.
        settings.$autoGapEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleGapSettingsRevisionChange() }
            .store(in: &cancellables)
        settings.$autoGapDuration
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleGapSettingsRevisionChange() }
            .store(in: &cancellables)
        settings.$autoGapIgnoreFirstTrack
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleGapSettingsRevisionChange() }
            .store(in: &cancellables)
        settings.$stopAfterEachPerformanceTrack
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleGapSettingsRevisionChange() }
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
              let nodeTime = activeDeck.playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = activeDeck.playerNode.playerTime(forNodeTime: nodeTime) else { return }

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
