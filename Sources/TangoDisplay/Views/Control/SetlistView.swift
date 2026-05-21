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
    @EnvironmentObject var reportStore: SetlistReportStore
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
    @State private var showSaveReportDialog = false
    @State private var saveReportName = ""
    @State private var showSaveReportError = false
    @State private var saveReportErrorMessage = ""
    @State private var showEQPopover = false
    @State private var showBalancePopover = false
    @State private var showAutoGapPopover = false
    @State private var showReplayGainPopover = false
    @State private var scrollTrigger: UUID? = nil
    @State private var showLastTandaWarning = false
    @State private var pasteMonitor: Any? = nil

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
            guard pasteMonitor == nil else { return }
            pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers?.lowercased() == "v",
                      !(NSApp.keyWindow?.firstResponder is NSText) else { return event }
                pasteFromClipboard()
                return nil
            }
        }
        .onDisappear {
            if let m = pasteMonitor { NSEvent.removeMonitor(m); pasteMonitor = nil }
        }
        .onReceive(player.$currentEntryID) { activeEntryID = $0 }
        .onReceive(player.$isActivePlaying) { isPlayerActive = $0 }
        .alert("Save Setlist Report", isPresented: $showSaveReportDialog) {
            TextField("Setlist name", text: $saveReportName)
            Button("Save") {
                let trimmed = saveReportName.trimmingCharacters(in: .whitespaces)
                let name = trimmed.isEmpty ? Self.defaultExportName() : trimmed
                saveSetlistReport(name: name)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for this setlist export. It will appear in the Reports tab.")
        }
        .alert("Save Failed", isPresented: $showSaveReportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveReportErrorMessage)
        }
    }

    // MARK: - Empty state

    private var emptyDropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 44))
                .foregroundColor(isDragTargeted ? ControlTheme.accent : .secondary)
            Text("Drag tracks here, or copy in your music app and press ⌘V")
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
        guard !isPlayerActive else { return nil }
        if let id = activeEntryID { return id }
        guard !setlist.entries.contains(where: { $0.state == .playing || $0.state == .paused })
        else { return nil }
        return setlist.entries.first(where: { $0.state == .queued })?.id
    }

    @ViewBuilder
    private func rowView(for entry: SetlistEntry, wouldSkipAutoGap: Bool) -> some View {
        let detector = settings.makeDetector()
        SetlistRowView(
            entry: entry,
            isStopAfter: entry.id == setlist.stopAfterEntryID,
            isActivelyPlaying: activeEntryID == entry.id && isPlayerActive,
            isNextToPlay: entry.id == nextToPlayID,
            showYear: settings.showYear,
            showTime: settings.showTime,
            showComments: settings.showComments,
            showAlbumArtist: settings.showAlbumArtist,
            wouldSkipAutoGap: wouldSkipAutoGap,
            autoFadeCortinasEnabled: settings.autoFadeCortinasEnabled,
            isLastTanda: entry.isLastTanda,
            genreColorsEnabled: settings.genreColorsEnabled,
            genreColorRules: settings.genreColorRules,
            genreColorTitleEnabled: settings.genreColorTitleEnabled,
            isCortina: detector.isCortina(genre: entry.track.genre),
            player: activeEntryID == entry.id && isPlayerActive ? player : nil
        )
        .tag(entry.id)
        .moveDisabled(entry.state == .playing)
        // NSViewRepresentable overlay handles double-click without adding any
        // SwiftUI gesture recognizer — keeping NSTableView's primary click
        // handler free to process single/multi-selection.
        .overlay(DoubleClickOverlay { player.jumpTo(entry) })
        .contextMenu {
            let targets: Set<UUID> = selectedIDs.contains(entry.id)
                ? selectedIDs : [entry.id]
            rowContextMenu(entry: entry, targets: targets)
        }
    }

    private var trackList: some View {
        let firstID = setlist.entries.first?.id
        let nonePlayedYet = !setlist.entries.contains(where: { $0.state == .played })
        let isIgnoringFirstTrack = settings.autoGapEnabled && settings.autoGapIgnoreFirstTrack
        return List(selection: $selectedIDs) {
            ForEach(setlist.entries) { entry in
                let wouldSkipAutoGap = isIgnoringFirstTrack && nonePlayedYet && entry.state == .queued && entry.id == firstID
                rowView(for: entry, wouldSkipAutoGap: wouldSkipAutoGap)
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
                Menu {
                    Button("Export to Apple Music") {
                        exportPlaylistName = Self.defaultExportName()
                        showExportDialog = true
                    }
                    Button("Export to M3U8…") {
                        exportM3U8()
                    }
                    Divider()
                    Button("Save Setlist Report…") {
                        saveReportName = Self.defaultExportName()
                        showSaveReportDialog = true
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(setlist.entries.isEmpty)
            }
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 2) {
                    Button { showEQPopover.toggle() } label: {
                        Label("Equaliser", systemImage: "slider.horizontal.3")
                    }
                    .disabled(!isPlayerActive)
                    .popover(isPresented: $showEQPopover) {
                        EQView().environmentObject(settings)
                    }
                    Button { showBalancePopover.toggle() } label: {
                        Label("Balance", systemImage: "dial.medium")
                    }
                    .disabled(!isPlayerActive)
                    .popover(isPresented: $showBalancePopover) {
                        BalanceView().environmentObject(settings)
                    }
                    Button { showAutoGapPopover.toggle() } label: {
                        Label("Auto-gap", systemImage: "timer")
                    }
                    .disabled(!settings.autoGapEnabled)
                    .popover(isPresented: $showAutoGapPopover) {
                        AutoGapPopoverView().environmentObject(settings)
                    }
                    Button { showReplayGainPopover.toggle() } label: {
                        Label("ReplayGain", systemImage: "waveform")
                    }
                    .popover(isPresented: $showReplayGainPopover) {
                        ReplayGainPopoverView(player: player)
                            .environmentObject(settings)
                    }
                    if settings.selectedAudioUnitPlugin != nil {
                        Button { player.openPluginWindow() } label: {
                            Label("Plugin", systemImage: "puzzlepiece.fill")
                        }
                        .disabled(!settings.audioUnitPluginEnabled || settings.audioUnitPluginBypassed)
                    }
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
        .alert("Last Tanda Not Configured", isPresented: $showLastTandaWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Set the Last Tanda label text in Appearance Settings before marking a Last Tanda.")
        }
    }

    private var deleteConfirmationTitle: String {
        let count = pendingDeleteIDs?.count ?? 0
        return count == 1 ? "Delete Track?" : "Delete \(count) Tracks?"
    }

    @ViewBuilder
    private func rowContextMenu(entry: SetlistEntry, targets: Set<UUID>) -> some View {
        let allPlayed = targets.allSatisfy { id in
            setlist.entries.first(where: { $0.id == id })?.state == .played
        }
        if allPlayed {
            Button("Mark as Not Played") { setlist.markUnplayed(ids: targets) }
        } else {
            Button("Mark as Played") {
                setlist.markPlayed(ids: targets)
                selectedIDs.subtract(targets)
            }
        }
        if targets.count == 1, let id = targets.first,
           let e = setlist.entries.first(where: { $0.id == id }) {
            Divider()
            if e.state != .played {
                Button {
                    setlist.stopAfterEntryID = (setlist.stopAfterEntryID == id) ? nil : id
                } label: {
                    Text(setlist.stopAfterEntryID == id ? "Resume after Playing" : "Stop after Playing")
                }
            }
            if e.state == .queued || e.state == .paused {
                Button(e.ignoresAutoGap ? "Resume Auto-gap" : "Ignore Auto-gap before this Track") {
                    setlist.toggleIgnoresAutoGap(id: id)
                }
            }
        }
        let detector = settings.makeDetector()
        if settings.autoFadeCortinasEnabled && appState.fadeMode == .none {
            let autoFadeTargets = targets.filter { id in
                guard let e = setlist.entries.first(where: { $0.id == id }) else { return false }
                return (e.state != .played || e.id == player.currentEntryID) && detector.isCortina(genre: e.track.genre)
            }
            let skippable = autoFadeTargets.filter { id in
                !(setlist.entries.first(where: { $0.id == id })?.ignoresAutoFade ?? false)
            }
            if !skippable.isEmpty {
                Divider()
                Button("Skip Auto-fade") {
                    for id in skippable { appState.toggleIgnoresAutoFadeForEntry(id: id) }
                }
            }
        }
        // Last Tanda: single cortina entry not yet fully played
        if targets.count == 1, let id = targets.first,
           let e = setlist.entries.first(where: { $0.id == id }),
           detector.isCortina(genre: e.track.genre),
           e.state != .played || e.id == player.currentEntryID {
            Divider()
            Button(e.isLastTanda ? "Remove Last Tanda" : "Mark as Last Tanda") {
                if !e.isLastTanda &&
                   settings.lastTandaLabel.trimmingCharacters(in: .whitespaces).isEmpty {
                    showLastTandaWarning = true
                } else {
                    appState.setLastTanda(id: id, value: !e.isLastTanda)
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { pendingDeleteIDs = targets }
    }

    private func exportM3U8() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(Self.defaultExportName()).m3u8"
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u8") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var lines = ["#EXTM3U"]
        for entry in setlist.entries {
            let secs = Int(entry.duration ?? -1)
            lines.append("#EXTINF:\(secs),\(entry.track.artist) - \(entry.track.title)")
            lines.append(entry.fileURL.path)
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func saveSetlistReport(name: String) {
        let entries = setlist.entries.map { e in
            SetlistReportEntry(
                title: e.track.title,
                artist: e.track.artist,
                genre: settings.displayLabel(for: e.track.genre),
                year: e.track.year,
                albumArtist: e.track.albumArtist,
                duration: e.duration,
                isPlayed: e.state != .queued,
                isLastTanda: e.isLastTanda
            )
        }
        let report = SetlistReport(id: UUID(), name: name, exportDate: Date(), entries: entries)
        do {
            try reportStore.save(report)
        } catch {
            saveReportErrorMessage = error.localizedDescription
            showSaveReportError = true
        }
    }

    private static func defaultExportName() -> String {
        let f = DateFormatter()
        f.dateFormat = "ddMMyy HH:mm"
        return "Tango Display SetList \(f.string(from: Date()))"
    }

    private func pasteFromClipboard() {
        let urls = (NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                    options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty {
            handleIncomingURLs(urls, anchorID: nil)
            return
        }

        // Foobar2000 uses a proprietary type; each item is a plist [fileURLString, 0]
        let foobarType = NSPasteboard.PasteboardType("com.foobar2000.location")
        var foobarURLs: [URL] = []
        for item in NSPasteboard.general.pasteboardItems ?? [] {
            guard let data = item.data(forType: foobarType),
                  let array = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [Any],
                  let urlString = array.first as? String,
                  let url = URL(string: urlString), url.isFileURL else { continue }
            foobarURLs.append(url)
        }
        guard !foobarURLs.isEmpty else { return }
        handleIncomingURLs(foobarURLs, anchorID: nil)
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
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(settings.autoGapEnabled ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(settings.autoGapEnabled
                        ? "Auto-gap: \(settings.autoGapDuration, specifier: "%.1f")s"
                        : "Auto-gap: off")
                }
                .font(.system(size: 11))
                .foregroundColor(settings.autoGapEnabled ? .primary : .secondary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(settings.autoFadeCortinasEnabled ? Color.orange : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text("Auto-fade: \(settings.autoFadeCortinasEnabled ? "on" : "off")")
                }
                .font(.system(size: 11))
                .foregroundColor(settings.autoFadeCortinasEnabled ? .primary : .secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(formatDuration(setlist.totalPlaylistDuration))
                    Text("·")
                    Text("\(unplayedCount) remaining")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Text("Next cortina:")
                    Text(setlistFormatDuration(timeUntilNextCortina))
                        .monospacedDigit()
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Text("Ends at:")
                    Text(formattedEndTime)
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var unplayedCount: Int {
        setlist.entries.filter { $0.state != .played }.count
    }

    private var timeUntilNextCortina: TimeInterval {
        let detector = settings.makeDetector()
        let entries = setlist.entries

        let startIdx: Int
        var remaining: TimeInterval

        if let id = player.currentEntryID,
           let idx = entries.firstIndex(where: { $0.id == id }) {
            let entry = entries[idx]
            if detector.isCortina(genre: entry.track.genre) { return 0 }
            startIdx = idx
            remaining = max(0, (entry.duration ?? 0) - player.elapsed)
        } else if let idx = entries.firstIndex(where: { $0.state != .played }) {
            let entry = entries[idx]
            if detector.isCortina(genre: entry.track.genre) { return 0 }
            startIdx = idx
            remaining = entry.duration ?? 0
        } else {
            return 0
        }

        for entry in entries[(startIdx + 1)...] {
            guard entry.state != .played else { continue }
            if detector.isCortina(genre: entry.track.genre) { return remaining }
            remaining += entry.duration ?? 0
        }
        return 0
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
                if entry.id == player.currentEntryID {
                    remaining += max(0, (entry.duration ?? 0) - player.elapsed)
                }
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
    var wouldSkipAutoGap: Bool = false
    var autoFadeCortinasEnabled: Bool = false
    var isLastTanda: Bool = false
    var genreColorsEnabled: Bool = false
    var genreColorRules: [GenreColorRule] = []
    var genreColorTitleEnabled: Bool = false
    var isCortina: Bool = false
    var player: LocalPlayerSource? = nil

    private var isCurrent: Bool { entry.state == .playing || entry.state == .paused || isActivelyPlaying }
    private var isCurrentPlaying: Bool { entry.state == .playing || isActivelyPlaying }
    private var isBoldBright: Bool {
        guard entry.state == .queued, !isNextToPlay, !isCurrent else { return false }
        return !genreColorsEnabled || isCortina
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                stateIndicator

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.track.title)
                        .font(.system(size: 13))
                        .fontWeight(isBoldBright ? .semibold : (entry.state == .queued ? .medium : .regular))
                        .lineLimit(1)
                        .foregroundColor(genreColorTitleEnabled ? genreTagColor : (entry.state == .played && !isActivelyPlaying ? .secondary : .primary))
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
                if entry.autoGapApplied {
                    Image(systemName: "wave.3.left.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                } else if entry.ignoresAutoGap || entry.autoGapSkipped || wouldSkipAutoGap {
                    Image(systemName: "wave.3.left.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if autoFadeCortinasEnabled && entry.ignoresAutoFade {
                    Image(systemName: "speaker.slash")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
                if isLastTanda {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }
            .padding(.top, 3)
            .padding(.bottom, isCurrent && player != nil ? 2 : 3)

            if isCurrent, let player = player {
                RowProgressBarView(player: player, entry: entry)
                    .padding(.leading, 22)
                    .padding(.bottom, 5)
            }
        }
        .contentShape(Rectangle())
        .listRowBackground(rowBackground)
    }

    private var genreTagColor: Color {
        if isNextToPlay { return .accentColor }
        if isCurrent && isCurrentPlaying { return .green }
        if isCurrent && entry.state == .paused { return .orange }
        if entry.state == .queued && genreColorsEnabled && !isCortina {
            if let rule = genreColorRules.first(where: {
                entry.track.genre.localizedCaseInsensitiveContains($0.keyword)
            }) {
                return Color(hex: rule.colorHex)
            }
        }
        if isBoldBright { return .primary }
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

// MARK: - In-row progress bar

private struct RowProgressBarView: View {
    @ObservedObject var player: LocalPlayerSource
    @EnvironmentObject var appState: AppState
    let entry: SetlistEntry

    var body: some View {
        let barColor: Color = entry.state == .paused ? .orange : ControlTheme.accent
        VStack(spacing: 2) {
            GeometryReader { geo in
                let progress = player.duration > 0
                    ? player.elapsed / max(player.duration, 1)
                    : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: geo.size.width * progress, height: 3)
                    let shouldShowPlayed = !appState.settings.markAsPlayedAfterCompletion
                        && player.duration > 0
                        && !player.isCurrentEntryMarkedAsPlayed
                    let playedFraction = min(1.0,
                        Double(appState.settings.markAsPlayedAfterSeconds) / player.duration)
                    Rectangle()
                        .fill(ControlTheme.accent.opacity(0.7))
                        .frame(width: 2, height: 8)
                        .position(x: playedFraction * geo.size.width, y: geo.size.height / 2)
                        .opacity(shouldShowPlayed ? 1 : 0)
                    let autoFadeDelay: Double = {
                        guard appState.settings.autoFadeCortinasEnabled,
                              appState.displayState.mode == .cortina,
                              player.duration > 0 else { return -1 }
                        if entry.ignoresAutoFade { return -1 }
                        let fade = appState.settings.builtInFadeDuration
                        let play = appState.settings.cortinaPlayTime
                        let dur = player.duration
                        if dur > play + fade { return play }
                        if dur > fade        { return dur - fade }
                        return -1
                    }()
                    Rectangle()
                        .fill(Color.orange.opacity(0.85))
                        .frame(width: 2, height: 8)
                        .position(x: (autoFadeDelay / player.duration) * geo.size.width,
                                  y: geo.size.height / 2)
                        .opacity(autoFadeDelay >= 0 ? 1 : 0)
                }
                .allowsHitTesting(false)
            }
            .frame(height: 16)
            HStack {
                Text(formatTime(player.elapsed))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text("-\(formatTime(max(0, player.duration - player.elapsed)))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
