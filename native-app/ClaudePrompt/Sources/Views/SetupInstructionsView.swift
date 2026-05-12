import SwiftUI

struct SetupInstructionsView: View {
    let hookConfig: String
    var onOpenSettings: () -> Void
    var onClose: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add this to ~/.claude/settings.json to enable Flowgate hooks:")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(hookConfig)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .textSelection(.enabled)
            }
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            HStack {
                Button(copied ? "Copied!" : "Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hookConfig, forType: .string)
                    copied = true
                }

                Button("Open Settings File") {
                    onOpenSettings()
                }

                Spacer()

                Button("Close") {
                    onClose()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 520, height: 380)
    }
}
