import { writable, get } from 'svelte/store';
import * as Tone from 'tone';
import type { Prompt, Settings, WsMessage, ToolCategory, UIPreferences, DevicesResponse } from './types';
import { DEFAULT_UI_PREFS } from './types';

// Complete tool categorization based on Claude Code documentation
export const TOOL_CATEGORIES = {
  read: new Set([
    'Read', 'Glob', 'Grep',
    'TaskList', 'TaskGet', 'TaskOutput',
    'ListMcpResourcesTool', 'ReadMcpResourceTool',
    'ToolSearch',
  ]),
  write: new Set([
    'Edit', 'Write', 'NotebookEdit',
    'TaskCreate', 'TaskUpdate',
  ]),
  execute: new Set([
    'Bash', 'KillShell',
    'Task', 'Skill',
  ]),
  web: new Set([
    'WebFetch', 'WebSearch',
  ]),
  interactive: new Set([
    'AskUserQuestion',
    'ExitPlanMode',
    'EnterPlanMode',
  ]),
} as const;

export type { ToolCategory } from './types';

export function getToolCategory(toolName: string): ToolCategory {
  if (toolName.startsWith('mcp__')) return 'mcp';
  if (TOOL_CATEGORIES.read.has(toolName)) return 'read';
  if (TOOL_CATEGORIES.write.has(toolName)) return 'write';
  if (TOOL_CATEGORIES.execute.has(toolName)) return 'execute';
  if (TOOL_CATEGORIES.web.has(toolName)) return 'web';
  if (TOOL_CATEGORIES.interactive.has(toolName)) return 'interactive';
  return 'other';
}

export function isInteractivePrompt(toolName: string): boolean {
  return toolName === 'AskUserQuestion' || toolName === 'ExitPlanMode';
}

// Prompts store
export const prompts = writable<Prompt[]>([]);

// Track auto-accepted prompts for visual feedback
const autoAcceptedIds = new Set<string>();
export const autoAccepted = writable<Set<string>>(new Set());

export function addPrompt(prompt: Prompt): void {
  prompts.update((list) => [...list, prompt]);
}

export function removePrompt(id: string): void {
  autoAcceptedIds.delete(id);
  autoAccepted.set(new Set(autoAcceptedIds));
  prompts.update((list) => list.filter((p) => p.id !== id));
}

export function markAutoAccepted(id: string): void {
  autoAcceptedIds.add(id);
  autoAccepted.set(new Set(autoAcceptedIds));
}

// Settings store - synced with server, not persisted locally
export const settings = writable<Settings>({
  rules: [],
  native: {
    showAutoAccept: true,
    enableAnimations: true,
  },
});

// UI preferences stored locally (not sent to server)
const UI_PREFS_KEY = 'claude-prompt-ui-prefs';

function loadUIPrefs(): UIPreferences {
  try {
    const stored = localStorage.getItem(UI_PREFS_KEY);
    if (stored) {
      return { ...DEFAULT_UI_PREFS, ...JSON.parse(stored) };
    }
  } catch {
    // Ignore parse errors
  }
  return DEFAULT_UI_PREFS;
}

export const uiPrefs = writable<UIPreferences>(loadUIPrefs());

uiPrefs.subscribe((value) => {
  try {
    localStorage.setItem(UI_PREFS_KEY, JSON.stringify(value));
  } catch {
    // Ignore storage errors
  }
  // Note: Volume updates are handled reactively in App.svelte via $: updateVolume($uiPrefs.volume)
});

// Session colors for multi-instance support
const SESSION_COLORS = [
  '#3b82f6', // blue
  '#22c55e', // green
  '#f59e0b', // amber
  '#ef4444', // red
  '#8b5cf6', // violet
  '#ec4899', // pink
  '#06b6d4', // cyan
  '#f97316', // orange
];

const sessionColorMap = new Map<string, string>();

export function getSessionColor(sessionId: string): string {
  if (!sessionColorMap.has(sessionId)) {
    const index = sessionColorMap.size % SESSION_COLORS.length;
    sessionColorMap.set(sessionId, SESSION_COLORS[index]);
  }
  return sessionColorMap.get(sessionId)!;
}

