# WebSocket Migration Summary

All HTTP REST endpoints have been replaced with WebSocket messages for real-time communication.

## What Changed

### Go Server
- All functionality now uses WebSocket messages instead of REST endpoints
- Single `/ws` endpoint handles all client communication
- Messages are bidirectional (client ↔ server)

### Native App (Swift)
✅ **Updated** - Now uses WebSocket exclusively

**Changes:**
1. `HTTPClient.swift` - No longer used for prompt operations
2. `WebSocketClient.swift` - Added send methods:
   - `sendResolve(id:decision:reason:)` - Resolve prompts
   - `sendTogglePause()` - Toggle global pause
   - `sendUpdateSettings(_:)` - Update server settings
3. `PromptManager.swift` - Uses WebSocket methods instead of HTTP
4. `SettingsManager.swift` - Uses WebSocket for settings sync
5. Simplified settings model to match Go server schema

### Web UI (Svelte)
✅ **Updated** - Now uses WebSocket for all operations

**Changes:**
1. `stores.ts` - Added WebSocket message sending:
   - `updateSettings()` - Send settings updates via WebSocket
   - `togglePauseAll()` - Uses WebSocket instead of HTTP
2. `Settings.svelte` - Simplified to read-only display (can be enhanced)
3. Settings synced automatically via WebSocket

### Stream Deck Client
✅ **Already using WebSocket** - No changes needed

## WebSocket Message Types

### Client → Server

```typescript
// Resolve a prompt
{
  type: "resolve",
  id: "prompt-123",
  decision: {
    decision: "allow",
    reason: "Approved by user"
  }
}

// Toggle global pause
{
  type: "togglePause"
}

// Update settings
{
  type: "updateSettings",
  settings: {
    rules: [...],
    native: { showAutoAccept: true, enableAnimations: true }
  }
}
```

### Server → Client

```typescript
// New prompt
{
  type: "prompt:new",
  prompt: { id, toolName, ... }
}

// Prompt resolved
{
  type: "prompt:resolved",
  id: "prompt-123",
  autoAccepted: false
}

// Prompt updated (e.g., after pause/resume)
{
  type: "prompt:updated",
  prompt: { id, toolName, autoAcceptAt, ... }
}

// Full prompt list
{
  type: "prompts:list",
  prompts: [...]
}

// Pause state changed
{
  type: "pause:changed",
  isPaused: true
}

// Settings updated
{
  type: "settings:updated",
  settings: { rules, native }
}
```

## Settings Schema Changes

### Old Schema (Removed)
- Complex `PermissionRule` with `matchType` and `matchValue`
- `ProjectConfig` for project-specific rules
- Separate UI settings

### New Schema (Simplified)
```typescript
// Go server schema
{
  rules: [
    {
      name: "Read operations",
      toolName: "Read",
      category: "read",
      pattern: null,
      action: { type: "accept-after", seconds: 3 },
      enabled: true,
      matchCount: 0
    }
  ],
  native: {
    showAutoAccept: true,
    enableAnimations: true
  }
}
```

**Native App Settings Structure:**
```swift
struct AppSettings {
    var server: ServerSettings  // Synced with Go server
    var nativeOnly: NativeOnlySettings  // Local only (hotkeys, window prefs)
}
```

## Benefits

1. **Real-time Updates** - All clients see changes immediately
2. **Single Connection** - No HTTP polling needed
3. **Simplified API** - One endpoint handles everything
4. **Bidirectional** - Server can push updates to clients
5. **Consistent Schema** - Same data structures everywhere

## Migration Checklist

- [x] Go server WebSocket handlers
- [x] Native app WebSocket client methods
- [x] Native app settings model simplified
- [x] Web UI WebSocket message sending
- [x] Web UI settings simplified
- [x] Stream Deck client (already done)
- [x] Remove unused HTTP client methods
- [x] Update documentation

## Testing

To test the WebSocket functionality:

1. **Start server:**
   ```bash
   pnpm dev
   ```

2. **Test web UI:**
   - Open http://127.0.0.1:8888
   - Trigger a prompt from Claude Code
   - Verify Yes/No/Other buttons work
   - Check pause/resume functionality
   - View settings (read-only for now)

3. **Test native app:**
   - Build and run native-app/ClaudePrompt
   - Verify prompt resolution works
   - Test global hotkeys
   - Check pause/resume

4. **Test Stream Deck:**
   ```bash
   pnpm dev:stream-deck
   ```
   - Verify buttons update
   - Test prompt resolution
   - Check pause/play button

## Removed Files/Endpoints

**HTTP Endpoints (Removed):**
- `GET /api/prompts` - Use WebSocket `prompts:list` message
- `POST /api/prompts/:id/resolve` - Use WebSocket `resolve` message
- `POST /api/pause` - Use WebSocket `togglePause` message
- `GET /api/settings` - Sent automatically on WebSocket connect
- `PUT /api/settings` - Use WebSocket `updateSettings` message

**Still Available:**
- `POST /api/prompt` - Hook endpoint (for Claude Code hooks)
- `GET /api/health` - Health check
- `GET /ws` - WebSocket endpoint

## Next Steps

Optional enhancements:

1. **Web UI Settings Editor** - Add ability to edit rules in web UI
2. **Rule Management API** - CRUD operations for rules
3. **Project-Specific Rules** - Add back project configurations
4. **Rule Templates** - Predefined rule sets
5. **Settings Import/Export** - Backup/restore functionality
