# Flowgate - Go Server

A lightweight Go server for managing Claude Code tool prompts with WebSocket-based real-time communication.

## Features

- **Single binary** - No runtime dependencies
- **WebSocket-first** - All client operations via WebSocket for efficiency
- **HTTP hook endpoint** - Blocking POST endpoint for Claude Code integration
- **Auto-accept timers** - Server-managed countdown timers with pause/resume
- **Verbose logging** - Debug mode with detailed operation logs

## Architecture

### HTTP Endpoints

- `POST /api/prompt` - Claude Code hook (blocking)
- `GET /api/health` - Health check
- `GET /ws` - WebSocket upgrade endpoint

### WebSocket Messages

**Client → Server:**
```json
{"type": "resolve", "id": "prompt-123", "decision": {"decision": "allow"}}
{"type": "togglePause"}
{"type": "updateSettings", "settings": {...}}
```

**Server → Client (broadcasts):**
```json
{"type": "prompt:new", "prompt": {...}}
{"type": "prompt:resolved", "id": "...", "autoAccepted": false}
{"type": "prompt:updated", "prompt": {...}}
{"type": "pause:changed", "isPaused": true}
{"type": "settings:updated", "settings": {...}}
{"type": "prompts:list", "prompts": [...]}
```

## Building

```bash
# Get dependencies
go mod download

# Build for current platform
go build -o flowgate-server

# Build for macOS (Intel)
GOOS=darwin GOARCH=amd64 go build -o flowgate-server-intel

# Build for macOS (Apple Silicon)
GOOS=darwin GOARCH=arm64 go build -o flowgate-server-arm64

# Cross-compile universal binary (requires macOS)
make universal
```

## Running

```bash
# Normal mode
./flowgate-server

# Verbose mode with detailed logging
VERBOSE=true ./flowgate-server

# Custom port
PORT=9000 ./flowgate-server
```

## Environment Variables

- `PORT` - Server port (default: 8888)
- `VERBOSE` - Enable verbose logging (true/1)

## Integration with Native App

The server automatically serves the web UI from `../server/public/` if available. For the native macOS app, embed the compiled binary in the app bundle:

```
Flowgate.app/
  Contents/
    MacOS/
      Flowgate              # SwiftUI app
    Resources/
      flowgate-server       # Go binary
```

Start the server from Swift:
```swift
let serverPath = Bundle.main.path(forResource: "flowgate-server", ofType: nil)
let process = Process()
process.executableURL = URL(fileURLWithPath: serverPath!)
try process.run()
```

## API Improvements vs TypeScript Version

1. **WebSocket-first** - Removed 6 HTTP endpoints, replaced with WS messages
2. **Single binary** - No Node.js runtime needed (~8MB vs ~50MB)
3. **Better concurrency** - Go's goroutines for each connection
4. **Type safety** - Compile-time type checking
5. **Lower memory** - ~10-20MB RSS vs ~50-100MB for Node.js

## TODO

- [ ] Device integration (Stream Deck)
- [ ] Settings persistence to file
- [ ] Prometheus metrics endpoint
- [ ] TLS support for remote access
