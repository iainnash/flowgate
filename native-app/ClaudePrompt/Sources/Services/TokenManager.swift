import Foundation

class TokenManager {
    static let shared = TokenManager()

    private let tokenPath: URL

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        tokenPath = homeDir
            .appendingPathComponent(".claude-prompt-ui")
            .appendingPathComponent("token")
    }

    /// Read authentication token from filesystem
    func readToken() -> String? {
        guard let tokenData = try? Data(contentsOf: tokenPath),
              let token = String(data: tokenData, encoding: .utf8) else {
            return nil
        }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
