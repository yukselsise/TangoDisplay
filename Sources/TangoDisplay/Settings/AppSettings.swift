import Foundation
import Combine
import CoreGraphics
import TangoDisplayCore

private let kPrefix = "TangoDisplay."

/// All user-configurable settings, persisted to UserDefaults.
/// Arrays are stored as comma-joined strings to avoid UserDefaults type-registration issues.
final class AppSettings: ObservableObject {

    // MARK: - Display labels

    @Published var cortinaLabel: String {
        didSet { UserDefaults.standard.set(cortinaLabel, forKey: kPrefix + "cortinaLabel") }
    }
    @Published var nextUpLabel: String {
        didSet { UserDefaults.standard.set(nextUpLabel, forKey: kPrefix + "nextUpLabel") }
    }
    @Published var idleMessage: String {
        didSet { UserDefaults.standard.set(idleMessage, forKey: kPrefix + "idleMessage") }
    }

    // MARK: - Cortina rules

    @Published var useAllowlist: Bool {
        didSet { UserDefaults.standard.set(useAllowlist, forKey: kPrefix + "useAllowlist") }
    }
    @Published var allowlistGenres: [String] {
        didSet { UserDefaults.standard.set(allowlistGenres.joined(separator: ","),
                                           forKey: kPrefix + "allowlistGenres") }
    }
    @Published var useDenylist: Bool {
        didSet { UserDefaults.standard.set(useDenylist, forKey: kPrefix + "useDenylist") }
    }
    @Published var denylistGenres: [String] {
        didSet {
            UserDefaults.standard.set(denylistGenres.joined(separator: ","),
                                       forKey: kPrefix + "denylistGenres")
            // Prune entries no longer in the denylist
            denylistPartialMatchGenres = denylistPartialMatchGenres.filter {
                denylistGenres.contains($0)
            }
            denylistLabelOverrides = denylistLabelOverrides.filter {
                denylistGenres.contains($0.key)
            }
        }
    }
    @Published var denylistPartialMatchGenres: Set<String> {
        didSet {
            UserDefaults.standard.set(
                Array(denylistPartialMatchGenres).joined(separator: ","),
                forKey: kPrefix + "denylistPartialMatchGenres"
            )
        }
    }
    @Published var denylistLabelOverrides: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(denylistLabelOverrides) {
                UserDefaults.standard.set(data, forKey: kPrefix + "denylistLabelOverrides")
            }
        }
    }

    // MARK: - Player source

    @Published var selectedPlayer: MusicPlayerChoice {
        didSet { UserDefaults.standard.set(selectedPlayer.rawValue, forKey: kPrefix + "selectedPlayer") }
    }

    @Published var jriverZoneID: Int {
        didSet { UserDefaults.standard.set(jriverZoneID, forKey: kPrefix + "jriverZoneID") }
    }

    @Published var builtInVolume: Float {
        didSet { UserDefaults.standard.set(builtInVolume, forKey: kPrefix + "builtInVolume") }
    }

    @Published var builtInFadeDuration: Double {
        didSet { UserDefaults.standard.set(builtInFadeDuration, forKey: kPrefix + "builtInFadeDuration") }
    }

    @Published var builtInOutputDeviceUID: String {
        didSet { UserDefaults.standard.set(builtInOutputDeviceUID, forKey: kPrefix + "builtInOutputDeviceUID") }
    }

    @Published var eqBand0Gain: Float {
        didSet { UserDefaults.standard.set(eqBand0Gain, forKey: kPrefix + "eqBand0Gain") }
    }
    @Published var eqBand1Gain: Float {
        didSet { UserDefaults.standard.set(eqBand1Gain, forKey: kPrefix + "eqBand1Gain") }
    }
    @Published var eqBand2Gain: Float {
        didSet { UserDefaults.standard.set(eqBand2Gain, forKey: kPrefix + "eqBand2Gain") }
    }
    @Published var eqBand3Gain: Float {
        didSet { UserDefaults.standard.set(eqBand3Gain, forKey: kPrefix + "eqBand3Gain") }
    }
    @Published var eqBand4Gain: Float {
        didSet { UserDefaults.standard.set(eqBand4Gain, forKey: kPrefix + "eqBand4Gain") }
    }

    var eqGains: [Float] { [eqBand0Gain, eqBand1Gain, eqBand2Gain, eqBand3Gain, eqBand4Gain] }

    @Published var markAsPlayedAfterCompletion: Bool {
        didSet { UserDefaults.standard.set(markAsPlayedAfterCompletion, forKey: kPrefix + "markAsPlayedAfterCompletion") }
    }

    @Published var markAsPlayedAfterSeconds: Int {
        didSet { UserDefaults.standard.set(markAsPlayedAfterSeconds, forKey: kPrefix + "markAsPlayedAfterSeconds") }
    }

    // MARK: - Built-in player track info

    @Published var duplicateTrackProtection: Bool {
        didSet { UserDefaults.standard.set(duplicateTrackProtection, forKey: kPrefix + "duplicateTrackProtection") }
    }
    @Published var showYear: Bool {
        didSet { UserDefaults.standard.set(showYear, forKey: kPrefix + "showYear") }
    }
    @Published var showTime: Bool {
        didSet { UserDefaults.standard.set(showTime, forKey: kPrefix + "showTime") }
    }
    @Published var showComments: Bool {
        didSet { UserDefaults.standard.set(showComments, forKey: kPrefix + "showComments") }
    }
    @Published var showAlbumArtist: Bool {
        didSet { UserDefaults.standard.set(showAlbumArtist, forKey: kPrefix + "showAlbumArtist") }
    }

    // MARK: - Appearance / presentation

    @Published var activeProfileID: UUID? {
        didSet { UserDefaults.standard.set(activeProfileID?.uuidString,
                                           forKey: kPrefix + "activeProfileID") }
    }
    @Published var targetDisplayID: CGDirectDisplayID? {
        didSet { UserDefaults.standard.set(targetDisplayID.map { Int($0) },
                                           forKey: kPrefix + "targetDisplayID") }
    }
    @Published var mirrorMode: Bool {
        didSet { UserDefaults.standard.set(mirrorMode, forKey: kPrefix + "mirrorMode") }
    }
    @Published var showTrackCounter: Bool {
        didSet { UserDefaults.standard.set(showTrackCounter, forKey: kPrefix + "showTrackCounter") }
    }

    // MARK: - Init

    init() {
        let ud = UserDefaults.standard
        cortinaLabel  = ud.string(forKey: kPrefix + "cortinaLabel")  ?? "CORTINA"
        nextUpLabel   = ud.string(forKey: kPrefix + "nextUpLabel")   ?? "COMING UP"
        idleMessage   = ud.string(forKey: kPrefix + "idleMessage")   ?? ""
        useAllowlist  = ud.object(forKey: kPrefix + "useAllowlist")
                           .flatMap { $0 as? Bool } ?? true
        allowlistGenres = AppSettings.parseGenres(
            ud.string(forKey: kPrefix + "allowlistGenres"), default: ["Cortina"])
        useDenylist   = ud.object(forKey: kPrefix + "useDenylist")
                           .flatMap { $0 as? Bool } ?? true
        denylistGenres = AppSettings.parseGenres(
            ud.string(forKey: kPrefix + "denylistGenres"), default: ["Tango", "Vals", "Milonga"])
        let rawPartial = ud.string(forKey: kPrefix + "denylistPartialMatchGenres")
        if let rawPartial, !rawPartial.isEmpty {
            denylistPartialMatchGenres = Set(AppSettings.parseGenres(rawPartial, default: []))
        } else {
            // First launch after update: enable partial match for all current denylist genres
            denylistPartialMatchGenres = Set(AppSettings.parseGenres(
                ud.string(forKey: kPrefix + "denylistGenres"), default: ["Tango", "Vals", "Milonga"]))
        }
        if let data = ud.data(forKey: kPrefix + "denylistLabelOverrides"),
           let overrides = try? JSONDecoder().decode([String: String].self, from: data) {
            denylistLabelOverrides = overrides
        } else {
            denylistLabelOverrides = [:]
        }
        let rawPlayer = ud.string(forKey: kPrefix + "selectedPlayer") ?? ""
        selectedPlayer = MusicPlayerChoice(rawValue: rawPlayer) ?? .musicApp
        jriverZoneID = ud.object(forKey: kPrefix + "jriverZoneID").flatMap { $0 as? Int } ?? -1
        builtInVolume = ud.object(forKey: kPrefix + "builtInVolume").flatMap { $0 as? Float } ?? 1.0
        builtInFadeDuration = ud.object(forKey: kPrefix + "builtInFadeDuration").flatMap { $0 as? Double } ?? 5.0
        builtInOutputDeviceUID = ud.string(forKey: kPrefix + "builtInOutputDeviceUID") ?? ""
        eqBand0Gain = ud.object(forKey: kPrefix + "eqBand0Gain").flatMap { $0 as? Float } ?? 0.0
        eqBand1Gain = ud.object(forKey: kPrefix + "eqBand1Gain").flatMap { $0 as? Float } ?? 0.0
        eqBand2Gain = ud.object(forKey: kPrefix + "eqBand2Gain").flatMap { $0 as? Float } ?? 0.0
        eqBand3Gain = ud.object(forKey: kPrefix + "eqBand3Gain").flatMap { $0 as? Float } ?? 0.0
        eqBand4Gain = ud.object(forKey: kPrefix + "eqBand4Gain").flatMap { $0 as? Float } ?? 0.0
        markAsPlayedAfterCompletion = ud.object(forKey: kPrefix + "markAsPlayedAfterCompletion")
            .flatMap { $0 as? Bool } ?? false
        let savedSeconds = ud.integer(forKey: kPrefix + "markAsPlayedAfterSeconds")
        markAsPlayedAfterSeconds = savedSeconds > 0 ? savedSeconds : 10
        duplicateTrackProtection = ud.object(forKey: kPrefix + "duplicateTrackProtection")
            .flatMap { $0 as? Bool } ?? false
        showYear = ud.object(forKey: kPrefix + "showYear").flatMap { $0 as? Bool } ?? true
        showTime = ud.object(forKey: kPrefix + "showTime").flatMap { $0 as? Bool } ?? true
        showComments = ud.object(forKey: kPrefix + "showComments").flatMap { $0 as? Bool } ?? false
        showAlbumArtist = ud.object(forKey: kPrefix + "showAlbumArtist").flatMap { $0 as? Bool } ?? false
        if let idString = ud.string(forKey: kPrefix + "activeProfileID") {
            activeProfileID = UUID(uuidString: idString)
        } else {
            activeProfileID = AppearanceProfile.classic.id
        }
        if ud.object(forKey: kPrefix + "targetDisplayID") != nil {
            let raw = ud.integer(forKey: kPrefix + "targetDisplayID")
            targetDisplayID = CGDirectDisplayID(raw)
        } else {
            targetDisplayID = nil
        }
        mirrorMode = ud.object(forKey: kPrefix + "mirrorMode").flatMap { $0 as? Bool } ?? true
        showTrackCounter = ud.object(forKey: kPrefix + "showTrackCounter").flatMap { $0 as? Bool } ?? true
    }

    // MARK: - Helpers

    private static func parseGenres(_ raw: String?, default defaultValue: [String]) -> [String] {
        guard let raw, !raw.isEmpty else { return defaultValue }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func displayLabel(for genre: String) -> String {
        let trimmed = genre.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()

        // Exact case-insensitive match
        if let match = denylistGenres.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }),
           let override = denylistLabelOverrides[match], !override.isEmpty {
            return override
        }

        // Partial (prefix) match — mirrors CortinaDetector's hasPrefix($0 + " ") logic
        if let match = denylistPartialMatchGenres.first(where: { lower.hasPrefix($0.lowercased() + " ") }),
           let override = denylistLabelOverrides[match], !override.isEmpty {
            return override
        }

        return trimmed
    }

    func makeDetector() -> CortinaDetector {
        CortinaDetector(
            useAllowlist: useAllowlist,
            allowlistGenres: Set(allowlistGenres.map { $0.lowercased() }),
            useDenylist: useDenylist,
            denylistGenres: Set(denylistGenres.map { $0.lowercased() }),
            denylistPartialGenres: Set(denylistPartialMatchGenres.map { $0.lowercased() })
        )
    }
}
