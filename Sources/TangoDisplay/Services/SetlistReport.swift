import Foundation

struct SetlistReport: Codable, Identifiable {
    let id: UUID
    let name: String
    let exportDate: Date
    let entries: [SetlistReportEntry]
}

struct SetlistReportEntry: Codable {
    let title: String
    let artist: String
    let genre: String
    let year: Int?
    let albumArtist: String?
    let duration: TimeInterval?
    let isPlayed: Bool
    let isLastTanda: Bool
    let isPerformance: Bool
}
