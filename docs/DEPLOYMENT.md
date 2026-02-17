# Deployment Guide

## Architecture

The Claude Prompt UI consists of:

1. **Go Server** (`go-server/`) - Backend API and WebSocket hub
2. **Web UI** (`ui/`) - Svelte frontend
3. **Stream Deck Client** (`stream-deck/`) - Node.js hardware integration
4. **Go Hook** (`hooks/`) - Claude Code integration
5. **Native App** (`native-app/`) - macOS native client

## Development

### Start Development Servers

```bash
# Start Go server + Vite dev server
pnpm dev

# The Go server runs on: http://127.0.0.1:8888
# The Vite dev server runs on: http://127.0.0.1:5173
# Vite proxies /api and /ws to the Go server
```

In development:
- **UI**: Vite dev server at `:5173` with hot reload
- **Backend**: Go server at `:8888`
- **WebSocket**: Proxied through Vite

### Start Stream Deck (Optional)

```bash
# In a separate terminal
pnpm dev:stream-deck
```

## Production Build

### Build Everything

```bash
pnpm build
```

This:
1. Builds UI → `go-server/public/`
2. Builds Go server → `go-server/claude-prompt-server`
3. Builds Go hook → `hooks/prompt-hook`
4. Builds Stream Deck client → `stream-deck/dist/`

### Run Production Server

```bash
cd go-server
./claude-prompt-server
```

The Go server serves:
- **Static UI**: from `go-server/public/`
- **API**: `/api/*` endpoints
- **WebSocket**: `/ws` endpoint
- **Hook**: `/api/prompt` endpoint

Access the UI at: http://127.0.0.1:8888

## UI Build Configuration

The UI (Svelte + Vite) builds to `go-server/public/`:

**File:** `ui/vite.config.ts`
```typescript
export default defineConfig({
  build: {
    outDir: '../go-server/public',
    emptyOutDir: true,
  },
});
```

The Go server looks for static files in these locations (in order):

**File:** `go-server/main.go`
```go
func findPublicDir() string {
    // 1. Current directory (when running from go-server/)
    if _, err := os.Stat("public"); err == nil {
        return "public"
    }

    // 2. go-server subdirectory (when running from project root)
    if _, err := os.Stat("go-server/public"); err == nil {
        return "go-server/public"
    }

    // 3. ui/dist (alternative location)
    if _, err := os.Stat("ui/dist"); err == nil {
        return "ui/dist"
    }

    return ""
}
```

## Directory Structure

```
claude-prompt-ui/
├── go-server/
│   ├── public/              # UI build output (gitignored)
│   │   ├── index.html
│   │   └── assets/
│   ├── claude-prompt-server # Binary (gitignored)
│   └── main.go
├── ui/
│   ├── src/
│   └── vite.config.ts       # Builds to ../go-server/public
├── hooks/
│   └── prompt-hook          # Binary (gitignored)
└── stream-deck/
    └── dist/                # Build output (gitignored)
```

## Environment Variables

### Go Server

```bash
PORT=8888              # Server port (default: 8888)
VERBOSE=true           # Enable verbose logging
```

### Go Hook

```bash
CLAUDE_PROMPT_UI_SERVER=http://127.0.0.1:8888  # Server URL
CLAUDE_PROMPT_UI_TIMEOUT=120000                # Timeout in ms
```

### Stream Deck Client

```bash
SERVER_URL=ws://127.0.0.1:8888/ws  # WebSocket URL
```

## Deployment Scenarios

### Scenario 1: Single Binary + Static Files

**What to deploy:**
- `go-server/claude-prompt-server`
- `go-server/public/` directory

**How to run:**
```bash
cd go-server
./claude-prompt-server
```

**Serves at:** http://127.0.0.1:8888

### Scenario 2: Development Mode

**What to run:**
```bash
pnpm dev
```

**Serves at:**
- Backend: http://127.0.0.1:8888
- Frontend: http://127.0.0.1:5173 (with hot reload)

