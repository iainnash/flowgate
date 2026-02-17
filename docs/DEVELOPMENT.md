# Development Guide

This guide covers building Flowgate from source, running in development mode, and understanding the architecture.

## Prerequisites

- **Go**: 1.21 or later
- **Node.js**: 20 or later
- **pnpm**: Package manager
- **Xcode**: For native macOS app (includes Swift toolchain)

## Project Structure

```
flowgate/
├── go-server/              # Go backend
│   ├── handlers/           # WebSocket hub
│   ├── middleware/         # Auth middleware
│   ├── models/             # Data types
│   ├── queue/              # Prompt queue + timers
│   ├── public/             # Built UI (generated)
│   └── main.go
├── ui/                     # Svelte frontend
│   └── src/
│       ├── lib/            # Stores + types
│       └── App.svelte
├── native-app/             # macOS menu bar app
│   └── ClaudePrompt/
│       └── Sources/
│           ├── Services/   # WebSocket, Server, Token managers
│           ├── Views/      # SwiftUI views
│           └── Models/     # Data models
├── stream-deck/            # Stream Deck client
│   ├── devices/
│   └── index.ts
├── hooks/                  # Claude Code hooks
│   └── prompt-hook.go      # Go hook
├── docs/                   # Documentation
├── scripts/                # Build scripts
│   ├── build-app.sh        # Build macOS app + DMG
│   └── generate-token.sh
└── build/                  # Build output (generated)
    ├── Flowgate.app
    └── Flowgate.dmg
```

## Quick Start

### 1. Install Dependencies

```bash
pnpm install
```

### 2. Build Everything

```bash
pnpm build
```

This builds:
- Go server binary
- Go hook binary
- Web UI
- Stream Deck client (TypeScript)

### 3. Development Mode

Terminal 1 - Server + UI:
```bash
pnpm dev
```

Terminal 2 - Stream Deck (optional):
```bash
pnpm dev:stream-deck
```

### 4. Configure Claude Code Hook

Add to `~/.config/claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": "/absolute/path/to/flowgate/hooks/prompt-hook"
  }
}
```

## Components

### Go Server

Location: `go-server/`

```bash
cd go-server

# Development
make run

# Build optimized binary
make build-release

# Create universal macOS binary
make universal
```

Server runs on `http://127.0.0.1:8888`

Environment variables:
- `PORT`: Server port (default: 8888)
- `VERBOSE`: Enable verbose logging (default: false)

### Web UI

Location: `ui/`

Built with Svelte + Vite. Features:
- Real-time prompt visualization
- Auto-accept countdown timers
- Tool categorization with color coding
- Multi-session support
- Dark theme
- Sound notifications (80s synth)

```bash
cd ui

# Development with hot reload
pnpm dev

# Build for production
pnpm build
```

### Go Hook

Location: `hooks/prompt-hook.go`

Claude Code hook that sends tool calls to the server for approval.

```bash
cd hooks
make build
```

