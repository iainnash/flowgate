import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    let hotkeyManager: HotkeyManager?
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
    @State private var showingRules: Bool = false
    @State private var recordingHotkeyCount: Int = 0

    init(settingsManager: SettingsManager, hotkeyManager: HotkeyManager? = nil) {
        self.settingsManager = settingsManager
        self.hotkeyManager = hotkeyManager
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
                Section("Rules") {
                    HStack {
                        Label("Configure Rules", systemImage: "slider.horizontal.3")
                        Spacer()
                        Text("\(settingsManager.settings.server.rules.count)")
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingRules = true
                    }
                }

                Section("Hotkeys") {
                    HStack {
                        Text("Accept prompt")
                        Spacer()
                        hotkeyRecorder(value: $acceptKey)
                    }

                    HStack {
                        Text("Deny prompt")
                        Spacer()
                        hotkeyRecorder(value: $denyKey)
                    }

                    HStack {
                        Text("Other response")
                        Spacer()
                        hotkeyRecorder(value: $otherKey)
                    }

                    HStack {
                        Text("Toggle window")
                        Spacer()
                        hotkeyRecorder(value: $toggleKey)
                    }

                    HStack {
                        Text("Pause/Play all")
                        Spacer()
                        hotkeyRecorder(value: $pauseAllKey)
                    }

                    Text("Click a field, then press a key combination. Escape cancels.")
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
                    .pickerStyle(.menu)

                    Toggle("Return focus when empty", isOn: $returnFocusWhenEmpty)
                        .help("Automatically return focus to the previous app when all prompts are cleared")

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
        .frame(width: 450, height: 550)
        .sheet(isPresented: $showingRules) {
            RulesListView(settingsManager: settingsManager)
                .frame(minWidth: 550, minHeight: 450)
        }
        .onDisappear {
            recordingHotkeyCount = 0
            hotkeyManager?.setSuspended(false)
        }
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

        // Re-register native hotkeys immediately
        hotkeyManager?.setup(config: settingsManager.settings.nativeOnly.globalHotkeys)

        // Push server settings to server via WebSocket
        settingsManager.pushToServer()
    }

    private func hotkeyRecorder(value: Binding<String>) -> some View {
        HotkeyRecorderField(value: value) { isRecording in
            if isRecording {
                recordingHotkeyCount += 1
            } else {
                recordingHotkeyCount = max(0, recordingHotkeyCount - 1)
            }
            hotkeyManager?.setSuspended(recordingHotkeyCount > 0)
        }
        .frame(width: 160)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settingsManager: SettingsManager(webSocket: WebSocketClient()))
    }
}
