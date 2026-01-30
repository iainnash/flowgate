import SwiftUI

struct MenuBarView: View {
    @ObservedObject var promptManager: PromptManager
    @ObservedObject var settingsManager: SettingsManager
    let onShowWindow: () -> Void
    let onQuit: () -> Void

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
        MenuBarView(
            promptManager: PromptManager(),
            settingsManager: SettingsManager(),
            onShowWindow: {},
            onQuit: {}
        )
    }
}
