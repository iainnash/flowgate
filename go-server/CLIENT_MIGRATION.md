# Client Migration Guide

Guide for updating web UI and native app to use WebSocket-only communication.

## Current (HTTP-based) vs New (WebSocket-based)

### Resolving a Prompt

**Before (HTTP POST):**
```typescript
// TypeScript/JavaScript
async function resolvePrompt(id: string, decision: Decision) {
  const response = await fetch(`${SERVER_URL}/api/prompts/${id}/resolve`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(decision)
  });
  return response.json();
}
```

**After (WebSocket message):**
```typescript
// TypeScript/JavaScript
function resolvePrompt(id: string, decision: Decision) {
  ws.send(JSON.stringify({
    type: 'resolve',
    id,
    decision
  }));
}
```

**Swift (before):**
```swift
// HTTP POST
func resolvePrompt(_ prompt: Prompt, decision: Decision) async throws {
    let url = URL(string: "\(serverURL)/api/prompts/\(prompt.id)/resolve")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(decision)

    let (_, response) = try await URLSession.shared.data(for: request)
    // handle response
}
```

**Swift (after):**
```swift
// WebSocket message
func resolvePrompt(_ prompt: Prompt, decision: Decision) {
    let message: [String: Any] = [
        "type": "resolve",
        "id": prompt.id,
        "decision": [
            "decision": decision.decision,
            "reason": decision.reason
        ]
    ]
    let data = try? JSONSerialization.data(withJSONObject: message)
    webSocket?.send(.data(data!))
}
```

### Toggle Global Pause

**Before (HTTP POST):**
```typescript
async function togglePause() {
  const response = await fetch(`${SERVER_URL}/api/pause`, {
    method: 'POST'
  });
  return response.json();
}
```

**After (WebSocket message):**
```typescript
function togglePause() {
  ws.send(JSON.stringify({
    type: 'togglePause'
  }));
}
```

### Update Settings

**Before (HTTP PUT):**
```typescript
async function updateSettings(settings: Settings) {
  const response = await fetch(`${SERVER_URL}/api/settings`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(settings)
  });
  return response.json();
}
```

**After (WebSocket message):**
```typescript
function updateSettings(settings: Settings) {
  ws.send(JSON.stringify({
    type: 'updateSettings',
    settings
  }));
}
```

## Client State Management

### Initial State on Connect

When the WebSocket connects, the server automatically sends:

```json
{"type": "prompts:list", "prompts": [...]}
{"type": "pause:changed", "isPaused": false}
{"type": "settings:updated", "settings": {...}}
```

So you don't need to make separate GET requests - just handle these messages:

```typescript
ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);

  switch (msg.type) {
    case 'prompts:list':
      setPrompts(msg.prompts);
      break;
    case 'pause:changed':
      setIsPaused(msg.isPaused);
      break;
    case 'settings:updated':
      setSettings(msg.settings);
      break;
    case 'prompt:new':
      addPrompt(msg.prompt);
      break;
    case 'prompt:resolved':
      removePrompt(msg.id);
      break;
    case 'prompt:updated':
      updatePrompt(msg.prompt);
      break;
  }
};
```

### Web UI Changes

**File: `ui/src/lib/stores.ts`**

Remove HTTP client functions, replace with WebSocket message senders:

```typescript
// Remove these:
export async function resolvePrompt(id: string, decision: Decision) { ... }
export async function togglePauseAll() { ... }
export async function updateSettings(settings: Settings) { ... }

// Replace with:
export function resolvePrompt(id: string, decision: Decision) {
  wsClient.send({ type: 'resolve', id, decision });
}

export function togglePauseAll() {
  wsClient.send({ type: 'togglePause' });
}

export function updateSettings(settings: Settings) {
  wsClient.send({ type: 'updateSettings', settings });
}
```

### Native App Changes

**File: `native-app/.../Services/HTTPClient.swift`**

Can be removed entirely or simplified to just health check. Move all operations to WebSocketClient.

**File: `native-app/.../Services/WebSocketClient.swift`**

Add message sending methods:

```swift
func resolvePrompt(id: String, decision: Decision) {
    let message: [String: Any] = [
        "type": "resolve",
        "id": id,
        "decision": [
            "decision": decision.decision,
            "reason": decision.reason ?? NSNull()
        ]
    ]
    sendMessage(message)
}

func togglePause() {
    sendMessage(["type": "togglePause"])
}

func updateSettings(_ settings: Settings) {
    let message: [String: Any] = [
        "type": "updateSettings",
        "settings": encodeSettings(settings)
    ]
    sendMessage(message)
}

private func sendMessage(_ message: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: message),
          let webSocketTask = webSocketTask else { return }
    webSocketTask.send(.data(data)) { error in
        if let error = error {
            print("WebSocket send error: \(error)")
        }
    }
}
```

## Benefits of Migration

1. **Simpler code** - No HTTP request/response handling
2. **Lower latency** - No HTTP handshake per operation
3. **Better UX** - Instant feedback, no loading states needed
4. **Less code** - Remove entire HTTP client layer
5. **Consistent** - All operations use same pattern

## Testing the Migration

1. Start Go server on port 8889:
   ```bash
   cd go-server
   PORT=8889 ./flowgate-server
   ```

2. Update client to point to port 8889:
   ```typescript
   const WS_URL = 'ws://localhost:8889/ws';
   ```

3. Test all operations:
   - [ ] Resolve prompt (allow/deny)
   - [ ] Toggle global pause
   - [ ] Update settings
   - [ ] Receive new prompts
   - [ ] Receive prompt updates
   - [ ] Reconnection handling

4. Once verified, switch to production port 8888

## Rollback Plan

If issues arise, keep the TypeScript server as fallback:
- Keep both servers installable
- Add environment variable to switch: `USE_GO_SERVER=true`
- Monitor for bugs in Go version
- Can hot-swap back to TypeScript server if needed