// WebSocket connection
let ws: WebSocket | null = null;
let reconnectTimeout: ReturnType<typeof setTimeout> | null = null;

export const connected = writable(false);
export const connectionError = writable<string | null>(null);

export function connectWebSocket(): void {
  if (ws) return;

  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';

  // Read token from URL parameter (passed by desktop app when opening browser)
  const urlParams = new URLSearchParams(window.location.search);
  const urlToken = urlParams.get('token') || '';

  // If URL has a token, always use it and update localStorage (replaces old token)
  // If no URL token, fall back to localStorage
  let savedToken = '';
  if (urlToken) {
    // New token from URL - save it (overwrites any old token)
    localStorage.setItem('claude-prompt-ui-token', urlToken);
    savedToken = urlToken;

    // Clean up URL by removing token parameter (optional, keeps URL clean)
    const cleanUrl = new URL(window.location.href);
    cleanUrl.searchParams.delete('token');
    window.history.replaceState({}, '', cleanUrl.toString());
  } else {
    savedToken = localStorage.getItem('claude-prompt-ui-token') || '';
  }

  const wsUrl = savedToken
    ? `${protocol}//${window.location.host}/ws?token=${encodeURIComponent(savedToken)}`
    : `${protocol}//${window.location.host}/ws`;

  ws = new WebSocket(wsUrl);

  ws.onopen = () => {
    connected.set(true);
    if (reconnectTimeout) {
      clearTimeout(reconnectTimeout);
      reconnectTimeout = null;
    }
  };

  ws.onclose = () => {
    connected.set(false);
    ws = null;
    // Reconnect after 2 seconds
    reconnectTimeout = setTimeout(connectWebSocket, 2000);
  };

  ws.onerror = () => {
    ws?.close();
  };

  ws.onmessage = (event) => {
    try {
      const message = JSON.parse(event.data) as WsMessage;
      handleMessage(message);
    } catch {
      // Ignore parse errors
    }
  };
}

function handleMessage(message: WsMessage): void {
  switch (message.type) {
    case 'prompt:new':
      addPrompt(message.prompt);
      notifyNewPrompt(message.prompt);
      break;
    case 'prompt:resolved':
      if (message.autoAccepted) {
        // Keep auto-accepted prompts visible for 1 second for context
        markAutoAccepted(message.id);
        setTimeout(() => removePrompt(message.id), 1000);
      } else {
        removePrompt(message.id);
      }
      break;
    case 'prompt:updated':
      // Update prompt in place (e.g., when autoAcceptAt changes after resume)
      prompts.update((list) =>
        list.map((p) => (p.id === message.prompt.id ? message.prompt : p))
      );
      break;
    case 'prompts:list':
      prompts.set(message.prompts);
      break;
    case 'pause:changed':
      globalPaused.set(message.isPaused);
      break;
    case 'settings:updated':
      // Update settings when server broadcasts changes
      if (message.settings) {
        settings.set(message.settings);
      }
      break;
  }
}

// Browser notifications
let notificationPermission: NotificationPermission = 'default';
let audioInitialized = false;

// 80s-style synth sounds using Tone.js
let synths: Record<string, Tone.Synth | Tone.PolySynth> = {};
let audioInitializing = false;

// Convert 0-100 volume to dB offset (-Infinity to 0)
function volumeToDb(volume: number): number {
  if (volume <= 0) return -Infinity;
  // Map 0-100 to -40dB to 0dB range
  return -40 + (volume / 100) * 40;
}

// Update all synth volumes
export function updateVolume(volume: number): void {
  if (!audioInitialized) return;
  const dbOffset = volumeToDb(volume);
  // Base volumes + offset
  if (synths.read) synths.read.volume.value = -12 + dbOffset + 40;
  if (synths.write) synths.write.volume.value = -10 + dbOffset + 40;
  if (synths.execute) synths.execute.volume.value = -8 + dbOffset + 40;
  if (synths.prompt) (synths.prompt as Tone.PolySynth).volume.value = -10 + dbOffset + 40;
  if (synths.other) synths.other.volume.value = -12 + dbOffset + 40;
}

