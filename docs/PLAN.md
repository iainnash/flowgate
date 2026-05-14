# Flowgate - Historical Design Plan

This document captures the original design and may mention superseded REST endpoints.
For the current API, use `docs/API.md`: `/api/prompt` and `/api/health` are HTTP,
while prompt listing, prompt resolution, settings, and pause actions use WebSocket
messages.

## Overview

A web-based approval UI that integrates with Claude Code via hooks, providing visual prompts with Yes/No/Other buttons, auto-accept countdown, and multi-instance support.

## Architecture

```
┌─────────────────┐     HTTP POST      ┌──────────────────┐     WebSocket     ┌─────────────────┐
│  Claude Code    │ ──────────────────▶│  Express Server  │◀────────────────▶│   Svelte UI     │
│  (Instance 1)   │                    │    (Port 8888)   │                   │  (Browser Tab)  │
├─────────────────┤                    │                  │                   │                 │
│  Claude Code    │ ──────────────────▶│  - Receives hook │                   │  - Prompt list  │
│  (Instance 2)   │                    │    requests      │                   │  - Countdown    │
├─────────────────┤                    │  - Queues        │                   │  - Settings     │
│  Claude Code    │ ──────────────────▶│    prompts       │                   │  - Auto-accept  │
│  (Instance N)   │                    │  - Returns       │                   │    toggles      │
└─────────────────┘                    │    decisions     │                   └─────────────────┘
        │                              └──────────────────┘
        │ hooks call                            │
        ▼                                       │
┌─────────────────┐                             │
│  /hooks/        │─────────────────────────────┘
│  prompt-hook.sh │  curl POST to server, wait for response
└─────────────────┘
```

## Project Structure

```
flowgate/
├── package.json              # Root package with workspaces
├── hooks/
│   ├── package.json          # Dependencies for hook (minimal)
│   ├── prompt-hook.ts        # TypeScript hook for PreToolUse
│   ├── tsconfig.json         # TypeScript config
│   └── install.ts            # Helper to install hooks in Claude settings
├── server/
│   ├── package.json
│   ├── index.ts              # Express + WebSocket server
│   ├── types.ts              # Shared types
│   └── queue.ts              # Prompt queue management
└── ui/
    ├── package.json
    ├── vite.config.ts
    ├── src/
    │   ├── App.svelte        # Main app
    │   ├── lib/
    │   │   ├── PromptCard.svelte    # Individual prompt with countdown
    │   │   ├── PromptList.svelte    # List of active prompts
    │   │   ├── Settings.svelte      # Settings panel
    │   │   ├── CountdownButton.svelte # Button with fill animation
    │   │   └── stores.ts            # Svelte stores for state
    │   └── main.ts
    └── index.html
```

## Server Design

### Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/prompt` | POST | Receive prompt request from hook (blocks until resolved) |
| `/api/health` | GET | Health check |
| `/ws` | WebSocket | Real-time prompt updates to UI |

Prompt listing, prompt resolution, settings updates, and pause actions are WebSocket messages.

### Prompt Request Format (from hook)

```json
{
  "session_id": "abc123",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm install lodash",
    "description": "Install lodash package"
  },
  "hook_event_name": "PreToolUse",
  "cwd": "/path/to/project"
}
```

### Prompt Response Format (to hook)

```json
{
  "decision": "allow",
  "reason": "User approved",
  "updatedInput": null
}
```

Or for denial:
```json
{
  "decision": "deny",
  "reason": "User denied: wrong command"
}
```

### Server Implementation (`server/index.ts`)

```typescript
import express from 'express';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';
import cors from 'cors';

interface Prompt {
  id: string;
  sessionId: string;
  toolName: string;
  toolInput: Record<string, any>;
  hookEventName: string;
  cwd: string;
  createdAt: number;
  resolver: (decision: Decision) => void;
}

interface Decision {
  decision: 'allow' | 'deny';
  reason?: string;
  updatedInput?: Record<string, any>;
}

interface Settings {
  autoAcceptTimeout: number;  // seconds, 0 = disabled
  autoAcceptCodeChanges: boolean;
  autoAcceptToolCalls: boolean;
}

const prompts = new Map<string, Prompt>();
let settings: Settings = {
  autoAcceptTimeout: 10,
  autoAcceptCodeChanges: false,
  autoAcceptToolCalls: true
};

// Server binds to localhost only - no external network access
const HOST = '127.0.0.1';
const PORT = 8888;

const app = express();
const server = createServer(app);
server.listen(PORT, HOST, () => {
  console.log(`Server running at http://${HOST}:${PORT}`);
  // Auto-open browser
  open(`http://localhost:${PORT}`);
});
```

## UI Design

### Main Components

#### PromptList.svelte
- Displays all active prompts in a vertical list
- Sorted by creation time (newest at top or bottom - configurable)
- Shows session ID badge for multi-instance identification
- Empty state when no prompts

#### PromptCard.svelte
- Shows tool name and description
- Session ID badge (color-coded per instance)
- Working directory path (truncated)
- Three buttons: Yes (green), No (red), Other (gray)
- Countdown fill animation on default button
- Expands to show full tool_input JSON on click

#### CountdownButton.svelte
```svelte
<script>
  export let label: string;
  export let countdown: number; // 0-100 percentage
  export let variant: 'yes' | 'no' | 'other';
