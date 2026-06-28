// Lightweight test runner — no XCTest or Xcode required.
// Run with: swift run TangoDisplayTests
//
// Convention:
//   suite("SuiteName") { ... }      — groups tests, prints header
//   test("name") { ... }            — individual test, catches thrown errors
//   expect(_ condition, file:line:) — assertion; throws on failure

import Foundation
import TangoDisplayCore

// MARK: - Minimal test framework

private var totalPassed = 0
private var totalFailed = 0
private var currentSuite = ""

struct TestFailure: Error {
    let message: String
    let file: StaticString
    let line: Int
}

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String = "",
    file: StaticString = #file,
    line: Int = #line
) throws {
    guard condition() else {
        let msg = message.isEmpty ? "Assertion failed" : message
        throw TestFailure(message: msg, file: file, line: line)
    }
}

func expectEqual<T: Equatable>(
    _ a: T,
    _ b: T,
    file: StaticString = #file,
    line: Int = #line
) throws {
    try expect(a == b, "Expected \(a) == \(b)", file: file, line: line)
}

func expectNil<T>(_ value: T?, file: StaticString = #file, line: Int = #line) throws {
    try expect(value == nil, "Expected nil but got \(String(describing: value))", file: file, line: line)
}

func expectNotNil<T>(_ value: T?, file: StaticString = #file, line: Int = #line) throws {
    try expect(value != nil, "Expected non-nil value", file: file, line: line)
}

func suite(_ name: String, _ body: () -> Void) {
    currentSuite = name
    print("\n── \(name) ──")
    body()
}

func test(_ name: String, body: () throws -> Void) {
    do {
        try body()
        print("  ✓ \(name)")
        totalPassed += 1
    } catch let failure as TestFailure {
        print("  ✗ \(name)")
        print("      \(failure.message) (\(failure.file):\(failure.line))")
        totalFailed += 1
    } catch {
        print("  ✗ \(name) — unexpected error: \(error)")
        totalFailed += 1
    }
}

// MARK: - CortinaDetector tests

func runCortinaDetectorTests() {
    suite("CortinaDetector — Allowlist only") {
        test("matching genre is cortina") {
            let d = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                    useDenylist: false, denylistGenres: [])
            try expect(d.isCortina(genre: "Cortina"))
        }
        test("non-matching genre is not cortina") {
            let d = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                    useDenylist: false, denylistGenres: [])
            try expect(!d.isCortina(genre: "Tango"))
        }
        test("case insensitive — CORTINA") {
            let d = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                    useDenylist: false, denylistGenres: [])
            try expect(d.isCortina(genre: "CORTINA"))
            try expect(d.isCortina(genre: "cortina"))
            try expect(d.isCortina(genre: "Cortina"))
        }
        test("empty genre is NOT cortina under allowlist-only") {
            let d = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                    useDenylist: false, denylistGenres: [])
            try expect(!d.isCortina(genre: ""))
        }
    }

    suite("CortinaDetector — Denylist only") {
        let d = CortinaDetector(useAllowlist: false, allowlistGenres: [],
                                useDenylist: true, denylistGenres: ["tango", "vals", "milonga"])
        test("dance genre is not cortina") {
            try expect(!d.isCortina(genre: "Tango"))
            try expect(!d.isCortina(genre: "Vals"))
            try expect(!d.isCortina(genre: "Milonga"))
        }
        test("non-dance genre is cortina") {
            try expect(d.isCortina(genre: "Pop"))
            try expect(d.isCortina(genre: "Cortina"))
        }
        test("empty genre is cortina") {
            try expect(d.isCortina(genre: ""))
        }
        test("case insensitive — TANGO") {
            try expect(!d.isCortina(genre: "TANGO"))
            try expect(!d.isCortina(genre: "Vals"))
        }
    }

    suite("CortinaDetector — Both rules (EITHER match → cortina)") {
        let d = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                useDenylist: true, denylistGenres: ["tango", "vals", "milonga"])
        test("allowlist match is cortina") {
            try expect(d.isCortina(genre: "Cortina"))
        }
        test("denylist match is cortina (Pop not in dance genres)") {
            try expect(d.isCortina(genre: "Pop"))
        }
        test("dance genre is NOT cortina") {
            try expect(!d.isCortina(genre: "Tango"))
        }
    }

    suite("CortinaDetector — Neither rule") {
        let d = CortinaDetector(useAllowlist: false, allowlistGenres: ["cortina"],
                                useDenylist: false, denylistGenres: ["tango"])
        test("never cortina") {
            try expect(!d.isCortina(genre: "Cortina"))
            try expect(!d.isCortina(genre: "Pop"))
            try expect(!d.isCortina(genre: ""))
            try expect(!d.isCortina(genre: "Tango"))
        }
    }

    suite("CortinaDetector — Denylist partial match") {
        let d = CortinaDetector(useAllowlist: false, allowlistGenres: [],
                                useDenylist: true, denylistGenres: ["tango", "vals", "milonga"],
                                denylistPartialGenres: ["tango", "vals", "milonga"])
        test("exact match still not cortina") {
            try expect(!d.isCortina(genre: "Tango"))
            try expect(!d.isCortina(genre: "Vals"))
            try expect(!d.isCortina(genre: "Milonga"))
        }
        test("prefix match with space — not cortina") {
            try expect(!d.isCortina(genre: "Tango Instrumental"))
            try expect(!d.isCortina(genre: "Tango Vocals"))
            try expect(!d.isCortina(genre: "Vals Instrumental"))
            try expect(!d.isCortina(genre: "Milonga Vocal"))
        }
        test("case insensitive prefix match — not cortina") {
            try expect(!d.isCortina(genre: "tango instrumental"))
            try expect(!d.isCortina(genre: "TANGO VOCALS"))
        }
        test("no space after term — is cortina") {
            try expect(d.isCortina(genre: "Tangoed"))
            try expect(d.isCortina(genre: "Valses"))
        }
        test("unrelated genre — is cortina") {
            try expect(d.isCortina(genre: "Pop"))
            try expect(d.isCortina(genre: "Cortina"))
        }

        let noPartial = CortinaDetector(useAllowlist: false, allowlistGenres: [],
                                        useDenylist: true, denylistGenres: ["tango", "vals", "milonga"])
        test("without partial match, Tango Instrumental IS cortina") {
            try expect(noPartial.isCortina(genre: "Tango Instrumental"))
        }
        test("without partial match, exact Tango is still NOT cortina") {
            try expect(!noPartial.isCortina(genre: "Tango"))
        }
    }

    suite("CortinaDetector — Whitespace trimming") {
        let denyOnly = CortinaDetector(useAllowlist: false, allowlistGenres: [],
                                       useDenylist: true, denylistGenres: ["tango", "vals", "milonga"])
        test("leading space on denylist genre is NOT cortina") {
            try expect(!denyOnly.isCortina(genre: " Tango"))
        }
        test("trailing space on denylist genre is NOT cortina") {
            try expect(!denyOnly.isCortina(genre: "Tango "))
        }
        test("leading and trailing spaces is NOT cortina") {
            try expect(!denyOnly.isCortina(genre: "  Tango  "))
        }
        test("tab-padded denylist genre is NOT cortina") {
            try expect(!denyOnly.isCortina(genre: "\tTango"))
        }

        let allowOnly = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                        useDenylist: false, denylistGenres: [])
        test("leading space on allowlist genre IS cortina") {
            try expect(allowOnly.isCortina(genre: " Cortina"))
        }
        test("trailing space on allowlist genre IS cortina") {
            try expect(allowOnly.isCortina(genre: "Cortina "))
        }

        let both = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                   useDenylist: true, denylistGenres: ["tango", "vals", "milonga"])
        test("both rules: spaced Tango is NOT cortina") {
            try expect(!both.isCortina(genre: " Tango"))
        }
        test("both rules: spaced Cortina IS cortina") {
            try expect(both.isCortina(genre: " Cortina"))
        }

        test("spaces-only genre treated as empty -> cortina under denylist") {
            try expect(denyOnly.isCortina(genre: "   "))
        }
    }
}

