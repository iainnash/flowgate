import SwiftUI

struct MenuBarView: View {
    @ObservedObject var promptManager: PromptManager
    @ObservedObject var settingsManager: SettingsManager
    let onShowWindow: () -> Void
    let onShowLog: () -> Void
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
        VStack(alignment: .leading, spacing: 8) {
            // Status
            HStack {
                Circle()
                    .fill(promptManager.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(promptManager.connectionStatus)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()

            // Prompts section
            if promptManager.prompts.isEmpty {
                Text("No pending prompts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
            } else {
                Text("\(promptManager.promptCount) pending prompt\(promptManager.promptCount == 1 ? "" : "s")")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)

                // Quick actions
                Button("Accept All") {
                    promptManager.acceptAll()
                }
                .padding(.horizontal, 12)

                Button("Deny All") {
                    promptManager.denyAll()
                }
                .padding(.horizontal, 12)
            }

            Divider()

            // Window toggle
            Button("Show Window") {
                onShowWindow()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .padding(.horizontal, 12)

            // Open Web UI
            Button("Open Web UI") {
                openWebUI()
            }
            .padding(.horizontal, 12)

            Divider()

            // Server controls
            Button(ServerManager.shared.serverRunning ? "Restart Server" : "Start Server") {
                Task {
                    if ServerManager.shared.serverRunning {
                        ServerManager.shared.restartServer()
                    } else {
                        ServerManager.shared.startServer()
                    }
                }
            }
            .padding(.horizontal, 12)

            Button("Show Server Log") {
                onShowLog()
            }
            .padding(.horizontal, 12)

            Divider()

            // Quit
            Button("Quit Claude Prompt") {
                onQuit()
            }
            .keyboardShortcut("q", modifiers: .command)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 200)
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
            onQuit: {}
        )
    }
}
