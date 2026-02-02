import Foundation
import SwiftUI

@MainActor
class SettingsManager: ObservableObject {
    @Published var settings: AppSettings = AppSettings.defaultSettings

    private let webSocket: WebSocketClient
    private var fileWatcher: DispatchSourceFileSystemObject?

    init(webSocket: WebSocketClient) {
        self.webSocket = webSocket
        loadFromFile()
        watchSettingsFile()
    }

    deinit {
        fileWatcher?.cancel()
    }

    func loadFromFile() {
        let url = AppSettings.settingsURL

        guard FileManager.default.fileExists(atPath: url.path) else {
            // Create default settings file if it doesn't exist
            saveToFile()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            settings = try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            print("Failed to load settings: \(error)")
        }
    }

    func saveToFile() {
        let url = AppSettings.settingsURL
        let directory = url.deletingLastPathComponent()

        do {
            // Create directory if needed
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: url)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }

    func updateServerSettings(_ serverSettings: ServerSettings) {
        // Update from server via WebSocket
        settings.server = serverSettings
        saveToFile()
    }

    func pushToServer() {
        // Send settings to server via WebSocket
        webSocket.sendUpdateSettings(settings.server)
    }

    private func watchSettingsFile() {
        let url = AppSettings.settingsURL
        let directory = url.deletingLastPathComponent()

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: url.path) {
            saveToFile()
        }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.loadFromFile()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileWatcher = source
    }

    // Convenience methods for native-only settings
    var floatingWindow: Bool {
        get { settings.nativeOnly.floatingWindow }
        set {
            settings.nativeOnly.floatingWindow = newValue
            saveToFile()
        }
    }

    var showInMenuBar: Bool {
        get { settings.nativeOnly.showInMenuBar }
        set {
            settings.nativeOnly.showInMenuBar = newValue
            saveToFile()
        }
    }

    var launchAtLogin: Bool {
        get { settings.nativeOnly.launchAtLogin }
        set {
            settings.nativeOnly.launchAtLogin = newValue
            saveToFile()
        }
    }
}
