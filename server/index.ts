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

const app: Application = express();
const server = createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });
const queue = new PromptQueue();
const deviceManager = createDeviceManager();

// Track connected WebSocket clients
const clients = new Set<WebSocket>();

// Broadcast to all connected clients
function broadcast(message: WsMessage): void {
  const data = JSON.stringify(message);
  for (const client of clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(data);
    }
  }
}

// Set up queue callbacks for broadcasting
queue.setCallbacks({
  onPromptAdded: (prompt: Prompt) => {
    broadcast({ type: 'prompt:new', prompt });
    deviceManager.onPromptsChanged(queue.list());
  },
  onPromptResolved: (id: string, autoAccepted: boolean) => {
    broadcast({ type: 'prompt:resolved', id, autoAccepted });
    deviceManager.onPromptResolved(id);
    deviceManager.onPromptsChanged(queue.list());
  },
});

// Set up device manager callbacks for prompt resolution
deviceManager.setCallbacks({
  onResolve: (id: string, decision: Decision) => {
    queue.resolve(id, decision);
  },
  onResolveAll: (decision: 'allow' | 'deny') => {
    const prompts = queue.list();
    for (const prompt of prompts) {
      queue.resolve(prompt.id, {
        decision,
        reason: decision === 'allow' ? 'Accepted all from device' : 'Denied all from device',
      });
    }
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
const publicDir = join(__dirname, 'public');
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
  if (!isValidHookInput(req.body)) {
    res.status(400).json({ error: 'Invalid hook input' });
    return;
  }

  try {
    const decision = await queue.add(req.body);
    res.json(decision);
  } catch (err) {
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

  if (!isValidDecision(req.body)) {
    res.status(400).json({ error: 'Invalid decision' });
    return;
  }

  const resolved = queue.resolve(id, req.body);
  if (!resolved) {
    res.status(404).json({ error: 'Prompt not found' });
    return;
  }

  res.json({ success: true });
});

// POST /api/prompts/:id/pause - Pause auto-accept timer for a prompt
app.post('/api/prompts/:id/pause', (req: Request, res: Response) => {
  const { id } = req.params;

  const paused = queue.pauseTimer(id);
  if (!paused) {
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

// WebSocket handling
wss.on('connection', (ws: WebSocket) => {
  clients.add(ws);

  // Send current state on connect
  ws.send(JSON.stringify({
    type: 'prompts:list',
    prompts: queue.list(),
  } satisfies WsMessage));

  ws.on('close', () => {
    clients.delete(ws);
  });

  ws.on('error', () => {
    clients.delete(ws);
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
