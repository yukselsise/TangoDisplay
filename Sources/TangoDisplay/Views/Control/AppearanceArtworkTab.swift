import AppKit
import SwiftUI
import TangoDisplayCore

struct AppearanceArtworkTab: View {
    @Binding var working: AppearanceProfile
    let bgThumbnail: NSImage?
    let onPickImage: () -> Void
    let onClearImage: () -> Void
    let artistBgThumbnails: [UUID: NSImage]
    let onPickArtistImage: (ArtistBackground) -> Void
    let onClearArtistImage: (ArtistBackground) -> Void
    let onAddArtistBackground: () -> Void
    let onRemoveArtistBackground: (ArtistBackground) -> Void

    @FocusState private var focusedEntryId: UUID?
    @State private var prevArtistCount: Int = 0

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $working.transitionStyle) {
                    ForEach(TransitionStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                HStack {
                    Text("Duration")
                    Slider(value: $working.transitionDuration, in: 0...2, step: 0.1)
                    Text(String(format: "%.1fs", working.transitionDuration))
                        .monospacedDigit()
                        .frame(width: 36)
                }
            } header: {
                Text("Transition")
                    .foregroundColor(ControlTheme.accent)
            }

            Section {
                Toggle("Show artwork on dance tracks", isOn: $working.showArtworkDance)
                if working.showArtworkDance || working.showArtworkCortina {
                    HStack {
                        Text("Opacity")
                        Slider(value: $working.albumArtworkOpacity, in: 0...1)
                        Text(String(format: "%.0f%%", working.albumArtworkOpacity * 100))
                            .monospacedDigit()
                            .frame(width: 44)
                    }
                    HStack {
                        Text("Scale")
                        Slider(value: $working.albumArtworkScale, in: 0.1...5.0)
                        Text(String(format: "%.2f×", working.albumArtworkScale))
                            .monospacedDigit()
                            .frame(width: 44)
                    }
                    HStack {
                        Text("Horizontal Position")
                        Slider(value: $working.albumArtworkOffsetX, in: -2000...2000)
                        Text(String(format: "%+.0f", working.albumArtworkOffsetX))
                            .monospacedDigit()
                            .frame(width: 48)
                    }
                    HStack {
                        Text("Vertical Position")
                        Slider(value: $working.albumArtworkOffsetY, in: -2000...2000)
                        Text(String(format: "%+.0f", working.albumArtworkOffsetY))
                            .monospacedDigit()
                            .frame(width: 48)
                    }
                }
            } header: {
                Text("Album Artwork")
                    .foregroundColor(ControlTheme.accent)
            }

            Section {
                HStack(spacing: 12) {
                    Group {
                        if let thumb = bgThumbnail {
                            Image(nsImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipped()
                                .cornerRadius(4)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(.secondary)
                                )
                        }
                    }
                    Spacer()
                    Button(working.backgroundImageFilename == nil ? "Pick Image…" : "Change Image…") {
                        onPickImage()
                    }
                    .buttonStyle(.bordered)
                    if working.backgroundImageFilename != nil {
                        Button("Clear") { onClearImage() }
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                    }
                }

                if working.backgroundImageFilename != nil {
                    HStack {
                        Text("Opacity")
                        Slider(value: $working.backgroundImageOpacity, in: 0...1)
                        Text(String(format: "%.0f%%", working.backgroundImageOpacity * 100))
                            .monospacedDigit()
                            .frame(width: 36)
                    }
                    HStack {
                        Text("Scale")
                        Slider(value: $working.backgroundImageScale, in: 0.1...5.0)
                        Text(String(format: "%.2f×", working.backgroundImageScale))
                            .monospacedDigit()
                            .frame(width: 44)
                    }
                    HStack {
                        Text("Horizontal Position")
                        Slider(value: $working.backgroundImageOffsetX, in: -2000...2000)
                        Text(String(format: "%+.0f", working.backgroundImageOffsetX))
                            .monospacedDigit()
                            .frame(width: 48)
                    }
                    HStack {
                        Text("Vertical Position")
                        Slider(value: $working.backgroundImageOffsetY, in: -2000...2000)
                        Text(String(format: "%+.0f", working.backgroundImageOffsetY))
                            .monospacedDigit()
                            .frame(width: 48)
                    }
                }
            } header: {
                Text("Background Image")
                    .foregroundColor(ControlTheme.accent)
            } footer: {
                Label {
                    Text("Background images are best checked in Live because external display resolution can vary.")
                } icon: {
                    Image(systemName: "info.circle")
                }
            }

            Section {
                Toggle("Enable artist backgrounds", isOn: $working.artistBackgroundsEnabled)

                if working.artistBackgroundsEnabled {
                    ForEach($working.artistBackgrounds) { $entry in
                        artistEntryRow(entry: $entry)
                    }

                    Button("Add Artist…") {
                        onAddArtistBackground()
                    }
                    .buttonStyle(.bordered)

                    if working.artistBackgrounds.contains(where: { $0.imageFilename != nil }) {
                        HStack {
                            Text("Opacity")
                            Slider(value: $working.artistBackgroundOpacity, in: 0...1)
                            Text(String(format: "%.0f%%", working.artistBackgroundOpacity * 100))
                                .monospacedDigit()
                                .frame(width: 36)
                        }
                        HStack {
                            Text("Scale")
                            Slider(value: $working.artistBackgroundScale, in: 0.1...5.0)
                            Text(String(format: "%.2f×", working.artistBackgroundScale))
                                .monospacedDigit()
                                .frame(width: 44)
                        }
                        HStack {
                            Text("Horizontal Position")
                            Slider(value: $working.artistBackgroundOffsetX, in: -2000...2000)
                            Text(String(format: "%+.0f", working.artistBackgroundOffsetX))
                                .monospacedDigit()
                                .frame(width: 48)
                        }
                        HStack {
                            Text("Vertical Position")
                            Slider(value: $working.artistBackgroundOffsetY, in: -2000...2000)
                            Text(String(format: "%+.0f", working.artistBackgroundOffsetY))
                                .monospacedDigit()
                                .frame(width: 48)
                        }
                    }
                }
            } header: {
                Text("Artist Backgrounds")
                    .foregroundColor(ControlTheme.accent)
            } footer: {
                if working.artistBackgroundsEnabled {
                    Label {
                        Text("Artist Backgrounds override the profile background image when the current track artist matches. Priority: matching artist → profile background → background colour.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            prevArtistCount = working.artistBackgrounds.count
        }
        .onChange(of: working.artistBackgrounds.count) { newCount in
            if newCount > prevArtistCount, let lastId = working.artistBackgrounds.last?.id {
                focusedEntryId = lastId
            }
            prevArtistCount = newCount
        }
    }

    @ViewBuilder
    private func artistEntryRow(entry: Binding<ArtistBackground>) -> some View {
        let e = entry.wrappedValue
        let isIncomplete = e.artistName.trimmingCharacters(in: .whitespaces).isEmpty || e.imageFilename == nil
        HStack(spacing: 10) {
            Group {
                if let thumb = artistBgThumbnails[e.id] {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipped()
                        .cornerRadius(4)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "person.crop.rectangle")
                                .foregroundColor(.secondary)
                        )
                }
            }

            Text("Name")
                .foregroundColor(.secondary)
                .fixedSize()

            TextField("", text: entry.artistName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            e.artistName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.red.opacity(0.7)
                                : Color(NSColor.separatorColor).opacity(0.5),
                            lineWidth: 1
                        )
                )
                .focused($focusedEntryId, equals: e.id)

            Button(e.imageFilename == nil ? "Pick Image…" : "Change Image…") {
                onPickArtistImage(e)
            }
            .buttonStyle(.bordered)

            if e.imageFilename != nil {
                Button("Clear") { onClearArtistImage(e) }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
            }

            if isIncomplete {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                    .help("This entry needs both an artist name and a background image before saving.")
            }

            Button {
                onRemoveArtistBackground(e)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
