import SwiftUI

struct DisplaySettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    @State private var draftCortinaLabel: String = ""
    @State private var draftNextUpLabel: String = ""
    @State private var draftIdleMessage: String = ""

    private var hasUnsavedLabelChanges: Bool {
        draftCortinaLabel != settings.cortinaLabel ||
        draftNextUpLabel  != settings.nextUpLabel  ||
        draftIdleMessage  != settings.idleMessage
    }

    var body: some View {
        Form {
            Section {
                Picker("Target display", selection: $settings.targetDisplayID) {
                    Text("Primary display").tag(Optional<UInt32>.none)
                    ForEach(appState.availableDisplays) { display in
                        Text(displayLabel(display)).tag(Optional(display.id))
                    }
                }

                HStack {
                    Button("Move Presentation Window") {
                        if let id = settings.targetDisplayID {
                            WindowManager.moveTo(displayID: id)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(settings.targetDisplayID == nil)

                    Button("Toggle Fullscreen") {
                        WindowManager.toggleFullscreen()
                    }
                    .buttonStyle(.bordered)
                }

                Text("Note: moving the window is not possible while in fullscreen mode.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Monitor")
                    .foregroundColor(ControlTheme.accent)
            }

            Section {
                Toggle("Mirror mode (show live preview in control window)", isOn: $settings.mirrorMode)
                Toggle("Show track counter (Track X of X)", isOn: $settings.showTrackCounter)
            } header: {
                Text("Control Window")
                    .foregroundColor(ControlTheme.accent)
            }

            Section {
                labelRow("Cortina",       binding: $draftCortinaLabel)
                labelRow("Coming up",     binding: $draftNextUpLabel)
                labelRow("Idle message",  binding: $draftIdleMessage)
                HStack {
                    if hasUnsavedLabelChanges {
                        Text("● Unsaved changes")
                            .font(.caption)
                            .foregroundColor(ControlTheme.accent)
                    }
                    Spacer()
                    Button("Save") {
                        settings.cortinaLabel = draftCortinaLabel
                        settings.nextUpLabel  = draftNextUpLabel
                        settings.idleMessage  = draftIdleMessage
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasUnsavedLabelChanges)
                }
            } header: {
                Text("Display Labels")
                    .foregroundColor(ControlTheme.accent)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            draftCortinaLabel = settings.cortinaLabel
            draftNextUpLabel  = settings.nextUpLabel
            draftIdleMessage  = settings.idleMessage
            appState.refreshDisplayList()
        }
    }

    private func displayLabel(_ d: DisplayInfo) -> String {
        d.isMain ? "\(d.name) (main)" : d.name
    }

    private func labelRow(_ label: String, binding: Binding<String>) -> some View {
        HStack {
            Text(label)
                .frame(width: 110, alignment: .leading)
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
        }
    }
}
