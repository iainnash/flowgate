import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';

vi.mock('tone', () => ({
  start: vi.fn().mockResolvedValue(undefined),
  now: vi.fn().mockReturnValue(0),
  Synth: vi.fn().mockImplementation(() => ({
    toDestination: vi.fn().mockReturnThis(),
    volume: { value: 0 },
    triggerAttackRelease: vi.fn(),
  })),
  PolySynth: vi.fn().mockImplementation(() => ({
    toDestination: vi.fn().mockReturnThis(),
    volume: { value: 0 },
    triggerAttackRelease: vi.fn(),
  })),
}));

import {
  addPrompt,
  autoAccepted,
  connectWebSocket,
  connected,
  getPromptDisplayIndex,
  getSessionColor,
  getToolCategory,
  globalPaused,
  prompts,
  removePrompt,
  settings,
  uiPrefs,
} from './stores';
import type { Prompt, Settings, UIPreferences } from './types';

class MockWebSocket {
  static CONNECTING = 0;
  static OPEN = 1;
  static CLOSING = 2;
  static CLOSED = 3;
  static instances: MockWebSocket[] = [];

  onopen: (() => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;
  onmessage: ((event: { data: string }) => void) | null = null;
  readyState = MockWebSocket.OPEN;
  sent: string[] = [];

  constructor(public url: string) {
    MockWebSocket.instances.push(this);
  }

  send(data: string): void {
    this.sent.push(data);
  }

  close(): void {
    this.readyState = MockWebSocket.CLOSED;
    this.onclose?.();
  }

  emit(message: unknown): void {
    this.onmessage?.({ data: JSON.stringify(message) });
  }
}

function createPrompt(overrides: Partial<Prompt> = {}): Prompt {
  return {
    id: 'prompt-1',
    sessionId: 'session-1',
    toolName: 'Bash',
    toolInput: { command: 'pnpm test' },
    hookEventName: 'PreToolUse',
    cwd: '/Users/iain/code/flowgate',
    createdAt: 1_700_000_000_000,
    acceptType: 'manual',
    ...overrides,
  };
}

function currentSettings(overrides: Partial<Settings> = {}): Settings {
  return {
    rules: [],
    native: {
      showAutoAccept: true,
      enableAnimations: true,
    },
    ...overrides,
  };
}

describe('stores', () => {
  beforeEach(() => {
    localStorage.clear();
    vi.restoreAllMocks();
    vi.stubGlobal('WebSocket', MockWebSocket);
    MockWebSocket.instances = [];

    prompts.set([]);
    autoAccepted.set(new Set());
    connected.set(false);
    globalPaused.set(false);
    settings.set(currentSettings());
    uiPrefs.set({ theme: 'dark', volume: 50 });
  });

  describe('prompt state', () => {
    it('adds and removes prompts by id', () => {
      addPrompt(createPrompt({ id: 'prompt-1' }));
      addPrompt(createPrompt({ id: 'prompt-2', toolName: 'Read' }));

      expect(get(prompts).map((prompt) => prompt.id)).toEqual(['prompt-1', 'prompt-2']);

      removePrompt('prompt-1');

      expect(get(prompts).map((prompt) => prompt.id)).toEqual(['prompt-2']);
    });

    it('ignores removal of unknown prompts', () => {
      addPrompt(createPrompt());
      removePrompt('missing');

      expect(get(prompts)).toHaveLength(1);
    });

    it('returns display positions for connected hardware controls', () => {
      const allPrompts = [
        createPrompt({ id: 'prompt-1' }),
        createPrompt({ id: 'prompt-2' }),
        createPrompt({ id: 'prompt-3' }),
        createPrompt({ id: 'prompt-4' }),
        createPrompt({ id: 'prompt-5' }),
      ];

      expect(getPromptDisplayIndex('prompt-1', allPrompts)).toBe('1');
      expect(getPromptDisplayIndex('prompt-4', allPrompts)).toBe('4');
      expect(getPromptDisplayIndex('prompt-5', allPrompts)).toBe('5+');
      expect(getPromptDisplayIndex('missing', allPrompts)).toBeUndefined();
    });
  });

  describe('settings and preferences', () => {
    it('uses the current settings shape', () => {
      const newSettings: Settings = currentSettings({
        rules: [
          {
            name: 'Read files after a delay',
            toolName: 'Read',
            category: 'read',
            action: { type: 'accept-after', seconds: 5 },
            enabled: true,
            matchCount: 0,
          },
        ],
      });

      settings.set(newSettings);

      expect(get(settings)).toEqual(newSettings);
    });

    it('persists UI preferences locally without mixing them into server settings', () => {
      const prefs: UIPreferences = { theme: 'light', volume: 25 };

      uiPrefs.set(prefs);

      expect(JSON.parse(localStorage.getItem('flowgate-prefs') ?? '{}')).toEqual(prefs);
      expect(get(settings)).toEqual(currentSettings());
    });
  });

  describe('tool metadata', () => {
    it('categorizes known and MCP tools', () => {
      expect(getToolCategory('Read')).toBe('read');
      expect(getToolCategory('Edit')).toBe('write');
      expect(getToolCategory('Bash')).toBe('execute');
      expect(getToolCategory('AskUserQuestion')).toBe('interactive');
      expect(getToolCategory('mcp__github__search')).toBe('mcp');
      expect(getToolCategory('SomethingNew')).toBe('other');
    });

    it('returns stable colors for the same session', () => {
      const first = getSessionColor('session-a');
      const second = getSessionColor('session-a');

      expect(first).toBe(second);
      expect(first).toMatch(/^#[0-9a-f]{6}$/i);
    });
  });

  describe('WebSocket messages', () => {
    it('updates stores from current server messages', () => {
      localStorage.setItem('flowgate-token', 'test-token');

      connectWebSocket();
      const socket = MockWebSocket.instances[0];
      socket.onopen?.();

      expect(socket.url).toBe('ws://localhost:3000/ws?token=test-token');
      expect(get(connected)).toBe(true);

      const prompt = createPrompt({ id: 'prompt-from-server', toolName: 'Read' });
      socket.emit({ type: 'prompt:new', prompt });
      expect(get(prompts)).toEqual([prompt]);

      socket.emit({
        type: 'prompt:updated',
        prompt: { ...prompt, acceptType: 'accept-after', autoAcceptIn: 10 },
      });
      expect(get(prompts)[0]).toMatchObject({ acceptType: 'accept-after', autoAcceptIn: 10 });

      socket.emit({ type: 'pause:changed', isPaused: true });
      expect(get(globalPaused)).toBe(true);

      const serverSettings = currentSettings({
        rules: [
          {
            name: 'Auto-accept reads',
            toolName: 'Read',
            action: { type: 'auto-accept' },
            enabled: true,
            matchCount: 2,
          },
        ],
      });
      socket.emit({ type: 'settings:updated', settings: serverSettings });
      expect(get(settings)).toEqual(serverSettings);

      socket.emit({ type: 'prompt:resolved', id: 'prompt-from-server', autoAccepted: false });
      expect(get(prompts)).toEqual([]);
    });
  });
});
