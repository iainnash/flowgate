import SwiftUI

struct LogView: View {
    @ObservedObject var serverManager = ServerManager.shared
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Server Log")
                    .font(.headline)

                Spacer()

                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(serverManager.serverRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(serverManager.serverRunning ? "Running" : "Stopped")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Button("Clear") {
                    serverManager.clearLog()
                }
                .font(.caption)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    Text(serverManager.serverLog.isEmpty ? "No log output yet..." : serverManager.serverLog)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                        .id("logBottom")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: serverManager.serverLog) { _ in
                    if autoScroll {
                        withAnimation {
                            proxy.scrollTo("logBottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct LogView_Previews: PreviewProvider {
    static var previews: some View {
        LogView()
    }
}