</script>

<button class="countdown-btn {variant}" style="--fill: {countdown}%">
  {label}
</button>

<style>
  .countdown-btn {
    position: relative;
    overflow: hidden;
  }
  .countdown-btn::before {
    content: '';
    position: absolute;
    left: 0;
    top: 0;
    height: 100%;
    width: var(--fill);
    background: rgba(255,255,255,0.3);
    transition: width 100ms linear;
  }
  .countdown-btn.yes { background: #22c55e; }
  .countdown-btn.no { background: #ef4444; }
  .countdown-btn.other { background: #6b7280; }
</style>
```

#### Settings.svelte
- Auto-accept timeout slider (0-60 seconds, 0 = disabled)
- Checkbox: Auto-accept code changes (Edit, Write, NotebookEdit)
- Checkbox: Auto-accept tool calls (Bash, other tools)
- Persisted to localStorage and synced to server

### Visual Design Principles

1. **Minimal & Fast**: No heavy frameworks, pure Svelte
2. **Dark theme**: Easy on eyes for dev work
3. **Color-coded sessions**: Each Claude instance gets distinct color
4. **Clear countdown**: Fill animation shows time remaining
5. **Compact cards**: Show essential info, expand for details

### UI Mockup

```
┌────────────────────────────────────────────────────────┐
│  Flowgate                                  ⚙️ Settings │
├────────────────────────────────────────────────────────┤
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │ 🔵 session-abc | Bash                            │ │
│  │ npm install lodash                               │ │
│  │ ~/projects/my-app                                │ │
│  │                                                  │ │
│  │  [████████░░ Yes]  [ No ]  [ Other ]            │ │
│  │           8s                                     │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │ 🟢 session-xyz | Edit                            │ │
│  │ Edit src/components/Button.tsx                   │ │
│  │ ~/projects/other-app                             │ │
│  │                                                  │ │
│  │  [ Yes ]  [ No ]  [ Other ]                     │ │
│  │  (auto-accept disabled for code changes)        │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
└────────────────────────────────────────────────────────┘
```

## Hook Implementation

### hooks/package.json

```json
{
  "name": "flowgate-hooks",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "install-hooks": "tsx install.ts"
  },
  "dependencies": {},
  "devDependencies": {
    "typescript": "^5.3.0",
    "tsx": "^4.7.0",
    "@types/node": "^20.0.0"
  }
}
```

### hooks/prompt-hook.ts

```typescript
#!/usr/bin/env npx tsx
/**
 * Claude Code PreToolUse hook that sends prompts to UI server
 * Reads JSON from stdin, sends to server, returns decision
 */

interface HookInput {
  session_id: string;
  tool_name: string;
  tool_input: Record<string, unknown>;
  hook_event_name: string;
  cwd: string;
  transcript_path?: string;
  permission_mode?: string;
}

interface ServerResponse {
  decision: 'allow' | 'deny' | 'ask';
  reason?: string;
  updatedInput?: Record<string, unknown>;
}

interface HookOutput {
  hookSpecificOutput: {
    hookEventName: string;
    permissionDecision: 'allow' | 'deny' | 'ask';
    permissionDecisionReason?: string;
    updatedInput?: Record<string, unknown>;
  };
}

const SERVER_URL = process.env.FLOWGATE_SERVER ?? 'http://localhost:8888';
const TIMEOUT_MS = parseInt(process.env.FLOWGATE_TIMEOUT ?? '120000', 10);

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf-8');
}

function output(data: HookOutput): void {
  console.log(JSON.stringify(data));
}

function fallbackToTerminal(reason: string): void {
  output({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'ask',
      permissionDecisionReason: reason,
    },
  });
}

