#!/usr/bin/env tsx
/**
 * Stream Deck client for Claude Prompt UI
 * Connects to Go server via WebSocket
 */

import { WebSocket } from 'ws';
import { readFileSync, existsSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';
import { StreamDeckPlugin } from './devices/streamdeck.js';
import type { WsMessage, ClientMessage, Prompt, Decision } from './types.js';

const SERVER_BASE_URL = process.env.SERVER_URL ?? 'ws://127.0.0.1:8888/ws';

// Read authentication token from ~/.claude-prompt-ui/token
function readToken(): string | null {
  const tokenPath = join(homedir(), '.claude-prompt-ui', 'token');
  if (!existsSync(tokenPath)) {
    console.error('[Client] Token file not found at:', tokenPath);
    console.error('[Client] Make sure the Go server is running to generate a token');
    return null;
  }
  try {
    return readFileSync(tokenPath, 'utf-8').trim();
  } catch (err) {
    console.error('[Client] Failed to read token:', err);
    return null;
  }
}

function getServerUrl(): string {
  const token = readToken();
  if (!token) {
    console.warn('[Client] No token found, connection will likely fail with 401');
    return SERVER_BASE_URL;
  }
  // Append token as query parameter
  const separator = SERVER_BASE_URL.includes('?') ? '&' : '?';
  return `${SERVER_BASE_URL}${separator}token=${token}`;
}

let ws: WebSocket | null = null;
let streamDeck: StreamDeckPlugin | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let prompts: Prompt[] = [];
let isPaused = false;

async function main(): Promise<void> {
  console.log('[Client] Starting Stream Deck client...');
  
  // Initialize Stream Deck
  streamDeck = new StreamDeckPlugin();
  
  // Set up callbacks
  streamDeck.onResolve = (id: string, decision: Decision) => {
    sendMessage({ type: 'resolve', id, decision });
  };
  
  streamDeck.onResolveAll = (decision: 'allow' | 'deny') => {
    sendMessage({ type: 'resolve-all', resolveDecision: decision });
  };
  
  streamDeck.onTogglePauseAll = () => {
    sendMessage({ type: 'toggle-pause' });
  };
  
  await streamDeck.init();
  
  // Connect to server
  connect();
  
  // Graceful shutdown
  process.on('SIGINT', async () => {
    console.log('[Client] Shutting down...');
    if (streamDeck) await streamDeck.destroy();
    if (ws) ws.close();
    process.exit(0);
  });
}

function connect(): void {
  if (ws) return;

  const serverUrl = getServerUrl();
  console.log(`[Client] Connecting to server...`);
  ws = new WebSocket(serverUrl);
  
  ws.on('open', () => {
    console.log('[Client] Connected to server');
    if (reconnectTimer) {
      clearTimeout(reconnectTimer);
      reconnectTimer = null;
    }
    
    // Request current prompt list
    sendMessage({ type: 'list' });
  });
  
  ws.on('message', (data: Buffer) => {
    try {
      const message = JSON.parse(data.toString()) as WsMessage;
      handleMessage(message);
    } catch (err) {
      console.error('[Client] Failed to parse message:', err);
    }
  });
  
  ws.on('close', () => {
    console.log('[Client] Disconnected from server');
    ws = null;
    
    // Reconnect after 2 seconds
    if (!reconnectTimer) {
      reconnectTimer = setTimeout(() => {
        reconnectTimer = null;
        connect();
      }, 2000);
    }
  });
  
  ws.on('error', (err) => {
    console.error('[Client] WebSocket error:', err.message);
  });
}

function sendMessage(message: ClientMessage): void {
  if (ws?.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(message));
  }
}

function handleMessage(message: WsMessage): void {
  switch (message.type) {
    case 'prompt:new':
      prompts.push(message.prompt);
      streamDeck?.onPromptsChanged(prompts);
      console.log(`[Client] New prompt: ${message.prompt.toolName} (${message.prompt.id})`);
      break;
      
    case 'prompt:resolved':
      console.log(`[Client] Resolving prompt ${message.id}, had ${prompts.length} prompts`);
      prompts = prompts.filter(p => p.id !== message.id);
      console.log(`[Client] After filter: ${prompts.length} prompts remaining`);
      streamDeck?.onPromptsChanged(prompts);
      streamDeck?.onPromptResolved(message.id);
      console.log(`[Client] Prompt resolved: ${message.id}`);
      break;
      
    case 'prompt:updated':
      prompts = prompts.map(p => p.id === message.prompt.id ? message.prompt : p);
      streamDeck?.onPromptsChanged(prompts);
      console.log(`[Client] Prompt updated: ${message.prompt.id}`);
      break;
      
    case 'prompts:list':
      prompts = message.prompts;
      streamDeck?.onPromptsChanged(prompts);
      console.log(`[Client] Prompt list: ${prompts.length} prompts`);
      break;
      
    case 'pause:changed':
      isPaused = message.isPaused;
      streamDeck?.onPauseStateChanged(isPaused);
      console.log(`[Client] Pause state: ${isPaused ? 'PAUSED' : 'PLAYING'}`);
      break;
  }
}

main().catch((err) => {
  console.error('[Client] Fatal error:', err);
  process.exit(1);
});
