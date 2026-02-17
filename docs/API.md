# API Reference

## HTTP Endpoints

### POST /api/prompt

Hook endpoint for submitting prompts. Accepts both camelCase and snake_case for compatibility.

**Authentication:** Required via `Authorization: Bearer <token>` header or query parameter `?token=<token>`

**Request (camelCase - Go hook):**
```json
{
  "sessionId": "abc123",
  "toolName": "Bash",
  "toolInput": { "command": "ls -la" },
  "hookEventName": "PreToolUse",
  "cwd": "/path/to/project"
}
```

**Response:**
```json
{
  "decision": "allow",
  "reason": "Auto-accepted by timer"
}
```

**Decision values:**
- `allow` - Tool execution permitted
- `deny` - Tool execution blocked
- `ask` - Return to terminal for user input

### GET /api/health

Health check endpoint. No authentication required.

**Response:**
```json
{
  "status": "ok"
}
```

### GET /api/settings

Get current server settings.

**Authentication:** Required

**Response:**
```json
{
  "rules": [...],
  "native": {
    "showAutoAccept": true,
    "enableAnimations": true
  }
}
```

### PUT /api/settings

Update server settings.

**Authentication:** Required

**Request:**
```json
{
  "rules": [...],
  "native": {
    "showAutoAccept": true,
    "enableAnimations": true
  }
}
```

### GET /api/devices

Get connected Stream Deck devices.

**Authentication:** Required

**Response:**
```json
{
  "devices": [
    {
      "name": "Stream Deck",
      "connected": true,
      "deviceModel": "Stream Deck MK.2"
    }
  ],
  "hasConnectedDevice": true
}
```

## WebSocket Protocol

### Connection

Connect to `ws://127.0.0.1:8888/ws?token=<token>`

### Server Messages

#### prompt:new

New prompt added to queue.

```json
{
  "type": "prompt:new",
  "prompt": {
    "id": "uuid",
    "sessionId": "abc123",
    "toolName": "Bash",
    "toolInput": { "command": "npm install" },
    "hookEventName": "PreToolUse",
    "cwd": "/path/to/project",
    "createdAt": 1699999999000,
    "acceptType": "accept-after",
    "autoAcceptIn": 5,
    "autoAcceptAt": 1700000004000
  }
}
```

#### prompt:resolved

Prompt was resolved (accepted, denied, or auto-accepted).

```json
{
  "type": "prompt:resolved",
  "id": "uuid",
  "autoAccepted": true
}
```

#### prompt:updated

Prompt state changed (e.g., timer paused/resumed).

```json
{
  "type": "prompt:updated",
  "prompt": { ... }
}
```

#### prompts:list

Full list of pending prompts. Sent on connection and on request.

```json
{
  "type": "prompts:list",
  "prompts": [...]
}
```

#### pause:changed

Global pause state changed.

```json
{
  "type": "pause:changed",
  "isPaused": true
}
```

#### settings:updated

Server settings changed.

```json
{
  "type": "settings:updated",
  "settings": { ... }
}
```

### Client Messages

#### resolve

Resolve a specific prompt.

```json
{
  "type": "resolve",
  "id": "prompt-uuid",
  "decision": {
    "decision": "allow",
    "reason": "User approved",
    "updatedInput": { ... }
  }
}
```

#### resolve-all

Resolve all pending prompts with the same decision.

```json
{
  "type": "resolve-all",
  "decision": {
    "decision": "allow"
  }
}
```

#### toggle-pause

Toggle global pause state.

```json
{
  "type": "togglePause"
}
```

#### list

Request full prompt list.

```json
{
  "type": "list"
}
```

#### updateSettings

Update server settings.

```json
{
  "type": "updateSettings",
  "settings": { ... }
}
```

## Data Types

### Prompt

```typescript
interface Prompt {
  id: string;                    // Unique identifier
  sessionId: string;             // Claude Code session ID
  toolName: string;              // Tool being invoked
  toolInput: Record<string, any>; // Tool parameters
  hookEventName: string;         // "PreToolUse"
  cwd: string;                   // Working directory
  createdAt: number;             // Timestamp (ms)
  acceptType: PromptAcceptType;  // How to handle
  autoAcceptIn?: number;         // Seconds until auto-accept
  autoAcceptAt?: number;         // Auto-accept timestamp (ms)
}

type PromptAcceptType = 'auto-accept' | 'accept-after' | 'manual';
```

### Decision

```typescript
interface Decision {
  decision: 'allow' | 'deny' | 'ask';
  reason?: string;
  updatedInput?: Record<string, any>;
}
```

### Rule

```typescript
interface Rule {
  name: string;
  toolName: string;
  category?: string;
  pattern?: string;
  action: RuleAction;
  enabled: boolean;
  matchCount: number;
}

interface RuleAction {
  type: 'manual' | 'auto-accept' | 'accept-after';
  seconds?: number;
}
```

### Settings

```typescript
interface Settings {
  rules: Rule[];
  native: {
    showAutoAccept: boolean;
    enableAnimations: boolean;
  };
}
```

## Tool Categories

Tools are categorized for rule matching and UI display:

| Category | Tools |
|----------|-------|
| `read` | Read, Glob, Grep, ListMcpResourcesTool, ReadMcpResourceTool, ToolSearch |
| `write` | Edit, Write, MultiEdit, NotebookEdit |
| `execute` | Bash, KillShell, Skill |
| `task` | Task, TaskList, TaskGet, TaskOutput, TaskCreate, TaskUpdate, TaskStop |
| `web` | WebFetch, WebSearch |
| `interactive` | AskUserQuestion, ExitPlanMode, EnterPlanMode |
| `mcp` | Any tool starting with `mcp__` |
| `other` | Unknown tools |

## Error Handling

### HTTP Errors

| Status | Meaning |
|--------|---------|
| 401 | Missing or invalid authentication token |
| 400 | Malformed request body |
| 500 | Internal server error |

### WebSocket Errors

The server will close the connection with:
- **4001**: Authentication failed
- **4002**: Invalid message format
