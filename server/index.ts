import express, { type Application, type Request, type Response } from 'express';
import cors from 'cors';
import { createServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import { existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import open from 'open';
import { PromptQueue } from './queue.js';
import { createDeviceManager } from './devices/index.js';
import type { Decision, HookInput, Prompt, Settings, WsMessage } from './types.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

const HOST = '127.0.0.1';
const PORT = parseInt(process.env.PORT ?? '8888', 10);
const DEV_UI_PORT = 5173;
const VERBOSE = process.env.VERBOSE === 'true' || process.env.VERBOSE === '1';

// Verbose logging utility
function log(...args: unknown[]): void {
  if (VERBOSE) {
    const timestamp = new Date().toISOString();
    console.log(`[${timestamp}]`, ...args);
  }
}

const app: Application = express();
const server = createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });
const queue = new PromptQueue();
const deviceManager = createDeviceManager();

// Track connected WebSocket clients
const clients = new Set<WebSocket>();

// Global pause state for all prompts
let globalPaused = false;

// Broadcast to all connected clients
function broadcast(message: WsMessage): void {
  const data = JSON.stringify(message);
  log('Broadcasting:', message.type, clients.size, 'clients');
  for (const client of clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(data);
    }
  }
}

// Set up queue callbacks for broadcasting
queue.setCallbacks({
  onPromptAdded: (prompt: Prompt) => {
    log('Prompt added:', prompt.id, prompt.toolName, prompt.acceptType);
    broadcast({ type: 'prompt:new', prompt });
    deviceManager.onPromptsChanged(queue.list());
  },
  onPromptResolved: (id: string, autoAccepted: boolean) => {
    log('Prompt resolved:', id, 'auto-accepted:', autoAccepted);
    broadcast({ type: 'prompt:resolved', id, autoAccepted });
    deviceManager.onPromptResolved(id);
    deviceManager.onPromptsChanged(queue.list());
  },
  onPromptUpdated: (prompt: Prompt) => {
    log('Prompt updated:', prompt.id, 'autoAcceptAt:', prompt.autoAcceptAt);
    broadcast({ type: 'prompt:updated', prompt });
  },
});

// Set up device manager callbacks for prompt resolution
deviceManager.setCallbacks({
  onResolve: (id: string, decision: Decision) => {
    log('Device resolved prompt:', id, decision.decision);
    queue.resolve(id, decision);
  },
  onResolveAll: (decision: 'allow' | 'deny') => {
    log('Device resolved all prompts:', decision);
    const prompts = queue.list();
    for (const prompt of prompts) {
      queue.resolve(prompt.id, {
        decision,
        reason: decision === 'allow' ? 'Accepted all from device' : 'Denied all from device',
      });
    }
  },
  onTogglePauseAll: () => {
    globalPaused = !globalPaused;
    log('Global pause toggled:', globalPaused);
    queue.setPaused(globalPaused);  // Update queue timers
    broadcast({ type: 'pause:changed', isPaused: globalPaused });
    deviceManager.onPauseStateChanged(globalPaused);
  },
});

// Middleware - allow both dev and prod origins
app.use(cors({
  origin: [
    `http://localhost:${PORT}`,
    `http://127.0.0.1:${PORT}`,
    `http://localhost:${DEV_UI_PORT}`,
    `http://127.0.0.1:${DEV_UI_PORT}`,
  ],
}));
app.use(express.json());

// Serve static files in production
// When running compiled JS from dist/, public is in parent directory
// When running with tsx from source, public is in same directory
let publicDir = join(__dirname, 'public');
if (!existsSync(publicDir)) {
  publicDir = join(__dirname, '..', 'public');
}
const hasPublicDir = existsSync(publicDir);
if (hasPublicDir) {
  app.use(express.static(publicDir));
}

// Validate hook input
function isValidHookInput(body: unknown): body is HookInput {
  if (typeof body !== 'object' || body === null) return false;
  const obj = body as Record<string, unknown>;
  return (
    typeof obj.session_id === 'string' &&
    typeof obj.tool_name === 'string' &&
    typeof obj.tool_input === 'object' &&
    typeof obj.hook_event_name === 'string' &&
    typeof obj.cwd === 'string'
  );
}

// Validate decision
function isValidDecision(body: unknown): body is Decision {
  if (typeof body !== 'object' || body === null) return false;
  const obj = body as Record<string, unknown>;
  return (
    obj.decision === 'allow' ||
    obj.decision === 'deny' ||
    obj.decision === 'ask'
  );
}

// API Routes

