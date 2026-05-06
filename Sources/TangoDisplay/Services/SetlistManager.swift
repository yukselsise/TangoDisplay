import AppKit
import AVFoundation
import AudioToolbox
import Combine
import Foundation
import TangoDisplayCore

enum SetlistEntryState: String, Codable {
    case queued, playing, paused, played
}

struct SetlistEntry: Identifiable, Codable {
    let id: UUID
    let fileURL: URL
    var track: Track
    var state: SetlistEntryState
    var duration: TimeInterval?

    init(id: UUID = UUID(), fileURL: URL, track: Track, state: SetlistEntryState = .queued) {
        self.id = id
        self.fileURL = fileURL
        self.track = track
        self.state = state
    }
}

enum DuplicateSessionDecision { case alwaysAdd, neverAdd }

final class SetlistManager: ObservableObject {
    @Published private(set) var entries: [SetlistEntry] = []
    @Published var stopAfterEntryID: UUID?
    private(set) var duplicateSessionDecision: DuplicateSessionDecision? = nil

    func setDuplicateSessionDecision(_ decision: DuplicateSessionDecision?) {
        duplicateSessionDecision = decision
    }

    var totalPlaylistDuration: TimeInterval {
        entries.compactMap { $0.duration }.reduce(0, +)
    }

