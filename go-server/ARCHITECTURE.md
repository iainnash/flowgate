# Architecture & Design Decisions

## WebSocket-First Design

### Old (TypeScript) Architecture
```
Client → HTTP GET/POST /api/* endpoints
Client → WebSocket /ws for real-time updates only
```

**Issues:**
- Mixed communication channels (HTTP + WS)
- Multiple round-trips for simple operations
- HTTP overhead for frequent operations
- Connection management complexity

### New (Go) Architecture
```
Hook → HTTP POST /api/prompt (blocking)
Client → WebSocket /ws (all operations)
```

**Benefits:**
- Single persistent connection per client
- Bidirectional communication
- Lower latency (no HTTP handshake per request)
- Simpler client code

## API Comparison

### TypeScript Version (7 HTTP endpoints)
```
POST /api/prompt            # Hook (blocking)
GET  /api/prompts           # List prompts
POST /api/prompts/:id/resolve  # Resolve prompt
POST /api/prompts/:id/pause    # Pause timer
GET  /api/settings          # Get settings
PUT  /api/settings          # Update settings
POST /api/pause             # Toggle global pause
WS   /ws                    # Real-time updates
```

### Go Version (2 HTTP endpoints)
```
POST /api/prompt            # Hook (blocking) - REQUIRED
GET  /api/health            # Health check - OPTIONAL
WS   /ws                    # All client operations + updates
```

## WebSocket Message Protocol

### Client → Server (Actions)
```json
{
  "type": "resolve",
  "id": "prompt-123",
  "decision": {
    "decision": "allow",
    "reason": "Approved by user"
  }
}

{"type": "togglePause"}

{
  "type": "updateSettings",
  "settings": {
    "rules": [...],
    "native": {...}
  }
}
```

### Server → Client (Events)
```json
{
  "type": "prompt:new",
  "prompt": {...}
}

{
  "type": "prompt:resolved",
  "id": "prompt-123",
  "autoAccepted": false
}

{
  "type": "prompt:updated",
  "prompt": {...}
}

{
  "type": "pause:changed",
  "isPaused": true
}

{
  "type": "settings:updated",
  "settings": {...}
}

{
  "type": "prompts:list",
  "prompts": [...]
}
```

## Performance Comparison

### Binary Size
- **TypeScript + Node.js**: ~50MB (Node.js runtime)
- **Go**: 8.6MB (single binary, no runtime)

### Memory Usage (typical)
- **TypeScript**: ~50-100MB RSS
- **Go**: ~10-20MB RSS

### Startup Time
- **TypeScript**: ~200-500ms (Node.js initialization)
- **Go**: ~10-50ms (instant)

### Request Latency
- **TypeScript HTTP**: ~2-5ms per request
- **Go WebSocket**: ~0.5-1ms per message

## Code Structure

```
go-server/
├── main.go              # Server entry point, HTTP routes
├── models/
│   └── types.go         # Data models, JSON types
├── queue/
│   └── queue.go         # Prompt queue, timer management
├── handlers/
│   └── websocket.go     # WebSocket hub, client management
└── devices/             # Future: Stream Deck integration
```

## Concurrency Model

### TypeScript (Event Loop)
- Single-threaded event loop
- Async/await for concurrency
- Timer callbacks run on main thread

### Go (Goroutines)
- One goroutine per WebSocket client
- Queue operations protected by mutex
- Timers run in separate goroutines
- Channel-based message passing

## Future Extensions

### Device Integration
The Go version leaves room for Stream Deck integration:
```go
type DeviceManager interface {
    OnPromptsChanged([]*Prompt)
    OnPromptResolved(string)
    OnPauseStateChanged(bool)
}
```

### Metrics
Could add Prometheus endpoint:
```go
GET /metrics  # Prometheus metrics
```

### Settings Persistence
Could save settings to file:
```go
type SettingsStore interface {
    Load() (*Settings, error)
    Save(*Settings) error
}
```

## Migration Path

1. **Phase 1** (Current): Keep both servers for testing
   - Go server on port 8889 for testing
   - TypeScript server on port 8888 (production)

2. **Phase 2**: Update clients to use WebSocket messages
   - Update web UI to send WS messages instead of HTTP
   - Update native app to send WS messages

3. **Phase 3**: Switch to Go server
   - Build Go binary for macOS
   - Embed in native app bundle
   - Remove TypeScript server

4. **Phase 4**: Add device support
   - Port Stream Deck integration to Go
   - Add other device plugins as needed
