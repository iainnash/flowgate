# Native App Build Fixes

## Summary

Fixed all compilation errors in the Swift native app after migrating to WebSocket-based architecture and simplified settings schema.

## Changes Made

### 1. Settings Model Updates

**File:** `Sources/Models/Settings.swift`

- Removed complex `PermissionRule` with `matchType`/`matchValue`
- Removed `ProjectConfig` for project-specific rules
- Simplified to match Go server schema:

```swift
// Go server rule structure
struct Rule: Identifiable, Codable {
    var id: String { name }
    let name: String
    let toolName: String
    let category: String?
    let pattern: String?
    let action: RuleAction
    let enabled: Bool
    let matchCount: Int
}

// Server settings (synced with Go server)
struct ServerSettings: Codable {
    var rules: [Rule]
    var native: NativeSettings  // showAutoAccept, enableAnimations
}

// Native-only settings (stored locally)
struct NativeOnlySettings: Codable {
    var floatingWindow: Bool
    var showInMenuBar: Bool
    var launchAtLogin: Bool
    var globalHotkeys: HotkeyConfig
    var focusStealMode: FocusStealMode
}

// Combined app settings
struct AppSettings: Codable {
    var server: ServerSettings
    var nativeOnly: NativeOnlySettings
}
```

### 2. Manager Initialization

**Files:**
- `Sources/Services/PromptManager.swift`
- `Sources/Services/SettingsManager.swift`
- `Sources/ClaudePromptApp.swift`

**Changes:**
- Both managers now require `WebSocketClient` parameter
- Shared WebSocketClient instance created in `AppDelegate`
- Managers linked together for settings updates

```swift
// AppDelegate initialization
override init() {
    let webSocketClient = WebSocketClient()
    self.promptManager = PromptManager(webSocket: webSocketClient)
    self.settingsManager = SettingsManager(webSocket: webSocketClient)
    super.init()
    promptManager.settingsManager = settingsManager
}
```

### 3. WebSocket Methods

**File:** `Sources/Services/WebSocketClient.swift`

Added send methods:
- `sendResolve(id:decision:reason:)` - Resolve prompts
- `sendTogglePause()` - Toggle global pause
- `sendUpdateSettings(_:)` - Update server settings

### 4. Settings Manager Updates

**File:** `Sources/Services/SettingsManager.swift`

- Removed `syncWithServer()` method (now via WebSocket)
- Changed `pushToServer()` to use WebSocket
- Added `updateServerSettings(_:)` for incoming updates

### 5. Settings View Updates

**File:** `Sources/Views/SettingsView.swift`

**Fixed path references:**
- `settings.native` → `settings.nativeOnly` (for local settings)
- `settings.native` → `settings.server.native` (for synced settings)

**Updated saveSettings():**
```swift
private func saveSettings() {
    // Native-only settings (local)
    settingsManager.settings.nativeOnly.globalHotkeys = ...
    settingsManager.settings.nativeOnly.floatingWindow = ...

    // Server-synced settings
    settingsManager.settings.server.native.showAutoAccept = ...
    settingsManager.settings.server.native.enableAnimations = ...

    settingsManager.saveToFile()
    settingsManager.pushToServer()  // Via WebSocket
}
```

### 6. Content View Updates

**File:** `Sources/Views/ContentView.swift`

**Fixed:**
- `settings.native.showAutoAccept` → `settings.server.native.showAutoAccept`
- `settings.native.enableAnimations` → `settings.server.native.enableAnimations`
- Extracted `promptCard(for:at:)` method to help compiler type-check

### 7. Preview Fixes

**Files:** All view files with previews

Fixed preview initializers to pass WebSocketClient:

```swift
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let ws = WebSocketClient()
        ContentView(
            promptManager: PromptManager(webSocket: ws),
            settingsManager: SettingsManager(webSocket: ws)
        )
    }
}
```

## Settings Path Reference

### Local Settings (NativeOnly)
Stored in: `~/.config/claude-prompt-ui/native-settings.json`

Access via: `settingsManager.settings.nativeOnly.*`

Fields:
- `floatingWindow: Bool`
- `showInMenuBar: Bool`
- `launchAtLogin: Bool`
- `globalHotkeys: HotkeyConfig`
- `focusStealMode: FocusStealMode`

### Server Settings
Synced via WebSocket

Access via: `settingsManager.settings.server.*`

Fields:
- `rules: [Rule]` - Permission rules
- `native.showAutoAccept: Bool` - Show auto-accept prompts in UI
- `native.enableAnimations: Bool` - Enable UI animations

## Build Instructions

```bash
cd native-app/ClaudePrompt

# Clean build
swift build --clean

# Debug build
swift build

# Release build
swift build -c release

# Run
swift run

# Or open in Xcode
open Package.swift
```

## Testing Checklist

- [x] App builds successfully
- [ ] WebSocket connection works
- [ ] Prompt resolution via buttons
- [ ] Global hotkeys work
- [ ] Settings persist locally
- [ ] Settings sync with server
- [ ] Pause/resume functionality
- [ ] Auto-accept countdown works
- [ ] Multiple sessions display correctly

## Next Steps

1. Test the native app with running Go server
2. Verify settings sync between web UI and native app
3. Test all hotkey combinations
4. Verify window positioning and focus stealing
5. Test with multiple Claude Code sessions

## Troubleshooting

### If you get "Cannot find type X in scope"
- Clean build directory: `swift build --clean`
- Ensure all files are saved
- Check import statements

### If settings don't sync
- Verify WebSocket connection in console
- Check server is running on port 8888
- Look for WebSocket errors in logs

### If prompts don't appear
- Check PromptManager WebSocket delegate is set
- Verify settingsManager link in AppDelegate
- Check server logs for incoming prompts
