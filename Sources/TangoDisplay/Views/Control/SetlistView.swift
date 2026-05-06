import AppKit
import SwiftUI
import UniformTypeIdentifiers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private func setlistFormatDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite && seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
}

struct SetlistView: View {
    @ObservedObject var setlist: SetlistManager
    let player: LocalPlayerSource
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    @State private var isDragTargeted = false
    @State private var activeEntryID: UUID? = nil
    @State private var isPlayerActive: Bool = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showClearConfirmation = false
    @State private var pendingDeleteIDs: Set<UUID>? = nil
    @State private var showExportDialog = false
    @State private var exportPlaylistName = ""
    @State private var showExportError = false
    @State private var exportErrorMessage = ""
    @State private var showEQPopover = false
    @State private var scrollTrigger: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            PlayerControlsView(player: player, onScrollToCurrentTrack: {
                scrollTrigger = activeEntryID
            })
            .environmentObject(appState)

            Divider()

            if setlist.entries.isEmpty {
                emptyDropZone
            } else {
                ScrollViewReader { proxy in
                    trackList
                        .onChange(of: scrollTrigger) { id in
                            guard let id else { return }
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                            scrollTrigger = nil
                        }
                }
            }

            if !setlist.entries.isEmpty {
                Divider()
                StatusBarView(player: player, setlist: setlist)
            }
        }
        .onAppear {
            activeEntryID = player.currentEntryID
            isPlayerActive = player.isActivePlaying
        }
        .onReceive(player.$currentEntryID) { activeEntryID = $0 }
        .onReceive(player.$isActivePlaying) { isPlayerActive = $0 }
    }

    // MARK: - Empty state

    private var emptyDropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 44))
                .foregroundColor(isDragTargeted ? ControlTheme.accent : .secondary)
            Text("Drag tracks here from Music.app, Swinsian, or Finder")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDragTargeted ? ControlTheme.accent.opacity(0.08) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            Task {
                let urls = await loadURLs(from: providers)
                handleIncomingURLs(urls, anchorID: nil)
            }
            return true
        }
    }

    // MARK: - Drop handling

    private func handleIncomingURLs(_ urls: [URL], anchorID: UUID?) {
        guard settings.duplicateTrackProtection else {
            setlist.insertURLs(urls, before: anchorID)
            return
        }

        let existingURLs = Set(setlist.entries.map(\.fileURL))
        var fresh: [URL] = []
        var duplicates: [URL] = []
        for url in urls {
            if existingURLs.contains(url) { duplicates.append(url) } else { fresh.append(url) }
        }

        if !fresh.isEmpty { setlist.insertURLs(fresh, before: anchorID) }
        guard !duplicates.isEmpty else { return }

        switch setlist.duplicateSessionDecision {
        case .alwaysAdd:
            setlist.insertURLs(duplicates, before: anchorID)
        case .neverAdd:
            break
        case nil:
            let (shouldAdd, remember) = promptForDuplicates()
            if remember { setlist.setDuplicateSessionDecision(shouldAdd ? .alwaysAdd : .neverAdd) }
            if shouldAdd { setlist.insertURLs(duplicates, before: anchorID) }
        }
    }

    private func promptForDuplicates() -> (shouldAdd: Bool, remember: Bool) {
        let alert = NSAlert()
        alert.messageText = "Track Already in Setlist"
        alert.informativeText = "This track already exists in this set. Add anyway?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Don't Add")

        let checkbox = NSButton(checkboxWithTitle: "Remember for this session", target: nil, action: nil)
        checkbox.sizeToFit()
        alert.accessoryView = checkbox

        let result = alert.runModal()
        return (
            shouldAdd: result == .alertFirstButtonReturn,
            remember: checkbox.state == .on
        )
    }

    // MARK: - Track list

    private var nextToPlayID: UUID? {
        guard !isPlayerActive,
              !setlist.entries.contains(where: { $0.state == .playing || $0.state == .paused })
        else { return nil }
        return setlist.entries.first(where: { $0.state == .queued })?.id
    }

    private var trackList: some View {
        List(selection: $selectedIDs) {
            ForEach(setlist.entries) { entry in
                SetlistRowView(
                    entry: entry,
                    isStopAfter: entry.id == setlist.stopAfterEntryID,
                    isActivelyPlaying: activeEntryID == entry.id && isPlayerActive,
                    isNextToPlay: entry.id == nextToPlayID,
                    showYear: settings.showYear,
                    showTime: settings.showTime,
                    showComments: settings.showComments,
                    showAlbumArtist: settings.showAlbumArtist
                )
                .tag(entry.id)
                .moveDisabled(entry.state == .played)
                // NSViewRepresentable overlay handles double-click without adding any
                // SwiftUI gesture recognizer — keeping NSTableView's primary click
                // handler free to process single/multi-selection.
                .overlay(DoubleClickOverlay { player.jumpTo(entry) })
                .contextMenu {
                    let targets: Set<UUID> = selectedIDs.contains(entry.id)
                        ? selectedIDs
                        : [entry.id]
                    let allPlayed = targets.allSatisfy { id in
                        setlist.entries.first(where: { $0.id == id })?.state == .played
                    }
                    if allPlayed {
                        Button("Mark as Not Played") {
                            setlist.markUnplayed(ids: targets)
                        }
                    } else {
                        Button("Mark as Played") {
                            setlist.markPlayed(ids: targets)
                            selectedIDs.subtract(targets)
                        }
                    }
                    if targets.count == 1, let id = targets.first {
                        Divider()
                        Button {
                            setlist.stopAfterEntryID = (setlist.stopAfterEntryID == id) ? nil : id
                        } label: {
                            Text(setlist.stopAfterEntryID == id ? "Resume after Playing" : "Stop after Playing")
                        }
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        pendingDeleteIDs = targets
                    }
                }
            }
            .onMove { source, dest in
                setlist.move(from: source, to: dest)
            }
            .onDelete { offsets in
                let ids = Set(offsets.compactMap { setlist.entries[safe: $0]?.id })
                pendingDeleteIDs = ids
            }
            .onInsert(of: [.fileURL]) { offset, providers in
                // Convert the integer offset to a stable UUID anchor immediately,
                // before any async work — the list may mutate during URL/metadata loading.
                let anchorID: UUID? = offset < setlist.entries.count
                    ? setlist.entries[offset].id
                    : nil
                Task {
                    let urls = await loadURLs(from: providers)
                    handleIncomingURLs(urls, anchorID: anchorID)
                }
            }
        }
        .listStyle(.plain)
        .overlay(alignment: .bottom) {
            dropHint
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    exportPlaylistName = Self.defaultExportName()
                    showExportDialog = true
                } label: {
                    Label("Export to Apple Music", systemImage: "square.and.arrow.up")
                }
                .disabled(setlist.entries.isEmpty)
            }
            ToolbarItem(placement: .automatic) {
                Button { showEQPopover.toggle() } label: {
                    Label("Equaliser", systemImage: "slider.horizontal.3")
                }
                .disabled(!isPlayerActive)
                .popover(isPresented: $showEQPopover) {
                    EQView().environmentObject(settings)
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) { showClearConfirmation = true } label: {
                    Label("Clear Setlist", systemImage: "trash")
                }
                .disabled(setlist.entries.isEmpty)
            }
        }
        .confirmationDialog(
            "Clear Setlist?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { setlist.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if isPlayerActive {
                Text("Playback will stop and all tracks will be removed.")
            } else {
                Text("All tracks will be removed.")
            }
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: Binding(
                get: { pendingDeleteIDs != nil },
                set: { if !$0 { pendingDeleteIDs = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let ids = pendingDeleteIDs {
                    setlist.remove(ids: ids)
                    selectedIDs.subtract(ids)
                    pendingDeleteIDs = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDeleteIDs = nil }
        }
        .alert("Export to Apple Music", isPresented: $showExportDialog) {
            TextField("Playlist name", text: $exportPlaylistName)
            Button("Export") {
                let trimmed = exportPlaylistName.trimmingCharacters(in: .whitespaces)
                let name = trimmed.isEmpty ? Self.defaultExportName() : trimmed
                let urls = setlist.entries.map(\.fileURL)
                createAppleMusicPlaylist(name: name, fileURLs: urls) { result in
                    if case .failure(let error) = result {
                        exportErrorMessage = error.localizedDescription
                        showExportError = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
    }

    private var deleteConfirmationTitle: String {
        let count = pendingDeleteIDs?.count ?? 0
        return count == 1 ? "Delete Track?" : "Delete \(count) Tracks?"
    }

    private static func defaultExportName() -> String {
        let f = DateFormatter()
        f.dateFormat = "ddMMyy HH:mm"
        return "Tango Display SetList \(f.string(from: Date()))"
    }

    private func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            let url: URL? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let url = item as? URL {
                        continuation.resume(returning: url)
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        continuation.resume(returning: url)
                    } else if let nsURL = item as? NSURL {
                        continuation.resume(returning: nsURL as URL)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            if let url, url.isFileURL {
                urls.append(url)
            }
        }
        return urls
    }

    private var dropHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("Drop tracks to add")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.bottom, 8)
    }
}

// MARK: - Status bar (isolated observer — re-renders every 0.5 s without affecting SetlistView)

private struct StatusBarView: View {
    @ObservedObject var player: LocalPlayerSource
    @ObservedObject var setlist: SetlistManager
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text(formatDuration(setlist.totalPlaylistDuration))
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)

            Spacer()

            HStack(spacing: 4) {
                Text("Ends at:")
                Text(formattedEndTime)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var setEndTime: Date? {
        guard appState.currentPlayerState != .stopped else { return nil }
        var remaining: TimeInterval = 0
        let stopAfterID = setlist.stopAfterEntryID
        for entry in setlist.entries {
            switch entry.state {
            case .playing:
                remaining += max(0, (entry.duration ?? 0) - player.elapsed)
            case .paused, .queued:
                remaining += entry.duration ?? 0
            case .played:
                break
            }
            if let stopID = stopAfterID, entry.id == stopID { break }
        }
        return Date().addingTimeInterval(remaining)
    }

    private var formattedEndTime: String {
        guard let end = setEndTime else { return "play to calculate" }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: end)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        setlistFormatDuration(seconds)
    }
}

