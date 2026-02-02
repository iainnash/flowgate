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

    static var settingsURL: URL {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("claude-prompt-ui")
        return configDir.appendingPathComponent("native-settings.json")
    }
}
