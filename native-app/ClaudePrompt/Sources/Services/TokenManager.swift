import Foundation

class TokenManager {
    static let shared = TokenManager()

    private let tokenPaths: [URL]

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        tokenPaths = [
            homeDir
                .appendingPathComponent(".flowgate")
                .appendingPathComponent("token"),
            homeDir
                .appendingPathComponent(".claude-prompt-ui")
                .appendingPathComponent("token")
        ]
    }

    /// Read authentication token from filesystem
    func readToken() -> String? {
        for tokenPath in tokenPaths {
            guard let tokenData = try? Data(contentsOf: tokenPath),
                  let token = String(data: tokenData, encoding: .utf8) else {
                continue
            }
            return token.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