// MARK: - TandaTracker tests

func runTandaTrackerTests() {
    let tracker = TandaTracker()
    let detector = CortinaDetector(useAllowlist: true, allowlistGenres: ["cortina"],
                                   useDenylist: false, denylistGenres: [])

    func tracks(_ genres: [String]) -> [Track] {
        genres.enumerated().map { i, g in
            Track(title: "T\(i)", artist: "A", genre: g, persistentID: "\(i)")
        }
    }

    suite("TandaTracker — Playlist-based position") {
        test("first track of tanda") {
            // C T T T C
            let t = tracks(["Cortina", "Tango", "Tango", "Tango", "Cortina"])
            let pos = tracker.position(tracks: t, currentIndex: 1, detector: detector)
            try expectEqual(pos?.current, 1)
            try expectEqual(pos?.total, 3)
        }
        test("mid-tanda") {
            let t = tracks(["Cortina", "Tango", "Tango", "Tango", "Cortina"])
            let pos = tracker.position(tracks: t, currentIndex: 2, detector: detector)
            try expectEqual(pos?.current, 2)
            try expectEqual(pos?.total, 3)
        }
        test("last track of tanda") {
            let t = tracks(["Cortina", "Tango", "Tango", "Tango", "Cortina"])
            let pos = tracker.position(tracks: t, currentIndex: 3, detector: detector)
            try expectEqual(pos?.current, 3)
            try expectEqual(pos?.total, 3)
        }
        test("single-track tanda") {
            let t = tracks(["Cortina", "Tango", "Cortina"])
            let pos = tracker.position(tracks: t, currentIndex: 1, detector: detector)
            try expectEqual(pos?.current, 1)
            try expectEqual(pos?.total, 1)
        }
        test("tanda at start of playlist (no leading cortina)") {
            let t = tracks(["Tango", "Tango", "Tango", "Cortina"])
            let pos = tracker.position(tracks: t, currentIndex: 1, detector: detector)
            try expectEqual(pos?.current, 2)
            try expectEqual(pos?.total, 3)
        }
        test("tanda at end of playlist (no trailing cortina)") {
            let t = tracks(["Cortina", "Tango", "Tango", "Tango"])
            let pos = tracker.position(tracks: t, currentIndex: 3, detector: detector)
            try expectEqual(pos?.current, 3)
            try expectEqual(pos?.total, 3)
        }
        test("current is cortina → returns nil") {
            let t = tracks(["Cortina", "Tango"])
            let pos = tracker.position(tracks: t, currentIndex: 0, detector: detector)
            try expectNil(pos)
        }
        test("out of bounds → returns nil") {
            let t = tracks(["Tango"])
            try expectNil(tracker.position(tracks: t, currentIndex: -1, detector: detector))
            try expectNil(tracker.position(tracks: t, currentIndex: 5, detector: detector))
        }
        test("second tanda in playlist") {
            // C T T C T T T C
            let t = tracks(["Cortina", "Tango", "Tango", "Cortina", "Tango", "Tango", "Tango", "Cortina"])
            let pos = tracker.position(tracks: t, currentIndex: 5, detector: detector)
            try expectEqual(pos?.current, 2)
            try expectEqual(pos?.total, 3)
        }
    }

    suite("TandaTracker — History-based position") {
        func h(_ n: Int) -> [Track] {
            (0..<n).map { Track(title: "T\($0)", artist: "A", genre: "Tango", persistentID: "\($0)") }
        }
        test("single track") {
            let pos = tracker.positionFromHistory(h(1))
            try expectEqual(pos?.current, 1)
            try expectNil(pos?.total)
        }
        test("multiple tracks") {
            let pos = tracker.positionFromHistory(h(3))
            try expectEqual(pos?.current, 3)
            try expectNil(pos?.total)
        }
        test("empty history returns nil") {
            try expectNil(tracker.positionFromHistory([]))
        }
    }
}

// MARK: - ProfileStore tests

func runProfileStoreTests() {
    suite("ProfileStore — Round-trip save/load/delete") {
        test("save and reload user profile") {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TangoDisplayTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = ProfileStore(storeURL: tmpDir)
            let profile = AppearanceProfile(
                id: UUID(), name: "Test Profile", isBuiltIn: false,
                backgroundColor: "#FF0000"
            )
            try store.save(profile)

            // Load from disk into a fresh store
            let store2 = ProfileStore(storeURL: tmpDir)
            store2.load()
            try expect(store2.userProfiles.count == 1, "Expected 1 user profile, got \(store2.userProfiles.count)")
            try expectEqual(store2.userProfiles[0].id, profile.id)
            try expectEqual(store2.userProfiles[0].backgroundColor, "#FF0000")
        }

        test("update existing profile") {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TangoDisplayTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = ProfileStore(storeURL: tmpDir)
            var profile = AppearanceProfile(id: UUID(), name: "A", isBuiltIn: false)
            try store.save(profile)
            profile.name = "B"
            try store.save(profile)
            try expectEqual(store.userProfiles.count, 1)
            try expectEqual(store.userProfiles[0].name, "B")
        }

        test("delete user profile") {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TangoDisplayTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = ProfileStore(storeURL: tmpDir)
            let profile = AppearanceProfile(id: UUID(), name: "Del", isBuiltIn: false)
            try store.save(profile)
            try expectEqual(store.userProfiles.count, 1)
            try store.delete(profile)
            try expectEqual(store.userProfiles.count, 0)
            // Verify file is gone
            let fileURL = tmpDir.appendingPathComponent("\(profile.id.uuidString).json")
            try expect(!FileManager.default.fileExists(atPath: fileURL.path), "File should be deleted")
        }

        test("built-in profiles are never written to disk") {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TangoDisplayTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = ProfileStore(storeURL: tmpDir)
            do {
                try store.save(AppearanceProfile.classic)
                try expect(false, "Should have thrown for built-in profile")
            } catch ProfileStoreError.cannotModifyBuiltIn {
                // Expected
            }
            let files = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path)) ?? []
            try expect(files.isEmpty, "No files should exist for built-in profile")
        }

        test("delete built-in profile throws") {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TangoDisplayTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = ProfileStore(storeURL: tmpDir)
            do {
                try store.delete(AppearanceProfile.modern)
                try expect(false, "Should have thrown for built-in profile")
            } catch ProfileStoreError.cannotModifyBuiltIn {
                // Expected
            }
        }

        test("allProfiles prepends built-ins") {
            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TangoDisplayTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = ProfileStore(storeURL: tmpDir)
            let user = AppearanceProfile(id: UUID(), name: "My Profile", isBuiltIn: false)
            try store.save(user)
            let all = store.allProfiles
            try expect(all.count == AppearanceProfile.builtIns.count + 1)
            try expect(all.prefix(AppearanceProfile.builtIns.count)
                          .map(\.id) == AppearanceProfile.builtIns.map(\.id),
                       "Built-ins should come first")
        }
    }
}

// MARK: - DisplayState transition tests (pure logic, no AppKit)