async function main(): Promise<void> {
  try {
    const inputJson = await readStdin();
    const input: HookInput = JSON.parse(inputJson);

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);

    try {
      const response = await fetch(`${SERVER_URL}/api/prompt`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: inputJson,
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        fallbackToTerminal(`Server returned ${response.status}`);
        return;
      }

      const result: ServerResponse = await response.json();

      if (result.decision === 'allow') {
        output({
          hookSpecificOutput: {
            hookEventName: 'PreToolUse',
            permissionDecision: 'allow',
            ...(result.updatedInput && { updatedInput: result.updatedInput }),
          },
        });
      } else if (result.decision === 'deny') {
        output({
          hookSpecificOutput: {
            hookEventName: 'PreToolUse',
            permissionDecision: 'deny',
            permissionDecisionReason: result.reason ?? 'Denied by user',
          },
        });
      } else {
        fallbackToTerminal('User chose to decide in terminal');
      }
    } catch (err) {
      clearTimeout(timeoutId);
      if (err instanceof Error && err.name === 'AbortError') {
        fallbackToTerminal('Request timeout - UI server not responding');
      } else {
        fallbackToTerminal(`Server unreachable: ${err}`);
      }
    }
  } catch (err) {
    fallbackToTerminal(`Failed to parse input: ${err}`);
  }
}

