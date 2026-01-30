# Native macOS App Plan

## Architecture Decision: Client/Server vs Socket Helper

### Recommendation: Keep Client/Server Architecture

**Why this is the better choice:**

1. **Existing Infrastructure** - The server already handles:
   - Prompt queue management with timeouts
   - Rule matching and auto-accept logic
   - WebSocket broadcasting to all clients
   - Settings synchronization
   - Multi-instance session tracking

2. **Coexistence** - Native app can run alongside web UI. Users can use either or both.

3. **Minimal Duplication** - No need to reimplement queue logic, rule matching, or settings management in Swift.

4. **Real-time Ready** - WebSocket already provides instant updates when prompts arrive or resolve.

**Why NOT a socket helper script:**
- Adds unnecessary indirection (Hook → Server → Socket Script → Native App)
- The server already provides WebSocket - adding another socket layer adds complexity without benefit
- Would need to manage another process lifecycle

**Why NOT embedding the server in the native app:**
- Would require reimplementing all server logic in Swift (queue, rules, categories, device support)
- Can't use web UI alongside native app
- Much larger scope of work

---

## Native App Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Claude Prompt (macOS)                     │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Menu Bar    │  │ Floating    │  │ Global Hotkeys      │  │
│  │ Status Item │  │ Window      │  │ (⌘Y/⌘N/⌘O)         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐│
│  │                   PromptManager                         ││
│  │  - Maintains list of active prompts                     ││
│  │  - Handles auto-accept timers                           ││
│  │  - Manages session colors                               ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  ┌─────────────────────────────┐  │
│  │  WebSocketClient    │  │  HTTPClient                 │  │
│  │  - Connect to :8888 │  │  - POST /api/prompts/resolve│  │
│  │  - Receive prompts  │  │  - GET/PUT /api/settings    │  │
│  └─────────────────────┘  └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                Existing Node.js Server                       │
│                    (port 8888)                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Features

### Core Features (Phase 1)

1. **Floating Window**
   - Always-on-top option (NSWindow.Level.floating)
   - Compact prompt card UI
   - Draggable, resizable
   - Click-through when no prompts (optional)

2. **Menu Bar Presence**
   - Status item with prompt count badge
   - Quick actions menu (Accept All, Deny All, Open Window)
   - Connection status indicator

3. **Global Hotkeys**
   - `⌘⇧Y` - Accept current/all prompts
   - `⌘⇧N` - Deny current prompt
   - `⌘⇧O` - Show "Other" dialog
   - `⌘⇧P` - Toggle window visibility
   - Configurable in settings

4. **WebSocket Integration**
   - Connect to `ws://127.0.0.1:8888/ws`
   - Handle message types: `prompt:new`, `prompt:resolved`, `prompts:list`, `settings:updated`
   - Auto-reconnect on disconnect

5. **HTTP API Integration**
   - `POST /api/prompts/:id/resolve` - Submit decisions
   - `GET/PUT /api/settings` - Sync settings

### Enhanced Features (Phase 2)

6. **Native Notifications**
   - macOS notification center integration
   - Actionable notifications (Accept/Deny buttons)
   - Sound customization

7. **Settings UI**
   - Native SwiftUI settings panel
   - Rule editor matching web UI capabilities
   - Import/export settings (JSON format matching web)

8. **Visual Polish**
   - Countdown animation on buttons
   - Session color coding
   - Tool category icons
   - Dark/light mode following system

### Advanced Features (Phase 3)

9. **Auto-Start**
   - Launch at login option
   - Auto-start server if not running

10. **Keyboard Navigation**
    - Arrow keys to select prompts
    - Tab through buttons
    - Full keyboard accessibility

11. **Spotlight/Alfred Integration**
    - Quick actions via Spotlight

---

## Settings File

Store settings in: `~/.config/claude-prompt-ui/settings.json`

