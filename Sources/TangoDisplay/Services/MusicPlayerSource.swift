import AppKit
import Foundation
import TangoDisplayCore

// MARK: - Player choice

enum MusicPlayerChoice: String, CaseIterable, Identifiable {
    case builtIn   = "builtIn"
    case musicApp  = "musicApp"
    case swinsian  = "swinsian"
    case embrace   = "embrace"
    case jriver    = "jriver"
    case megaSeg   = "megaSeg"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .builtIn:  return "Setlist (Built-In Player)"
        case .musicApp: return "Music.app"
        case .swinsian: return "Swinsian"
        case .embrace:  return "Embrace"
        case .jriver:   return "JRiver Media Center"
        case .megaSeg:  return "MegaSeg"
        }
    }
}

// MARK: - Protocol

/// Abstracts polling/push-based music player monitoring.
/// All callbacks must be delivered on the main queue.
protocol MusicPlayerSource: AnyObject {
    var onTrackUpdate: ((Track?, PlayerState) -> Void)? { get set }
    var onPlaylistUpdate: ((tracks: [Track], currentIndex: Int)?) -> Void { get set }
    /// Delivers the track immediately following the current one, or nil when unavailable.
    /// Fired before onTrackUpdate each poll so callers can use it during cortina transitions.
    var onNextTrackUpdate: ((Track?) -> Void)? { get set }
    var onWatchdogChanged: ((Bool) -> Void)? { get set }
    /// Whether the source can enumerate the playlist. False means tandaPosition.total
    /// is always nil and the track counter is not useful.
    var supportsPlaylist: Bool { get }
    func start()
    func stop()
    func pollNow()
    func triggerPlaylistFetch()
    /// Fetches album artwork for the given track. Returns nil when unavailable.
    func fetchArtwork(for track: Track) async -> NSImage?
    // Transport controls — no-op defaults in extension; LocalPlayerSource overrides all five.
    func play()
    func pause()
    func skipNext()
    func skipNextImmediate()
    func skipPrevious()
    func seek(to seconds: Double)
}

extension MusicPlayerSource {
    var supportsPlaylist: Bool { true }
    var isTransportControllable: Bool { false }
    func fetchArtwork(for track: Track) async -> NSImage? { nil }
    func play() {}
    func pause() {}
    func skipNext() {}
    func skipNextImmediate() { skipNext() }
    func skipPrevious() {}
    func seek(to seconds: Double) {}
}
