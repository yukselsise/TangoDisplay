import SwiftUI
import TangoDisplayCore

struct AppearanceColoursTab: View {
    @Binding var working: AppearanceProfile

    var body: some View {
        Form {
            Section {
                colorRow("Background",    hex: $working.backgroundColor)
                colorRow("Artist",        hex: $working.artistColor)
                colorRow("Title",         hex: $working.titleColor)
                colorRow("Genre / Label", hex: $working.genreColor)
                colorRow("Year",          hex: $working.yearColor)
                colorRow("Singer",        hex: $working.singerColor)
                colorRow("Track Counter", hex: $working.trackCounterColor)
            } header: {
                Text("Display Colours")
                    .foregroundColor(ControlTheme.accent)
            }

            Section {
                colorRow("Cortina Label",    hex: $working.cortinaLabelColor)
                colorRow("Next Up Label",    hex: $working.nextUpLabelColor)
                colorRow("Cortina Artist",   hex: $working.cortinaArtistColor)
                colorRow("Cortina Title",    hex: $working.cortinaTitleColor)
                colorRow("Idle Message",     hex: $working.idleMessageColor)
            } header: {
                Text("Labels & Messages")
                    .foregroundColor(ControlTheme.accent)
            }

            Section {
                colorRow("Override Text", hex: $working.overrideTextColor)
            } header: {
                Text("Override Text")
                    .foregroundColor(ControlTheme.accent)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Colour row helper

    private func colorRow(_ label: String, hex: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(hex: hex.wrappedValue) },
                set: { hex.wrappedValue = $0.hexString }
            ))
            .labelsHidden()
            .frame(width: 44)
        }
    }
}