function initAudio(): void {
  if (audioInitialized || audioInitializing) return;
  audioInitializing = true;

  // Initialize async but don't block
  Tone.start().then(() => {
    // Soft pad for read operations - gentle and non-intrusive
    synths.read = new Tone.Synth({
      oscillator: { type: 'sine' },
      envelope: { attack: 0.1, decay: 0.3, sustain: 0.4, release: 0.8 },
    }).toDestination();
    synths.read.volume.value = -12;

    // Bright lead for write operations - more attention-getting
    synths.write = new Tone.Synth({
      oscillator: { type: 'triangle' },
      envelope: { attack: 0.02, decay: 0.2, sustain: 0.3, release: 0.5 },
    }).toDestination();
    synths.write.volume.value = -10;

    // Punchy bass for execute operations - distinctive
    synths.execute = new Tone.Synth({
      oscillator: { type: 'sawtooth' },
      envelope: { attack: 0.01, decay: 0.15, sustain: 0.2, release: 0.4 },
    }).toDestination();
    synths.execute.volume.value = -8;

    // Warm chord for user prompts - friendly and inviting
    synths.prompt = new Tone.PolySynth(Tone.Synth, {
      oscillator: { type: 'sine' },
      envelope: { attack: 0.05, decay: 0.4, sustain: 0.5, release: 1.0 },
    }).toDestination();
    synths.prompt.volume.value = -10;

    // Default for other tools
    synths.other = new Tone.Synth({
      oscillator: { type: 'square' },
      envelope: { attack: 0.05, decay: 0.2, sustain: 0.3, release: 0.5 },
    }).toDestination();
    synths.other.volume.value = -12;

    audioInitialized = true;
    audioInitializing = false;

    // Apply initial volume from UI prefs
    const currentPrefs = get(uiPrefs);
    updateVolume(currentPrefs.volume);
  }).catch(() => {
    audioInitializing = false;
  });
}

function playToolSound(category: 'read' | 'write' | 'execute' | 'prompt' | 'other'): void {
  if (!audioInitialized) return;

  // Check if muted
  const currentPrefs = get(uiPrefs);
  if (currentPrefs.volume <= 0) return;

  const now = Tone.now();
  const step = 0.08; // Arp step timing

  switch (category) {
    case 'read':
      // Low gentle rising arp - C minor
      synths.read.triggerAttackRelease('C2', '16n', now);
      synths.read.triggerAttackRelease('Eb2', '16n', now + step);
      synths.read.triggerAttackRelease('G2', '16n', now + step * 2);
      break;
    case 'write':
      // Low rising arp with octave - more alert
      synths.write.triggerAttackRelease('G2', '16n', now);
      synths.write.triggerAttackRelease('B2', '16n', now + step);
      synths.write.triggerAttackRelease('D3', '16n', now + step * 2);
      synths.write.triggerAttackRelease('G3', '8n', now + step * 3);
      break;
    case 'execute':
      // Low descending arp - attention-getting
      synths.execute.triggerAttackRelease('E3', '16n', now);
      synths.execute.triggerAttackRelease('C3', '16n', now + step);
      synths.execute.triggerAttackRelease('G2', '16n', now + step * 2);
      synths.execute.triggerAttackRelease('C2', '8n', now + step * 3);
      break;
    case 'prompt':
      // Low warm arp - friendly, longer
      (synths.prompt as Tone.PolySynth).triggerAttackRelease('C2', '8n', now);
      (synths.prompt as Tone.PolySynth).triggerAttackRelease('E2', '8n', now + step);
      (synths.prompt as Tone.PolySynth).triggerAttackRelease('G2', '8n', now + step * 2);
      (synths.prompt as Tone.PolySynth).triggerAttackRelease(['C3', 'E3', 'G3'], '4n', now + step * 3);
      break;
    case 'other':
    default:
      // Low simple arp
      synths.other.triggerAttackRelease('A2', '16n', now);
      synths.other.triggerAttackRelease('E2', '16n', now + step);
      synths.other.triggerAttackRelease('A2', '8n', now + step * 2);
      break;
  }
}

