import Foundation
import SwiftUI
import UserNotifications

@MainActor
class PromptManager: ObservableObject, WebSocketClientDelegate {
    @Published var prompts: [Prompt] = []
    @Published var isConnected = false
    @Published var connectionStatus: String = "Disconnected"
    @Published var isPaused = false

    private let webSocket: WebSocketClient
    var settingsManager: SettingsManager?

    // Session colors for multi-instance support
    private var sessionColors: [String: Color] = [:]
    private let colorPalette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .yellow, .red
    ]
    private var nextColorIndex = 0

    var promptCount: Int { prompts.count }

    // Count of manual prompts (for badge - excludes auto-accept)
    var manualPromptCount: Int {
        prompts.filter { $0.acceptType == .manual }.count
    }

    // Sort prompts: manual first, then by creation time
    var sortedPrompts: [Prompt] {
        prompts.sorted { a, b in
            let aIsManual = a.acceptType == .manual
            let bIsManual = b.acceptType == .manual
            if aIsManual != bIsManual {
                return aIsManual // Manual prompts come first
            }
            return a.createdAt < b.createdAt
        }
    }

    var currentPrompt: Prompt? { sortedPrompts.first }

    init(webSocket: WebSocketClient) {
        self.webSocket = webSocket
        webSocket.delegate = self
    }

    func connect() {
        webSocket.connect()
    }

    func disconnect() {
        webSocket.disconnect()
    }

    func resolvePrompt(_ prompt: Prompt, decision: Decision, reason: String? = nil) {
        webSocket.sendResolve(id: prompt.id, decision: decision, reason: reason)
    }

    func acceptCurrent() {
        guard let prompt = currentPrompt else { return }
        resolvePrompt(prompt, decision: .allow)
    }

    func denyCurrent() {
        guard let prompt = currentPrompt else { return }
        resolvePrompt(prompt, decision: .deny)
    }

    func acceptAll() {
        for prompt in prompts {
            resolvePrompt(prompt, decision: .allow)
        }
    }

    func denyAll() {
        for prompt in prompts {
            resolvePrompt(prompt, decision: .deny)
        }
    }

    func togglePauseAll() {
        webSocket.sendTogglePause()
    }

    func colorForSession(_ sessionId: String) -> Color {
        if let color = sessionColors[sessionId] {
            return color
        }
        let color = colorPalette[nextColorIndex % colorPalette.count]
        sessionColors[sessionId] = color
        nextColorIndex += 1
        return color
    }

    // MARK: - WebSocketClientDelegate

    nonisolated func webSocketDidReceive(_ message: WSMessage) {
        Task { @MainActor in
            switch message {
            case .connected:
                isConnected = true
                connectionStatus = "Connected"

            case .disconnected:
                isConnected = false
                connectionStatus = "Disconnected"

            case .promptNew(let prompt):
                addPrompt(prompt)
                sendNotification(for: prompt)

            case .promptResolved(let id, _):
                removePrompt(id: id)

            case .promptUpdated(let updatedPrompt):
                updatePrompt(updatedPrompt)

            case .promptsList(let promptList):
                prompts = promptList

            case .settingsUpdated(let serverSettings):
                settingsManager?.updateServerSettings(serverSettings)

            case .pauseChanged(let paused):
                isPaused = paused
            }
        }
    }

    private func addPrompt(_ prompt: Prompt) {
        if !prompts.contains(where: { $0.id == prompt.id }) {
            prompts.insert(prompt, at: 0)
            // Auto-accept timers are handled server-side
        }
    }

    private func removePrompt(id: String) {
        prompts.removeAll { $0.id == id }
    }

    private func updatePrompt(_ updatedPrompt: Prompt) {
        if let index = prompts.firstIndex(where: { $0.id == updatedPrompt.id }) {
            prompts[index] = updatedPrompt
        }
    }

    private func sendNotification(for prompt: Prompt) {
        // Only send if running as a proper app bundle
        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = "Claude Prompt"
        content.body = "\(prompt.toolName): \(prompt.description)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: prompt.id,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func requestNotificationPermission() {
        // Only request if running as a proper app bundle
        guard Bundle.main.bundleIdentifier != nil else {
            print("Skipping notification permission - not running as app bundle")
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
}