    private let saveURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("TangoDisplay")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("setlist.json")
    }()

    init() { load() }

    // MARK: - Queue mutations (all called on main)

    func addURLs(_ urls: [URL]) {
        insertURLs(urls, before: nil)
    }

    // anchorID is the UUID of the entry to insert before; nil means append to end.
    // Capturing a UUID (rather than an Int) prevents stale-index bugs when the
    // list mutates during the async metadata read.
    func insertURLs(_ urls: [URL], before anchorID: UUID?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            var collected: [SetlistEntry] = []
            for url in urls {
                guard isAudioURL(url) else { continue }
                let track = await SetlistManager.readMetadata(from: url)
                collected.append(SetlistEntry(fileURL: url, track: track))
            }
            self.insert(collected, before: anchorID)
        }
    }

    func insert(_ newEntries: [SetlistEntry], before anchorID: UUID?) {
        let index = anchorID
            .flatMap { id in entries.firstIndex(where: { $0.id == id }) }
            ?? entries.count
        entries.insert(contentsOf: newEntries, at: index)
        save()
        loadMissingDurations()
    }

    func remove(at offsets: IndexSet) {
        if let stopID = stopAfterEntryID, offsets.map({ entries[$0].id }).contains(stopID) {
            stopAfterEntryID = nil
        }
        entries.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        // Filter out played/playing entries — they cannot be reordered.
        // Using filter (not reject) handles the case where a playing track is
        // selected alongside queued tracks and SwiftUI includes all selected
        // indices in the drag source.
        let movable = IndexSet(source.filter {
            let s = entries[$0].state
            return s == .queued || s == .paused
        })
        guard !movable.isEmpty else { return }
        entries.move(fromOffsets: movable, toOffset: destination)
        save()
    }

    func clear() {
        stopAfterEntryID = nil
        duplicateSessionDecision = nil
        entries.removeAll()
        save()
    }

    // MARK: - Playback state tracking

    func markPlaying(id: UUID) {
        for i in entries.indices {
            if entries[i].id == id {
                entries[i].state = .playing
            } else if entries[i].state == .playing || entries[i].state == .paused {
                entries[i].state = .played
            }
        }
    }

    func markPaused(id: UUID) {
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].state = .paused
        }
    }

    func markQueued(id: UUID) {
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].state = .queued
        }
    }

    func markPlayed(id: UUID) {
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].state = .played
        }
    }

    func markPlayed(ids: Set<UUID>) {
        for i in entries.indices where ids.contains(entries[i].id) {
            entries[i].state = .played
        }
        save()
    }

    func markUnplayed(ids: Set<UUID>) {
        for i in entries.indices where ids.contains(entries[i].id) {
            entries[i].state = .queued
        }
        save()
    }

    func remove(ids: Set<UUID>) {
        if let stopID = stopAfterEntryID, ids.contains(stopID) {
            stopAfterEntryID = nil
        }
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func entry(after id: UUID) -> SetlistEntry? {
        guard let i = entries.firstIndex(where: { $0.id == id }), i + 1 < entries.count else { return nil }
        return entries[i + 1]
    }

    func firstUnplayed(after id: UUID) -> SetlistEntry? {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries[(i + 1)...].first(where: { $0.state != .played })
    }

    func entry(before id: UUID) -> SetlistEntry? {
        guard let i = entries.firstIndex(where: { $0.id == id }), i > 0 else { return nil }
        return entries[i - 1]
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              var decoded = try? JSONDecoder().decode([SetlistEntry].self, from: data) else { return }
        decoded = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        for i in decoded.indices where decoded[i].state == .playing || decoded[i].state == .paused {
            decoded[i].state = .queued
        }
        entries = decoded
        loadMissingDurations()
    }

    private func loadMissingDurations() {
        let needsLoad = entries.filter { $0.duration == nil }.map { $0.id }
        for id in needsLoad {
            Task {
                guard let idx = self.entries.firstIndex(where: { $0.id == id }) else { return }
                let url = self.entries[idx].fileURL
                let asset = AVURLAsset(url: url)
                guard let cmDuration = try? await asset.load(.duration) else { return }
                let seconds = CMTimeGetSeconds(cmDuration)
                guard seconds.isFinite && seconds > 0 else { return }
                await MainActor.run {
                    guard let i = self.entries.firstIndex(where: { $0.id == id }) else { return }
                    self.entries[i].duration = seconds
                    self.save()
                }
            }
        }
    }

    // MARK: - Metadata reading

    static func readMetadata(from url: URL) async -> Track {
        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.metadata)) ?? []

        // Treat empty strings the same as missing: return nil so the ?? chain keeps searching.
        func string(for id: AVMetadataIdentifier) -> String? {
            guard let val = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: id)
                .first?.stringValue, !val.isEmpty else { return nil }
            return val
        }

        // Raw-key scan for formats (FLAC/Vorbis) where AVFoundation has no typed identifier,
        // also catches stray tags where identifier mapping fails.
        func string(forRawKey rawKey: String) -> String? {
            guard let val = metadata
                .first(where: { ($0.key as? String)?.lowercased() == rawKey.lowercased() })?
                .stringValue, !val.isEmpty else { return nil }
            return val
        }

        // Skips Apple machine-generated COMM frames (iTunNORM, iTunSMPB, iTunPGAP, etc.) that
        // store binary data as hex strings — AVFoundation returns all COMM frames and .first may
        // land on one of these instead of the human-readable comment.
        func humanReadableComment() -> String? {
            let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .id3MetadataComments)
            for item in items {
                let info = item.extraAttributes?[AVMetadataExtraAttributeKey.info] as? String ?? ""
                guard !info.hasPrefix("iTun") else { continue }
                if let val = item.stringValue, !val.isEmpty { return val }
            }
            return nil
        }

        // M4A predefined genre: `gnre` atom stores an integer (ID3v1 index + 1).
        // Music.app uses this when the user picks from its genre dropdown rather than typing.
        func predefinedGenreName() -> String? {
            guard let item = AVMetadataItem.metadataItems(
                from: metadata, filteredByIdentifier: .iTunesMetadataPredefinedGenre).first
            else { return nil }
            if let str = item.stringValue, !str.isEmpty { return str }
            guard let n = item.numberValue?.intValue, n > 0, n <= id3GenreNames.count
            else { return nil }
            return id3GenreNames[n - 1]
        }

        let title = string(for: .commonIdentifierTitle)
            ?? url.deletingPathExtension().lastPathComponent
        let artist = string(for: .commonIdentifierArtist) ?? ""
        // Genre: search across all common tagging conventions; empty values are treated as absent
        // so a stale empty tag in one keyspace doesn't block lookup in the next.
        let genre = string(for: .id3MetadataContentType)   // MP3: TCON frame
            ?? string(for: .iTunesMetadataUserGenre)         // M4A: ©gen text atom
            ?? predefinedGenreName()                         // M4A: gnre integer atom (Music.app dropdown)
            ?? string(forRawKey: "genre")                    // FLAC/Vorbis comment
            ?? string(forRawKey: "tcon")                     // raw ID3 key fallback
            ?? SetlistManager.genreFromAudioToolbox(url)     // AIFF ID3 chunk (AVFoundation misses these)
            ?? ""

        let year: Int? = string(for: .id3MetadataYear).flatMap { Int($0) }
            ?? string(for: .iTunesMetadataReleaseDate).flatMap { Int(String($0.prefix(4))) }
        let comment = humanReadableComment()
            ?? string(for: .iTunesMetadataUserComment)
        let albumArtist = string(for: .id3MetadataBand)
            ?? string(for: .iTunesMetadataAlbumArtist)

        return Track(
            title: title,
            artist: artist,
            genre: genre,
            persistentID: url.absoluteString,
            year: year,
            comment: comment,
            albumArtist: albumArtist
        )
    }

    private static func genreFromAudioToolbox(_ url: URL) -> String? {
        var audioFile: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &audioFile) == noErr,
              let af = audioFile else { return nil }
        defer { AudioFileClose(af) }

        var dataSize = UInt32(MemoryLayout<CFDictionary?>.size)
        var cfDict: CFDictionary?
        guard AudioFileGetProperty(af, kAudioFilePropertyInfoDictionary, &dataSize, &cfDict) == noErr,
              let info = cfDict as? [String: Any],
              let genre = info[kAFInfoDictionary_Genre as String] as? String,
              !genre.isEmpty else { return nil }
        return genre
    }
}

