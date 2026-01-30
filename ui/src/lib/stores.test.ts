import { describe, it, expect, beforeEach, vi } from 'vitest';
import { get } from 'svelte/store';

// Mock Tone.js to avoid ESM issues in tests
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
  prompts,
  settings,
  addPrompt,
  removePrompt,
  getSessionColor,
  findMatchingRule,
  ruleMatchesTool,
} from './stores';
import type { Prompt, PermissionRule, Settings } from './types';

describe('stores', () => {
  beforeEach(() => {
    prompts.set([]);
    settings.set({
      rules: [
        {
          id: '1',
          name: 'Read operations',
          matchType: 'category',
          matchValue: 'read',
          action: { type: 'accept-after', seconds: 3 },
          enabled: true,
        },
        {
          id: '2',
          name: 'Everything else',
          matchType: 'all',
          matchValue: '*',
          action: { type: 'require-verify' },
          enabled: true,
        },
      ],
      projects: [],
    });
    localStorage.clear();
  });

  describe('prompts store', () => {
    const createPrompt = (id: string): Prompt => ({
      id,
      sessionId: 'session-1',
      toolName: 'Bash',
      toolInput: { command: 'ls' },
      hookEventName: 'PreToolUse',
      cwd: '/home/user',
      createdAt: Date.now(),
    });

    it('should add prompt', () => {
      addPrompt(createPrompt('1'));
      expect(get(prompts)).toHaveLength(1);
    });

    it('should add multiple prompts', () => {
      addPrompt(createPrompt('1'));
      addPrompt(createPrompt('2'));
      expect(get(prompts)).toHaveLength(2);
    });

    it('should remove prompt by id', () => {
      addPrompt(createPrompt('1'));
      addPrompt(createPrompt('2'));
      removePrompt('1');
      expect(get(prompts)).toHaveLength(1);
      expect(get(prompts)[0].id).toBe('2');
    });

    it('should handle removing non-existent prompt', () => {
      addPrompt(createPrompt('1'));
      removePrompt('unknown');
      expect(get(prompts)).toHaveLength(1);
    });
  });

  describe('settings store', () => {
    it('should have rules array', () => {
      const s = get(settings);
      expect(s.rules).toBeDefined();
      expect(Array.isArray(s.rules)).toBe(true);
    });

    it('should have projects array', () => {
      const s = get(settings);
      expect(s.projects).toBeDefined();
      expect(Array.isArray(s.projects)).toBe(true);
    });

    it('should persist to localStorage', () => {
      const newSettings: Settings = {
        rules: [{
          id: 'test',
          name: 'Test',
          matchType: 'all',
          matchValue: '*',
          action: { type: 'require-verify' },
          enabled: true,
        }],
        projects: [],
      };
      settings.set(newSettings);
      const stored = JSON.parse(
        localStorage.getItem('claude-prompt-ui-settings') || '{}'
      );
      expect(stored.rules).toHaveLength(1);
      expect(stored.rules[0].name).toBe('Test');
    });
  });

  describe('ruleMatchesTool', () => {
    it('should match by category', () => {
      const rule: PermissionRule = {
        id: '1',
        name: 'Read',
        matchType: 'category',
        matchValue: 'read',
        action: { type: 'auto-accept' },
        enabled: true,
      };
      expect(ruleMatchesTool(rule, 'Read')).toBe(true);
      expect(ruleMatchesTool(rule, 'Glob')).toBe(true);
      expect(ruleMatchesTool(rule, 'Bash')).toBe(false);
    });

    it('should match by specific tool', () => {
      const rule: PermissionRule = {
        id: '1',
        name: 'Bash only',
        matchType: 'tool',
        matchValue: 'Bash',
        action: { type: 'auto-accept' },
        enabled: true,
      };
      expect(ruleMatchesTool(rule, 'Bash')).toBe(true);
      expect(ruleMatchesTool(rule, 'Read')).toBe(false);
    });

    it('should match by pattern', () => {
      const rule: PermissionRule = {
        id: '1',
        name: 'MCP tools',
        matchType: 'pattern',
        matchValue: 'mcp__.*',
        action: { type: 'auto-accept' },
        enabled: true,
      };
      expect(ruleMatchesTool(rule, 'mcp__slack__send')).toBe(true);
      expect(ruleMatchesTool(rule, 'Bash')).toBe(false);
    });

    it('should match all tools with "all" type', () => {
      const rule: PermissionRule = {
        id: '1',
        name: 'Catch all',
        matchType: 'all',
        matchValue: '*',
        action: { type: 'require-verify' },
        enabled: true,
      };
      expect(ruleMatchesTool(rule, 'Bash')).toBe(true);
      expect(ruleMatchesTool(rule, 'Read')).toBe(true);
      expect(ruleMatchesTool(rule, 'mcp__anything')).toBe(true);
    });

    it('should not match disabled rules', () => {
      const rule: PermissionRule = {
        id: '1',
        name: 'Disabled',
        matchType: 'all',
        matchValue: '*',
        action: { type: 'auto-accept' },
        enabled: false,
      };
      expect(ruleMatchesTool(rule, 'Bash')).toBe(false);
    });
  });

  describe('findMatchingRule', () => {
    it('should find first matching rule', () => {
      const s: Settings = {
        rules: [
          {
            id: '1',
            name: 'Read',
            matchType: 'category',
            matchValue: 'read',
            action: { type: 'auto-accept' },
            enabled: true,
          },
          {
            id: '2',
            name: 'Catch all',
            matchType: 'all',
            matchValue: '*',
            action: { type: 'require-verify' },
            enabled: true,
          },
        ],
        projects: [],
      };
      const rule = findMatchingRule(s, 'Read', '/home/user');
      expect(rule?.id).toBe('1');
    });

    it('should fall back to catch-all rule', () => {
      const s: Settings = {
        rules: [
          {
            id: '1',
            name: 'Read',
            matchType: 'category',
            matchValue: 'read',
            action: { type: 'auto-accept' },
            enabled: true,
          },
          {
            id: '2',
            name: 'Catch all',
            matchType: 'all',
            matchValue: '*',
            action: { type: 'require-verify' },
            enabled: true,
          },
        ],
        projects: [],
      };
      const rule = findMatchingRule(s, 'Bash', '/home/user');
      expect(rule?.id).toBe('2');
    });

    it('should match project-specific rules first', () => {
      const s: Settings = {
        rules: [
          {
            id: '1',
            name: 'Global catch-all',
            matchType: 'all',
            matchValue: '*',
            action: { type: 'require-verify' },
            enabled: true,
          },
        ],
        projects: [
          {
            projectPath: '/home/user/myproject',
            rules: [
              {
                id: '2',
                name: 'Project auto-accept',
                matchType: 'all',
                matchValue: '*',
                action: { type: 'auto-accept' },
                enabled: true,
              },
            ],
          },
        ],
      };
      const rule = findMatchingRule(s, 'Bash', '/home/user/myproject/src');
      expect(rule?.id).toBe('2');
    });

    it('should fall back to global rules when no project matches', () => {
      const s: Settings = {
        rules: [
          {
            id: '1',
            name: 'Global catch-all',
            matchType: 'all',
            matchValue: '*',
            action: { type: 'require-verify' },
            enabled: true,
          },
        ],
        projects: [
          {
            projectPath: '/other/path',
            rules: [
              {
                id: '2',
                name: 'Project auto-accept',
                matchType: 'all',
                matchValue: '*',
                action: { type: 'auto-accept' },
                enabled: true,
              },
            ],
          },
        ],
      };
      const rule = findMatchingRule(s, 'Bash', '/home/user/different');
      expect(rule?.id).toBe('1');
    });
  });

  describe('getSessionColor', () => {
    it('should return consistent color for same session', () => {
      const color1 = getSessionColor('session-a');
      const color2 = getSessionColor('session-a');
      expect(color1).toBe(color2);
    });

    it('should return different colors for different sessions', () => {
      const color1 = getSessionColor('session-a');
      const color2 = getSessionColor('session-b');
      expect(color1).not.toBe(color2);
    });

    it('should return valid hex color', () => {
      const color = getSessionColor('test');
      expect(color).toMatch(/^#[0-9a-f]{6}$/i);
    });
  });
});
