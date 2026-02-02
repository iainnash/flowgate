# Claude Prompt UI

A visual approval interface for Claude Code tool calls with Stream Deck support.

## Architecture

- **Go Server** (`go-server/`): High-performance backend handling prompt queue and WebSocket connections
- **Web UI** (`ui/`): Svelte-based approval interface
- **Stream Deck Client** (`stream-deck/`): Node.js client for hardware button integration
- **Go Hook** (`hooks/`): Claude Code hook written in Go with camelCase API

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

### 3. Run Development Mode

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
    "PreToolUse": "/absolute/path/to/claude-prompt-ui/hooks/prompt-hook"
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

### Go Hook

Location: `hooks/prompt-hook.go`

Claude Code hook that sends tool calls to the server for approval.

Build:
```bash
cd hooks
make build
```

Configuration via environment:
- `CLAUDE_PROMPT_UI_SERVER`: Server URL (default: http://127.0.0.1:8888)
- `CLAUDE_PROMPT_UI_TIMEOUT`: Timeout in ms (default: 120000)

## API

### POST /api/prompt

Hook endpoint. Accepts both camelCase and snake_case for compatibility.

Request (camelCase - Go hook):
```json
{
  "sessionId": "abc123",
  "toolName": "Bash",
  "toolInput": { "command": "ls -la" },
  "hookEventName": "PreToolUse",
  "cwd": "/path/to/project"
}
```

Response:
```json
{
  "decision": "allow",
  "reason": "Auto-accepted by timer"
}
```

### WebSocket /ws

Real-time updates for UI and Stream Deck clients.

Server messages:
- `prompt:new` - New prompt added
- `prompt:resolved` - Prompt was resolved
- `prompt:updated` - Prompt state changed (e.g., pause/resume)
- `prompts:list` - Full prompt list
- `pause:changed` - Global pause state changed

Client messages:
- `resolve` - Resolve a specific prompt
- `resolve-all` - Resolve all pending prompts
- `toggle-pause` - Toggle global pause
- `list` - Request prompt list

### GET /api/health

Health check endpoint.

## Development

### Project Structure

```
claude-prompt-ui/
├── go-server/          # Go backend
│   ├── handlers/       # WebSocket hub
│   ├── models/         # Data types
│   ├── queue/          # Prompt queue + timers
│   └── main.go
├── ui/                 # Svelte frontend
│   └── src/
│       ├── lib/        # Stores + types
│       └── App.svelte
├── stream-deck/        # Stream Deck client
│   ├── devices/
│   └── index.ts
├── hooks/              # Claude Code hooks
│   ├── prompt-hook.go  # Go hook (recommended)
│   └── prompt-hook.ts  # TypeScript hook (legacy)
└── scripts/            # Build scripts
```

### Running Tests

```bash
# All tests
pnpm test

# Watch mode
pnpm test:watch

# E2E tests
pnpm test:e2e
```

### Building for Production

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

## Features

### Auto-Accept Rules

Configure in `go-server/models/types.go`:

- `auto-accept`: Approve immediately (no UI display)
- `accept-after`: Show in UI with countdown timer
- `manual`: Require explicit approval

### Pause/Resume

Global pause stops all auto-accept timers. Timers resume from remaining time when unpaused.

### Multi-Session Support

Handle multiple Claude Code sessions simultaneously with color-coded badges.

### Stream Deck Integration

Physical buttons for:
- Approve/deny individual prompts (slots 1-4)
- Approve all pending prompts
- Pause/resume auto-accept timers

## License

MIT
