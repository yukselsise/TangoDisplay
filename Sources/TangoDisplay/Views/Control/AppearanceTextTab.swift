import AppKit
import SwiftUI
import TangoDisplayCore

struct AppearanceTextTab: View {
    @Binding var working: AppearanceProfile

    private let availableFonts: [String] = ["System"] + NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        Form {
            Section {
                fontRow("Artist",        name: $working.artistFontName,       size: $working.artistFontSize,
                        bold: $working.artistFontBold,       italic: $working.artistFontItalic)
                fontRow("Title",         name: $working.titleFontName,        size: $working.titleFontSize,
                        bold: $working.titleFontBold,        italic: $working.titleFontItalic)
                fontRow("Genre",         name: $working.genreFontName,        size: $working.genreFontSize,
                        bold: $working.genreFontBold,        italic: $working.genreFontItalic)
                fontRow("Year",          name: $working.yearFontName,         size: $working.yearFontSize,
                        bold: $working.yearFontBold,         italic: $working.yearFontItalic)
                HStack {
                    Text("Singer Source")
                        .frame(width: 100, alignment: .leading)
                    Picker("", selection: $working.singerSource) {
                        ForEach(SingerSource.allCases, id: \.self) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                fontRow("Singer",        name: $working.singerFontName,       size: $working.singerFontSize,
                        bold: $working.singerFontBold,       italic: $working.singerFontItalic)
                fontRow("Track Counter", name: $working.trackCounterFontName, size: $working.trackCounterFontSize,
                        bold: $working.trackCounterFontBold, italic: $working.trackCounterFontItalic)
            } header: {
                Text("Fonts")
                    .foregroundColor(ControlTheme.accent)
            }

            Section {
                fontRow("Cortina Label", name: $working.cortinaLabelFontName,  size: $working.cortinaLabelFontSize,
                        bold: $working.cortinaLabelFontBold,  italic: $working.cortinaLabelFontItalic)
                fontRow("Next Up Label", name: $working.nextUpLabelFontName,   size: $working.nextUpLabelFontSize,
                        bold: $working.nextUpLabelFontBold,   italic: $working.nextUpLabelFontItalic)
                fontRow("Idle Message",  name: $working.idleMessageFontName,   size: $working.idleMessageFontSize,
                        bold: $working.idleMessageFontBold,   italic: $working.idleMessageFontItalic)
                fontRow("Cortina Artist", name: $working.cortinaArtistFontName, size: $working.cortinaArtistFontSize,
                        bold: $working.cortinaArtistFontBold, italic: $working.cortinaArtistFontItalic)
                fontRow("Cortina Title",  name: $working.cortinaTitleFontName,  size: $working.cortinaTitleFontSize,
                        bold: $working.cortinaTitleFontBold,  italic: $working.cortinaTitleFontItalic)
            } header: {
                Text("Cortina & Message Text")
                    .foregroundColor(ControlTheme.accent)
            } footer: {
                Label {
                    Text("Use larger sizes for projector-based venues.")
                } icon: {
                    Image(systemName: "info.circle")
                }
            }

            Section {
                fontRow("Override Text", name: $working.overrideTextFontName,   size: $working.overrideTextFontSize,
                        bold: $working.overrideTextFontBold, italic: $working.overrideTextFontItalic)
            } header: {
                Text("Override Text")
                    .foregroundColor(ControlTheme.accent)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Font row helper

    private func fontRow(_ label: String, name: Binding<String>, size: Binding<Double>,
                         bold: Binding<Bool>, italic: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .frame(width: 100, alignment: .leading)
            Picker("", selection: name) {
                ForEach(availableFonts, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .labelsHidden()
            .frame(width: 180, alignment: .leading)
            Spacer()
            Stepper(value: size, in: 8...200, step: 2) {
                Text(String(format: "%.0fpt", size.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 44)
            }
            Toggle("B", isOn: bold)
                .toggleStyle(.button)
                .font(.system(size: 12, weight: .bold))
                .help("Bold")
            Toggle("I", isOn: italic)
                .toggleStyle(.button)
                .font(.system(size: 12).italic())
                .help("Italic")
        }
    }
}