func runDisplayStateTests() {
    // Helper: simulate the core logic that AppState applies
    let detector = CortinaDetector(
        useAllowlist: true, allowlistGenres: ["cortina"],
        useDenylist: true, denylistGenres: ["tango", "vals", "milonga"]
    )
    let tracker = TandaTracker()

    func track(_ title: String, genre: String, pid: String? = nil) -> Track {
        Track(title: title, artist: "A", genre: genre, persistentID: pid ?? title)
    }

    suite("DisplayState — Mode transitions") {
        test("stopped → idle") {
            var state = DisplayState(mode: .playing, currentTrack: track("A", genre: "Tango"))
            // Simulate stopping
            state = DisplayState()
            try expectEqual(state.mode, .idle)
            try expectNil(state.currentTrack)
        }

        test("playing → cortina clears tanda position") {
            var state = DisplayState(mode: .playing,
                                     currentTrack: track("A", genre: "Tango"),
                                     tandaPosition: TandaPosition(current: 2, total: 4))
            let cortina = track("C", genre: "Cortina")
            state = DisplayState(mode: .cortina, currentTrack: cortina)
            try expectEqual(state.mode, .cortina)
            try expectNil(state.tandaPosition)
        }

        test("cortina → playing sets mode correctly") {
            var state = DisplayState(mode: .cortina)
            let tango = track("A", genre: "Tango")
            let pos = tracker.positionFromHistory([tango])
            state = DisplayState(mode: .playing, currentTrack: tango, tandaPosition: pos)
            try expectEqual(state.mode, .playing)
            try expectEqual(state.currentTrack?.genre, "Tango")
            try expectEqual(state.tandaPosition?.current, 1)
        }

        test("override mode ignores track updates") {
            var state = DisplayState(mode: .override, overrideText: "Custom Message")
            // Simulate logic: if mode == .override, don't update
            let newTrack = track("NewTrack", genre: "Tango")
            let shouldUpdate = state.mode != .override
            if shouldUpdate { state.currentTrack = newTrack }
            try expectEqual(state.mode, .override)
            try expect(state.currentTrack == nil, "Override mode should ignore track changes")
            try expectEqual(state.overrideText, "Custom Message")
        }

        test("override cleared returns to idle") {
            var state = DisplayState(mode: .override, overrideText: "Custom")
            state = DisplayState()  // clearOverride resets to idle
            try expectEqual(state.mode, .idle)
            try expectNil(state.overrideText)
        }

        test("empty genre treated as cortina under denylist") {
            let isCortina = detector.isCortina(genre: "")
            try expect(isCortina, "Empty genre should be detected as cortina")
        }

        test("paused mode preserves content") {
            let tango = track("A", genre: "Tango")
            var state = DisplayState(mode: .playing, currentTrack: tango,
                                     tandaPosition: TandaPosition(current: 2, total: 4))
            // Simulate pause: change mode only
            state.mode = .paused
            try expectEqual(state.mode, .paused)
            try expectEqual(state.currentTrack?.title, "A")
            try expectEqual(state.tandaPosition?.current, 2)
        }

        test("next track set during cortina") {
            let cortina = track("C", genre: "Cortina")
            let nextTango = track("Di Sarli", genre: "Tango")
            let state = DisplayState(mode: .cortina, currentTrack: cortina, nextTrack: nextTango)
            try expectEqual(state.mode, .cortina)
            try expectEqual(state.nextTrack?.title, "Di Sarli")
        }

        test("upcoming track uses cortina's real position, not stale index") {
            // Playlist: dance, dance, cortina, dance, dance
            // Simulates the user skipping to the cortina at index 2 while
            // playlistCurrentIndex is stale at 0.
            let tracks: [Track] = [
                track("D1", genre: "Tango",   pid: "d1"),
                track("D2", genre: "Tango",   pid: "d2"),
                track("C1", genre: "Cortina", pid: "c1"),
                track("D3", genre: "Tango",   pid: "d3"),
                track("D4", genre: "Tango",   pid: "d4"),
            ]
            let cortina = tracks[2]

            // Simulate stale index (pointing before the cortina)
            var staleIndex = 0
            // Anchor to real position via persistentID lookup (the fix)
            if let idx = tracks.firstIndex(where: { $0.persistentID == cortina.persistentID }) {
                staleIndex = idx
            }
            // Forward scan from correct position
            let startSearch = staleIndex + 1
            let nextTrack = startSearch < tracks.count
                ? tracks[startSearch...].first { !detector.isCortina(genre: $0.genre) }
                : nil

            try expect(nextTrack?.persistentID == "d3",
                       "Upcoming track should be D3 (after the cortina), not D1")
        }

        test("upcoming track is nil when cortina is last in playlist") {
            let tracks: [Track] = [
                track("D1", genre: "Tango",   pid: "d1"),
                track("C1", genre: "Cortina", pid: "c1"),
            ]
            let cortina = tracks[1]
            var idx = 0
            if let i = tracks.firstIndex(where: { $0.persistentID == cortina.persistentID }) {
                idx = i
            }
            let startSearch = idx + 1
            let nextTrack = startSearch < tracks.count
                ? tracks[startSearch...].first { !detector.isCortina(genre: $0.genre) }
                : nil
            try expect(nextTrack == nil, "No upcoming track when cortina is last in playlist")
        }

        test("playlist-based tanda position during playing") {
            let tracks: [Track] = [
                track("C1", genre: "Cortina", pid: "c1"),
                track("T1", genre: "Tango", pid: "t1"),
                track("T2", genre: "Tango", pid: "t2"),
                track("T3", genre: "Tango", pid: "t3"),
                track("C2", genre: "Cortina", pid: "c2"),
            ]
            let pos = tracker.position(tracks: tracks, currentIndex: 2, detector: detector)
            let state = DisplayState(mode: .playing,
                                     currentTrack: tracks[2],
                                     tandaPosition: pos)
            try expectEqual(state.tandaPosition?.current, 2)
            try expectEqual(state.tandaPosition?.total, 3)
        }
    }
}

// MARK: - ReplayGain tests