### Scenario 3: Docker (Future)

```dockerfile
FROM golang:1.21 AS go-builder
WORKDIR /app
COPY go-server/ ./go-server/
COPY hooks/ ./hooks/
RUN cd go-server && go build -o claude-prompt-server
RUN cd hooks && go build -o prompt-hook

FROM node:20 AS ui-builder
WORKDIR /app
COPY ui/ ./ui/
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN corepack enable pnpm
RUN pnpm install
RUN pnpm --filter ui build

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=go-builder /app/go-server/claude-prompt-server .
COPY --from=go-builder /app/hooks/prompt-hook ./hooks/
COPY --from=ui-builder /app/go-server/public ./public/
EXPOSE 8888
CMD ["./claude-prompt-server"]
```

## Testing the Production Build

```bash
# 1. Build everything
pnpm build

# 2. Start server
cd go-server
./claude-prompt-server

# 3. Open browser
open http://127.0.0.1:8888

# 4. Configure Claude Code hook
# Edit ~/.config/claude/settings.json:
{
  "hooks": {
    "PreToolUse": "/absolute/path/to/hooks/prompt-hook"
  }
}

# 5. Test with Claude Code
claude
# Trigger a tool use, should see prompt in UI
```

## Port Configuration

### Default Ports

- **Go Server**: 8888
- **Vite Dev Server**: 5173
- **WebSocket**: Same as Go server port

### Changing Ports

**Development:**
```bash
# Change Go server port
PORT=9000 pnpm dev
```

**Production:**
```bash
cd go-server
PORT=9000 ./claude-prompt-server
```

**Update UI proxy in development:**
```typescript
// ui/vite.config.ts
export default defineConfig({
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://127.0.0.1:9000',  // Update port
      '/ws': {
        target: 'ws://127.0.0.1:9000',  // Update port
        ws: true,
      },
    },
  },
});
```

## Troubleshooting

### UI not loading

**Symptom:** 404 errors or blank page

**Fix:**
1. Check UI was built: `ls -la go-server/public/`
2. Rebuild UI: `pnpm --filter ui build`
3. Check server logs for "Serving static files from: ..."

### WebSocket connection failed

**Symptom:** "Disconnected" in UI

**Fix:**
1. Check server is running: `curl http://127.0.0.1:8888/api/health`
2. Check port matches in code
3. Check firewall settings

### Hook not working

**Symptom:** Prompts don't appear in UI

**Fix:**
1. Check hook is executable: `chmod +x hooks/prompt-hook`
2. Test hook directly: `echo '{"sessionId":"test","toolName":"Bash","toolInput":{"command":"ls"},"hookEventName":"PreToolUse","cwd":"/tmp"}' | ./hooks/prompt-hook`
3. Check Claude Code settings have absolute path
4. Check server logs for incoming requests

## Performance

### UI Bundle Size

Compressed:
- CSS: ~3.4 KB
- JS: ~78.8 KB
- Total: ~82.2 KB

### Go Server

- Memory: ~10-20 MB
- CPU: Minimal (event-driven)
- Connections: Handles 100+ concurrent WebSocket clients

### Build Times

- UI build: ~1-2s
- Go server build: ~2-3s
- Go hook build: ~1-2s
- Total: ~5-7s

## Security Considerations

### CORS

Currently allows `localhost` and `127.0.0.1`:

```go
c := cors.New(cors.Options{
    AllowedOrigins: []string{
        "http://localhost:*",
        "http://127.0.0.1:*",
    },
    AllowedMethods: []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
    AllowCredentials: true,
})
```

### Production Recommendations

1. **Use HTTPS** for production deployments
2. **Restrict CORS** to specific origins
3. **Add authentication** if exposing publicly
4. **Rate limit** hook endpoint
5. **Log all decisions** for audit trail

## Next Steps

- [ ] Add Docker support
- [ ] Add systemd service file
- [ ] Add nginx reverse proxy example
- [ ] Add TLS/SSL support
- [ ] Add authentication layer
