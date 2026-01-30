import Foundation

class HTTPClient {
    private let baseURL = URL(string: "http://127.0.0.1:8888")!
    private let session = URLSession.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func resolvePrompt(id: String, decision: Decision, reason: String? = nil) async throws {
        let url = baseURL.appendingPathComponent("api/prompts/\(id)/resolve")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["decision": decision.rawValue]
        if let reason = reason {
            body["reason"] = reason
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HTTPError.requestFailed
        }
    }

    func fetchPrompts() async throws -> [Prompt] {
        let url = baseURL.appendingPathComponent("api/prompts")
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HTTPError.requestFailed
        }

        return try decoder.decode([Prompt].self, from: data)
    }

    func fetchSettings() async throws -> ServerSettings {
        let url = baseURL.appendingPathComponent("api/settings")
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HTTPError.requestFailed
        }

        return try decoder.decode(ServerSettings.self, from: data)
    }

    func updateSettings(_ settings: ServerSettings) async throws {
        let url = baseURL.appendingPathComponent("api/settings")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(settings)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HTTPError.requestFailed
        }
    }

    func pauseTimer(id: String) async throws {
        let url = baseURL.appendingPathComponent("api/prompts/\(id)/pause")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HTTPError.requestFailed
        }
    }

    func togglePauseAll() async throws -> Bool {
        let url = baseURL.appendingPathComponent("api/pause")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HTTPError.requestFailed
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["isPaused"] as? Bool ?? false
    }

    func checkServerHealth() async -> Bool {
        let url = baseURL.appendingPathComponent("api/prompts")
        do {
            let (_, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return (200...299).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    enum HTTPError: LocalizedError {
        case requestFailed

        var errorDescription: String? {
            switch self {
            case .requestFailed:
                return "HTTP request failed"
            }
        }
    }
}
