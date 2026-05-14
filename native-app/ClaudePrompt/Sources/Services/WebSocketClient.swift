import Foundation
import Starscream
import AppKit

enum WSMessage {
    case promptNew(Prompt)
    case promptResolved(id: String, autoAccepted: Bool)
    case promptUpdated(Prompt)
    case promptsList([Prompt])
    case settingsUpdated(ServerSettings)
    case pauseChanged(Bool)
    case connected
    case disconnected(Error?)
}

protocol WebSocketClientDelegate: AnyObject {
    func webSocketDidReceive(_ message: WSMessage)
}

class WebSocketClient: NSObject, ObservableObject {
    private var socket: WebSocket?
    private var isConnected = false
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3

    @Published var connectionStatus: ConnectionStatus = .disconnected

    weak var delegate: WebSocketClientDelegate?

    enum ConnectionStatus {
        case connected
        case connecting
        case disconnected
        case error(String)

        var description: String {
            switch self {
            case .connected: return "Connected"
            case .connecting: return "Connecting..."
            case .disconnected: return "Disconnected"
            case .error(let msg): return "Error: \(msg)"
            }
        }
    }

    override init() {
        super.init()
    }

    func connect() {
        guard socket == nil else { return }

        connectionStatus = .connecting

        // Read token from filesystem
        guard let token = TokenManager.shared.readToken() else {
            connectionStatus = .error("Cannot read authentication token")
            showAuthErrorAlert()
            return
        }

        // Build URL with token query parameter
        var urlComponents = URLComponents(string: "ws://127.0.0.1:8888/ws")!
        urlComponents.queryItems = [URLQueryItem(name: "token", value: token)]

        guard let url = urlComponents.url else {
            connectionStatus = .error("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }

    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        socket?.disconnect()
        socket = nil
        isConnected = false
        connectionStatus = .disconnected
    }

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            connectionStatus = .error("Max reconnection attempts reached")
            return
        }

        reconnectAttempts += 1
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.socket = nil
            self?.connect()
        }
    }

    private func showAuthErrorAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Authentication Failed"
            alert.informativeText = """
                Could not connect to the server. The authentication token may be invalid or missing.

                Please restart Flowgate to regenerate the server and token.

                If the problem persists:
                1. Quit the app completely
                2. Delete ~/.flowgate/token
                3. Restart the app
                """
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Restart App")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Restart the app
                NSApplication.shared.relaunch()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let type = json?["type"] as? String else { return }

            switch type {
            case "prompt:new":
                if let promptData = json?["prompt"] as? [String: Any] {
                    let prompt = try parsePrompt(promptData)
                    delegate?.webSocketDidReceive(.promptNew(prompt))
                }

            case "prompt:resolved":
                if let id = json?["id"] as? String {
                    let autoAccepted = json?["autoAccepted"] as? Bool ?? false
                    delegate?.webSocketDidReceive(.promptResolved(id: id, autoAccepted: autoAccepted))
                }

            case "prompt:updated":
                if let promptData = json?["prompt"] as? [String: Any] {
                    let prompt = try parsePrompt(promptData)
                    delegate?.webSocketDidReceive(.promptUpdated(prompt))
                }

            case "prompts:list":
                if let promptsData = json?["prompts"] as? [[String: Any]] {
                    let prompts = try promptsData.map { try parsePrompt($0) }
                    delegate?.webSocketDidReceive(.promptsList(prompts))
                }

            case "settings:updated":
                if let settingsData = json?["settings"] {
                    let settingsJSON = try JSONSerialization.data(withJSONObject: settingsData)
                    let settings = try JSONDecoder().decode(ServerSettings.self, from: settingsJSON)
                    delegate?.webSocketDidReceive(.settingsUpdated(settings))
                }

            case "pause:changed":
                if let isPaused = json?["isPaused"] as? Bool {
                    delegate?.webSocketDidReceive(.pauseChanged(isPaused))
                }

            default:
                break
            }
        } catch {
            print("Failed to parse WebSocket message: \(error)")
        }
    }

    private func parsePrompt(_ data: [String: Any]) throws -> Prompt {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(Prompt.self, from: jsonData)
    }

    // MARK: - Send Messages

    func sendResolve(id: String, decision: Decision, reason: String? = nil, updatedInput: [String: Any]? = nil, additionalContext: String? = nil) {
        var decisionData: [String: Any] = ["decision": decision.rawValue]
        if let reason = reason {
            decisionData["reason"] = reason
        }
        if let updatedInput = updatedInput {
            decisionData["updatedInput"] = updatedInput
        }
        if let additionalContext = additionalContext {
            decisionData["additionalContext"] = additionalContext
        }

        let message: [String: Any] = [
            "type": "resolve",
            "id": id,
            "decision": decisionData
        ]

        sendMessage(message)
    }

    func sendTogglePause() {
        let message: [String: Any] = [
            "type": "togglePause"
        ]
        sendMessage(message)
    }

    func sendUpdateSettings(_ settings: ServerSettings) {
        guard let settingsData = try? JSONEncoder().encode(settings),
              let settingsJSON = try? JSONSerialization.jsonObject(with: settingsData) else {
            return
        }

        let message: [String: Any] = [
            "type": "updateSettings",
            "settings": settingsJSON
        ]
        sendMessage(message)
    }

    private func sendMessage(_ message: [String: Any]) {
        guard isConnected,
              let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        socket?.write(string: text)
    }
}

extension WebSocketClient: Starscream.WebSocketDelegate {
    func didReceive(event: Starscream.WebSocketEvent, client: any Starscream.WebSocketClient) {
        switch event {
        case .connected:
            isConnected = true
            reconnectAttempts = 0
            connectionStatus = .connected
            delegate?.webSocketDidReceive(.connected)

        case .disconnected(_, let code):
            isConnected = false
            connectionStatus = .disconnected

            // Check for authentication error (401)
            if code == 401 {
                connectionStatus = .error("Authentication failed")
                showAuthErrorAlert()
                return
            }

            delegate?.webSocketDidReceive(.disconnected(nil))
            scheduleReconnect()

        case .text(let text):
            handleMessage(text)

        case .binary:
            break

        case .error(let error):
            isConnected = false

            // Check for HTTP error in the error description
            if let errorDescription = error?.localizedDescription,
               errorDescription.contains("401") {
                connectionStatus = .error("Authentication failed")
                showAuthErrorAlert()
                return
            }

            connectionStatus = .error(error?.localizedDescription ?? "Unknown error")
            delegate?.webSocketDidReceive(.disconnected(error))
            scheduleReconnect()

        case .cancelled:
            isConnected = false
            connectionStatus = .disconnected
            scheduleReconnect()

        default:
            break
        }
    }
}

extension NSApplication {
    func relaunch() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [Bundle.main.bundlePath]
        task.launch()
        NSApp.terminate(nil)
    }
}