main();
```

### hooks/install.ts

```typescript
#!/usr/bin/env npx tsx
/**
 * Install hooks into Claude Code settings
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { homedir } from 'os';

const __dirname = dirname(fileURLToPath(import.meta.url));

interface ClaudeSettings {
  hooks?: {
    PreToolUse?: Array<{
      matcher: string;
      hooks: Array<{
        type: string;
        command: string;
        timeout: number;
      }>;
    }>;
  };
}

const hookPath = join(__dirname, 'prompt-hook.ts');
const settingsDir = join(homedir(), '.claude');
const settingsFile = join(settingsDir, 'settings.json');

// Ensure .claude directory exists
mkdirSync(settingsDir, { recursive: true });

// Read existing settings or create empty object
let settings: ClaudeSettings = {};
if (existsSync(settingsFile)) {
  try {
    settings = JSON.parse(readFileSync(settingsFile, 'utf-8'));
  } catch {
    console.warn('Could not parse existing settings, starting fresh');
  }
}

// Add hook configuration
settings.hooks = settings.hooks ?? {};
settings.hooks.PreToolUse = [
  {
    matcher: '*',
    hooks: [
      {
        type: 'command',
        command: `npx tsx "${hookPath}"`,
        timeout: 120,
      },
    ],
  },
];

// Write settings
writeFileSync(settingsFile, JSON.stringify(settings, null, 2));
console.log(`Hooks installed to ${settingsFile}`);
console.log(`Hook command: npx tsx "${hookPath}"`);
```

## Settings Configuration

### Default Settings

```json
{
  "autoAcceptTimeout": 10,
  "autoAcceptCodeChanges": false,
  "autoAcceptToolCalls": true,
  "sessionColors": {}
}
```

### Tool Categories

**Code Changes** (require explicit approval by default):
- `Edit`
- `Write`
- `NotebookEdit`

**Tool Calls** (auto-accept by default):
- `Bash`
- `Glob`
- `Grep`
- `Read`
- `WebFetch`
- `WebSearch`
- All MCP tools (`mcp__*`)

## Implementation Steps

### Phase 1: Server Foundation
1. Initialize Node.js project with TypeScript
2. Set up Express server with CORS
3. Implement `/api/prompt` endpoint (blocking request handler)
4. Add prompt queue with Map storage
5. Implement WebSocket server for real-time updates

### Phase 2: Svelte UI
1. Initialize Svelte project with Vite
2. Create PromptCard component with countdown
3. Create PromptList component
4. Implement WebSocket connection to server
5. Add local state management with Svelte stores

### Phase 3: Hook Integration
1. Create prompt-hook.ts with fetch logic
2. Create install.ts helper script
3. Build hooks package
4. Test with single Claude instance
5. Test with multiple instances

### Phase 4: Settings & Polish
1. Add Settings panel component
2. Implement localStorage persistence
3. Add session color coding
4. Add "Other" text input modal
5. Polish animations and transitions

### Phase 5: Developer Experience
1. Add npm scripts for dev/build/start
2. Create README with setup instructions
3. Add environment variable configuration
4. Test error scenarios (server down, timeout, etc.)

## Verification Plan

1. **Install dependencies**: `pnpm install`
2. **Start server**: `pnpm --filter server dev`
3. **Start UI**: `pnpm --filter ui dev` (auto-opens browser at localhost:8888)
4. **Install hooks**: `pnpm --filter hooks install-hooks`
5. **Run tests**: `pnpm test` (all unit + integration tests)
6. **Test single instance**: Run Claude Code, trigger a tool use
7. **Verify prompt appears** in browser UI with notification sound
8. **Test Yes button**: Should approve immediately
9. **Test No button**: Should deny with reason
10. **Test Other button**: Should open modal with deny/modify options
11. **Test auto-accept**: Wait for countdown, verify approval
12. **Test multi-instance**: Open 2 Claude sessions, verify both prompts appear with different colors
13. **Test settings**: Change timeout, verify countdown changes
14. **Test code change toggle**: Disable auto-accept for Edit, verify no countdown
15. **Run E2E tests**: `pnpm test:e2e`

## Tech Stack

- **Server**: Node.js, Express, ws (WebSocket), TypeScript
- **UI**: Svelte 5, Vite, TypeScript
- **Hooks**: TypeScript (tsx for execution)
- **Build**: pnpm workspaces
- **Testing**: Vitest (unit + integration), Playwright (E2E)

## Test Suite

### Testing Framework

**Vitest** for unit and integration tests - fast, native Vite support, TypeScript out of the box.
**Playwright** for E2E tests - reliable browser automation.

### Project Test Structure

```
flowgate/
├── hooks/
│   ├── __tests__/
│   │   └── prompt-hook.test.ts   # Hook logic tests
│   └── vitest.config.ts
├── server/
│   ├── __tests__/
│   │   ├── queue.test.ts         # Prompt queue unit tests
│   │   ├── api.test.ts           # API endpoint tests
│   │   └── websocket.test.ts     # WebSocket integration tests
│   └── vitest.config.ts
├── ui/
│   ├── src/
│   │   └── lib/
│   │       └── __tests__/
│   │           ├── PromptCard.test.ts
│   │           ├── CountdownButton.test.ts
│   │           ├── Settings.test.ts
│   │           └── stores.test.ts
│   └── vitest.config.ts
└── e2e/
    ├── playwright.config.ts
    └── tests/
        ├── approval-flow.spec.ts
        ├── multi-instance.spec.ts
        └── auto-accept.spec.ts
```

### Hook Tests (`hooks/__tests__/`)

#### prompt-hook.test.ts
```typescript
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { spawn } from 'child_process';
import { createServer, Server } from 'http';

describe('prompt-hook', () => {
  let mockServer: Server;
  let serverPort: number;

  beforeEach(async () => {
    // Create a mock server for testing
    mockServer = createServer((req, res) => {
      let body = '';
      req.on('data', chunk => body += chunk);
      req.on('end', () => {
        const input = JSON.parse(body);

        // Simulate different responses based on tool name
        if (input.tool_name === 'DangerousTool') {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ decision: 'deny', reason: 'Blocked dangerous tool' }));
        } else if (input.tool_name === 'ModifyTool') {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            decision: 'allow',
            updatedInput: { ...input.tool_input, modified: true }
          }));
        } else {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ decision: 'allow' }));
        }
      });
    });

    await new Promise<void>(resolve => {
      mockServer.listen(0, '127.0.0.1', () => {
        const addr = mockServer.address() as { port: number };
        serverPort = addr.port;
        resolve();
      });
    });
  });

  afterEach(() => {
    mockServer?.close();
  });

  function runHook(input: object): Promise<{ stdout: string; stderr: string; code: number }> {
    return new Promise((resolve) => {
      const child = spawn('npx', ['tsx', 'prompt-hook.ts'], {
        cwd: __dirname.replace('__tests__', ''),
        env: {
          ...process.env,
          FLOWGATE_SERVER: `http://127.0.0.1:${serverPort}`,
        },
      });

      let stdout = '';
      let stderr = '';

      child.stdout.on('data', data => stdout += data);
      child.stderr.on('data', data => stderr += data);
      child.stdin.write(JSON.stringify(input));
      child.stdin.end();

      child.on('close', code => resolve({ stdout, stderr, code: code ?? 0 }));
    });
  }

  it('should return allow decision for normal tools', async () => {
    const result = await runHook({
      session_id: 'test',
      tool_name: 'Bash',
      tool_input: { command: 'ls' },
      hook_event_name: 'PreToolUse',
      cwd: '/tmp',
    });

    expect(result.code).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe('allow');
  });

  it('should return deny decision with reason', async () => {
    const result = await runHook({
      session_id: 'test',
      tool_name: 'DangerousTool',
      tool_input: {},
      hook_event_name: 'PreToolUse',
      cwd: '/tmp',
    });

    expect(result.code).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe('deny');
    expect(output.hookSpecificOutput.permissionDecisionReason).toBe('Blocked dangerous tool');
  });

  it('should include updatedInput when server modifies input', async () => {
    const result = await runHook({
      session_id: 'test',
      tool_name: 'ModifyTool',
      tool_input: { original: 'value' },
      hook_event_name: 'PreToolUse',
      cwd: '/tmp',
    });

    expect(result.code).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe('allow');
    expect(output.hookSpecificOutput.updatedInput.modified).toBe(true);
  });

  it('should fallback to ask when server is unreachable', async () => {
    mockServer.close();

    const result = await runHook({
      session_id: 'test',
      tool_name: 'Bash',
      tool_input: {},
      hook_event_name: 'PreToolUse',
      cwd: '/tmp',
    });

    expect(result.code).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe('ask');
    expect(output.hookSpecificOutput.permissionDecisionReason).toContain('unreachable');
  });

  it('should handle malformed stdin gracefully', async () => {
    const child = spawn('npx', ['tsx', 'prompt-hook.ts'], {
      cwd: __dirname.replace('__tests__', ''),
      env: {
        ...process.env,
        FLOWGATE_SERVER: `http://127.0.0.1:${serverPort}`,
      },
    });

    let stdout = '';
    child.stdout.on('data', data => stdout += data);
    child.stdin.write('not valid json');
    child.stdin.end();

    await new Promise(resolve => child.on('close', resolve));

    const output = JSON.parse(stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe('ask');
    expect(output.hookSpecificOutput.permissionDecisionReason).toContain('parse');
  });
});
```

### Server Tests (`server/__tests__/`)

#### queue.test.ts - Prompt Queue Unit Tests
```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { PromptQueue } from '../queue';

describe('PromptQueue', () => {
  let queue: PromptQueue;

  beforeEach(() => {
    queue = new PromptQueue();
  });

  it('should add prompt and return unique id', () => {
    const prompt = {
      sessionId: 'test-session',
      toolName: 'Bash',
      toolInput: { command: 'ls' },
      hookEventName: 'PreToolUse',
      cwd: '/home/user'
    };
    const id = queue.add(prompt);
    expect(id).toBeDefined();
    expect(queue.get(id)).toMatchObject(prompt);
  });

  it('should list all pending prompts', () => {
    queue.add({ sessionId: 's1', toolName: 'Bash', toolInput: {}, hookEventName: 'PreToolUse', cwd: '/' });
    queue.add({ sessionId: 's2', toolName: 'Edit', toolInput: {}, hookEventName: 'PreToolUse', cwd: '/' });
    expect(queue.list()).toHaveLength(2);
  });

  it('should resolve prompt and remove from queue', async () => {
    const id = queue.add({ sessionId: 's1', toolName: 'Bash', toolInput: {}, hookEventName: 'PreToolUse', cwd: '/' });
    const promise = queue.waitForResolution(id);
    queue.resolve(id, { decision: 'allow' });
    const result = await promise;
    expect(result.decision).toBe('allow');
    expect(queue.get(id)).toBeUndefined();
  });

  it('should handle multiple sessions independently', () => {
    queue.add({ sessionId: 'session-a', toolName: 'Bash', toolInput: {}, hookEventName: 'PreToolUse', cwd: '/' });
    queue.add({ sessionId: 'session-b', toolName: 'Bash', toolInput: {}, hookEventName: 'PreToolUse', cwd: '/' });
    const prompts = queue.list();
    expect(prompts.filter(p => p.sessionId === 'session-a')).toHaveLength(1);
    expect(prompts.filter(p => p.sessionId === 'session-b')).toHaveLength(1);
  });

  it('should categorize tool as code change', () => {
    expect(queue.isCodeChange('Edit')).toBe(true);
    expect(queue.isCodeChange('Write')).toBe(true);
    expect(queue.isCodeChange('NotebookEdit')).toBe(true);
    expect(queue.isCodeChange('Bash')).toBe(false);
    expect(queue.isCodeChange('Read')).toBe(false);
  });
});
```

#### api.test.ts - API Endpoint Tests
```typescript
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { createApp } from '../index';

describe('API Endpoints', () => {
  let app: Express.Application;

  beforeAll(() => {
    app = createApp();
  });

  describe('POST /api/prompt', () => {
    it('should accept valid prompt and return id', async () => {
      const promptPromise = request(app)
        .post('/api/prompt')
        .send({
          session_id: 'test',
          tool_name: 'Bash',
          tool_input: { command: 'echo hello' },
          hook_event_name: 'PreToolUse',
          cwd: '/tmp'
        });

      // Resolve the prompt from another "thread"
      setTimeout(async () => {
        const listRes = await request(app).get('/api/prompts');
        const promptId = listRes.body[0].id;
        await request(app)
          .post(`/api/prompts/${promptId}/resolve`)
          .send({ decision: 'allow' });
      }, 100);

      const res = await promptPromise;
      expect(res.status).toBe(200);
      expect(res.body.decision).toBe('allow');
    });

    it('should reject malformed prompt', async () => {
      const res = await request(app)
        .post('/api/prompt')
        .send({ invalid: 'data' });
      expect(res.status).toBe(400);
    });
  });

  describe('GET /api/prompts', () => {
    it('should return empty array when no prompts', async () => {
      const res = await request(app).get('/api/prompts');
      expect(res.status).toBe(200);
      expect(res.body).toEqual([]);
    });
  });

  describe('GET/PUT /api/settings', () => {
    it('should return default settings', async () => {
      const res = await request(app).get('/api/settings');
      expect(res.status).toBe(200);
      expect(res.body.autoAcceptTimeout).toBe(10);
    });

    it('should update settings', async () => {
      await request(app)
        .put('/api/settings')
        .send({ autoAcceptTimeout: 20 });
      const res = await request(app).get('/api/settings');
      expect(res.body.autoAcceptTimeout).toBe(20);
    });
  });
});
```

#### websocket.test.ts - WebSocket Integration Tests
```typescript
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import WebSocket from 'ws';
import { createServer } from '../index';

describe('WebSocket', () => {
  let server: ReturnType<typeof createServer>;
  let ws: WebSocket;

  beforeAll(async () => {
    server = createServer();
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  });

  afterAll(() => {
    ws?.close();
    server?.close();
  });

  it('should broadcast new prompt to connected clients', async () => {
    const addr = server.address() as { port: number };
    ws = new WebSocket(`ws://127.0.0.1:${addr.port}/ws`);

    const messagePromise = new Promise<any>(resolve => {
      ws.on('message', data => resolve(JSON.parse(data.toString())));
    });

    await new Promise(resolve => ws.on('open', resolve));

    // Trigger a prompt via API
    await fetch(`http://127.0.0.1:${addr.port}/api/prompt`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        session_id: 'ws-test',
        tool_name: 'Bash',
        tool_input: { command: 'test' },
        hook_event_name: 'PreToolUse',
        cwd: '/'
      })
    });

    const msg = await messagePromise;
    expect(msg.type).toBe('prompt:new');
    expect(msg.prompt.sessionId).toBe('ws-test');
  });
});
```

### UI Tests (`ui/src/lib/__tests__/`)

#### CountdownButton.test.ts
```typescript
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import CountdownButton from '../CountdownButton.svelte';

describe('CountdownButton', () => {
  it('should render with label', () => {
    render(CountdownButton, { props: { label: 'Yes', countdown: 0, variant: 'yes' } });
    expect(screen.getByText('Yes')).toBeDefined();
  });

  it('should apply correct variant class', () => {
    const { container } = render(CountdownButton, { props: { label: 'No', countdown: 0, variant: 'no' } });
    expect(container.querySelector('.countdown-btn.no')).toBeDefined();
  });

  it('should set fill CSS variable based on countdown', () => {
    const { container } = render(CountdownButton, { props: { label: 'Yes', countdown: 75, variant: 'yes' } });
    const btn = container.querySelector('.countdown-btn');
    expect(btn?.getAttribute('style')).toContain('--fill: 75%');
  });
});
```

#### PromptCard.test.ts
```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/svelte';
import PromptCard from '../PromptCard.svelte';

describe('PromptCard', () => {
  const mockPrompt = {
    id: 'test-1',
    sessionId: 'session-abc',
    toolName: 'Bash',
    toolInput: { command: 'npm install', description: 'Install deps' },
    cwd: '/home/user/project',
    createdAt: Date.now()
  };

  it('should display tool name and description', () => {
    render(PromptCard, { props: { prompt: mockPrompt, settings: { autoAcceptTimeout: 10 } } });
    expect(screen.getByText('Bash')).toBeDefined();
    expect(screen.getByText(/npm install/)).toBeDefined();
  });

  it('should display session badge', () => {
    render(PromptCard, { props: { prompt: mockPrompt, settings: { autoAcceptTimeout: 10 } } });
    expect(screen.getByText(/session-abc/)).toBeDefined();
  });

  it('should emit resolve event on Yes click', async () => {
    const { component } = render(PromptCard, { props: { prompt: mockPrompt, settings: { autoAcceptTimeout: 10 } } });
    const handler = vi.fn();
    component.$on('resolve', handler);

    await fireEvent.click(screen.getByText('Yes'));
    expect(handler).toHaveBeenCalledWith(expect.objectContaining({
      detail: { id: 'test-1', decision: 'allow' }
    }));
  });

  it('should show Other input modal on Other click', async () => {
    render(PromptCard, { props: { prompt: mockPrompt, settings: { autoAcceptTimeout: 10 } } });
    await fireEvent.click(screen.getByText('Other'));
    expect(screen.getByPlaceholderText(/Enter custom response/)).toBeDefined();
  });

  it('should not show countdown for code changes when disabled', () => {
    const editPrompt = { ...mockPrompt, toolName: 'Edit' };
    const { container } = render(PromptCard, {
      props: {
        prompt: editPrompt,
        settings: { autoAcceptTimeout: 10, autoAcceptCodeChanges: false }
      }
    });
    // Countdown should not be visible
    expect(container.querySelector('[data-testid="countdown"]')).toBeNull();
  });
});
```

#### stores.test.ts
```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { get } from 'svelte/store';
import { prompts, settings, addPrompt, removePrompt, updateSettings } from '../stores';

describe('Stores', () => {
  beforeEach(() => {
    prompts.set([]);
    settings.set({ autoAcceptTimeout: 10, autoAcceptCodeChanges: false, autoAcceptToolCalls: true });
  });

  describe('prompts store', () => {
    it('should add prompt', () => {
      addPrompt({ id: '1', sessionId: 's1', toolName: 'Bash', toolInput: {}, cwd: '/', createdAt: Date.now() });
      expect(get(prompts)).toHaveLength(1);
    });

    it('should remove prompt by id', () => {
      addPrompt({ id: '1', sessionId: 's1', toolName: 'Bash', toolInput: {}, cwd: '/', createdAt: Date.now() });
      addPrompt({ id: '2', sessionId: 's1', toolName: 'Edit', toolInput: {}, cwd: '/', createdAt: Date.now() });
      removePrompt('1');
      expect(get(prompts)).toHaveLength(1);
      expect(get(prompts)[0].id).toBe('2');
    });
  });

  describe('settings store', () => {
    it('should update settings', () => {
      updateSettings({ autoAcceptTimeout: 20 });
      expect(get(settings).autoAcceptTimeout).toBe(20);
    });

    it('should persist to localStorage', () => {
      updateSettings({ autoAcceptTimeout: 30 });
      const stored = JSON.parse(localStorage.getItem('flowgate-settings') || '{}');
      expect(stored.autoAcceptTimeout).toBe(30);
    });
  });
});
```

### E2E Tests (`e2e/tests/`)

#### approval-flow.spec.ts
```typescript
import { test, expect } from '@playwright/test';

test.describe('Approval Flow', () => {
  test('should approve prompt via Yes button', async ({ page, request }) => {
    await page.goto('http://localhost:8888');

    // Simulate hook sending a prompt
    const promptRes = request.post('http://localhost:8888/api/prompt', {
      data: {
        session_id: 'e2e-test',
        tool_name: 'Bash',
        tool_input: { command: 'echo hello' },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp'
      }
    });

    // Wait for prompt card to appear
    await expect(page.getByText('Bash')).toBeVisible();
    await expect(page.getByText('echo hello')).toBeVisible();

    // Click Yes
    await page.getByRole('button', { name: 'Yes' }).click();

    // Verify prompt resolved
    const result = await promptRes;
    expect(result.ok()).toBe(true);
    const body = await result.json();
    expect(body.decision).toBe('allow');

    // Verify prompt removed from UI
    await expect(page.getByText('echo hello')).not.toBeVisible();
  });

  test('should deny prompt with custom reason via Other', async ({ page, request }) => {
    await page.goto('http://localhost:8888');

    const promptRes = request.post('http://localhost:8888/api/prompt', {
      data: {
        session_id: 'e2e-test',
        tool_name: 'Bash',
        tool_input: { command: 'rm -rf /' },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp'
      }
    });

    await expect(page.getByText('rm -rf')).toBeVisible();
    await page.getByRole('button', { name: 'Other' }).click();

    // Fill in denial reason
    await page.getByPlaceholder(/Enter custom response/).fill('Too dangerous');
    await page.getByRole('button', { name: 'Deny' }).click();

    const result = await promptRes;
    const body = await result.json();
    expect(body.decision).toBe('deny');
    expect(body.reason).toBe('Too dangerous');
  });
});
```

#### auto-accept.spec.ts
```typescript
import { test, expect } from '@playwright/test';

test.describe('Auto-Accept', () => {
  test('should auto-accept after timeout', async ({ page, request }) => {
    await page.goto('http://localhost:8888');

    // Set short timeout for testing
    await page.getByRole('button', { name: 'Settings' }).click();
    await page.getByLabel('Auto-accept timeout').fill('2');
    await page.keyboard.press('Escape');

    const promptRes = request.post('http://localhost:8888/api/prompt', {
      data: {
        session_id: 'auto-test',
        tool_name: 'Bash',
        tool_input: { command: 'ls' },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp'
      }
    });

    // Wait for auto-accept (2 seconds + buffer)
    const result = await promptRes;
    const body = await result.json();
    expect(body.decision).toBe('allow');
  });

  test('should NOT auto-accept code changes when disabled', async ({ page, request }) => {
    await page.goto('http://localhost:8888');

    // Ensure auto-accept for code changes is off
    await page.getByRole('button', { name: 'Settings' }).click();
    await page.getByLabel('Auto-accept code changes').uncheck();
    await page.getByLabel('Auto-accept timeout').fill('1');
    await page.keyboard.press('Escape');

    const promptPromise = request.post('http://localhost:8888/api/prompt', {
      data: {
        session_id: 'code-test',
        tool_name: 'Edit',
        tool_input: { file_path: '/test.txt', old_string: 'a', new_string: 'b' },
        hook_event_name: 'PreToolUse',
        cwd: '/tmp'
      }
    });

    // Countdown should not be visible for Edit
    await expect(page.getByTestId('countdown')).not.toBeVisible();

    // Manually approve after timeout would have passed
    await page.waitForTimeout(1500);
    await page.getByRole('button', { name: 'Yes' }).click();

    const result = await promptPromise;
    expect(result.ok()).toBe(true);
  });
});
```

#### multi-instance.spec.ts
```typescript
import { test, expect } from '@playwright/test';

test.describe('Multi-Instance Support', () => {
  test('should display prompts from multiple sessions with distinct badges', async ({ page, request }) => {
    await page.goto('http://localhost:8888');

    // Send prompts from two different sessions
    request.post('http://localhost:8888/api/prompt', {
      data: {
        session_id: 'session-alpha',
        tool_name: 'Bash',
        tool_input: { command: 'echo alpha' },
        hook_event_name: 'PreToolUse',
        cwd: '/project-a'
      }
    });

    request.post('http://localhost:8888/api/prompt', {
      data: {
        session_id: 'session-beta',
        tool_name: 'Edit',
        tool_input: { file_path: '/test.txt' },
        hook_event_name: 'PreToolUse',
        cwd: '/project-b'
      }
    });

    // Verify both prompts appear
    await expect(page.getByText('session-alpha')).toBeVisible();
    await expect(page.getByText('session-beta')).toBeVisible();

    // Verify different colors (badges should have different background colors)
    const alphaColor = await page.getByText('session-alpha').evaluate(el =>
      window.getComputedStyle(el).backgroundColor
    );
    const betaColor = await page.getByText('session-beta').evaluate(el =>
      window.getComputedStyle(el).backgroundColor
    );
    expect(alphaColor).not.toBe(betaColor);
  });
});
```

### Running Tests

```bash
# Run all tests
pnpm test

# Run server tests only
pnpm --filter server test

# Run UI tests only
pnpm --filter ui test

# Run E2E tests (requires server running)
pnpm test:e2e

# Run tests in watch mode
pnpm test:watch

# Run with coverage
pnpm test:coverage
```

### CI Configuration (package.json scripts)

```json
{
  "scripts": {
    "test": "pnpm -r test",
    "test:watch": "pnpm -r test:watch",
    "test:coverage": "pnpm -r test:coverage",
    "test:e2e": "playwright test",
    "test:ci": "pnpm test && pnpm test:e2e"
  }
}

## User Preferences (Confirmed)

- **Auto-open browser**: Yes, when server starts
- **Port**: 8888
- **Notifications**: Browser notification + sound on new prompts
- **"Other" button behavior**: Both options - can deny with reason OR modify and approve
- **Network binding**: Localhost only (127.0.0.1) - no external network access
