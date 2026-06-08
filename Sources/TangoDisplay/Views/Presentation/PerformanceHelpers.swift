import TangoDisplayCore

func resolvePerformancePlaceholders(_ text: String, track: Track?) -> String {
    var result = text
    result = result.replacingOccurrences(of: "{title}",  with: track?.title  ?? "")
    result = result.replacingOccurrences(of: "{artist}", with: track?.artist ?? "")
    result = result.replacingOccurrences(of: "{genre}",  with: track?.genre  ?? "")
    result = result.replacingOccurrences(of: "{year}",   with: track?.year.map { String($0) } ?? "")
    return result
}
