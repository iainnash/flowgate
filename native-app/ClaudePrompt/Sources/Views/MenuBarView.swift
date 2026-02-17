import SwiftUI

struct MenuBarView: View {
    @ObservedObject var promptManager: PromptManager
    @ObservedObject var settingsManager: SettingsManager
    let onShowWindow: () -> Void
    let onShowLog: () -> Void
    let onShowSettings: () -> Void
    let onQuit: () -> Void

    private func openWebUI() {
        Task {
            // Ensure server is running
            let isRunning = await ServerManager.shared.isServerRunning()
            if !isRunning {
                await MainActor.run {
                    ServerManager.shared.startServer()
                }

                // Wait for server to start
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }

            // Read token from filesystem
            guard let token = TokenManager.shared.readToken() else {
                print("Cannot read auth token")
                return
            }

            // Open browser with token in URL
            await MainActor.run {
                let urlString = "http://localhost:8888?token=\(token)"
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            HStack {
                Circle()
                    .fill(promptManager.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(promptManager.connectionStatus)
                    .font(.caption)
                Spacer()
                if promptManager.promptCount > 0 {
                    Text("\(promptManager.promptCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Prompts section
            if !promptManager.prompts.isEmpty {
                MenuSection(title: "Prompts") {
                    MenuButton(title: "Accept All", shortcut: nil) {
                        promptManager.acceptAll()
                    }
                    MenuButton(title: "Deny All", shortcut: nil) {
                        promptManager.denyAll()
                    }
                }
                Divider()
            }

            // View section
            MenuSection(title: "View") {
                MenuButton(title: "Show Prompts Window", shortcut: "⌘1") {
                    onShowWindow()
                }
                MenuButton(title: "Show Server Log", shortcut: "⌘2") {
                    onShowLog()
                }
                MenuButton(title: "Open Web UI", shortcut: "⌘O") {
                    openWebUI()
                }
            }

            Divider()

            // Server section
            MenuSection(title: "Server") {
                if ServerManager.shared.serverRunning {
                    MenuButton(title: "Restart Server", shortcut: "⌘R") {
                        ServerManager.shared.restartServer()
                    }
                    MenuButton(title: "Stop Server", shortcut: nil) {
                        ServerManager.shared.stopServer()
                    }
                } else {
                    MenuButton(title: "Start Server", shortcut: nil) {
                        ServerManager.shared.startServer()
                    }
                }
                MenuButton(title: "Clear Log", shortcut: "⌘K") {
                    ServerManager.shared.clearLog()
                }
            }

            Divider()

            // App section
            MenuSection(title: "App") {
                MenuButton(title: "Settings...", shortcut: "⌘,") {
                    onShowSettings()
                }
                MenuButton(title: "Quit Flowgate", shortcut: "⌘Q") {
                    onQuit()
                }
            }
        }
        .frame(width: 220)
    }
}

// MARK: - Helper Views

struct MenuSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            content
        }
    }
}

struct MenuButton: View {
    let title: String
    let shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuButtonStyle())
        .padding(.horizontal, 8)
    }
}

struct MenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(4)
    }
}

struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        let ws = WebSocketClient()
        MenuBarView(
            promptManager: PromptManager(webSocket: ws),
            settingsManager: SettingsManager(webSocket: ws),
            onShowWindow: {},
            onShowLog: {},
            onShowSettings: {},
            onQuit: {}
        )
    }
}
