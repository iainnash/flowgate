# Claude Prompt Native macOS App

A native macOS menu bar app for the Claude Prompt UI approval system.

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
- The claude-prompt-ui server running on port 8888

## Quick Start

```bash
# Make sure the server is running first
cd /path/to/claude-prompt-ui
pnpm dev

# Then in another terminal, build and run the native app
cd native-app/ClaudePrompt
swift run ClaudePrompt
```

## Building

```bash
cd native-app/ClaudePrompt

# Debug build
swift build

# Release build
swift build -c release

# Run directly
swift run ClaudePrompt

# Or run the built executable
.build/debug/ClaudePrompt      # debug
.build/release/ClaudePrompt    # release
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
        │   ├── HTTPClient.swift        # REST API calls
        │   ├── PromptManager.swift     # Prompt state management
        │   ├── SettingsManager.swift   # Settings file I/O
        │   └── HotkeyManager.swift     # Global hotkey registration
        └── Views/
            ├── ContentView.swift       # Main window content
            ├── PromptCardView.swift    # Individual prompt card
            └── MenuBarView.swift       # Menu bar popover
```

## Configuration

Settings are stored in `~/.config/claude-prompt-ui/settings.json`:

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

The native app connects to the existing Node.js server via WebSocket and HTTP:

```
Native App (Swift/SwiftUI)
    ├── WebSocket → ws://127.0.0.1:8888/ws (real-time updates)
    └── HTTP API → http://127.0.0.1:8888/api/* (actions)
              │
              ▼
    Existing Server (Node.js, port 8888)
              ▲
              │
    Claude Code Hook (PreToolUse)
```

## Dependencies

- [Starscream](https://github.com/daltoniam/Starscream) - WebSocket client
- [HotKey](https://github.com/soffes/HotKey) - Global keyboard shortcuts

## Known Limitations (Phase 1)

- Server must be started separately (not bundled)
- Settings UI not yet implemented (edit JSON directly or use web UI)
- No launch-at-login support yet
- No countdown animation on buttons yet

See `PLAN.md` for the full roadmap.