func runReplayGainTests() {
    suite("parseReplayGainDb") {
        test("parses negative dB with unit") {
            try expectEqual(parseReplayGainDb("-7.23 dB"), -7.23)
        }
        test("parses positive dB with unit") {
            try expectEqual(parseReplayGainDb("+3.00 dB"), 3.0)
        }
        test("parses negative dB without unit") {
            try expectEqual(parseReplayGainDb("-5.4"), -5.4)
        }
        test("parses value with uppercase DB") {
            try expectEqual(parseReplayGainDb("-2.0 DB"), -2.0)
        }
        test("returns nil for non-numeric") {
            try expectNil(parseReplayGainDb("abc dB"))
        }
        test("returns nil for nil input") {
            try expectNil(parseReplayGainDb(nil))
        }
        test("returns nil for empty string") {
            try expectNil(parseReplayGainDb(""))
        }
    }

    suite("calculateReplayGainLinear — mode off") {
        test("always returns 1.0 when mode is off") {
            let info = ReplayGainInfo(trackGainDb: -7.0, trackPeak: 0.95, albumGainDb: -6.0, albumPeak: 0.90)
            let settings = ReplayGainSettings(mode: .off, preampDb: 0, preventClipping: false)
            try expectEqual(calculateReplayGainLinear(info: info, settings: settings), 1.0)
        }
        test("returns 1.0 when mode is off and info is nil") {
            let settings = ReplayGainSettings(mode: .off, preampDb: 0, preventClipping: false)
            try expectEqual(calculateReplayGainLinear(info: nil, settings: settings), 1.0)
        }
    }

    suite("calculateReplayGainLinear — track gain mode") {
        test("applies track gain correctly") {
            let info = ReplayGainInfo(trackGainDb: -6.0206, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: false)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            // -6.0206 dB ≈ 0.5 linear
            try expect(abs(gain - 0.5) < 0.001, "Expected ~0.5, got \(gain)")
        }
        test("returns 1.0 when track gain is missing") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: 0.95, albumGainDb: -5.0, albumPeak: 0.90)
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: false)
            try expectEqual(calculateReplayGainLinear(info: info, settings: settings), 1.0)
        }
        test("returns 1.0 when info is nil") {
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: false)
            try expectEqual(calculateReplayGainLinear(info: nil, settings: settings), 1.0)
        }
        test("returns 1.0 when all fields are nil") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: false)
            try expectEqual(calculateReplayGainLinear(info: info, settings: settings), 1.0)
        }
    }

    suite("calculateReplayGainLinear — album gain mode") {
        test("applies album gain correctly") {
            let info = ReplayGainInfo(trackGainDb: -7.0, trackPeak: 0.95, albumGainDb: -5.0, albumPeak: 0.90)
            let settings = ReplayGainSettings(mode: .album, preampDb: 0, preventClipping: false)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            let expected = Float(pow(10.0, -5.0 / 20.0))
            try expect(abs(gain - expected) < 0.0001, "Expected \(expected), got \(gain)")
        }
        test("returns 1.0 when album gain is missing even if track gain is present") {
            let info = ReplayGainInfo(trackGainDb: -7.0, trackPeak: 0.95, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .album, preampDb: 0, preventClipping: false)
            try expectEqual(calculateReplayGainLinear(info: info, settings: settings), 1.0)
        }
    }

    suite("calculateReplayGainLinear — preamp") {
        test("adds preamp dB to gain") {
            let info = ReplayGainInfo(trackGainDb: 0.0, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: 6.0, preventClipping: false)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            let expected = Float(pow(10.0, 6.0 / 20.0))
            try expect(abs(gain - expected) < 0.0001, "Expected \(expected), got \(gain)")
        }
        test("negative preamp reduces gain") {
            let info = ReplayGainInfo(trackGainDb: 0.0, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: -6.0, preventClipping: false)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            let expected = Float(pow(10.0, -6.0 / 20.0))
            try expect(abs(gain - expected) < 0.0001, "Expected \(expected), got \(gain)")
        }
    }

    suite("calculateReplayGainLinear — clipping protection") {
        test("reduces gain when gain * peak exceeds 1.0") {
            // +4 dB gain with peak 0.90 → linear ≈ 1.585 * 0.90 > 1.0, should clamp to 1/0.90
            let info = ReplayGainInfo(trackGainDb: 4.0, trackPeak: 0.90, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: true)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            let maxGain = Float(1.0 / 0.90)
            try expect(abs(gain - maxGain) < 0.0001, "Expected \(maxGain), got \(gain)")
        }
        test("does not reduce gain when clipping protection is off") {
            let info = ReplayGainInfo(trackGainDb: 4.0, trackPeak: 0.90, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: false)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            let expected = Float(pow(10.0, 4.0 / 20.0))
            try expect(abs(gain - expected) < 0.0001, "Expected \(expected), got \(gain)")
        }
        test("no clipping reduction needed when gain * peak is within 1.0") {
            // -7.23 dB gain with peak 0.95 → linear ≈ 0.436 * 0.95 < 1.0, no clamping
            let info = ReplayGainInfo(trackGainDb: -7.23, trackPeak: 0.95, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: true)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            let expected = Float(pow(10.0, -7.23 / 20.0))
            try expect(abs(gain - expected) < 0.0001, "Expected \(expected), got \(gain)")
        }
        test("skips clipping check when peak is nil") {
            let info = ReplayGainInfo(trackGainDb: 4.0, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let settings = ReplayGainSettings(mode: .track, preampDb: 0, preventClipping: true)
            let gain = calculateReplayGainLinear(info: info, settings: settings)
            let expected = Float(pow(10.0, 4.0 / 20.0))
            try expect(abs(gain - expected) < 0.0001, "Expected \(expected), got \(gain)")
        }
    }
}

// MARK: - Auto ReplayGain tests

