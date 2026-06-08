import Foundation
import Combine
import TangoDisplayCore

/// Mediates between the TangoDisplay app state and a `RemoteTransport`.
///
/// Once a transport is attached, the underlying listener stays bound for the lifetime
/// of the app process. The user-facing on/off toggle calls `resume()` / `pause()`,
/// which only gates acceptance — it does NOT re-bind the port. This avoids the
/// EADDRINUSE / NWError 48 race that occurs when a TCP listener is cancelled and
/// rebound on the same port in quick succession on macOS. A full teardown only
/// happens via `teardown(completion:)`, called from `applicationWillTerminate`.
@MainActor
final class RemoteControlBridge: NSObject, ObservableObject {

    private let appState: AppState
    private let settings: AppSettings
    private var transport: RemoteTransport?

    private var stateCancellables = Set<AnyCancellable>()
    private var transportCancellables = Set<AnyCancellable>()
    private var authenticatedClients = Set<UUID>()

    private let stateChangeSubject = PassthroughSubject<Void, Never>()

    @Published private(set) var connectionCount: Int = 0
    /// True while a transport is attached and its listener is bound.
    @Published private(set) var isRunning: Bool = false
    /// True while inbound auth + commands are honoured. When false, new connections
    /// are dropped immediately and existing clients are disconnected.
    @Published private(set) var isAcceptingClients: Bool = false
    @Published private(set) var lastError: String? = nil

    init(appState: AppState, settings: AppSettings) {
        self.appState = appState
        self.settings = settings
    }

    // MARK: - Attach / resume / pause / teardown