export async function requestNotificationPermission(): Promise<void> {
  if ('Notification' in window) {
    notificationPermission = await Notification.requestPermission();
  }
  // Initialize audio on user gesture (non-blocking)
  initAudio();
}

type SoundCategory = 'read' | 'write' | 'execute' | 'prompt' | 'other';

function toolCategoryToSoundCategory(category: import('./types').ToolCategory): SoundCategory {
  switch (category) {
    case 'read': return 'read';
    case 'write': return 'write';
    case 'execute': return 'execute';
    case 'interactive': return 'prompt';
    case 'web':
    case 'mcp':
    case 'other':
    default:
      return 'other';
  }
}

function notifyNewPrompt(prompt: Prompt): void {
  // Don't play sound for auto-accept prompts
  const shouldPlaySound = prompt.acceptType !== 'auto-accept';

  if (shouldPlaySound) {
    // Play synth sound based on tool category
    const category = getToolCategory(prompt.toolName);
    const soundCategory = toolCategoryToSoundCategory(category);
    playToolSound(soundCategory);
  }

  // Browser notification (only for non-auto-accept)
  if (shouldPlaySound && notificationPermission === 'granted') {
    new Notification('Claude Prompt', {
      body: `${prompt.toolName}: ${getPromptDescription(prompt)}`,
      icon: '/favicon.ico',
      tag: prompt.id,
    });
  }
}

function getPromptDescription(prompt: Prompt): string {
  const input = prompt.toolInput;
  if ('command' in input && typeof input.command === 'string') {
    return input.command.slice(0, 50);
  }
  if ('file_path' in input && typeof input.file_path === 'string') {
    return input.file_path;
  }
  return JSON.stringify(input).slice(0, 50);
}

// Device connection tracking
export const deviceConnected = writable(false);
export const deviceStatus = writable<DevicesResponse>({ devices: [], hasConnectedDevice: false });

// Global pause state (false = playing/auto-accept enabled, true = paused)
export const globalPaused = writable(false);

let devicePollInterval: ReturnType<typeof setInterval> | null = null;

export async function fetchDeviceStatus(): Promise<void> {
  try {
    const res = await fetch('/api/devices');
    if (res.ok) {
      const status: DevicesResponse = await res.json();
      deviceStatus.set(status);
      deviceConnected.set(status.hasConnectedDevice);
    }
  } catch {
    // Ignore fetch errors
  }
}

export function startDevicePolling(): void {
  if (devicePollInterval) return;
  fetchDeviceStatus();
  devicePollInterval = setInterval(fetchDeviceStatus, 5000);
}

export function stopDevicePolling(): void {
  if (devicePollInterval) {
    clearInterval(devicePollInterval);
    devicePollInterval = null;
  }
}

/**
 * Get the display index (1-4 or "5+") for a prompt.
 * Returns undefined if no device is connected.
 */
export function getPromptDisplayIndex(promptId: string, allPrompts: Prompt[]): string | undefined {
  const index = allPrompts.findIndex(p => p.id === promptId);
  if (index === -1) return undefined;
  if (index < 4) return String(index + 1);
  return '5+';
}

// API helpers - all use WebSocket now
export function resolvePrompt(id: string, decision: { decision: 'allow' | 'deny' | 'ask'; reason?: string; updatedInput?: Record<string, unknown> }): void {
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    console.error('WebSocket not connected, cannot resolve prompt');
    return;
  }

  ws.send(JSON.stringify({
    type: 'resolve',
    id,
    decision,
  }));
}

export function updateSettings(newSettings: Settings): void {
  if (!ws || ws.readyState !== WebSocket.OPEN) return;

  ws.send(JSON.stringify({
    type: 'updateSettings',
    settings: newSettings
  }));
}

export function togglePauseAll(): void {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'togglePause' }));
  }
}