func runAutoReplayGainTests() {

    // MARK: Helpers

    func makeAnalysis(gainDb: Double, lufs: Double, samplePeak: Double? = nil,
                      truePeak: Double? = nil) -> LoudnessAnalysisResult {
        LoudnessAnalysisResult(
            filePath: "/fake/track.flac", fileSize: 1_000_000,
            modifiedDate: Date(), duration: 180,
            integratedLoudnessLufs: lufs, calculatedReplayGainDb: gainDb,
            targetLoudnessLufs: -18.0,
            samplePeak: samplePeak, truePeak: truePeak, analysedAt: Date())
    }

    func baseSettings(mode: ReplayGainMode, preventClipping: Bool = false,
                       preamp: Double = 0) -> ReplayGainSettings {
        ReplayGainSettings(mode: mode, preampDb: preamp,
                           preventClipping: preventClipping, targetLoudnessLufs: -18.0)
    }

    // MARK: calculateReplayGain — auto mode

    suite("calculateReplayGain — auto mode") {
        test("uses track metadata when present, ignores analysis") {
            let info = ReplayGainInfo(trackGainDb: -7.0, trackPeak: nil, albumGainDb: -5.0, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: -3.0, lufs: -15.0)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .auto))
            try expectEqual(result.source, .metadataTrack)
            let expected = Float(pow(10.0, -7.0 / 20.0))
            try expect(abs(result.linearGain - expected) < 0.0001,
                       "Expected ~\(expected), got \(result.linearGain)")
        }

        test("uses analysis when track metadata is absent") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: -7.1, lufs: -10.9)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .auto))
            try expectEqual(result.source, .analysed)
            let expected = Float(pow(10.0, -7.1 / 20.0))
            try expect(abs(result.linearGain - expected) < 0.0001,
                       "Expected ~\(expected), got \(result.linearGain)")
        }

        test("does not use album metadata in auto mode") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: -5.0, albumPeak: nil)
            let result = calculateReplayGain(info: info, analysis: nil,
                                              settings: baseSettings(mode: .auto))
            try expectEqual(result.source, .none)
            try expectEqual(result.linearGain, 1.0)
        }

        test("returns 1.0 when neither metadata nor analysis present") {
            let result = calculateReplayGain(info: nil, analysis: nil,
                                              settings: baseSettings(mode: .auto))
            try expectEqual(result.source, .none)
            try expectEqual(result.linearGain, 1.0)
        }

        test("integratedLoudnessLufs populated for analysed source") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: -7.1, lufs: -10.9)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .auto))
            try expect(result.integratedLoudnessLufs != nil, "Expected integratedLoudnessLufs to be set")
            try expect(abs(result.integratedLoudnessLufs! - (-10.9)) < 0.001,
                       "Expected -10.9, got \(result.integratedLoudnessLufs!)")
        }

        test("integratedLoudnessLufs is nil for metadata source") {
            let info = ReplayGainInfo(trackGainDb: -7.0, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let result = calculateReplayGain(info: info, analysis: nil,
                                              settings: baseSettings(mode: .auto))
            try expectNil(result.integratedLoudnessLufs)
        }
    }

    // MARK: calculateReplayGain — mode isolation

    suite("calculateReplayGain — mode isolation") {
        test("track mode ignores analysis") {
            let info = ReplayGainInfo(trackGainDb: -7.0, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: -3.0, lufs: -15.0)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .track))
            try expectEqual(result.source, .metadataTrack)
        }

        test("album mode ignores analysis") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: -5.0, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: -3.0, lufs: -15.0)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .album))
            try expectEqual(result.source, .metadataAlbum)
        }

        test("off mode ignores metadata and analysis") {
            let info = ReplayGainInfo(trackGainDb: -7.0, trackPeak: nil, albumGainDb: -5.0, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: -3.0, lufs: -15.0)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .off))
            try expectEqual(result.source, .none)
            try expectEqual(result.linearGain, 1.0)
        }
    }

    // MARK: calculateReplayGain — preamp with analysis

    suite("calculateReplayGain — preamp with analysed gain") {
        test("preamp applies to analysed gain") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: -7.0, lufs: -11.0)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .auto, preamp: 2.0))
            let expected = Float(pow(10.0, (-7.0 + 2.0) / 20.0))
            try expect(abs(result.linearGain - expected) < 0.0001,
                       "Expected ~\(expected), got \(result.linearGain)")
        }
    }

    // MARK: calculateReplayGain — clipping with analysis peaks

    suite("calculateReplayGain — clipping protection with analysed peaks") {
        test("uses samplePeak for clipping protection") {
            // gain +4 dB * samplePeak 0.90 > 1.0 → clamp to 1/0.90
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: 4.0, lufs: -22.0, samplePeak: 0.90)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .auto, preventClipping: true))
            let maxGain = Float(1.0 / 0.90)
            try expect(result.clippingProtectionApplied, "Expected clipping protection to be applied")
            try expect(abs(result.linearGain - maxGain) < 0.0001,
                       "Expected \(maxGain), got \(result.linearGain)")
        }

        test("prefers truePeak over samplePeak when both present") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            // truePeak is lower than samplePeak → truePeak is the binding constraint
            let analysis = makeAnalysis(gainDb: 4.0, lufs: -22.0, samplePeak: 0.90, truePeak: 0.85)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .auto, preventClipping: true))
            let maxGain = Float(1.0 / 0.85)
            try expect(result.clippingProtectionApplied, "Expected clipping protection to be applied")
            try expect(abs(result.linearGain - maxGain) < 0.0001,
                       "Expected \(maxGain) (truePeak), got \(result.linearGain)")
        }

        test("clipping off — full gain applied even when would clip") {
            let info = ReplayGainInfo(trackGainDb: nil, trackPeak: nil, albumGainDb: nil, albumPeak: nil)
            let analysis = makeAnalysis(gainDb: 4.0, lufs: -22.0, samplePeak: 0.90)
            let result = calculateReplayGain(info: info, analysis: analysis,
                                              settings: baseSettings(mode: .auto, preventClipping: false))
            let expected = Float(pow(10.0, 4.0 / 20.0))
            try expect(!result.clippingProtectionApplied, "Expected no clipping protection")
            try expect(abs(result.linearGain - expected) < 0.0001,
                       "Expected \(expected), got \(result.linearGain)")
        }
    }

    // MARK: LoudnessAnalysisCacheKey equality

    suite("LoudnessAnalysisCacheKey — equality (path + size + modDate only)") {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let key = LoudnessAnalysisCacheKey(filePath: "/music/track.flac",
                                            fileSize: 10_000_000,
                                            modifiedDate: date)

        test("identical keys are equal") {
            let key2 = LoudnessAnalysisCacheKey(filePath: "/music/track.flac",
                                                 fileSize: 10_000_000,
                                                 modifiedDate: date)
            try expect(key == key2, "Keys with same fields should be equal")
        }

        test("mismatch on fileSize") {
            let key2 = LoudnessAnalysisCacheKey(filePath: "/music/track.flac",
                                                 fileSize: 9_999_999,
                                                 modifiedDate: date)
            try expect(key != key2, "Keys should differ when fileSize changes")
        }

        test("mismatch on modifiedDate") {
            let key2 = LoudnessAnalysisCacheKey(filePath: "/music/track.flac",
                                                 fileSize: 10_000_000,
                                                 modifiedDate: Date(timeIntervalSince1970: 1_700_000_001))
            try expect(key != key2, "Keys should differ when modifiedDate changes")
        }

        test("duration variation does not affect key — prevents spurious cache misses") {
            // AVAudioFile may report slightly different frame counts across codec versions.
            // Cache key must be stable regardless of decoded duration precision.
            let k1 = LoudnessAnalysisCacheKey(filePath: "/music/a.m4a",
                                               fileSize: 5_000_000,
                                               modifiedDate: date)
            let k2 = LoudnessAnalysisCacheKey(filePath: "/music/a.m4a",
                                               fileSize: 5_000_000,
                                               modifiedDate: date)
            try expect(k1 == k2, "Keys must be equal regardless of any duration value")
        }

        test("mismatch on filePath") {
            let key2 = LoudnessAnalysisCacheKey(filePath: "/music/other.flac",
                                                 fileSize: 10_000_000,
                                                 modifiedDate: date)
            try expect(key != key2, "Keys should differ when filePath changes")
        }
    }
}

// MARK: - AudioUnitPlugin tests

