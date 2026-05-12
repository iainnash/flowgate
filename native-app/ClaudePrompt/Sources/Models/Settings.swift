import Foundation

// Go server rule action
struct RuleAction: Codable {
    let type: String  // "manual", "auto-accept", "accept-after"
    let seconds: Int?

    init(type: String, seconds: Int? = nil) {
        self.type = type
        self.seconds = seconds
    }

    static let manual = RuleAction(type: "manual")
    static let autoAccept = RuleAction(type: "auto-accept")
    static func acceptAfter(_ seconds: Int) -> RuleAction {
        return RuleAction(type: "accept-after", seconds: seconds)
    }
}

// Go server rule structure
struct Rule: Identifiable, Codable {
    var id: String { name } // Use name as identifier
    let name: String
    let toolName: String
    let category: String?
    let pattern: String?
    let action: RuleAction
    let enabled: Bool
    let matchCount: Int

    init(
        name: String,
        toolName: String,
        category: String? = nil,
        pattern: String? = nil,
        action: RuleAction,
        enabled: Bool = true,
        matchCount: Int = 0
    ) {
        self.name = name
        self.toolName = toolName
        self.category = category
        self.pattern = pattern
        self.action = action
        self.enabled = enabled
        self.matchCount = matchCount
    }
}

// Go server native settings (minimal - only these two fields synced with server)
struct NativeSettings: Codable {
    var showAutoAccept: Bool
    var enableAnimations: Bool

    init(
        showAutoAccept: Bool = true,
        enableAnimations: Bool = true
    ) {
        self.showAutoAccept = showAutoAccept
        self.enableAnimations = enableAnimations
    }
}

// Go server settings format (matches server exactly)
struct ServerSettings: Codable {
    var rules: [Rule]
    var native: NativeSettings

    init(rules: [Rule] = [], native: NativeSettings = NativeSettings()) {
        self.rules = rules
        self.native = native
    }
}

// MARK: - Native-only settings (not synced with server)

struct HotkeyConfig: Codable {
    var accept: String
    var deny: String
    var other: String
    var toggle: String
    var pauseAll: String

    init(
        accept: String = "cmd+shift+y",
        deny: String = "cmd+shift+n",
        other: String = "cmd+shift+o",
        toggle: String = "cmd+shift+p",
        pauseAll: String = "cmd+shift+space"
    ) {
        self.accept = accept
        self.deny = deny
        self.other = other
        self.toggle = toggle
        self.pauseAll = pauseAll
    }

    init(from decoder: Decoder) throws {
        let defaults = HotkeyConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        accept = try container.decodeIfPresent(String.self, forKey: .accept) ?? defaults.accept
        deny = try container.decodeIfPresent(String.self, forKey: .deny) ?? defaults.deny
        other = try container.decodeIfPresent(String.self, forKey: .other) ?? defaults.other
        toggle = try container.decodeIfPresent(String.self, forKey: .toggle) ?? defaults.toggle
        pauseAll = try container.decodeIfPresent(String.self, forKey: .pauseAll) ?? defaults.pauseAll
    }
}

enum FocusStealMode: String, Codable, CaseIterable {
    case confirmationNeeded = "confirmation"  // Only steal focus for manual approval prompts
    case always = "always"                    // Steal focus for all prompts including auto-accept
    case never = "never"                      // Never steal focus

    var displayName: String {
        switch self {
        case .confirmationNeeded: return "Manual approval only"
        case .always: return "All prompts"
        case .never: return "Never"
        }
    }
}

// Native-only settings stored locally
struct NativeOnlySettings: Codable {
    var floatingWindow: Bool
    var showInMenuBar: Bool
    var launchAtLogin: Bool
    var globalHotkeys: HotkeyConfig
    var focusStealMode: FocusStealMode
    var returnFocusWhenEmpty: Bool

    init(
        floatingWindow: Bool = true,
        showInMenuBar: Bool = true,
        launchAtLogin: Bool = false,
        globalHotkeys: HotkeyConfig = HotkeyConfig(),
        focusStealMode: FocusStealMode = .confirmationNeeded,
        returnFocusWhenEmpty: Bool = true
    ) {
        self.floatingWindow = floatingWindow
        self.showInMenuBar = showInMenuBar
        self.launchAtLogin = launchAtLogin
        self.globalHotkeys = globalHotkeys
        self.focusStealMode = focusStealMode
        self.returnFocusWhenEmpty = returnFocusWhenEmpty
    }

    init(from decoder: Decoder) throws {
        let defaults = NativeOnlySettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        floatingWindow = try container.decodeIfPresent(Bool.self, forKey: .floatingWindow) ?? defaults.floatingWindow
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? defaults.showInMenuBar
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        globalHotkeys = try container.decodeIfPresent(HotkeyConfig.self, forKey: .globalHotkeys) ?? defaults.globalHotkeys
        focusStealMode = try container.decodeIfPresent(FocusStealMode.self, forKey: .focusStealMode) ?? defaults.focusStealMode
        returnFocusWhenEmpty = try container.decodeIfPresent(Bool.self, forKey: .returnFocusWhenEmpty) ?? defaults.returnFocusWhenEmpty
    }
}

// Full app settings combining server settings + native-only settings
struct AppSettings: Codable {
    var server: ServerSettings
    var nativeOnly: NativeOnlySettings

    init(
        server: ServerSettings = ServerSettings(),
        nativeOnly: NativeOnlySettings = NativeOnlySettings()
    ) {
        self.server = server
        self.nativeOnly = nativeOnly
    }

    static let defaultSettings = AppSettings()

    init(from decoder: Decoder) throws {
        let defaults = AppSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        server = try container.decodeIfPresent(ServerSettings.self, forKey: .server) ?? defaults.server
        nativeOnly = try container.decodeIfPresent(NativeOnlySettings.self, forKey: .nativeOnly) ?? defaults.nativeOnly
    }

    static var settingsURL: URL {
        let flowgateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("flowgate")
            .appendingPathComponent("native-settings.json")
        if FileManager.default.fileExists(atPath: flowgateURL.path) {
            return flowgateURL
        }

        let legacyURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("claude-prompt-ui")
            .appendingPathComponent("native-settings.json")
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }

        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("flowgate")
        return configDir.appendingPathComponent("native-settings.json")
    }
}