private func isAudioURL(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return ["mp3", "m4a", "aiff", "aif", "wav", "flac", "caf", "opus"].contains(ext)
}

// Standard iTunes/ID3v1/Winamp genre list (192 entries).
// The M4A `gnre` atom stores (index + 1), so gnre=114 → index 113 → "Tango".
private let id3GenreNames: [String] = [
    "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge",
    "Hip-Hop", "Jazz", "Metal", "New Age", "Oldies", "Other", "Pop", "R&B",
    "Rap", "Reggae", "Rock", "Techno", "Industrial", "Alternative", "Ska",
    "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop",
    "Vocal", "Jazz+Funk", "Fusion", "Trance", "Classical", "Instrumental",
    "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise", "AlternRock",
    "Bass", "Soul", "Punk", "Space", "Meditative", "Instrumental Pop",
    "Instrumental Rock", "Ethnic", "Gothic", "Darkwave", "Techno-Industrial",
    "Electronic", "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy",
    "Cult", "Gangsta", "Top 40", "Christian Rap", "Pop/Funk", "Jungle",
    "Native American", "Cabaret", "New Wave", "Psychedelic", "Rave", "Showtunes",
    "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro",
    "Musical", "Rock & Roll", "Hard Rock",
    // Winamp extensions (80+)
    "Folk", "Folk-Rock", "National Folk", "Swing", "Fast Fusion", "Bebop",
    "Latin", "Revival", "Celtic", "Bluegrass", "Avantgarde", "Gothic Rock",
    "Progressive Rock", "Psychedelic Rock", "Symphonic Rock", "Slow Rock",
    "Big Band", "Chorus", "Easy Listening", "Acoustic", "Humour", "Speech",
    "Chanson", "Opera", "Chamber Music", "Sonata", "Symphony", "Booty Bass",
    "Primus", "Porn Groove", "Satire", "Slow Jam", "Club",
    "Tango",         // index 113
    "Samba", "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle",
    "Duet", "Punk Rock", "Drum Solo", "A Cappella", "Euro-House", "Dance Hall",
    "Goa", "Drum & Bass", "Club-House", "Hardcore", "Terror", "Indie",
    "BritPop", "Negerpunk", "Polsk Punk", "Beat", "Christian Gangsta Rap",
    "Heavy Metal", "Black Metal", "Crossover", "Contemporary Christian",
    "Christian Rock", "Merengue", "Salsa", "Thrash Metal", "Anime", "JPop",
    "Synthpop",
]
