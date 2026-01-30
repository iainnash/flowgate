import Foundation
import Starscream

enum WSMessage {
    case promptNew(Prompt)
    case promptResolved(id: String, autoAccepted: Bool)
    case promptsList([Prompt])
    case settingsUpdated(ServerSettings)
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
    private let serverURL = URL(string: "ws://127.0.0.1:8888/ws")!

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

        var request = URLRequest(url: serverURL)
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
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.socket = nil
            self?.connect()
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
}

extension WebSocketClient: Starscream.WebSocketDelegate {
    func didReceive(event: Starscream.WebSocketEvent, client: any Starscream.WebSocketClient) {
        switch event {
        case .connected:
            isConnected = true
            connectionStatus = .connected
            delegate?.webSocketDidReceive(.connected)

        case .disconnected(_, _):
            isConnected = false
            connectionStatus = .disconnected
            delegate?.webSocketDidReceive(.disconnected(nil))
            scheduleReconnect()

        case .text(let text):
            handleMessage(text)

        case .binary:
            break

        case .error(let error):
            isConnected = false
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