func runAudioUnitPluginTests() {
    suite("Cleanup ledger") {
        test("failed detach resources remain owned and successful ones clear") {
            enum Failure: Error { case detach }
            let result = retainCleanupFailures([1, 2, 3]) { value in
                if value == 2 { throw Failure.detach }
            }
            try expectEqual(result.remaining, [2])
            try expectNotNil(result.firstError)
        }
    }

    suite("AudioUnitPluginSelection — model") {
        test("encodes and decodes round-trip") {
            let sel = AudioUnitPluginSelection(
                id: UUID(),
                name: "Test EQ",
                manufacturerName: "Acme Audio",
                componentType: 1635083896,
                componentSubType: 1162298982,
                componentManufacturer: 1634758764
            )
            let data = try JSONEncoder().encode(sel)
            let decoded = try JSONDecoder().decode(AudioUnitPluginSelection.self, from: data)
            try expectEqual(decoded.name, sel.name)
            try expectEqual(decoded.manufacturerName, sel.manufacturerName)
            try expectEqual(decoded.componentType, sel.componentType)
            try expectEqual(decoded.componentSubType, sel.componentSubType)
            try expectEqual(decoded.componentManufacturer, sel.componentManufacturer)
            try expectEqual(decoded.id, sel.id)
        }

        test("reconstructs component values from stored data") {
            let type: UInt32 = 1635083896
            let sub: UInt32  = 9999
            let mfr: UInt32  = 1634758764
            let sel = AudioUnitPluginSelection(
                name: "FX", manufacturerName: "Co",
                componentType: type, componentSubType: sub, componentManufacturer: mfr
            )
            let data = try JSONEncoder().encode(sel)
            let out = try JSONDecoder().decode(AudioUnitPluginSelection.self, from: data)
            try expectEqual(out.componentType, type)
            try expectEqual(out.componentSubType, sub)
            try expectEqual(out.componentManufacturer, mfr)
        }

        test("invalid JSON decodes safely to nil") {
            let bad = "not json".data(using: .utf8)!
            let result = try? JSONDecoder().decode(AudioUnitPluginSelection.self, from: bad)
            try expectNil(result)
        }

        test("Equatable — identical values are equal") {
            let id = UUID()
            let a = AudioUnitPluginSelection(id: id, name: "X", manufacturerName: "Y",
                                             componentType: 1, componentSubType: 2, componentManufacturer: 3)
            let b = AudioUnitPluginSelection(id: id, name: "X", manufacturerName: "Y",
                                             componentType: 1, componentSubType: 2, componentManufacturer: 3)
            try expect(a == b)
        }

        test("Equatable — different id is not equal") {
            let a = AudioUnitPluginSelection(name: "X", manufacturerName: "Y",
                                             componentType: 1, componentSubType: 2, componentManufacturer: 3)
            let b = AudioUnitPluginSelection(name: "X", manufacturerName: "Y",
                                             componentType: 1, componentSubType: 2, componentManufacturer: 3)
            try expect(a != b)
        }

        test("plugin slot state persists full component identity") {
            let state = PluginSlotState(
                slotID: UUID(), componentType: 11, componentSubType: 22,
                componentManufacturer: 33, auState: "state", isEnabled: true
            )
            let decoded = try JSONDecoder().decode(
                PluginSlotState.self,
                from: JSONEncoder().encode(state)
            )
            try expectEqual(decoded.componentType, 11)
            try expectEqual(decoded.componentSubType, 22)
            try expectEqual(decoded.componentManufacturer, 33)
        }

        test("legacy plugin slot state remains decodable") {
            let id = UUID()
            let json = """
            {"slotID":"\(id.uuidString)","componentSubType":22,"auState":"state","isEnabled":true}
            """.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(PluginSlotState.self, from: json)
            try expectEqual(decoded.slotID, id)
            try expectNil(decoded.componentType)
            try expectNil(decoded.componentManufacturer)
        }
    }

    suite("AudioUnitPluginStatus — display text") {
        test("disabled") {
            try expectEqual(AudioUnitPluginStatus.disabled.displayText, "Plugin: Disabled")
        }
        test("noPluginSelected") {
            try expectEqual(AudioUnitPluginStatus.noPluginSelected.displayText, "Plugin: No plugin selected")
        }
        test("loading") {
            try expectEqual(AudioUnitPluginStatus.loading("Focusrite Red 2 EQ").displayText,
                            "Plugin: Loading Focusrite Red 2 EQ…")
        }
        test("active") {
            try expectEqual(AudioUnitPluginStatus.active("MJUC").displayText, "Plugin: Active — MJUC")
        }
        test("bypassed") {
            try expectEqual(AudioUnitPluginStatus.bypassed("MJUC").displayText, "Plugin: Bypassed — MJUC")
        }
        test("unavailable") {
            try expectEqual(AudioUnitPluginStatus.unavailable("Focusrite Red 2 EQ").displayText,
                            "Plugin: Not available — Focusrite Red 2 EQ")
        }
        test("failed") {
            try expectEqual(AudioUnitPluginStatus.failed("REAMP", reason: "timeout").displayText,
                            "Plugin: Failed to load — REAMP")
        }
    }

    suite("AudioUnitPluginStatus — predicates") {
        test("isActive true only for active") {
            try expect(AudioUnitPluginStatus.active("X").isActive)
            try expect(!AudioUnitPluginStatus.disabled.isActive)
            try expect(!AudioUnitPluginStatus.loading("X").isActive)
            try expect(!AudioUnitPluginStatus.bypassed("X").isActive)
            try expect(!AudioUnitPluginStatus.failed("X", reason: "r").isActive)
        }
        test("isInert true for disabled and noPluginSelected") {
            try expect(AudioUnitPluginStatus.disabled.isInert)
            try expect(AudioUnitPluginStatus.noPluginSelected.isInert)
            try expect(!AudioUnitPluginStatus.active("X").isInert)
            try expect(!AudioUnitPluginStatus.loading("X").isInert)
            try expect(!AudioUnitPluginStatus.bypassed("X").isInert)
            try expect(!AudioUnitPluginStatus.unavailable("X").isInert)
            try expect(!AudioUnitPluginStatus.failed("X", reason: "r").isInert)
        }
        test("shortDisplayText empty for inert statuses") {
            try expectEqual(AudioUnitPluginStatus.disabled.shortDisplayText, "")
            try expectEqual(AudioUnitPluginStatus.noPluginSelected.shortDisplayText, "")
        }
        test("shortDisplayText non-empty for active statuses") {
            try expect(!AudioUnitPluginStatus.active("MJUC").shortDisplayText.isEmpty)
            try expect(!AudioUnitPluginStatus.bypassed("MJUC").shortDisplayText.isEmpty)
            try expect(!AudioUnitPluginStatus.loading("MJUC").shortDisplayText.isEmpty)
        }
        test("Equatable — same cases are equal") {
            try expect(AudioUnitPluginStatus.active("X") == AudioUnitPluginStatus.active("X"))
            try expect(AudioUnitPluginStatus.disabled == AudioUnitPluginStatus.disabled)
        }
        test("Equatable — different cases are not equal") {
            try expect(AudioUnitPluginStatus.active("X") != AudioUnitPluginStatus.bypassed("X"))
            try expect(AudioUnitPluginStatus.failed("X", reason: "a") != AudioUnitPluginStatus.failed("X", reason: "b"))
        }
    }
}

// MARK: - SmartAutoGap tests

