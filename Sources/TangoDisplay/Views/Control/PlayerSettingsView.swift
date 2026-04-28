import SwiftUI

struct PlayerSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Music player", selection: $settings.selectedPlayer) {
                    ForEach(MusicPlayerChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Player Source")
                    .foregroundColor(ControlTheme.accent)
            }

            Section {
                playerStatusInfo
            } header: {
                Text("Notes")
                    .foregroundColor(ControlTheme.accent)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var playerStatusInfo: some View {
        switch settings.selectedPlayer {
        case .musicApp:
            Label {
                Text("Polls Music.app every 2 seconds via AppleScript. Playlist look-ahead and tanda counting are fully supported.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }

        case .swinsian:
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Listens for Swinsian push notifications in real time. Upcoming tanda look-ahead is supported when playing from a queue or playlist.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                Label {
                    Text("Track counter shows position within the current tanda (e.g. Track 2). The total (e.g. of 4) is unavailable — Swinsian's queue starts at the current track so backwards context is unavailable.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
            }

        case .embrace:
            Label {
                Text("Listens for Embrace notifications and polls via AppleScript in real time. Playlist look-ahead and tanda counting are fully supported.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }
}
