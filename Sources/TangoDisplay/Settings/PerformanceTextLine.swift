import Foundation

struct PerformanceTextLine: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String       // may contain {title}, {artist}, {genre}, {year}
    var fontName: String
    var fontSize: Double
    var colorHex: String   // "#RRGGBB"
    var showDuringCortina: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, text, fontName, fontSize, colorHex, showDuringCortina
    }

    init(id: UUID = UUID(), text: String, fontName: String, fontSize: Double,
         colorHex: String, showDuringCortina: Bool = false) {
        self.id = id
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.showDuringCortina = showDuringCortina
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self,   forKey: .id)
        text             = try c.decode(String.self, forKey: .text)
        fontName         = try c.decode(String.self, forKey: .fontName)
        fontSize         = try c.decode(Double.self, forKey: .fontSize)
        colorHex         = try c.decode(String.self, forKey: .colorHex)
        showDuringCortina = try c.decodeIfPresent(Bool.self, forKey: .showDuringCortina) ?? false
    }
}
