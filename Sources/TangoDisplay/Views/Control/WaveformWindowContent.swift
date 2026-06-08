import SwiftUI

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
                return
            }
            isLoading = true
            waveformData = await WaveformLoader.shared.load(url: url)
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

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let playheadX = CGFloat(progress) * size.width
            let barWidth  = size.width / CGFloat(samples.count)

            for (i, sample) in samples.enumerated() {
                let x      = CGFloat(i) * barWidth
                let height = max(2, CGFloat(sample) * size.height * 0.9)
                let rect   = CGRect(
                    x: x,
                    y: (size.height - height) / 2,
                    width: max(1, barWidth - 0.5),
                    height: height
                )
                let isPast = (x + barWidth * 0.5) < playheadX
                context.fill(
                    Path(rect),
                    with: .color(isPast ? Color.primary : Color.secondary.opacity(0.45))
                )
            }

            // Playhead line
            let lineRect = CGRect(x: playheadX - 0.5, y: 0, width: 1, height: size.height)
            context.fill(Path(lineRect), with: .color(.red.opacity(0.8)))
        }
    }
}
