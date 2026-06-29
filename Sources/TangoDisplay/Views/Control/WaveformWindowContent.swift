import SwiftUI
import TangoDisplayCore

struct WaveformWindowContent: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let player = appState.localPlayer {
            WaveformWindowPlayer(player: player)
        } else {
            Text("No track playing")
                .foregroundColor(.secondary)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }
}

// MARK: -

private struct WaveformWindowPlayer: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var player: LocalPlayerSource

    @State private var waveformData: WaveformLoader.WaveformData? = nil
    @State private var isLoading = false

    private var currentFileURL: URL? {
        // Primary: a setlist entry the player has confirmed as playing/paused
        if let url = appState.setlist.entries.first(where: {
            $0.state == .playing || $0.state == .paused
        })?.fileURL { return url }
        // Fallback: player's current entry (may be .queued during transitions or pause-advance)
        if let id = player.currentEntryID,
           let entry = appState.setlist.entries.first(where: { $0.id == id }) {
            return entry.fileURL
        }
        return nil
    }

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
            } else if let data = waveformData {
                WaveformPlayerView(data: data, player: player)
            } else {
                Text("No track playing")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task(id: currentFileURL) {
            guard let url = currentFileURL else {
                waveformData = nil
                isLoading = false
                return
            }
            waveformData = nil
            isLoading = true
            let loadedData = await WaveformLoader.shared.load(url: url)
            guard !Task.isCancelled, currentFileURL == url else { return }
            waveformData = loadedData
            isLoading = false
        }
    }
}

// MARK: -

private struct WaveformPlayerView: View {
    let data: WaveformLoader.WaveformData
    @ObservedObject var player: LocalPlayerSource

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            Text(formatTime(player.elapsed))
                .font(.system(size: 13).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 34, alignment: .trailing)

            WaveformBarsView(
                samples: data.samples,
                progress: data.duration > 0 ? player.elapsed / data.duration : 0
            )

            Text(formatTime(data.duration))
                .font(.system(size: 13).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 34, alignment: .leading)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: -

private struct WaveformBarsView: View {
    let samples: [Float]
    let progress: Double   // 0.0 – 1.0

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            let bucketCount = max(1, Int(geometry.size.width * displayScale))
            let values = WaveformEnvelope.downsamplePeaks(samples, buckets: bucketCount)
            let clampedProgress = min(max(progress, 0), 1)

            Canvas { context, size in
                guard !values.isEmpty else { return }
                let middle = size.height / 2
                let minimumHalfHeight = 1 / displayScale
                let shape = Self.silhouettePath(
                    values: values,
                    size: size,
                    middle: middle,
                    minimumHalfHeight: minimumHalfHeight
                )

                context.fill(shape, with: .color(Color.secondary.opacity(0.4)))

                let playedWidth = size.width * clampedProgress
                context.drawLayer { playedContext in
                    playedContext.clip(
                        to: Path(CGRect(x: 0, y: 0, width: playedWidth, height: size.height))
                    )
                    playedContext.fill(shape, with: .color(.accentColor))
                }

                let playhead = CGRect(x: playedWidth - 0.5, y: 0, width: 1, height: size.height)
                context.fill(Path(playhead), with: .color(.red.opacity(0.8)))
            }
        }
    }

    private static func silhouettePath(
        values: [Float],
        size: CGSize,
        middle: CGFloat,
        minimumHalfHeight: CGFloat
    ) -> Path {
        var path = Path()
        guard let first = values.first, let last = values.last else { return path }
        let step = size.width / CGFloat(values.count)

        func halfHeight(for value: Float) -> CGFloat {
            max(minimumHalfHeight, CGFloat(abs(value)) * middle * 0.9)
        }

        path.move(to: CGPoint(x: 0, y: middle - halfHeight(for: first)))
        for (index, value) in values.enumerated() {
            path.addLine(to: CGPoint(
                x: CGFloat(index) * step,
                y: middle - halfHeight(for: value)
            ))
        }
        path.addLine(to: CGPoint(x: size.width, y: middle - halfHeight(for: last)))
        for (index, value) in values.enumerated().reversed() {
            path.addLine(to: CGPoint(
                x: CGFloat(index) * step,
                y: middle + halfHeight(for: value)
            ))
        }
        path.closeSubpath()
        return path
    }
}
