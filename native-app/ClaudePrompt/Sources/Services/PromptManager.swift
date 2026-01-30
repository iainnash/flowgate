import Foundation
import SwiftUI
import UserNotifications

@MainActor
class PromptManager: ObservableObject, WebSocketClientDelegate {
    @Published var prompts: [Prompt] = []
    @Published var isConnected = false
    @Published var connectionStatus: String = "Disconnected"

    private let webSocket = WebSocketClient()
    private let httpClient = HTTPClient()

    // Session colors for multi-instance support
    private var sessionColors: [String: Color] = [:]
    private let colorPalette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .yellow, .red
    ]
    private var nextColorIndex = 0

    var promptCount: Int { prompts.count }

    var currentPrompt: Prompt? { prompts.first }

    init() {
        webSocket.delegate = self
    }

    func connect() {
        webSocket.connect()
    }

    func disconnect() {
        webSocket.disconnect()
    }

    func resolvePrompt(_ prompt: Prompt, decision: Decision, reason: String? = nil) {
        Task {
            do {
                try await httpClient.resolvePrompt(id: prompt.id, decision: decision, reason: reason)
            } catch {
                print("Failed to resolve prompt: \(error)")
            }
        }
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

    func pauseTimer(for prompt: Prompt) {
        Task {
            do {
                try await httpClient.pauseTimer(id: prompt.id)
            } catch {
                print("Failed to pause timer: \(error)")
            }
        }
    }

    func denyAll() {
        for prompt in prompts {
            resolvePrompt(prompt, decision: .deny)
        }
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

            case .promptsList(let promptList):
                prompts = promptList

            case .settingsUpdated:
                // Settings updates handled by SettingsManager
                break
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
