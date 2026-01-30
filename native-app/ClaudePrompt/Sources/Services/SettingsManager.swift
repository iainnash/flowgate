import Foundation
import SwiftUI

@MainActor
class SettingsManager: ObservableObject {
    @Published var settings: AppSettings = AppSettings.defaultSettings

    private let httpClient = HTTPClient()
    private var fileWatcher: DispatchSourceFileSystemObject?

    init() {
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

    func syncWithServer() async {
        do {
            let serverSettings = try await httpClient.fetchSettings()
            // Merge server settings (rules, projects) with native settings
            settings.rules = serverSettings.rules
            settings.projects = serverSettings.projects
            saveToFile()
        } catch {
            print("Failed to sync settings from server: \(error)")
        }
    }

    func pushToServer() async {
        do {
            let serverSettings = ServerSettings(rules: settings.rules, projects: settings.projects)
            try await httpClient.updateSettings(serverSettings)
        } catch {
            print("Failed to push settings to server: \(error)")
        }
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

    // Convenience methods for native settings
    var floatingWindow: Bool {
        get { settings.native.floatingWindow }
        set {
            settings.native.floatingWindow = newValue
            saveToFile()
        }
    }

    var showInMenuBar: Bool {
        get { settings.native.showInMenuBar }
        set {
            settings.native.showInMenuBar = newValue
            saveToFile()
        }
    }

    var launchAtLogin: Bool {
        get { settings.native.launchAtLogin }
        set {
            settings.native.launchAtLogin = newValue
            saveToFile()
        }
    }
}
