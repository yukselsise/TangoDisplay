import SwiftUI

struct PlayerSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    @State private var jriverZones: [JRiverZone] = []
    @State private var isLoadingZones = false

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

            if settings.selectedPlayer == .jriver {
                Section {
                    LabeledContent("Zone:") {
                        HStack(spacing: 8) {
                            Picker("", selection: $settings.jriverZoneID) {
                                Text("Active (follows current)").tag(-1)
                                ForEach(jriverZones) { zone in
                                    Text(zone.name).tag(zone.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .fixedSize()
                            Button(isLoadingZones ? "Loading…" : "Refresh") {
                                loadJRiverZones()
                            }
                            .disabled(isLoadingZones)
                        }
                    }
                    Text("Pin TangoDisplay to a specific zone so pre-listening in another zone never affects the display.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Zone")
                        .foregroundColor(ControlTheme.accent)
                }
                .onAppear { if jriverZones.isEmpty { loadJRiverZones() } }
            }

            if settings.selectedPlayer == .builtIn {
                Section {
                    LabeledContent("Main output:") {
                        Picker("", selection: $settings.builtInOutputDeviceUID) {
                            Text("System Default").tag("")
                            ForEach(appState.availableAudioOutputDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    LabeledContent("Cortina fade") {
                        HStack(spacing: 8) {
                            Slider(value: $settings.builtInFadeDuration, in: 1...15, step: 0.5)
                            Text("\(settings.builtInFadeDuration, specifier: "%.1f")s")
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                    Text("Duration of the volume fade when using Fade & Stop or Fade & Continue.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    LabeledContent("Mark as played") {
                        Picker("", selection: $settings.markAsPlayedAfterCompletion) {
                            Text("After song ends").tag(true)
                            Text("After...").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    if !settings.markAsPlayedAfterCompletion {
                        LabeledContent("") {
                            HStack(spacing: 8) {
                                Slider(
                                    value: Binding(
                                        get: { Double(settings.markAsPlayedAfterSeconds) },
                                        set: { settings.markAsPlayedAfterSeconds = Int($0.rounded()) }
                                    ),
                                    in: 1...30,
                                    step: 1
                                )
                                Text("\(settings.markAsPlayedAfterSeconds)s")
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                    Text("Controls when a track is marked as played. Once marked, resuming playback skips to the next track.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Toggle("Duplicate track protection", isOn: $settings.duplicateTrackProtection)
                    Text("Warns before adding a track that is already in the setlist.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Built-in Player")
                        .foregroundColor(ControlTheme.accent)
                }

                Section {
                    Toggle("Title", isOn: .constant(true)).disabled(true)
                    Toggle("Artist", isOn: .constant(true)).disabled(true)
                    Toggle("Genre", isOn: .constant(true)).disabled(true)
                    Toggle("Year", isOn: $settings.showYear)
                    Toggle("Time", isOn: $settings.showTime)
                    Toggle("Comments", isOn: $settings.showComments)
                    Toggle("Album Artist", isOn: $settings.showAlbumArtist)
                    Text("Controls which fields are shown in the setlist rows.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Track Info")
                        .foregroundColor(ControlTheme.accent)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { appState.refreshAudioOutputDeviceList() }
    }

    private func loadJRiverZones() {
        isLoadingZones = true
        JRiverPoller.fetchZones { zones in
            jriverZones = zones
            isLoadingZones = false
        }
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

        case .jriver:
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Polls JRiver Media Center every 2 seconds via its MCWS HTTP API. Playlist look-ahead and tanda counting are fully supported.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                Label {
                    Text("JRiver must be running with Media Network enabled (Tools → Options → Media Network). Connects to 127.0.0.1 on the default MCWS port.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                Label {
                    Text("If you use multiple zones (e.g. Player + Prelistening), use the Zone picker below to pin TangoDisplay to a specific zone.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
            }

        case .builtIn:
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("TangoDisplay plays audio directly. Build your setlist in the Setlist tab by dragging tracks from Music.app, Swinsian, or Finder.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                Label {
                    Text("Fully integrated support.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
    }
}
