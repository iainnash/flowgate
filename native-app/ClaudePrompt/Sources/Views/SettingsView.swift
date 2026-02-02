import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @Environment(\.dismiss) var dismiss

    @State private var acceptKey: String
    @State private var denyKey: String
    @State private var otherKey: String
    @State private var toggleKey: String
    @State private var pauseAllKey: String
    @State private var floatingWindow: Bool
    @State private var showInMenuBar: Bool
    @State private var focusStealMode: FocusStealMode
    @State private var returnFocusWhenEmpty: Bool
    @State private var showAutoAccept: Bool
    @State private var enableAnimations: Bool

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        let settings = settingsManager.settings
        _acceptKey = State(initialValue: settings.nativeOnly.globalHotkeys.accept)
        _denyKey = State(initialValue: settings.nativeOnly.globalHotkeys.deny)
        _otherKey = State(initialValue: settings.nativeOnly.globalHotkeys.other)
        _toggleKey = State(initialValue: settings.nativeOnly.globalHotkeys.toggle)
        _pauseAllKey = State(initialValue: settings.nativeOnly.globalHotkeys.pauseAll)
        _floatingWindow = State(initialValue: settings.nativeOnly.floatingWindow)
        _showInMenuBar = State(initialValue: settings.nativeOnly.showInMenuBar)
        _focusStealMode = State(initialValue: settings.nativeOnly.focusStealMode)
        _returnFocusWhenEmpty = State(initialValue: settings.nativeOnly.returnFocusWhenEmpty)
        _showAutoAccept = State(initialValue: settings.server.native.showAutoAccept)
        _enableAnimations = State(initialValue: settings.server.native.enableAnimations)
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

                    HStack {
                        Text("Pause/Play all")
                        Spacer()
                        TextField("", text: $pauseAllKey)
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

                    Picker("Steal focus", selection: $focusStealMode) {
                        ForEach(FocusStealMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Toggle("Return focus when empty", isOn: $returnFocusWhenEmpty)
                        .help("Automatically return focus to the previous app when all prompts are cleared")
                }
                    .pickerStyle(.menu)

                    Toggle("Show auto-accept prompts", isOn: $showAutoAccept)
                    Toggle("Enable animations", isOn: $enableAnimations)
                }

                Section("Server") {
                    HStack {
                        Text("Server URL")
                        Spacer()
                        Text("http://127.0.0.1:8888")
                            .foregroundColor(.secondary)
                    }

                    Text("Settings sync automatically via WebSocket")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 500)
    }

    private func saveSettings() {
        // Update native-only settings (stored locally)
        settingsManager.settings.nativeOnly.globalHotkeys.accept = acceptKey
        settingsManager.settings.nativeOnly.globalHotkeys.deny = denyKey
        settingsManager.settings.nativeOnly.globalHotkeys.other = otherKey
        settingsManager.settings.nativeOnly.globalHotkeys.toggle = toggleKey
        settingsManager.settings.nativeOnly.globalHotkeys.pauseAll = pauseAllKey
        settingsManager.settings.nativeOnly.floatingWindow = floatingWindow
        settingsManager.settings.nativeOnly.showInMenuBar = showInMenuBar
        settingsManager.settings.nativeOnly.focusStealMode = focusStealMode
        settingsManager.settings.nativeOnly.returnFocusWhenEmpty = returnFocusWhenEmpty

        // Update server-synced native settings
        settingsManager.settings.server.native.showAutoAccept = showAutoAccept
        settingsManager.settings.server.native.enableAnimations = enableAnimations

        // Save to local file
        settingsManager.saveToFile()

        // Push server settings to server via WebSocket
        settingsManager.pushToServer()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settingsManager: SettingsManager(webSocket: WebSocketClient()))
    }
}