// MARK: - Double-click overlay

// Uses NSClickGestureRecognizer with delaysPrimaryMouseButtonEvents = false so
// NSTableView receives primary clicks unobstructed (enabling mouse selection),
// while still detecting double-clicks to jump to a track.
private struct DoubleClickOverlay: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let gr = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.fired)
        )
        gr.numberOfClicksRequired = 2
        gr.delaysPrimaryMouseButtonEvents = false
        view.addGestureRecognizer(gr)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fired() { action() }
    }
}

// MARK: - Row

struct SetlistRowView: View {
    let entry: SetlistEntry
    let isStopAfter: Bool
    var isActivelyPlaying: Bool = false
    var isNextToPlay: Bool = false
    var showYear: Bool = true
    var showTime: Bool = true
    var showComments: Bool = false
    var showAlbumArtist: Bool = false

    private var isCurrent: Bool { entry.state == .playing || entry.state == .paused || isActivelyPlaying }
    private var isCurrentPlaying: Bool { entry.state == .playing || isActivelyPlaying }

    var body: some View {
        HStack(spacing: 8) {
            stateIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.track.title)
                    .font(.system(size: 13))
                    .fontWeight(entry.state == .queued ? .medium : .regular)
                    .lineLimit(1)
                    .foregroundColor(entry.state == .played && !isActivelyPlaying ? .secondary : .primary)
                Text(entry.track.artist + (showYear ? (entry.track.year.map { " · \($0)" } ?? "") : ""))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                let extraParts = [
                    showComments ? entry.track.comment : nil,
                    showAlbumArtist ? entry.track.albumArtist : nil
                ].compactMap { $0 }.filter { !$0.isEmpty }
                if !extraParts.isEmpty {
                    Text(extraParts.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if showTime, let dur = entry.duration {
                Text(setlistFormatDuration(dur))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if !entry.track.genre.isEmpty {
                Text(entry.track.genre)
                    .font(.system(size: 10))
                    .foregroundColor(genreTagColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(genreTagColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            if isStopAfter {
                Image(systemName: "stop.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 3)
        .listRowBackground(rowBackground)
    }

    private var genreTagColor: Color {
        if isNextToPlay { return .accentColor }
        if isCurrent && isCurrentPlaying { return .green }
        if isCurrent && entry.state == .paused { return .orange }
        return .secondary
    }

    private var rowBackground: Color {
        if isNextToPlay { return Color.accentColor.opacity(0.15) }
        guard isCurrent else { return .clear }
        return entry.state == .paused ? Color.orange.opacity(0.15) : Color.accentColor.opacity(0.15)
    }

    private var stateIndicator: some View {
        Group {
            switch entry.state {
            case .playing:
                Image(systemName: "waveform")
                    .foregroundColor(.green)
            case .paused:
                Image(systemName: "stop.fill")
                    .foregroundColor(.orange)
            case .played:
                Image(systemName: "checkmark")
                    .foregroundColor(isCurrentPlaying ? .green : Color.secondary.opacity(0.6))
            case .queued:
                if isNextToPlay {
                    Image(systemName: "play.fill")
                        .foregroundColor(.accentColor)
                } else {
                    Color.clear
                }
            }
        }
        .font(.system(size: 11))
        .frame(width: 14)
    }
}