func runSmartAutoGapTests() {
    suite("SmartAutoGap — exact injected duration") {
        test("subtracts trailing and leading silence from target") {
            try expectEqual(SmartAutoGap.injectedDuration(target: 5, trailing: 1, leading: 1), 3)
        }
        test("returns zero when intrinsic silence equals target") {
            try expectEqual(SmartAutoGap.injectedDuration(target: 5, trailing: 2, leading: 3), 0)
        }
        test("returns zero when intrinsic silence exceeds target") {
            try expectEqual(SmartAutoGap.injectedDuration(target: 5, trailing: 3, leading: 4), 0)
        }
        test("returns target when there is no intrinsic silence") {
            try expectEqual(SmartAutoGap.injectedDuration(target: 5, trailing: 0, leading: 0), 5)
        }
        test("handles invalid inputs safely") {
            try expectEqual(SmartAutoGap.injectedDuration(target: 5, trailing: .nan, leading: 1), 4)
            try expectEqual(SmartAutoGap.injectedDuration(target: .infinity, trailing: 1, leading: 1), 0)
        }
    }

    suite("SmartAutoGap — intrinsic silence measurement") {
        test("measures leading and trailing silent blocks") {
            let result = SmartAutoGap.measureSilence(
                samples: [Array(repeating: 0, count: 20) + Array(repeating: 1, count: 30) + Array(repeating: 0, count: 10)],
                sampleRate: 1_000
            )
            try expectEqual(result, IntrinsicSilence(leading: 0.02, trailing: 0.01))
        }
        test("continuous tone has no intrinsic silence") {
            try expectEqual(SmartAutoGap.measureSilence(samples: [Array(repeating: 1, count: 30)], sampleRate: 1_000), .zero)
        }
        test("all-silent audio is counted once") {
            let result = SmartAutoGap.measureSilence(samples: [Array(repeating: 0, count: 30)], sampleRate: 1_000)
            try expectEqual(result, IntrinsicSilence(leading: 0.03, trailing: 0))
        }
        test("an audible sample in either stereo channel breaks silence") {
            let result = SmartAutoGap.measureSilence(
                samples: [Array(repeating: 0, count: 20), Array(repeating: 0, count: 10) + Array(repeating: 1, count: 10)],
                sampleRate: 1_000
            )
            try expectEqual(result, IntrinsicSilence(leading: 0.01, trailing: 0))
        }
        test("threshold value is inclusively silent") {
            let threshold = Float(4.0 / 255.0)
            let result = SmartAutoGap.measureSilence(samples: [Array(repeating: threshold, count: 10) + Array(repeating: 1, count: 10)], sampleRate: 1_000)
            try expectEqual(result, IntrinsicSilence(leading: 0.01, trailing: 0))
        }
        test("partial final blocks use their actual frame duration") {
            let result = SmartAutoGap.measureSilence(samples: [Array(repeating: 1, count: 10) + Array(repeating: 0, count: 5)], sampleRate: 1_000)
            try expectEqual(result, IntrinsicSilence(leading: 0, trailing: 0.005))
        }
        test("extremely large finite sample rates return zero safely") {
            try expectEqual(
                SmartAutoGap.measureSilence(samples: [[0]], sampleRate: .greatestFiniteMagnitude),
                .zero
            )
        }
        test("NaN in either stereo channel makes its block audible") {
            let result = SmartAutoGap.measureSilence(
                samples: [Array(repeating: 0, count: 20), Array(repeating: 0, count: 10) + [.nan] + Array(repeating: 0, count: 9)],
                sampleRate: 1_000
            )
            try expectEqual(result, IntrinsicSilence(leading: 0.01, trailing: 0))
        }
        test("infinity in either stereo channel makes its block audible") {
            let result = SmartAutoGap.measureSilence(
                samples: [Array(repeating: 0, count: 10) + [.infinity] + Array(repeating: 0, count: 9), Array(repeating: 0, count: 20)],
                sampleRate: 1_000
            )
            try expectEqual(result, IntrinsicSilence(leading: 0.01, trailing: 0))
        }
        test("unequal channels stop at the shortest shared frame count") {
            let result = SmartAutoGap.measureSilence(
                samples: [Array(repeating: 0, count: 10) + Array(repeating: 1, count: 10), Array(repeating: 0, count: 10)],
                sampleRate: 1_000
            )
            try expectEqual(result, IntrinsicSilence(leading: 0.01, trailing: 0))
        }
    }

    suite("SmartAutoGap — prepared pair identity") {
        test("matching pair calculates the exact injected gap") {
            let prepared = PreparedAutoGap(currentID: "A", nextID: "B", trailing: 1, leading: 1)
            try expectEqual(prepared.injectedDuration(currentID: "A", nextID: "B", target: 5), 3)
        }
        test("reordered next entry rejects stale analysis") {
            let prepared = PreparedAutoGap(currentID: "A", nextID: "B", trailing: 1, leading: 1)
            try expectEqual(prepared.injectedDuration(currentID: "A", nextID: "C", target: 5), nil)
        }
    }
    suite("SmartAutoGap — streaming measurement") {
        test("chunk boundaries preserve ten millisecond blocks") {
            var meter = SilenceAccumulator(sampleRate: 1_000, channelCount: 2)
            meter.append(samples: [Array(repeating: 0, count: 7), Array(repeating: 0, count: 7)])
            meter.append(samples: [Array(repeating: 0, count: 13), Array(repeating: 0, count: 3) + Array(repeating: 1, count: 10)])
            try expectEqual(meter.finish(), IntrinsicSilence(leading: 0.01, trailing: 0))
        }
    }
    suite("SmartAutoGap — transition policy") {
        test("disabled ignored manual and stopping transitions bypass gaps") {
            try expectEqual(SmartAutoGapTransitionPolicy.shouldSchedule(enabled: false, ignored: false, automatic: true, willStop: false), false)
            try expectEqual(SmartAutoGapTransitionPolicy.shouldSchedule(enabled: true, ignored: true, automatic: true, willStop: false), false)
            try expectEqual(SmartAutoGapTransitionPolicy.shouldSchedule(enabled: true, ignored: false, automatic: false, willStop: false), false)
            try expectEqual(SmartAutoGapTransitionPolicy.shouldSchedule(enabled: true, ignored: false, automatic: true, willStop: true), false)
        }
        test("automatic eligible pair schedules") {
            try expectEqual(SmartAutoGapTransitionPolicy.shouldSchedule(enabled: true, ignored: false, automatic: true, willStop: false), true)
        }
        test("pending pair validates generation and adjacency") {
            let pending = PendingAutoGapIdentity(currentID: "A", nextID: "B", generation: 4)
            try expect(pending.matches(currentID: "A", nextID: "B", generation: 4))
            try expect(!pending.matches(currentID: "A", nextID: "C", generation: 4))
            try expect(!pending.matches(currentID: "A", nextID: "B", generation: 5))
        }
        test("old completion cannot match a newer active gap") {
            let oldCompletion = PendingAutoGapIdentity(currentID: "A", nextID: "B", generation: 4)
            let newerActiveGap = PendingAutoGapIdentity(currentID: "B", nextID: "C", generation: 5)
            try expect(!oldCompletion.matches(
                currentID: newerActiveGap.currentID,
                nextID: newerActiveGap.nextID,
                generation: newerActiveGap.generation
            ))
        }
    }
}

