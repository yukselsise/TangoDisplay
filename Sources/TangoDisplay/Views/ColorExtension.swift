import SwiftUI
import TangoDisplayCore

extension Color {
    /// Parses "#RRGGBB" or "#RRGGBBAA" hex strings.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let r, g, b, a: Double
        switch hex.count {
        case 6:
            r = Double((rgb >> 16) & 0xFF) / 255
            g = Double((rgb >> 8)  & 0xFF) / 255
            b = Double( rgb        & 0xFF) / 255
            a = 1.0
        case 8:
            r = Double((rgb >> 24) & 0xFF) / 255
            g = Double((rgb >> 16) & 0xFF) / 255
            b = Double((rgb >> 8)  & 0xFF) / 255
            a = Double( rgb        & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

extension AppearanceProfile {
    var backgroundSwiftUIColor: Color    { Color(hex: backgroundColor) }
    var titleSwiftUIColor: Color         { Color(hex: titleColor) }
    var artistSwiftUIColor: Color        { Color(hex: artistColor) }
    var genreSwiftUIColor: Color         { Color(hex: genreColor) }
    var yearSwiftUIColor: Color          { Color(hex: yearColor) }
    var trackCounterSwiftUIColor: Color  { Color(hex: trackCounterColor) }
    var singerSwiftUIColor: Color        { Color(hex: singerColor) }

    func font(name: String, size: Double, bold: Bool, italic: Bool) -> Font {
        let weight: Font.Weight = bold ? .bold : .regular
        var f: Font
        if name == "System" || name.isEmpty {
            f = .system(size: size, weight: weight, design: .default)
        } else {
            f = .custom(name, size: size).weight(weight)
        }
        return italic ? f.italic() : f
    }

    var titleFont: Font  { font(name: titleFontName,  size: titleFontSize,  bold: titleFontBold,  italic: titleFontItalic) }
    var artistFont: Font { font(name: artistFontName, size: artistFontSize, bold: artistFontBold, italic: artistFontItalic) }
    var genreFont: Font  { font(name: genreFontName,  size: genreFontSize,  bold: genreFontBold,  italic: genreFontItalic) }
    var yearFont: Font   { font(name: yearFontName,   size: yearFontSize,   bold: yearFontBold,   italic: yearFontItalic) }
    var singerFont: Font        { font(name: singerFontName,       size: singerFontSize,       bold: singerFontBold,       italic: singerFontItalic) }
    var trackCounterFont: Font  { font(name: trackCounterFontName, size: trackCounterFontSize, bold: trackCounterFontBold, italic: trackCounterFontItalic) }

    var cortinaLabelSwiftUIColor:  Color { Color(hex: cortinaLabelColor) }
    var cortinaArtistSwiftUIColor: Color { Color(hex: cortinaArtistColor) }
    var cortinaTitleSwiftUIColor:  Color { Color(hex: cortinaTitleColor) }
    var nextUpLabelSwiftUIColor:    Color { Color(hex: nextUpLabelColor) }
    var idleMessageSwiftUIColor:    Color { Color(hex: idleMessageColor) }
    var lastTandaLabelSwiftUIColor: Color { Color(hex: lastTandaLabelColor) }

    var cortinaLabelFont:   Font { font(name: cortinaLabelFontName,   size: cortinaLabelFontSize,   bold: cortinaLabelFontBold,   italic: cortinaLabelFontItalic) }
    var cortinaArtistFont:  Font { font(name: cortinaArtistFontName,  size: cortinaArtistFontSize,  bold: cortinaArtistFontBold,  italic: cortinaArtistFontItalic) }
    var cortinaTitleFont:   Font { font(name: cortinaTitleFontName,   size: cortinaTitleFontSize,   bold: cortinaTitleFontBold,   italic: cortinaTitleFontItalic) }
    var nextUpLabelFont:    Font { font(name: nextUpLabelFontName,    size: nextUpLabelFontSize,    bold: nextUpLabelFontBold,    italic: nextUpLabelFontItalic) }
    var idleMessageFont:    Font { font(name: idleMessageFontName,    size: idleMessageFontSize,    bold: idleMessageFontBold,    italic: idleMessageFontItalic) }
    var lastTandaLabelFont: Font { font(name: lastTandaLabelFontName, size: lastTandaLabelFontSize, bold: lastTandaLabelFontBold, italic: lastTandaLabelFontItalic) }
    var overrideTextSwiftUIColor: Color { Color(hex: overrideTextColor) }
    var overrideTextFont: Font { font(name: overrideTextFontName, size: overrideTextFontSize, bold: overrideTextFontBold, italic: overrideTextFontItalic) }
}
