import Foundation

public struct ArtistBackground: Codable, Identifiable, Equatable {
    public var id: UUID
    public var artistName: String      // text to match against track.artist (partial, case-insensitive)
    public var imageFilename: String?  // "artist-{uuid}.{ext}" stored in images dir

    public init(id: UUID = UUID(), artistName: String, imageFilename: String? = nil) {
        self.id = id
        self.artistName = artistName
        self.imageFilename = imageFilename
    }
}

public struct AppearanceProfile: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var isBuiltIn: Bool

    public var titleFontName: String
    public var titleFontSize: Double
    public var titleFontBold: Bool
    public var titleFontItalic: Bool
    public var artistFontName: String
    public var artistFontSize: Double
    public var artistFontBold: Bool
    public var artistFontItalic: Bool
    public var genreFontName: String
    public var genreFontSize: Double
    public var genreFontBold: Bool
    public var genreFontItalic: Bool
    public var showYear: Bool
    public var yearFontName: String
    public var yearFontSize: Double
    public var yearFontBold: Bool
    public var yearFontItalic: Bool

    public var backgroundColor: String
    public var titleColor: String
    public var artistColor: String
    public var genreColor: String
    public var yearColor: String
    public var trackCounterColor: String

    public var transitionStyle: TransitionStyle
    public var transitionDuration: Double

    // Background image (optional — nil means no image)
    public var backgroundImageFilename: String?  // "{profileUUID}.{ext}" stored in images dir
    public var backgroundImageOpacity: Double    // 0.0–1.0
    public var backgroundImageScale: Double      // multiplier, 1.0 = fill screen
    public var backgroundImageOffsetX: Double    // points, horizontal pan
    public var backgroundImageOffsetY: Double    // points, vertical pan

    // Artist Backgrounds — per-artist images that override the profile background when the track artist matches
    public var artistBackgroundsEnabled: Bool
    public var artistBackgrounds: [ArtistBackground]
    public var artistBackgroundOpacity: Double
    public var artistBackgroundScale: Double
    public var artistBackgroundOffsetX: Double
    public var artistBackgroundOffsetY: Double

    // Album artwork overlay (shown above background, below text; hidden during cortinas)
    public var showAlbumArtwork: Bool
    public var albumArtworkOpacity: Double   // 0.0–1.0
    public var albumArtworkScale: Double     // multiplier, 1.0 = natural size scaled to fit
    public var albumArtworkOffsetX: Double   // points, horizontal pan
    public var albumArtworkOffsetY: Double   // points, vertical pan

    // Configurable vertical order of text items on the display
    public var danceItemOrder: [DisplayTextItem]   // order for dance track display
    public var cortinaItemOrder: [DisplayTextItem] // order for cortina "coming up" section

    // Singer line (displays a track metadata field below the title)
    public var showSinger: Bool
    public var singerSource: SingerSource
    public var showSingerDuringCortina: Bool
    public var singerFontName: String
    public var singerFontSize: Double
    public var singerFontBold: Bool
    public var singerFontItalic: Bool
    public var singerColor: String

    // Per-type field visibility (Dance Track)
    public var showGenreDance:   Bool
    public var showArtistDance:  Bool
    public var showYearDance:    Bool
    public var showTitleDance:   Bool
    public var showSingerDance:  Bool
    public var showArtworkDance: Bool

    // Per-type field visibility (Cortina "Coming Up")
    public var showNextTrackDuringCortina: Bool
    public var showGenreCortina:   Bool
    public var showArtistCortina:  Bool
    public var showYearCortina:    Bool
    public var showTitleCortina:   Bool
    public var showSingerCortina:  Bool
    public var showArtworkCortina: Bool

    // Cortina track display (artist/title of the cortina itself)
    public var showCortinaTrackDuringCortina: Bool
    public var showCortinaTrackArtist: Bool
    public var showCortinaTrackTitle:  Bool

    // Cortina label font/colour (was hardcoded to titleFont + artistColor)
    public var cortinaLabelFontName:   String
    public var cortinaLabelFontSize:   Double
    public var cortinaLabelFontBold:   Bool
    public var cortinaLabelFontItalic: Bool
    public var cortinaLabelColor:      String

    // Cortina track artist font/colour
    public var cortinaArtistFontName:   String
    public var cortinaArtistFontSize:   Double
    public var cortinaArtistFontBold:   Bool
    public var cortinaArtistFontItalic: Bool
    public var cortinaArtistColor:      String

    // Cortina track title font/colour
    public var cortinaTitleFontName:   String
    public var cortinaTitleFontSize:   Double
    public var cortinaTitleFontBold:   Bool
    public var cortinaTitleFontItalic: Bool
    public var cortinaTitleColor:      String

    // Next-up label font/colour (was hardcoded to genreFont + genreColor)
    public var nextUpLabelFontName:   String
    public var nextUpLabelFontSize:   Double
    public var nextUpLabelFontBold:   Bool
    public var nextUpLabelFontItalic: Bool
    public var nextUpLabelColor:      String

    // Idle message font/colour (was hardcoded .system(48, ultraLight) + artistColor.opacity(0.4))
    public var idleMessageFontName:   String
    public var idleMessageFontSize:   Double
    public var idleMessageFontBold:   Bool
    public var idleMessageFontItalic: Bool
    public var idleMessageColor:      String

    // Orderable items for cortina-track section
    public var cortinaTrackItemOrder: [DisplayTextItem]

    // Last Tanda label font/colour
    public var lastTandaLabelFontName:   String
    public var lastTandaLabelFontSize:   Double
    public var lastTandaLabelFontBold:   Bool
    public var lastTandaLabelFontItalic: Bool
    public var lastTandaLabelColor:      String
    public var showLastTandaLabel:       Bool

    // Track Counter font
    public var trackCounterFontName:   String
    public var trackCounterFontSize:   Double
    public var trackCounterFontBold:   Bool
    public var trackCounterFontItalic: Bool

    // Override text font/colour
    public var overrideTextFontName:   String
    public var overrideTextFontSize:   Double
    public var overrideTextFontBold:   Bool
    public var overrideTextFontItalic: Bool
    public var overrideTextColor:      String

    public init(id: UUID, name: String, isBuiltIn: Bool,
                titleFontName: String = "System", titleFontSize: Double = 72,
                titleFontBold: Bool = true, titleFontItalic: Bool = false,
                artistFontName: String = "System", artistFontSize: Double = 96,
                artistFontBold: Bool = false, artistFontItalic: Bool = false,
                genreFontName: String = "System", genreFontSize: Double = 36,
                genreFontBold: Bool = false, genreFontItalic: Bool = false,
                showYear: Bool = false,
                yearFontName: String = "System", yearFontSize: Double = 36,
                yearFontBold: Bool = false, yearFontItalic: Bool = false,
                backgroundColor: String = "#000000",
                titleColor: String = "#FFFFFF",
                artistColor: String = "#FFFFFF",
                genreColor: String = "#AAAAAA",
                yearColor: String = "#AAAAAA",
                trackCounterColor: String = "#AAAAAA",
                transitionStyle: TransitionStyle = .fade,
                transitionDuration: Double = 0.4,
                backgroundImageFilename: String? = nil,
                backgroundImageOpacity: Double = 1.0,
                backgroundImageScale: Double = 1.0,
                backgroundImageOffsetX: Double = 0.0,
                backgroundImageOffsetY: Double = 0.0,
                artistBackgroundsEnabled: Bool = false,
                artistBackgrounds: [ArtistBackground] = [],
                artistBackgroundOpacity: Double = 1.0,
                artistBackgroundScale: Double = 1.0,
                artistBackgroundOffsetX: Double = 0.0,
                artistBackgroundOffsetY: Double = 0.0,
                showAlbumArtwork: Bool = false,
                albumArtworkOpacity: Double = 1.0,
                albumArtworkScale: Double = 1.0,
                albumArtworkOffsetX: Double = 0.0,
                albumArtworkOffsetY: Double = 0.0,
                danceItemOrder: [DisplayTextItem] = [.genre, .artist, .year, .title, .singer, .lastTandaLabel],
                cortinaItemOrder: [DisplayTextItem] = [.genre, .artist, .year, .singer, .lastTandaLabel],
                showSinger: Bool = false,
                singerSource: SingerSource = .comments,
                showSingerDuringCortina: Bool = false,
                singerFontName: String = "System",
                singerFontSize: Double = 48,
                singerFontBold: Bool = false,
                singerFontItalic: Bool = false,
                singerColor: String = "#AAAAAA",
                showGenreDance: Bool = true,
                showArtistDance: Bool = true,
                showYearDance: Bool = false,
                showTitleDance: Bool = true,
                showSingerDance: Bool = false,
                showArtworkDance: Bool = false,
                showNextTrackDuringCortina: Bool = true,
                showGenreCortina: Bool = true,
                showArtistCortina: Bool = true,
                showYearCortina: Bool = false,
                showTitleCortina: Bool = false,
                showSingerCortina: Bool = false,
                showArtworkCortina: Bool = false,
                showCortinaTrackDuringCortina: Bool = false,
                showCortinaTrackArtist: Bool = true,
                showCortinaTrackTitle: Bool = true,
                cortinaLabelFontName: String = "System", cortinaLabelFontSize: Double = 72,
                cortinaLabelFontBold: Bool = false, cortinaLabelFontItalic: Bool = false,
                cortinaLabelColor: String = "#FFFFFF",
                cortinaArtistFontName: String = "System", cortinaArtistFontSize: Double = 96,
                cortinaArtistFontBold: Bool = false, cortinaArtistFontItalic: Bool = false,
                cortinaArtistColor: String = "#FFFFFF",
                cortinaTitleFontName: String = "System", cortinaTitleFontSize: Double = 72,
                cortinaTitleFontBold: Bool = false, cortinaTitleFontItalic: Bool = false,
                cortinaTitleColor: String = "#FFFFFF",
                nextUpLabelFontName: String = "System", nextUpLabelFontSize: Double = 36,
                nextUpLabelFontBold: Bool = false, nextUpLabelFontItalic: Bool = false,
                nextUpLabelColor: String = "#AAAAAA",
                idleMessageFontName: String = "System", idleMessageFontSize: Double = 48,
                idleMessageFontBold: Bool = false, idleMessageFontItalic: Bool = false,
                idleMessageColor: String = "#FFFFFF",
                cortinaTrackItemOrder: [DisplayTextItem] = [.cortinaLabel, .cortinaArtist, .cortinaTitle],
                lastTandaLabelFontName: String = "System", lastTandaLabelFontSize: Double = 36,
                lastTandaLabelFontBold: Bool = false, lastTandaLabelFontItalic: Bool = false,
                lastTandaLabelColor: String = "#FF4444",
                showLastTandaLabel: Bool = true,
                trackCounterFontName: String = "System", trackCounterFontSize: Double = 36,
                trackCounterFontBold: Bool = false, trackCounterFontItalic: Bool = false,
                overrideTextFontName: String = "System", overrideTextFontSize: Double = 72,
                overrideTextFontBold: Bool = false, overrideTextFontItalic: Bool = false,
                overrideTextColor: String = "#FFFFFF") {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.titleFontName = titleFontName
        self.titleFontSize = titleFontSize
        self.titleFontBold = titleFontBold
        self.titleFontItalic = titleFontItalic
        self.artistFontName = artistFontName
        self.artistFontSize = artistFontSize
        self.artistFontBold = artistFontBold
        self.artistFontItalic = artistFontItalic
        self.genreFontName = genreFontName
        self.genreFontSize = genreFontSize
        self.genreFontBold = genreFontBold
        self.genreFontItalic = genreFontItalic
        self.showYear = showYear
        self.yearFontName = yearFontName
        self.yearFontSize = yearFontSize
        self.yearFontBold = yearFontBold
        self.yearFontItalic = yearFontItalic
        self.backgroundColor = backgroundColor
        self.titleColor = titleColor
        self.artistColor = artistColor
        self.genreColor = genreColor
        self.yearColor = yearColor
        self.trackCounterColor = trackCounterColor
        self.transitionStyle = transitionStyle
        self.transitionDuration = transitionDuration
        self.backgroundImageFilename = backgroundImageFilename
        self.backgroundImageOpacity = backgroundImageOpacity
        self.backgroundImageScale = backgroundImageScale
        self.backgroundImageOffsetX = backgroundImageOffsetX
        self.backgroundImageOffsetY = backgroundImageOffsetY
        self.artistBackgroundsEnabled = artistBackgroundsEnabled
        self.artistBackgrounds        = artistBackgrounds
        self.artistBackgroundOpacity  = artistBackgroundOpacity
        self.artistBackgroundScale    = artistBackgroundScale
        self.artistBackgroundOffsetX  = artistBackgroundOffsetX
        self.artistBackgroundOffsetY  = artistBackgroundOffsetY
        self.showAlbumArtwork = showAlbumArtwork
        self.albumArtworkOpacity = albumArtworkOpacity
        self.albumArtworkScale = albumArtworkScale
        self.albumArtworkOffsetX = albumArtworkOffsetX
        self.albumArtworkOffsetY = albumArtworkOffsetY
        self.danceItemOrder = danceItemOrder
        self.cortinaItemOrder = cortinaItemOrder
        self.showSinger = showSinger
        self.singerSource = singerSource
        self.showSingerDuringCortina = showSingerDuringCortina
        self.singerFontName = singerFontName
        self.singerFontSize = singerFontSize
        self.singerFontBold = singerFontBold
        self.singerFontItalic = singerFontItalic
        self.singerColor = singerColor
        self.showGenreDance   = showGenreDance
        self.showArtistDance  = showArtistDance
        self.showYearDance    = showYearDance
        self.showTitleDance   = showTitleDance
        self.showSingerDance  = showSingerDance
        self.showArtworkDance = showArtworkDance
        self.showNextTrackDuringCortina = showNextTrackDuringCortina
        self.showGenreCortina   = showGenreCortina
        self.showArtistCortina  = showArtistCortina
        self.showYearCortina    = showYearCortina
        self.showTitleCortina   = showTitleCortina
        self.showSingerCortina  = showSingerCortina
        self.showArtworkCortina = showArtworkCortina
        self.showCortinaTrackDuringCortina = showCortinaTrackDuringCortina
        self.showCortinaTrackArtist = showCortinaTrackArtist
        self.showCortinaTrackTitle  = showCortinaTrackTitle
        self.cortinaLabelFontName   = cortinaLabelFontName
        self.cortinaLabelFontSize   = cortinaLabelFontSize
        self.cortinaLabelFontBold   = cortinaLabelFontBold
        self.cortinaLabelFontItalic = cortinaLabelFontItalic
        self.cortinaLabelColor      = cortinaLabelColor
        self.cortinaArtistFontName   = cortinaArtistFontName
        self.cortinaArtistFontSize   = cortinaArtistFontSize
        self.cortinaArtistFontBold   = cortinaArtistFontBold
        self.cortinaArtistFontItalic = cortinaArtistFontItalic
        self.cortinaArtistColor      = cortinaArtistColor
        self.cortinaTitleFontName   = cortinaTitleFontName
        self.cortinaTitleFontSize   = cortinaTitleFontSize
        self.cortinaTitleFontBold   = cortinaTitleFontBold
        self.cortinaTitleFontItalic = cortinaTitleFontItalic
        self.cortinaTitleColor      = cortinaTitleColor
        self.nextUpLabelFontName   = nextUpLabelFontName
        self.nextUpLabelFontSize   = nextUpLabelFontSize
        self.nextUpLabelFontBold   = nextUpLabelFontBold
        self.nextUpLabelFontItalic = nextUpLabelFontItalic
        self.nextUpLabelColor      = nextUpLabelColor
        self.idleMessageFontName   = idleMessageFontName
        self.idleMessageFontSize   = idleMessageFontSize
        self.idleMessageFontBold   = idleMessageFontBold
        self.idleMessageFontItalic = idleMessageFontItalic
        self.idleMessageColor      = idleMessageColor
        self.cortinaTrackItemOrder = cortinaTrackItemOrder
        self.lastTandaLabelFontName   = lastTandaLabelFontName
        self.lastTandaLabelFontSize   = lastTandaLabelFontSize
        self.lastTandaLabelFontBold   = lastTandaLabelFontBold
        self.lastTandaLabelFontItalic = lastTandaLabelFontItalic
        self.lastTandaLabelColor      = lastTandaLabelColor
        self.showLastTandaLabel       = showLastTandaLabel
        self.trackCounterFontName     = trackCounterFontName
        self.trackCounterFontSize     = trackCounterFontSize
        self.trackCounterFontBold     = trackCounterFontBold
        self.trackCounterFontItalic   = trackCounterFontItalic
        self.overrideTextFontName   = overrideTextFontName
        self.overrideTextFontSize   = overrideTextFontSize
        self.overrideTextFontBold   = overrideTextFontBold
        self.overrideTextFontItalic = overrideTextFontItalic
        self.overrideTextColor      = overrideTextColor
    }

    // Custom decoder so existing JSON lacking the image keys still loads cleanly.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                   = try c.decode(UUID.self,            forKey: .id)
        name                 = try c.decode(String.self,          forKey: .name)
        isBuiltIn            = try c.decode(Bool.self,            forKey: .isBuiltIn)
        titleFontName        = try c.decode(String.self,          forKey: .titleFontName)
        titleFontSize        = try c.decode(Double.self,          forKey: .titleFontSize)
        titleFontBold        = try c.decodeIfPresent(Bool.self,    forKey: .titleFontBold)    ?? false
        titleFontItalic      = try c.decodeIfPresent(Bool.self,    forKey: .titleFontItalic)   ?? false
        artistFontName       = try c.decode(String.self,           forKey: .artistFontName)
        artistFontSize       = try c.decode(Double.self,           forKey: .artistFontSize)
        artistFontBold       = try c.decodeIfPresent(Bool.self,    forKey: .artistFontBold)    ?? false
        artistFontItalic     = try c.decodeIfPresent(Bool.self,    forKey: .artistFontItalic)  ?? false
        genreFontName        = try c.decode(String.self,           forKey: .genreFontName)
        genreFontSize        = try c.decode(Double.self,           forKey: .genreFontSize)
        genreFontBold        = try c.decodeIfPresent(Bool.self,    forKey: .genreFontBold)     ?? false
        genreFontItalic      = try c.decodeIfPresent(Bool.self,    forKey: .genreFontItalic)   ?? false
        showYear             = try c.decodeIfPresent(Bool.self,    forKey: .showYear)          ?? false
        yearFontName         = try c.decodeIfPresent(String.self,  forKey: .yearFontName)      ?? "System"
        yearFontSize         = try c.decodeIfPresent(Double.self,  forKey: .yearFontSize)      ?? 36
        yearFontBold         = try c.decodeIfPresent(Bool.self,    forKey: .yearFontBold)      ?? false
        yearFontItalic       = try c.decodeIfPresent(Bool.self,    forKey: .yearFontItalic)    ?? false
        backgroundColor      = try c.decode(String.self,          forKey: .backgroundColor)
        titleColor           = try c.decode(String.self,          forKey: .titleColor)
        artistColor          = try c.decode(String.self,          forKey: .artistColor)
        genreColor           = try c.decode(String.self,          forKey: .genreColor)
        yearColor            = try c.decodeIfPresent(String.self,  forKey: .yearColor)         ?? "#AAAAAA"
        trackCounterColor    = try c.decodeIfPresent(String.self, forKey: .trackCounterColor) ?? "#AAAAAA"
        transitionStyle      = try c.decode(TransitionStyle.self, forKey: .transitionStyle)
        transitionDuration   = try c.decode(Double.self,          forKey: .transitionDuration)
        // New fields — absent in older JSON files, fall back to defaults
        backgroundImageFilename = try c.decodeIfPresent(String.self,  forKey: .backgroundImageFilename)
        backgroundImageOpacity  = try c.decodeIfPresent(Double.self,  forKey: .backgroundImageOpacity)  ?? 1.0
        backgroundImageScale    = try c.decodeIfPresent(Double.self,  forKey: .backgroundImageScale)    ?? 1.0
        backgroundImageOffsetX  = try c.decodeIfPresent(Double.self,  forKey: .backgroundImageOffsetX)  ?? 0.0
        backgroundImageOffsetY  = try c.decodeIfPresent(Double.self,  forKey: .backgroundImageOffsetY)  ?? 0.0
        artistBackgroundsEnabled = try c.decodeIfPresent(Bool.self,               forKey: .artistBackgroundsEnabled) ?? false
        artistBackgrounds        = try c.decodeIfPresent([ArtistBackground].self, forKey: .artistBackgrounds)        ?? []
        artistBackgroundOpacity  = try c.decodeIfPresent(Double.self,             forKey: .artistBackgroundOpacity)  ?? 1.0
        artistBackgroundScale    = try c.decodeIfPresent(Double.self,             forKey: .artistBackgroundScale)    ?? 1.0
        artistBackgroundOffsetX  = try c.decodeIfPresent(Double.self,             forKey: .artistBackgroundOffsetX)  ?? 0.0
        artistBackgroundOffsetY  = try c.decodeIfPresent(Double.self,             forKey: .artistBackgroundOffsetY)  ?? 0.0
        showAlbumArtwork        = try c.decodeIfPresent(Bool.self,    forKey: .showAlbumArtwork)        ?? false
        albumArtworkOpacity     = try c.decodeIfPresent(Double.self,  forKey: .albumArtworkOpacity)     ?? 1.0
        albumArtworkScale       = try c.decodeIfPresent(Double.self,  forKey: .albumArtworkScale)       ?? 1.0
        albumArtworkOffsetX     = try c.decodeIfPresent(Double.self,  forKey: .albumArtworkOffsetX)     ?? 0.0
        albumArtworkOffsetY     = try c.decodeIfPresent(Double.self,  forKey: .albumArtworkOffsetY)     ?? 0.0
        showSinger              = try c.decodeIfPresent(Bool.self,         forKey: .showSinger)              ?? false
        singerSource            = try c.decodeIfPresent(SingerSource.self, forKey: .singerSource)            ?? .comments
        showSingerDuringCortina = try c.decodeIfPresent(Bool.self,         forKey: .showSingerDuringCortina) ?? false
        singerFontName          = try c.decodeIfPresent(String.self,  forKey: .singerFontName)          ?? "System"
        singerFontSize          = try c.decodeIfPresent(Double.self,  forKey: .singerFontSize)          ?? 48
        singerFontBold          = try c.decodeIfPresent(Bool.self,    forKey: .singerFontBold)          ?? false
        singerFontItalic        = try c.decodeIfPresent(Bool.self,    forKey: .singerFontItalic)        ?? false
        singerColor             = try c.decodeIfPresent(String.self,  forKey: .singerColor)             ?? "#AAAAAA"
        danceItemOrder   = try c.decodeIfPresent([DisplayTextItem].self, forKey: .danceItemOrder)   ?? [.genre, .artist, .year, .title, .singer]
        var decodedCortinaOrder = try c.decodeIfPresent([DisplayTextItem].self, forKey: .cortinaItemOrder) ?? [.genre, .artist, .year, .singer]
        if !decodedCortinaOrder.contains(.title) {
            if let singerIdx = decodedCortinaOrder.firstIndex(of: .singer) {
                decodedCortinaOrder.insert(.title, at: singerIdx)
            } else {
                decodedCortinaOrder.append(.title)
            }
        }
        if !decodedCortinaOrder.contains(.nextUpLabel) {
            decodedCortinaOrder.insert(.nextUpLabel, at: 0)
        }
        cortinaItemOrder = decodedCortinaOrder

        // Legacy field values for migration
        let legacyShowYear          = (try c.decodeIfPresent(Bool.self, forKey: .showYear))             ?? false
        let legacyShowSinger        = (try c.decodeIfPresent(Bool.self, forKey: .showSinger))           ?? false
        let legacyShowSingerCortina = (try c.decodeIfPresent(Bool.self, forKey: .showSingerDuringCortina)) ?? false
        let legacyShowArtwork       = (try c.decodeIfPresent(Bool.self, forKey: .showAlbumArtwork))     ?? false
        let legacyCortinaHadTitle   = (try c.decodeIfPresent([DisplayTextItem].self, forKey: .cortinaItemOrder))?.contains(.title) ?? false

        showGenreDance   = (try c.decodeIfPresent(Bool.self, forKey: .showGenreDance))   ?? true
        showArtistDance  = (try c.decodeIfPresent(Bool.self, forKey: .showArtistDance))  ?? true
        showYearDance    = (try c.decodeIfPresent(Bool.self, forKey: .showYearDance))    ?? legacyShowYear
        showTitleDance   = (try c.decodeIfPresent(Bool.self, forKey: .showTitleDance))   ?? true
        showSingerDance  = (try c.decodeIfPresent(Bool.self, forKey: .showSingerDance))  ?? legacyShowSinger
        showArtworkDance = (try c.decodeIfPresent(Bool.self, forKey: .showArtworkDance)) ?? legacyShowArtwork

        showNextTrackDuringCortina = (try c.decodeIfPresent(Bool.self, forKey: .showNextTrackDuringCortina)) ?? true
        showGenreCortina   = (try c.decodeIfPresent(Bool.self, forKey: .showGenreCortina))   ?? true
        showArtistCortina  = (try c.decodeIfPresent(Bool.self, forKey: .showArtistCortina))  ?? true
        showYearCortina    = (try c.decodeIfPresent(Bool.self, forKey: .showYearCortina))    ?? legacyShowYear
        showTitleCortina   = (try c.decodeIfPresent(Bool.self, forKey: .showTitleCortina))   ?? legacyCortinaHadTitle
        showSingerCortina  = (try c.decodeIfPresent(Bool.self, forKey: .showSingerCortina))  ?? legacyShowSingerCortina
        showArtworkCortina = (try c.decodeIfPresent(Bool.self, forKey: .showArtworkCortina)) ?? legacyShowArtwork

        showCortinaTrackDuringCortina = (try c.decodeIfPresent(Bool.self, forKey: .showCortinaTrackDuringCortina)) ?? false
        showCortinaTrackArtist        = (try c.decodeIfPresent(Bool.self, forKey: .showCortinaTrackArtist))        ?? true
        showCortinaTrackTitle         = (try c.decodeIfPresent(Bool.self, forKey: .showCortinaTrackTitle))         ?? true

        cortinaLabelFontName   = try c.decodeIfPresent(String.self, forKey: .cortinaLabelFontName)   ?? titleFontName
        cortinaLabelFontSize   = try c.decodeIfPresent(Double.self, forKey: .cortinaLabelFontSize)   ?? titleFontSize
        cortinaLabelFontBold   = try c.decodeIfPresent(Bool.self,   forKey: .cortinaLabelFontBold)   ?? titleFontBold
        cortinaLabelFontItalic = try c.decodeIfPresent(Bool.self,   forKey: .cortinaLabelFontItalic) ?? titleFontItalic
        cortinaLabelColor      = try c.decodeIfPresent(String.self, forKey: .cortinaLabelColor)      ?? artistColor

        cortinaArtistFontName   = try c.decodeIfPresent(String.self, forKey: .cortinaArtistFontName)   ?? "System"
        cortinaArtistFontSize   = try c.decodeIfPresent(Double.self, forKey: .cortinaArtistFontSize)   ?? 96
        cortinaArtistFontBold   = try c.decodeIfPresent(Bool.self,   forKey: .cortinaArtistFontBold)   ?? false
        cortinaArtistFontItalic = try c.decodeIfPresent(Bool.self,   forKey: .cortinaArtistFontItalic) ?? false
        cortinaArtistColor      = try c.decodeIfPresent(String.self, forKey: .cortinaArtistColor)      ?? "#FFFFFF"

        cortinaTitleFontName   = try c.decodeIfPresent(String.self, forKey: .cortinaTitleFontName)   ?? "System"
        cortinaTitleFontSize   = try c.decodeIfPresent(Double.self, forKey: .cortinaTitleFontSize)   ?? 72
        cortinaTitleFontBold   = try c.decodeIfPresent(Bool.self,   forKey: .cortinaTitleFontBold)   ?? false
        cortinaTitleFontItalic = try c.decodeIfPresent(Bool.self,   forKey: .cortinaTitleFontItalic) ?? false
        cortinaTitleColor      = try c.decodeIfPresent(String.self, forKey: .cortinaTitleColor)      ?? "#FFFFFF"

        nextUpLabelFontName   = try c.decodeIfPresent(String.self, forKey: .nextUpLabelFontName)   ?? genreFontName
        nextUpLabelFontSize   = try c.decodeIfPresent(Double.self, forKey: .nextUpLabelFontSize)   ?? genreFontSize
        nextUpLabelFontBold   = try c.decodeIfPresent(Bool.self,   forKey: .nextUpLabelFontBold)   ?? genreFontBold
        nextUpLabelFontItalic = try c.decodeIfPresent(Bool.self,   forKey: .nextUpLabelFontItalic) ?? genreFontItalic
        nextUpLabelColor      = try c.decodeIfPresent(String.self, forKey: .nextUpLabelColor)      ?? genreColor

        idleMessageFontName   = try c.decodeIfPresent(String.self, forKey: .idleMessageFontName)   ?? "System"
        idleMessageFontSize   = try c.decodeIfPresent(Double.self, forKey: .idleMessageFontSize)   ?? 48
        idleMessageFontBold   = try c.decodeIfPresent(Bool.self,   forKey: .idleMessageFontBold)   ?? false
        idleMessageFontItalic = try c.decodeIfPresent(Bool.self,   forKey: .idleMessageFontItalic) ?? false
        idleMessageColor      = try c.decodeIfPresent(String.self, forKey: .idleMessageColor)      ?? artistColor

        cortinaTrackItemOrder = try c.decodeIfPresent([DisplayTextItem].self, forKey: .cortinaTrackItemOrder)
            ?? [.cortinaLabel, .cortinaArtist, .cortinaTitle]

        lastTandaLabelFontName   = try c.decodeIfPresent(String.self, forKey: .lastTandaLabelFontName)   ?? "System"
        lastTandaLabelFontSize   = try c.decodeIfPresent(Double.self, forKey: .lastTandaLabelFontSize)   ?? 36
        lastTandaLabelFontBold   = try c.decodeIfPresent(Bool.self,   forKey: .lastTandaLabelFontBold)   ?? false
        lastTandaLabelFontItalic = try c.decodeIfPresent(Bool.self,   forKey: .lastTandaLabelFontItalic) ?? false
        lastTandaLabelColor      = try c.decodeIfPresent(String.self, forKey: .lastTandaLabelColor)      ?? "#FF4444"
        showLastTandaLabel       = try c.decodeIfPresent(Bool.self,   forKey: .showLastTandaLabel)       ?? true

        trackCounterFontName   = try c.decodeIfPresent(String.self, forKey: .trackCounterFontName)   ?? "System"
        trackCounterFontSize   = try c.decodeIfPresent(Double.self, forKey: .trackCounterFontSize)   ?? 36
        trackCounterFontBold   = try c.decodeIfPresent(Bool.self,   forKey: .trackCounterFontBold)   ?? false
        trackCounterFontItalic = try c.decodeIfPresent(Bool.self,   forKey: .trackCounterFontItalic) ?? false

        overrideTextFontName   = try c.decodeIfPresent(String.self, forKey: .overrideTextFontName)   ?? "System"
        overrideTextFontSize   = try c.decodeIfPresent(Double.self, forKey: .overrideTextFontSize)   ?? 72
        overrideTextFontBold   = try c.decodeIfPresent(Bool.self,   forKey: .overrideTextFontBold)   ?? false
        overrideTextFontItalic = try c.decodeIfPresent(Bool.self,   forKey: .overrideTextFontItalic) ?? false
        overrideTextColor      = try c.decodeIfPresent(String.self, forKey: .overrideTextColor)      ?? titleColor

        // Migration: append .lastTandaLabel to order lists if absent
        if !danceItemOrder.contains(.lastTandaLabel) {
            danceItemOrder.append(.lastTandaLabel)
        }
        if !cortinaItemOrder.contains(.lastTandaLabel) {
            cortinaItemOrder.append(.lastTandaLabel)
        }
    }

    public func singerValue(from track: Track) -> String? {
        switch singerSource {
        case .comments:    return track.comment
        case .albumArtist: return track.albumArtist
        }
    }

    /// Returns the first artist background entry whose name is found within `artist` (partial,
    /// case-insensitive, diacritic-insensitive match). Returns nil when the feature is disabled
    /// or no entry matches.
    public func matchingArtistBackground(for artist: String) -> ArtistBackground? {
        guard artistBackgroundsEnabled else { return nil }
        let needle = artist.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return artistBackgrounds.first { entry in
            let key = entry.artistName.trimmingCharacters(in: .whitespaces)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return !key.isEmpty && needle.contains(key)
        }
    }

    public static let builtIns: [AppearanceProfile] = [.classic, .modern, .highContrast]

    public static let classic = AppearanceProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Classic", isBuiltIn: true,
        backgroundColor: "#1A1208",
        titleColor: "#F5E6C8", artistColor: "#F5E6C8", genreColor: "#C8A97A",
        trackCounterColor: "#C8A97A"
    )

    public static let modern = AppearanceProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Modern", isBuiltIn: true,
        backgroundColor: "#1C1C1E",
        titleColor: "#FFFFFF", artistColor: "#FFFFFF", genreColor: "#8E8E93",
        trackCounterColor: "#8E8E93"
    )

    public static let highContrast = AppearanceProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "High Contrast", isBuiltIn: true,
        backgroundColor: "#000000",
        titleColor: "#FFFF00", artistColor: "#FFFF00", genreColor: "#FFFFFF",
        trackCounterColor: "#B3B3B3",
        transitionStyle: .cut, transitionDuration: 0.0
    )
}

