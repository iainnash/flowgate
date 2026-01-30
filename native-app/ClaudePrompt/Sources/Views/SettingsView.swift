import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @Environment(\.dismiss) var dismiss

    @State private var acceptKey: String
    @State private var denyKey: String
    @State private var otherKey: String
    @State private var toggleKey: String
    @State private var floatingWindow: Bool
    @State private var showInMenuBar: Bool

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        let settings = settingsManager.settings
        _acceptKey = State(initialValue: settings.native.globalHotkeys.accept)
        _denyKey = State(initialValue: settings.native.globalHotkeys.deny)
        _otherKey = State(initialValue: settings.native.globalHotkeys.other)
        _toggleKey = State(initialValue: settings.native.globalHotkeys.toggle)
        _floatingWindow = State(initialValue: settings.native.floatingWindow)
        _showInMenuBar = State(initialValue: settings.native.showInMenuBar)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    saveSettings()
                    dismiss()
                }
                .keyboardShortcut(.return)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Settings content
            Form {
                Section("Hotkeys") {
                    HStack {
                        Text("Accept prompt")
                        Spacer()
                        TextField("", text: $acceptKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .multilineTextAlignment(.center)
                    }

                    HStack {
                        Text("Deny prompt")
                        Spacer()
                        TextField("", text: $denyKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .multilineTextAlignment(.center)
                    }

                    HStack {
                        Text("Other response")
                        Spacer()
                        TextField("", text: $otherKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .multilineTextAlignment(.center)
                    }

                    HStack {
                        Text("Toggle window")
                        Spacer()
                        TextField("", text: $toggleKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .multilineTextAlignment(.center)
                    }

                    Text("Format: cmd+shift+key (e.g., cmd+shift+y)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Navigation") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard shortcuts:")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack {
                            Text("↑ / k")
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                            Text("Select previous prompt")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("↓ / j")
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                            Text("Select next prompt")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Enter")
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                            Text("Accept selected")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Escape")
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                            Text("Deny selected")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Window") {
                    Toggle("Float on top", isOn: $floatingWindow)
                    Toggle("Show in menu bar", isOn: $showInMenuBar)
                }

                Section("Server") {
                    HStack {
                        Text("Server URL")
                        Spacer()
                        Text("http://127.0.0.1:8888")
                            .foregroundColor(.secondary)
                    }

                    Button("Sync settings from server") {
                        Task {
                            await settingsManager.syncWithServer()
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 500)
    }

    private func saveSettings() {
        settingsManager.settings.native.globalHotkeys.accept = acceptKey
        settingsManager.settings.native.globalHotkeys.deny = denyKey
        settingsManager.settings.native.globalHotkeys.other = otherKey
        settingsManager.settings.native.globalHotkeys.toggle = toggleKey
        settingsManager.settings.native.floatingWindow = floatingWindow
        settingsManager.settings.native.showInMenuBar = showInMenuBar
        settingsManager.saveToFile()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settingsManager: SettingsManager())
    }
}
