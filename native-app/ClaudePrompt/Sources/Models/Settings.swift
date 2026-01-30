import Foundation

enum RuleMatchType: String, Codable {
    case category
    case tool
    case pattern
    case all
}

// Server uses action as object: { type: 'auto-accept' } or { type: 'accept-after', seconds: 5 }
struct RuleAction: Codable {
    let type: String  // "auto-accept", "accept-after", "require-verify"
    let seconds: Int?

    init(type: String, seconds: Int? = nil) {
        self.type = type
        self.seconds = seconds
    }

    static let autoAccept = RuleAction(type: "auto-accept")
    static let requireVerify = RuleAction(type: "require-verify")
    static func acceptAfter(_ seconds: Int) -> RuleAction {
        return RuleAction(type: "accept-after", seconds: seconds)
    }
}

struct PermissionRule: Identifiable, Codable {
    let id: String
    let name: String
    let matchType: RuleMatchType
    let matchValue: String
    let action: RuleAction
    let enabled: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        matchType: RuleMatchType,
        matchValue: String,
        action: RuleAction,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.matchType = matchType
        self.matchValue = matchValue
        self.action = action
        self.enabled = enabled
    }
}

struct ProjectConfig: Codable {
    let projectPath: String
    var rules: [PermissionRule]

    init(projectPath: String, rules: [PermissionRule] = []) {
        self.projectPath = projectPath
        self.rules = rules
    }
}

struct UISettings: Codable {
    var theme: String
    var volume: Int

    init(theme: String = "system", volume: Int = 80) {
        self.theme = theme
        self.volume = volume
    }
}

struct HotkeyConfig: Codable {
    var accept: String
    var deny: String
    var other: String
    var toggle: String

    init(
        accept: String = "cmd+shift+y",
        deny: String = "cmd+shift+n",
        other: String = "cmd+shift+o",
        toggle: String = "cmd+shift+p"
    ) {
        self.accept = accept
        self.deny = deny
        self.other = other
        self.toggle = toggle
    }
}

struct NativeSettings: Codable {
    var floatingWindow: Bool
    var showInMenuBar: Bool
    var launchAtLogin: Bool
    var globalHotkeys: HotkeyConfig

    init(
        floatingWindow: Bool = true,
        showInMenuBar: Bool = true,
        launchAtLogin: Bool = false,
        globalHotkeys: HotkeyConfig = HotkeyConfig()
    ) {
        self.floatingWindow = floatingWindow
        self.showInMenuBar = showInMenuBar
        self.launchAtLogin = launchAtLogin
        self.globalHotkeys = globalHotkeys
    }
}

// Server settings format (rules + projects only)
struct ServerSettings: Codable {
    var rules: [PermissionRule]
    var projects: [ProjectConfig]

    init(rules: [PermissionRule] = [], projects: [ProjectConfig] = []) {
        self.rules = rules
        self.projects = projects
    }
}

// Full app settings including native-specific options
struct AppSettings: Codable {
    var rules: [PermissionRule]
    var projects: [ProjectConfig]
    var ui: UISettings
    var native: NativeSettings

    init(
        rules: [PermissionRule] = [],
        projects: [ProjectConfig] = [],
        ui: UISettings = UISettings(),
        native: NativeSettings = NativeSettings()
    ) {
        self.rules = rules
        self.projects = projects
        self.ui = ui
        self.native = native
    }

    static let defaultSettings = AppSettings()

    static var settingsURL: URL {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("claude-prompt-ui")
        return configDir.appendingPathComponent("settings.json")
    }
}