    /// One-time attach: creates the listener and starts accepting clients. Called from
    /// `AppState` the first time the user enables Setlist Remote in a session.
    func attach(transport: RemoteTransport) throws {
        if let old = self.transport {
            // Previous attach failed (e.g. port really was in use). Drop the old
            // instance — if it had bound the port we wouldn't be retrying.
            old.stop(completion: {})
            transportCancellables.removeAll()
        }
        self.transport = transport
        transport.delegate = self
        if let http = transport as? HTTPServerTransport {
            http.onListenerFailure = { [weak self] message in
                Task { @MainActor in self?.reportStartError(message) }
            }
        }
        try transport.start()
        transport.connectionCountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in self?.connectionCount = count }
            .store(in: &transportCancellables)
        subscribeToState()
        isRunning = true
        isAcceptingClients = true
        lastError = nil
    }

    /// Re-enable acceptance after a `pause()`. Cheap and safe to call repeatedly.
    func resume() {
        guard isRunning else { return }
        isAcceptingClients = true
        lastError = nil
    }

    /// Disable acceptance: kicks every connected client and refuses new auth attempts.
    /// The listener stays bound — see the type doc-comment for why.
    func pause() {
        guard isRunning else { return }
        isAcceptingClients = false
        guard let transport else { return }
        for clientID in authenticatedClients {
            transport.disconnect(clientID)
        }
        authenticatedClients.removeAll()
    }

    /// Full shutdown — cancels the listener and tears down all subscriptions.
    /// Intended for `applicationWillTerminate`; not used by the on/off toggle.
    func teardown(completion: (@Sendable () -> Void)? = nil) {
        stateCancellables.removeAll()
        transportCancellables.removeAll()
        authenticatedClients.removeAll()
        connectionCount = 0
        isRunning = false
        isAcceptingClients = false
        let t = transport
        transport = nil
        if let t {
            t.stop(completion: completion ?? {})
        } else {
            completion?()
        }
    }

    func reportStartError(_ message: String) {
        lastError = message
        isRunning = false
        isAcceptingClients = false
    }

    // MARK: - State subscription

    private func subscribeToState() {
        // Any change to a subscribed publisher emits on stateChangeSubject;
        // throttling coalesces rapid slider drags into one snapshot per 100 ms.
        let settings = self.settings
        let appState = self.appState

        settings.$builtInVolume.dropFirst().sink { [weak self] _ in self?.stateChangeSubject.send() }.store(in: &stateCancellables)
        settings.$cortinaVolumeReductionDb.dropFirst().sink { [weak self] _ in self?.stateChangeSubject.send() }.store(in: &stateCancellables)
        settings.$replayGainMode.dropFirst().sink { [weak self] _ in self?.stateChangeSubject.send() }.store(in: &stateCancellables)
        settings.$replayGainPreampDb.dropFirst().sink { [weak self] _ in self?.stateChangeSubject.send() }.store(in: &stateCancellables)
        settings.$replayGainPreventClipping.dropFirst().sink { [weak self] _ in self?.stateChangeSubject.send() }.store(in: &stateCancellables)
        settings.$replayGainTargetLufs.dropFirst().sink { [weak self] _ in self?.stateChangeSubject.send() }.store(in: &stateCancellables)

        appState.$displayState.dropFirst().sink { [weak self] _ in self?.stateChangeSubject.send() }.store(in: &stateCancellables)
        appState.$currentPlayerState.dropFirst().sink { [weak self] _ in self?.stateChangeSubject.send() }.store(in: &stateCancellables)

        stateChangeSubject
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in self?.broadcastSnapshot() }
            .store(in: &stateCancellables)
    }

    private func broadcastSnapshot() {
        guard let transport, !authenticatedClients.isEmpty else { return }
        guard let json = snapshotJSON() else { return }
        for clientID in authenticatedClients {
            transport.send(json, to: clientID)
        }
    }

    // MARK: - JSON snapshot

    private func snapshotJSON() -> String? {
        let s = settings
        let display = appState.displayState
        let playerState = appState.currentPlayerState
        let local = appState.localPlayer

        var nowPlaying: [String: Any] = [
            "playerState": playerState.rawValue,
            "displayMode": displayModeString(display.mode),
            "snapshotAt": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if let track = display.currentTrack {
            nowPlaying["title"] = track.title
            nowPlaying["artist"] = track.artist
            nowPlaying["genre"] = track.genre
        }
        if let tanda = display.tandaPosition {
            var t: [String: Any] = ["current": tanda.current]
            if let total = tanda.total { t["total"] = total }
            nowPlaying["tanda"] = t
        }
        if let local {
            nowPlaying["elapsedSec"] = local.elapsed
            nowPlaying["durationSec"] = local.duration
        }
        if let override = display.overrideText {
            nowPlaying["overrideText"] = override
        }

        let payload: [String: Any] = [
            "type": "state",
            "mainVolume": s.builtInVolume,
            "cortinaVolumeDb": s.cortinaVolumeReductionDb,
            "replayGain": [
                "mode": s.replayGainMode.rawValue,
                "preampDb": s.replayGainPreampDb,
                "preventClipping": s.replayGainPreventClipping,
                "targetLufs": s.replayGainTargetLufs
            ],
            "nowPlaying": nowPlaying
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func displayModeString(_ mode: DisplayMode) -> String {
        switch mode {
        case .playing:      return "playing"
        case .cortina:      return "cortina"
        case .idle:         return "idle"
        case .paused:       return "paused"
        case .override:     return "override"
        case .performance:  return "performance"
        }
    }

    // MARK: - Inbound command handling

    private func handle(message: String, from clientID: UUID) {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "auth":
            handleAuth(pin: json["pin"] as? String, from: clientID)
        case "set":
            guard isAcceptingClients, authenticatedClients.contains(clientID) else { return }
            handleSet(field: json["field"] as? String, value: json["value"], from: clientID)
        default:
            break
        }
    }

    private func handleAuth(pin: String?, from clientID: UUID) {
        guard let transport else { return }
        // If paused, refuse auth — client will see the disconnect and retry later.
        guard isAcceptingClients else {
            transport.disconnect(clientID)
            return
        }
        let expected = settings.remoteControlPin
        guard let pin, !expected.isEmpty, pin == expected else {
            let nack = #"{"type":"auth","ok":false}"#
            transport.send(nack, to: clientID)
            transport.disconnect(clientID)
            return
        }
        authenticatedClients.insert(clientID)
        let ack = #"{"type":"auth","ok":true}"#
        transport.send(ack, to: clientID)
        if let snapshot = snapshotJSON() {
            transport.send(snapshot, to: clientID)
        }
    }

    private func handleSet(field: String?, value: Any?, from clientID: UUID) {
        guard let field, let value else { return }
        switch field {
        case "mainVolume":
            if let v = (value as? Double) ?? (value as? Int).map(Double.init) {
                appState.syncVolume(Float(max(0.0, min(1.0, v))))
            }
        case "cortinaVolumeDb":
            if let v = (value as? Double) ?? (value as? Int).map(Double.init) {
                settings.cortinaVolumeReductionDb = max(-10.0, min(0.0, v))
            }
        case "replayGain.mode":
            if let raw = value as? String, let mode = ReplayGainMode(rawValue: raw) {
                settings.replayGainMode = mode
            }
        case "replayGain.preampDb":
            if let v = (value as? Double) ?? (value as? Int).map(Double.init) {
                settings.replayGainPreampDb = Float(max(-12.0, min(6.0, v)))
            }
        case "replayGain.preventClipping":
            if let b = value as? Bool {
                settings.replayGainPreventClipping = b
            }
        case "replayGain.targetLufs":
            if let v = (value as? Double) ?? (value as? Int).map(Double.init) {
                settings.replayGainTargetLufs = Float(max(-23.0, min(-14.0, v)))
            }
        default:
            break
        }
    }
}

// MARK: - RemoteTransportDelegate

extension RemoteControlBridge: RemoteTransportDelegate {
    nonisolated func transport(_ transport: RemoteTransport, didConnect clientID: UUID) {
        Task { @MainActor in
            // Drop new connections immediately when paused — the web client's
            // reconnect loop will retry, and once resumed the next attempt succeeds.
            guard self.isAcceptingClients else {
                transport.disconnect(clientID)
                return
            }
            let hello = #"{"type":"hello","needsAuth":true}"#
            transport.send(hello, to: clientID)
        }
    }

    nonisolated func transport(_ transport: RemoteTransport, didDisconnect clientID: UUID) {
        Task { @MainActor in
            self.authenticatedClients.remove(clientID)
        }
    }

    nonisolated func transport(_ transport: RemoteTransport, didReceiveText text: String, from clientID: UUID) {
        Task { @MainActor in
            self.handle(message: text, from: clientID)
        }
    }
}