// POST /api/prompt - Receive prompt from hook (blocking)
app.post('/api/prompt', async (req: Request, res: Response) => {
  log('POST /api/prompt', req.body.tool_name, req.body.session_id);
  if (!isValidHookInput(req.body)) {
    log('Invalid hook input');
    res.status(400).json({ error: 'Invalid hook input' });
    return;
  }

  try {
    const decision = await queue.add(req.body);
    log('Decision:', decision.decision, decision.reason);
    res.json(decision);
  } catch (err) {
    log('Error processing prompt:', err);
    res.status(500).json({ error: 'Failed to process prompt' });
  }
});

// GET /api/prompts - List active prompts
app.get('/api/prompts', (_req: Request, res: Response) => {
  res.json(queue.list());
});

// POST /api/prompts/:id/resolve - Resolve a prompt
app.post('/api/prompts/:id/resolve', (req: Request, res: Response) => {
  const { id } = req.params;
  log('POST /api/prompts/:id/resolve', id, req.body.decision);

  if (!isValidDecision(req.body)) {
    log('Invalid decision');
    res.status(400).json({ error: 'Invalid decision' });
    return;
  }

  const resolved = queue.resolve(id, req.body);
  if (!resolved) {
    log('Prompt not found:', id);
    res.status(404).json({ error: 'Prompt not found' });
    return;
  }

  res.json({ success: true });
});

// POST /api/prompts/:id/pause - Pause auto-accept timer for a prompt
app.post('/api/prompts/:id/pause', (req: Request, res: Response) => {
  const { id } = req.params;
  log('POST /api/prompts/:id/pause', id);

  const paused = queue.pauseTimer(id);
  if (!paused) {
    log('Prompt not found:', id);
    res.status(404).json({ error: 'Prompt not found' });
    return;
  }

  res.json({ success: true });
});

// GET /api/settings - Get current settings
app.get('/api/settings', (_req: Request, res: Response) => {
  res.json(queue.getSettings());
});

// PUT /api/settings - Update settings
app.put('/api/settings', (req: Request, res: Response) => {
  log('PUT /api/settings', JSON.stringify(req.body));
  const settings = queue.updateSettings(req.body as Partial<Settings>);
  broadcast({ type: 'settings:updated', settings });
  res.json(settings);
});

// GET /api/devices - Get connected device status
app.get('/api/devices', (_req: Request, res: Response) => {
  res.json({
    devices: deviceManager.getStatus(),
    hasConnectedDevice: deviceManager.hasConnectedDevice(),
  });
});

// POST /api/pause - Toggle global pause state
app.post('/api/pause', (_req: Request, res: Response) => {
  globalPaused = !globalPaused;
  log('POST /api/pause - toggled to:', globalPaused);
  queue.setPaused(globalPaused);  // Update queue timers
  broadcast({ type: 'pause:changed', isPaused: globalPaused });
  deviceManager.onPauseStateChanged(globalPaused);
  res.json({ isPaused: globalPaused });
});

// GET /api/pause - Get current pause state
app.get('/api/pause', (_req: Request, res: Response) => {
  res.json({ isPaused: globalPaused });
});

// WebSocket handling
wss.on('connection', (ws: WebSocket) => {
  clients.add(ws);
  log('WebSocket client connected - total clients:', clients.size);

  // Send current state on connect
  ws.send(JSON.stringify({
    type: 'prompts:list',
    prompts: queue.list(),
  } satisfies WsMessage));

  // Send current pause state
  ws.send(JSON.stringify({
    type: 'pause:changed',
    isPaused: globalPaused,
  } satisfies WsMessage));

  ws.on('close', () => {
    clients.delete(ws);
    log('WebSocket client disconnected - total clients:', clients.size);
  });

  ws.on('error', () => {
    clients.delete(ws);
    log('WebSocket client error - removed from clients');
  });
});

// SPA fallback - serve index.html for non-API routes in production
if (hasPublicDir) {
  app.get('*', (_req: Request, res: Response) => {
    res.sendFile(join(publicDir, 'index.html'));
  });
}

// Start server
server.listen(PORT, HOST, async () => {
  console.log(`Server running at http://${HOST}:${PORT}`);
  console.log(`WebSocket at ws://${HOST}:${PORT}/ws`);

  // Initialize device plugins
  if (process.env.NODE_ENV !== 'test') {
    await deviceManager.init();
  }

  // Auto-open browser only in production (when serving static files)
  if (process.env.NODE_ENV !== 'test' && hasPublicDir) {
    open(`http://localhost:${PORT}`);
  }
});

// Export for testing
export { app, server, queue, deviceManager };