```json
{
  "rules": [
    {
      "id": "uuid",
      "type": "category",
      "match": "read",
      "action": "auto-accept",
      "delay": 0
    }
  ],
  "projects": [
    {
      "path": "/path/to/project",
      "rules": []
    }
  ],
  "ui": {
    "theme": "system",
    "volume": 80
  },
  "native": {
    "floatingWindow": true,
    "showInMenuBar": true,
    "launchAtLogin": false,
    "globalHotkeys": {
      "accept": "cmd+shift+y",
      "deny": "cmd+shift+n",
      "other": "cmd+shift+o",
      "toggle": "cmd+shift+p"
    }
  }
}
```

The native app will:
1. Read settings from this file on launch
2. Watch for file changes (for external edits)
3. Sync with server via WebSocket `settings:updated` messages
4. Write back when user changes settings in native UI

---

## Project Structure

```
native-app/
├── ClaudePrompt/
│   ├── ClaudePromptApp.swift          # App entry point, menu bar setup
│   ├── Info.plist                      # App metadata, permissions
│   │
│   ├── Models/
│   │   ├── Prompt.swift                # Prompt data model
│   │   ├── Settings.swift              # Settings model (mirrors web format)
│   │   ├── Decision.swift              # Decision enum (allow/deny/ask)
│   │   └── ToolCategory.swift          # Tool categories enum
│   │
│   ├── Services/
│   │   ├── WebSocketClient.swift       # WebSocket connection management
│   │   ├── HTTPClient.swift            # REST API calls
│   │   ├── PromptManager.swift         # Prompt state management
│   │   ├── SettingsManager.swift       # Settings file I/O
│   │   └── HotkeyManager.swift         # Global hotkey registration
│   │
│   ├── Views/
│   │   ├── FloatingWindow.swift        # Main floating window
│   │   ├── PromptCardView.swift        # Individual prompt card
│   │   ├── CountdownButtonView.swift   # Button with countdown fill
│   │   ├── SettingsView.swift          # Settings panel
│   │   ├── MenuBarView.swift           # Menu bar popover
│   │   └── OtherInputView.swift        # "Other" response dialog
│   │
│   └── Resources/
│       ├── Assets.xcassets             # Icons, colors
│       └── Sounds/                     # Notification sounds
│
├── ClaudePrompt.xcodeproj/
├── Package.swift                       # SPM dependencies
└── README.md
```

---

## Dependencies

```swift
// Package.swift
dependencies: [
    // WebSocket client
    .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),

    // Global hotkeys
    .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),

    // JSON handling (built-in Codable should suffice)
]
```

---

## Implementation Phases

### Phase 1: Minimal Viable Product (Core) - COMPLETE
- [x] Swift Package Manager project setup with SwiftUI
- [x] WebSocket client connecting to server (Starscream)
- [x] Basic floating window with prompt list
- [x] Accept/Deny/Other buttons working
- [x] Menu bar status item with badge
- [x] Global hotkeys (HotKey library)

### Phase 2: Feature Parity
- [ ] Global hotkeys
- [ ] Settings UI
- [ ] Native notifications
- [ ] Countdown animations
- [ ] Session color coding
- [ ] "Other" response dialog

### Phase 3: Polish & Advanced
- [ ] Launch at login
- [ ] Auto-start server
- [ ] Keyboard navigation
- [ ] Import/export settings
- [ ] Visual polish and animations

---

## Server Compatibility

The native app requires the existing server to be running. Options for managing this:

1. **Manual** - User starts server separately (`pnpm --filter server start`)

2. **Auto-detect & Prompt** - Native app checks if server is running, prompts user to start it

3. **Bundled Server** - Native app includes Node.js runtime and server code, manages lifecycle

Recommendation: Start with option 2, consider option 3 for a fully standalone distribution.

---

## Open Questions

1. **Distribution** - Direct download, Homebrew, or Mac App Store?
   - App Store has sandboxing restrictions that may conflict with socket access
   - Direct/Homebrew likely better for developer tool

2. **Notarization** - Need Apple Developer account for distribution outside App Store

3. **Server Bundling** - If bundled, should we use:
   - Full Node.js runtime (~70MB)
   - Compiled binary via pkg/nexe (~50MB)
   - Rewrite minimal server in Swift (complex)

4. **Multiple Monitors** - Should floating window follow focus or stay on primary?