func runDualDeckStateTests() {
    suite("DualDeckState") {
        test("A activates while B remains empty") {
            var state = DualDeckState<String>()
            state.activate(deck: .a, entryID: "current", generation: 1)
            try expectEqual(state.activeDeck, .a)
            try expectEqual(state[.a], DeckSnapshot(phase: .active, entryID: "current", generation: 1))
            try expectEqual(state[.b].phase, .empty)
        }
        test("B preparation becomes ready only for matching callback identity") {
            var state = DualDeckState<String>()
            let stale = state.beginPreparation(deck: .b, entryID: "wrong")!
            let token = state.beginPreparation(deck: .b, entryID: "next")!
            try expectEqual(state[.b].phase, .preparing)
            try expect(!state.markReady(stale))
            try expect(state.markReady(token))
            try expectEqual(state[.b].phase, .ready)
        }
        test("commit requires matching identities and generation") {
            var state = DualDeckState<String>()
            state.activate(deck: .a, entryID: "current", generation: 3)
            let preparation = state.beginPreparation(deck: .b, entryID: "next")!
            _ = state.markReady(preparation)
            try expectNil(state.commitTransition(currentID: "wrong", nextID: "next", settingsRevision: 4))
            try expectNil(state.commitTransition(currentID: "current", nextID: "wrong", settingsRevision: 4))
            let token = state.commitTransition(currentID: "current", nextID: "next", settingsRevision: 4)
            try expectNotNil(token)
            try expectEqual(token?.outgoingGeneration, 3)
            try expectEqual(token?.incomingGeneration, preparation.generation)
        }
        test("promotion swaps active and standby decks") {
            var state = DualDeckState<String>()
            state.activate(deck: .a, entryID: "current", generation: 1)
            let preparation = state.beginPreparation(deck: .b, entryID: "next")!
            _ = state.markReady(preparation)
            let token = state.commitTransition(currentID: "current", nextID: "next", settingsRevision: 4)!
            try expectEqual(state.promote(token, settingsRevision: 4), .b)
            try expectEqual(state.activeDeck, .b)
            try expectEqual(state[.b].phase, .active)
            try expectEqual(state[.a].phase, .recycling)
        }
        test("reorder invalidates a non-adjacent standby") {
            var state = DualDeckState<String>()
            let preparation = state.beginPreparation(deck: .b, entryID: "old-next")!
            _ = state.markReady(preparation)
            try expect(state.invalidateStandby(unlessEntryID: "new-next"))
            try expectEqual(state[.b].phase, .empty)
        }
        test("stale callback cannot mutate newer preparation") {
            var state = DualDeckState<String>()
            let stale = state.beginPreparation(deck: .b, entryID: "next")!
            _ = state.beginPreparation(deck: .b, entryID: "next")!
            try expect(!state.markReady(stale))
            try expectEqual(state[.b].phase, .preparing)
        }
        test("stop-after policy rejects preparation") {
            var state = DualDeckState<String>()
            try expectNil(state.beginPreparation(deck: .b, entryID: "next", automaticTransitionAllowed: false))
            try expectEqual(state[.b].phase, .empty)
        }
        test("settings revision invalidates a stale committed timeline") {
            var state = DualDeckState<String>()
            state.activate(deck: .a, entryID: "current", generation: 1)
            let preparation = state.beginPreparation(deck: .b, entryID: "next")!
            _ = state.markReady(preparation)
            let token = state.commitTransition(currentID: "current", nextID: "next", settingsRevision: 4)!
            try expectNil(state.promote(token, settingsRevision: 5))
            try expectEqual(state.activeDeck, .a)
        }
        test("recycled deck can prepare with a new generation and promote B back to A") {
            var state = DualDeckState<String>()
            state.activate(deck: .a, entryID: "one", generation: 10)
            let firstPreparation = state.beginPreparation(deck: .b, entryID: "two")!
            _ = state.markReady(firstPreparation)
            let first = state.commitTransition(currentID: "one", nextID: "two", settingsRevision: 1)!
            try expectEqual(state.promote(first, settingsRevision: 1), .b)
            state.reset(deck: .a)
            let secondPreparation = state.beginPreparation(deck: .a, entryID: "three")!
            _ = state.markReady(secondPreparation)
            let second = state.commitTransition(currentID: "two", nextID: "three", settingsRevision: 1)!
            try expect(second.generation != first.generation)
            try expectEqual(state.promote(second, settingsRevision: 1), .a)
        }
        test("settings mismatch cancels schedule restores ready and permits recommit") {
            var state = DualDeckState<String>()
            state.activate(deck: .a, entryID: "current", generation: 1)
            let preparation = state.beginPreparation(deck: .b, entryID: "next")!
            _ = state.markReady(preparation)
            let stale = state.commitTransition(currentID: "current", nextID: "next", settingsRevision: 4)!
            try expectNil(state.promote(stale, settingsRevision: 5))
            try expectNil(state.committedTransition)
            try expectEqual(state[.b].phase, .ready)
            let fresh = state.commitTransition(currentID: "current", nextID: "next", settingsRevision: 5)!
            try expectEqual(state.promote(fresh, settingsRevision: 5), .b)
        }
        test("activating another deck leaves exactly one active") {
            var state = DualDeckState<String>()
            state.activate(deck: .a, entryID: "one", generation: 1)
            state.activate(deck: .b, entryID: "two", generation: 2)
            try expectEqual(state[.a].phase, .empty)
            try expectEqual(state[.b].phase, .active)
        }
        test("failed recycling and reset lifecycle states are explicit") {
            var state = DualDeckState<String>()
            let preparation = state.beginPreparation(deck: .b, entryID: "next")!
            try expect(state.markFailed(preparation))
            try expectEqual(state[.b].phase, .failed)
            try expect(state.recycle(preparation))
            try expectEqual(state[.b].phase, .recycling)
            state.reset(deck: .b)
            try expectEqual(state[.b].phase, .empty)
            let cancelled = state.beginPreparation(deck: .b, entryID: "later")!
            state.cancel(deck: .b)
            try expect(!state.markReady(cancelled))
        }
        test("cancel all invalidates delayed preparation callback generations") {
            var state = DualDeckState<String>()
            state.activate(deck: .a, entryID: "current", generation: 4)
            let cancelled = state.beginPreparation(deck: .b, entryID: "next")!
            state.cancelAll()
            try expectNil(state.activeDeck)
            try expectNil(state.committedTransition)
            try expect(!state.markReady(cancelled))
            try expectEqual(state[.a].phase, .empty)
            try expectEqual(state[.b].phase, .empty)
        }
        test("repreparing same identity after stop rejects delayed old callback") {
            var state = DualDeckState<String>()
            let old = state.beginPreparation(deck: .b, entryID: "same")!
            state.cancelAll()
            let fresh = state.beginPreparation(deck: .b, entryID: "same")!
            try expect(fresh.generation > old.generation)
            try expect(!state.markReady(old))
            try expectEqual(state[.b].phase, .preparing)
            try expect(state.markReady(fresh))
        }
        test("generation advancement reports exhaustion instead of wrapping") {
            try expectEqual(DualDeckGeneration.next(after: 41), 42)
            try expectNil(DualDeckGeneration.next(after: .max))
        }
    }
}

func runStandbyPreparationTests() {
    suite("StandbyPreparationPolicy — should prepare") {
        test("real next unplayed entry with no stop condition is eligible") {
            try expect(StandbyPreparationPolicy.shouldPrepare(willStop: false))
        }
        test("stop-after or performance suppression blocks preparation") {
            try expect(!StandbyPreparationPolicy.shouldPrepare(willStop: true))
        }
    }
    suite("StandbyPreparationToken — async-boundary validation") {
        test("identity match requires deck, current, next, and generation to agree") {
            let configID = UUID()
            let token = StandbyPreparationToken<String>(
                deck: .b, currentID: "current", nextID: "next",
                generation: 7, settingsRevision: 1, pluginConfigurationID: configID
            )
            try expect(token.matchesIdentity(deck: .b, currentID: "current", nextID: "next", generation: 7))
            try expect(!token.matchesIdentity(deck: .a, currentID: "current", nextID: "next", generation: 7))
            try expect(!token.matchesIdentity(deck: .b, currentID: "stale", nextID: "next", generation: 7))
            try expect(!token.matchesIdentity(deck: .b, currentID: "current", nextID: "other", generation: 7))
            try expect(!token.matchesIdentity(deck: .b, currentID: "current", nextID: "next", generation: 8))
        }
        test("settings revision changes do not affect identity match") {
            let token = StandbyPreparationToken<String>(
                deck: .b, currentID: "current", nextID: "next",
                generation: 3, settingsRevision: 1, pluginConfigurationID: nil
            )
            // A gap-only setting change bumps settingsRevision but must not force a reopen.
            try expect(token.matchesIdentity(deck: .b, currentID: "current", nextID: "next", generation: 3))
            try expectEqual(token.settingsRevision, 1)
        }
    }
    suite("StandbyReusePolicy — retain B only when identity and configuration match") {
        test("reorder that leaves next entry unchanged retains the prepared deck") {
            let configID = UUID()
            try expect(StandbyReusePolicy.canReuse(
                preparedNextID: "next", preparedPluginConfigurationID: configID,
                observedNextID: "next", observedPluginConfigurationID: configID
            ))
        }
        test("reorder that changes the next entry cancels the prepared deck") {
            let configID = UUID()
            try expect(!StandbyReusePolicy.canReuse(
                preparedNextID: "next", preparedPluginConfigurationID: configID,
                observedNextID: "other", observedPluginConfigurationID: configID
            ))
        }
        test("removal of the next entry cancels the prepared deck") {
            try expect(!StandbyReusePolicy.canReuse(
                preparedNextID: "next", preparedPluginConfigurationID: nil,
                observedNextID: nil, observedPluginConfigurationID: nil
            ))
        }
        test("plugin configuration change on the same next entry cancels the prepared deck") {
            let originalConfigID = UUID()
            let newConfigID = UUID()
            try expect(!StandbyReusePolicy.canReuse(
                preparedNextID: "next", preparedPluginConfigurationID: originalConfigID,
                observedNextID: "next", observedPluginConfigurationID: newConfigID
            ))
        }
    }
}

// MARK: - Main entry point

runCortinaDetectorTests()
runTandaTrackerTests()
runProfileStoreTests()
runDisplayStateTests()
runReplayGainTests()
runAutoReplayGainTests()
runAudioUnitPluginTests()
runSmartAutoGapTests()
runDualDeckStateTests()
runStandbyPreparationTests()

print("\n════════════════════════════════")
let icon = totalFailed == 0 ? "✓" : "✗"
print("\(icon) \(totalPassed) passed, \(totalFailed) failed")
print("════════════════════════════════")

if totalFailed > 0 {
    exit(1)
}
