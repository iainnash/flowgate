import Foundation
import AppKit

class ServerManager: ObservableObject {
    static let shared = ServerManager()

    @Published var serverRunning = false
    @Published var serverError: String?
    @Published var serverLog: String = ""

    private var serverProcess: Process?
    private let serverPort = 8888
    private let maxLogLines = 500

    private init() {}

    /// Check if server is already running by trying to connect to health endpoint
    func isServerRunning() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(serverPort)/api/health") else {
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            // Server not responding
        }

        return false
    }

    /// Start the embedded server binary
    func startServer() {
        // Check if already running
        Task {
            if await isServerRunning() {
                await MainActor.run {
                    serverRunning = true
                }
                return
            }

            await MainActor.run {
                startServerProcess()
            }
        }
    }

    /// Find the server binary - checks environment variable first, then app bundle
    private func findServerBinary() -> String? {
        // 1. Check environment variable override
        if let envPath = ProcessInfo.processInfo.environment["CLAUDE_PROMPT_SERVER_PATH"],
           FileManager.default.fileExists(atPath: envPath) {
            return envPath
        }

        // 2. Check app bundle Resources
        if let resourcePath = Bundle.main.resourcePath {
            let bundlePath = (resourcePath as NSString).appendingPathComponent("claude-prompt-server")
            if FileManager.default.fileExists(atPath: bundlePath) {
                return bundlePath
            }
        }

        return nil
    }

    private func startServerProcess() {
        // Find server binary
        guard let serverPath = findServerBinary() else {
            serverError = "Server binary not found. Set CLAUDE_PROMPT_SERVER_PATH or use the bundled app."
            appendLog("[\(Self.timestamp)] Error: Server binary not found\n")
            return
        }

        // Clear previous log
        serverLog = "[\(Self.timestamp)] Starting server...\n"
        appendLog("[\(Self.timestamp)] Binary: \(serverPath)\n")

        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverPath)
        process.currentDirectoryURL = URL(fileURLWithPath: (serverPath as NSString).deletingLastPathComponent)

        // Set environment variables
        var environment = ProcessInfo.processInfo.environment
        environment["PORT"] = "\(serverPort)"
        process.environment = environment

        // Capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Read stdout asynchronously
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.appendLog(output)
                }
            }
        }

        // Read stderr asynchronously
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.appendLog(output)
                }
            }
        }

        // Handle termination
        process.terminationHandler = { [weak self] process in
            // Clean up handlers
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            DispatchQueue.main.async {
                self?.serverRunning = false
                self?.appendLog("[\(Self.timestamp)] Server stopped (exit code: \(process.terminationStatus))\n")
                if process.terminationStatus != 0 {
                    self?.serverError = "Server exited with code \(process.terminationStatus)"
                }
            }
        }

        do {
            try process.run()
            serverProcess = process

            // Wait a moment for server to start, then verify
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task {
                    if await self.isServerRunning() {
                        await MainActor.run {
                            self.serverRunning = true
                            self.serverError = nil
                        }
                    } else {
                        await MainActor.run {
                            self.serverError = "Server failed to start"
                        }
                    }
                }
            }
        } catch {
            serverError = "Failed to launch server: \(error.localizedDescription)"
            appendLog("[\(Self.timestamp)] Error: \(error.localizedDescription)\n")
        }
    }

    private func appendLog(_ text: String) {
        serverLog += text
        // Trim to max lines
        let lines = serverLog.components(separatedBy: "\n")
        if lines.count > maxLogLines {
            serverLog = lines.suffix(maxLogLines).joined(separator: "\n")
        }
    }

    private static var timestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    func clearLog() {
        serverLog = ""
    }

    /// Stop the server process
    func stopServer() {
        serverProcess?.terminate()
        serverProcess = nil
        serverRunning = false
    }

    /// Restart the server process
    func restartServer() {
        stopServer()
        // Wait a moment for process to terminate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startServer()
        }
    }
}
