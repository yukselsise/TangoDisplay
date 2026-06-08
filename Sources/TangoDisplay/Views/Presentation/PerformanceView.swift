import SwiftUI
import TangoDisplayCore

struct PerformanceView: View {
    let currentTrack: Track?
    let settings: AppSettings

    var body: some View {
        VStack(spacing: 24) {
            ForEach(settings.performanceTextLines) { line in
                Text(resolvePerformancePlaceholders(line.text, track: currentTrack))
                    .font(performanceFont(line))
                    .foregroundColor(Color(hex: line.colorHex))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func performanceFont(_ line: PerformanceTextLine) -> Font {
        if line.fontName == "System" || line.fontName.isEmpty {
            return .system(size: line.fontSize)
        }
        return .custom(line.fontName, size: line.fontSize)
    }
}