Environment variables:
- `CLAUDE_PROMPT_UI_SERVER`: Server URL (default: http://127.0.0.1:8888)
- `CLAUDE_PROMPT_UI_TIMEOUT`: Timeout in ms (default: 120000)
- `CLAUDE_PROMPT_UI_TOKEN`: Auth token (auto-read from `~/.claude-prompt-ui/token`)

### Native macOS App

Location: `native-app/ClaudePrompt/`

SwiftUI menu bar application with embedded Go server.

**Features:**
- Menu bar icon with badge showing pending prompt count
- Floating window for prompt management
- Embedded server - starts automatically on app launch
- Auto-authentication - reads token from shared location
- Global hotkeys for accept/deny/toggle
- Server log viewer for debugging

**Build and run (development):**
```bash
cd native-app/ClaudePrompt
swift build
.build/debug/ClaudePrompt
```

**Build production DMG:**
```bash
./scripts/build-app.sh
```

Output:
- `build/Flowgate.app` - App bundle
- `build/Flowgate.dmg` - Installer DMG

### Stream Deck Client

Location: `stream-deck/`

Node.js client that connects hardware Stream Deck to the Go server.

Layout (15-key):
```
┌─────┬─────┬─────┬─────┬─────┐
│ 1-Y │ 2-Y │ 3-Y │ 4-Y │ ALL │
├─────┼─────┼─────┼─────┼─────┤
│ 1-N │ 2-N │ 3-N │ 4-N │     │
├─────┼─────┼─────┼─────┼─────┤
│ 1-O │ 2-O │ 3-O │ 4-O │PAUSE│
└─────┴─────┴─────┴─────┴─────┘
```

Configuration:
```bash
SERVER_URL=ws://localhost:8888/ws pnpm --filter stream-deck-client dev
```

## Running Tests

```bash
# All tests
pnpm test

# Watch mode
pnpm test:watch

# E2E tests
pnpm test:e2e
```

## Building for Production

```bash
# Build everything
pnpm build

# Go server only
pnpm build:server

# Hook only
pnpm build:hook

# Stream Deck client only
pnpm build:stream-deck
```

## Auto-Accept Rules

Configure in server settings or via the UI:

- `auto-accept`: Approve immediately (no UI display)
- `accept-after`: Show in UI with countdown timer
- `manual`: Require explicit approval

### Rule Matching

Rules are evaluated in order. Each rule can match on:
- **Tool name**: Exact match (e.g., "Bash", "Edit")
- **Category**: Tool category (read, write, execute, task, web, interactive, mcp)
- **Pattern**: Regex pattern against tool input

Example rules:
```json
{
  "rules": [
    {
      "name": "Auto-accept reads",
      "toolName": "Read",
      "action": { "type": "auto-accept" }
    },
    {
      "name": "Review file writes",
      "toolName": "Edit",
      "action": { "type": "manual" }
    },
    {
      "name": "Allow npm after delay",
      "toolName": "Bash",
      "pattern": "^(npm|pnpm)\\s",
      "action": { "type": "accept-after", "seconds": 3 }
    }
  ]
}
```

## Keyboard Shortcuts

### Native App

| Shortcut | Action |
|----------|--------|
| `⌘⇧P` | Toggle window |
| `⌘⇧Y` | Accept current prompt |
| `⌘⇧N` | Deny current prompt |
| `⌘⇧O` | Show "Other" dialog |
| `↑/k` | Select previous prompt |
| `↓/j` | Select next prompt |
| `Enter` | Accept (convenience) |
| `Escape` | Deny (convenience) |

### Web UI

| Shortcut | Action |
|----------|--------|
| `y` | Accept current |
| `n` | Deny current |
| `a` | Accept all |
| `d` | Deny all |
| `p` | Toggle pause |

## Architecture Details

### Data Flow

1. **Claude Code** triggers a tool use (e.g., Bash command)
2. **Hook** intercepts the call and POSTs to server
3. **Server** queues the prompt and notifies all WebSocket clients
4. **UI/App** displays the prompt to the user
5. **User** clicks Accept/Deny
6. **Server** returns decision to the waiting hook
7. **Hook** returns result to Claude Code
8. **Claude Code** either executes the tool or receives denial

### WebSocket Protocol

Server messages:
- `prompt:new` - New prompt added
- `prompt:resolved` - Prompt was resolved
- `prompt:updated` - Prompt state changed (e.g., pause/resume)
- `prompts:list` - Full prompt list
- `pause:changed` - Global pause state changed
- `settings:updated` - Settings changed

Client messages:
- `resolve` - Resolve a specific prompt
- `resolve-all` - Resolve all pending prompts
- `toggle-pause` - Toggle global pause
- `list` - Request prompt list
- `updateSettings` - Update server settings

### Tool Categories

| Category | Tools | Color |
|----------|-------|-------|
| Read | Read, Glob, Grep | Green |
| Write | Edit, Write, NotebookEdit | Red |
| Execute | Bash, KillShell, Skill | Orange |
| Task | Task, TaskList, TaskGet, etc. | Purple |
| Web | WebFetch, WebSearch | Blue |
| Interactive | AskUserQuestion, ExitPlanMode | Purple |
| MCP | mcp__* | Cyan |
| Other | Unknown tools | Gray |

## Troubleshooting

### Server not starting

1. Check if port 8888 is in use: `lsof -i :8888`
2. Check server logs in the native app: Menu > Show Server Log

### Hook not working

1. Check hook is executable: `chmod +x hooks/prompt-hook`
2. Test hook directly:
   ```bash
   echo '{"sessionId":"test","toolName":"Bash","toolInput":{"command":"ls"},"hookEventName":"PreToolUse","cwd":"/tmp"}' | ./hooks/prompt-hook
   ```
3. Check Claude Code settings have absolute path

### WebSocket disconnecting

1. Check server health: `curl http://localhost:8888/api/health`
2. Check authentication token exists: `cat ~/.claude-prompt-ui/token`
3. Restart the app to regenerate token if needed