public enum DisplayTextItem: String, Codable, CaseIterable {
    case genre, artist, year, title, singer
    case cortinaLabel    // "CORTINA" heading text
    case cortinaArtist   // cortina track's own artist
    case cortinaTitle    // cortina track's own title
    case nextUpLabel     // "COMING UP" heading text
    case lastTandaLabel  // "LAST TANDA" announcement label

    public var displayName: String {
        switch self {
        case .genre:           "Genre"
        case .artist:          "Artist"
        case .year:            "Year"
        case .title:           "Title"
        case .singer:          "Singer"
        case .cortinaLabel:    "Cortina Label"
        case .cortinaArtist:   "Cortina Artist"
        case .cortinaTitle:    "Cortina Title"
        case .nextUpLabel:     "Next Up Label"
        case .lastTandaLabel:  "Last Tanda Label"
        }
    }
}

public enum SingerSource: String, Codable, CaseIterable {
    case comments    = "comments"
    case albumArtist = "albumArtist"

    public var displayName: String {
        switch self {
        case .comments:    "Comments"
        case .albumArtist: "Album Artist"
        }
    }
}

public enum TransitionStyle: String, Codable, CaseIterable {
    case fade
    case cut
    case fadeToBlack
    case push
    case zoom

    public var displayName: String {
        switch self {
        case .fade:        "Crossfade"
        case .cut:         "Hard Cut"
        case .fadeToBlack: "Fade Through Black"
        case .push:        "Push"
        case .zoom:        "Zoom"
        }
    }
}

