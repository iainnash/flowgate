# Flowgate Native macOS App

A native macOS menu bar app for the Flowgate approval system.

## Features

- **Menu Bar Status** - Shows connection status and prompt count badge
- **Floating Window** - Always-on-top window for quick access (toggleable)
- **Global Hotkeys** - Accept/deny prompts without focusing the app
  - `Cmd+Shift+Y` - Accept current prompt
  - `Cmd+Shift+N` - Deny current prompt
  - `Cmd+Shift+O` - Show "Other" dialog
  - `Cmd+Shift+P` - Toggle floating window
- **Native Notifications** - macOS notification center integration
- **Real-time Updates** - WebSocket connection to server

## Requirements

- macOS 13.0 or later
- Swift 5.9+
- The flowgate server running on port 8888

## Quick Start

```bash
# Make sure the server is running first
cd /path/to/flowgate
pnpm dev

# Then in another terminal, build and run the native app
cd native-app/ClaudePrompt
swift run Flowgate
```

## Building

```bash
cd native-app/ClaudePrompt

# Debug build
swift build

# Release build
swift build -c release

# Run directly
swift run Flowgate

# Or run the built executable
.build/debug/Flowgate      # debug
.build/release/Flowgate    # release
```

## Project Structure

```
native-app/
├── PLAN.md                         # Architecture and implementation plan
├── README.md                       # This file
└── ClaudePrompt/
    ├── Package.swift               # Swift Package Manager config
    ├── build.sh                    # Build helper script
    └── Sources/
        ├── ClaudePromptApp.swift   # App entry point
        ├── Models/
        │   ├── Prompt.swift        # Prompt, Decision, ToolCategory
        │   └── Settings.swift      # AppSettings, rules, native config
        ├── Services/
        │   ├── WebSocketClient.swift   # WebSocket connection
        │   ├── HTTPClient.swift        # Legacy health/REST helper
        │   ├── PromptManager.swift     # Prompt state management
        │   ├── SettingsManager.swift   # Settings file I/O
        │   └── HotkeyManager.swift     # Global hotkey registration
        └── Views/
            ├── ContentView.swift       # Main window content
            ├── PromptCardView.swift    # Individual prompt card
            └── MenuBarView.swift       # Menu bar popover
```

## Configuration

Settings are stored in `~/.config/flowgate/settings.json`:

```json
{
  "rules": [...],
  "projects": [...],
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

## Architecture

The native app starts the embedded Go server and uses WebSocket messages for prompt actions and settings updates:

```
Native App (Swift/SwiftUI)
    ├── WebSocket → ws://127.0.0.1:8888/ws (real-time updates)
              │
              ▼
    Embedded Go Server (port 8888)
              ▲
              │
    Claude Code Hook (PreToolUse)
```

## Dependencies

- [Starscream](https://github.com/daltoniam/Starscream) - WebSocket client
- [HotKey](https://github.com/soffes/HotKey) - Global keyboard shortcuts

## Known Limitations (Phase 1)

- No launch-at-login support yet

See `PLAN.md` for the full roadmap.
