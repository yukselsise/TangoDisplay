import AppKit
import SwiftUI
import TangoDisplayCore

struct PerformanceSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    @State private var bgThumbnail: NSImage? = nil

    private let availableFonts: [String] = ["System"] + NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            backgroundSection
            Divider()
            textLinesSection
        }
        .onAppear { reloadThumbnail() }
    }

    // MARK: - Background image

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background Image")
                .font(.subheadline.bold())

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
                            .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                    }
                }
                Spacer()
                Button(settings.performanceBackgroundImageFilename == nil ? "Pick Image…" : "Change Image…") {
                    pickBackgroundImage()
                }
                .buttonStyle(.bordered)
                if settings.performanceBackgroundImageFilename != nil {
                    Button("Clear") { clearBackgroundImage() }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                }
            }

            if settings.performanceBackgroundImageFilename != nil {
                Toggle("Show during cortina", isOn: $settings.performanceBackgroundDuringCortina)
                    .toggleStyle(.checkbox)
                    .help("Use the performance background image during the cortina that precedes a performance track")
            }
        }
    }

    private func pickBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a background image for the performance display"
        guard panel.runModal() == .OK, let src = panel.url else { return }

        let ext = src.pathExtension.isEmpty ? "jpg" : src.pathExtension
        let filename = "performance-bg.\(ext)"
        let dest = appState.profileStore.imageURL(for: filename)
        appState.profileStore.createImagesDirectoryIfNeeded()

        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try? FileManager.default.copyItem(at: src, to: dest)

        settings.performanceBackgroundImageFilename = filename
        bgThumbnail = NSImage(contentsOf: dest)
    }

    private func clearBackgroundImage() {
        if let filename = settings.performanceBackgroundImageFilename {
            try? FileManager.default.removeItem(at: appState.profileStore.imageURL(for: filename))
        }
        settings.performanceBackgroundImageFilename = nil
        bgThumbnail = nil
    }

    private func reloadThumbnail() {
        guard let filename = settings.performanceBackgroundImageFilename else {
            bgThumbnail = nil
            return
        }
        bgThumbnail = NSImage(contentsOf: appState.profileStore.imageURL(for: filename))
    }

    // MARK: - Text lines

    private var textLinesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Text Lines")
                .font(.subheadline.bold())

            Text("Available placeholders: {title}  {artist}  {genre}  {year}")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(settings.performanceTextLines.indices, id: \.self) { index in
                textLineRow(line: $settings.performanceTextLines[index], number: index + 1)
            }
            .onMove { from, to in
                settings.performanceTextLines.move(fromOffsets: from, toOffset: to)
            }
            .onDelete { offsets in
                settings.performanceTextLines.remove(atOffsets: offsets)
            }

            Button {
                settings.performanceTextLines.append(
                    PerformanceTextLine(text: "", fontName: "System", fontSize: 48, colorHex: "#FFFFFF")
                )
            } label: {
                Label("Add Line", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func textLineRow(line: Binding<PerformanceTextLine>, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Text Line \(number)", text: line.text)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Picker("Font", selection: line.fontName) {
                    ForEach(availableFonts, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .labelsHidden()
                .frame(width: 180)

                Text(String(format: "%.0fpt", line.wrappedValue.fontSize))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)

                Stepper("", value: line.fontSize, in: 8...300, step: 4)
                    .labelsHidden()
                    .fixedSize()

                Toggle("Show during cortina", isOn: line.showDuringCortina)
                    .toggleStyle(.checkbox)
                    .help("Show this line during the cortina before a performance")
                    .fixedSize()

                Spacer()

                ColorPicker("", selection: Binding(
                    get: { Color(hex: line.wrappedValue.colorHex) },
                    set: { newColor in
                        if let hex = nsHex(from: newColor) {
                            line.wrappedValue.colorHex = hex
                        }
                    }
                ))
                .labelsHidden()
                .frame(width: 32)

                Button(role: .destructive) {
                    if let idx = settings.performanceTextLines.firstIndex(where: { $0.id == line.wrappedValue.id }) {
                        settings.performanceTextLines.remove(at: idx)
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.07))
        .cornerRadius(6)
    }

    private func nsHex(from color: Color) -> String? {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let r = Int(ns.redComponent * 255)
        let g = Int(ns.greenComponent * 255)
        let b = Int(ns.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
