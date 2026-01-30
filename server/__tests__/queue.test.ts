import { describe, it, expect, beforeEach, vi } from 'vitest';
import { PromptQueue } from '../queue.js';
import type { HookInput, PermissionRule } from '../types.js';

describe('PromptQueue', () => {
  let queue: PromptQueue;

  beforeEach(() => {
    queue = new PromptQueue();
    vi.useFakeTimers();
  });

  const createInput = (overrides: Partial<HookInput> = {}): HookInput => ({
    session_id: 'test-session',
    tool_name: 'Bash',
    tool_input: { command: 'ls' },
    hook_event_name: 'PreToolUse',
    cwd: '/home/user',
    ...overrides,
  });

  const createRule = (overrides: Partial<PermissionRule> = {}): PermissionRule => ({
    id: crypto.randomUUID(),
    name: 'Test Rule',
    matchType: 'category',
    matchValue: 'execute',
    action: { type: 'accept-after', seconds: 5 },
    enabled: true,
    ...overrides,
  });

  it('should add prompt and return it in list', () => {
    const input = createInput();
    queue.add(input);
    const list = queue.list();
    expect(list).toHaveLength(1);
    expect(list[0].sessionId).toBe('test-session');
    expect(list[0].toolName).toBe('Bash');
  });

  it('should generate unique ids for prompts', () => {
    queue.add(createInput());
    queue.add(createInput());
    const list = queue.list();
    expect(list[0].id).not.toBe(list[1].id);
  });

  it('should get prompt by id', () => {
    queue.add(createInput());
    const list = queue.list();
    const prompt = queue.get(list[0].id);
    expect(prompt).toBeDefined();
    expect(prompt?.toolName).toBe('Bash');
  });

  it('should return undefined for unknown id', () => {
    expect(queue.get('unknown')).toBeUndefined();
  });

  it('should resolve prompt and remove from queue', async () => {
    const promise = queue.add(createInput());
    const list = queue.list();
    const id = list[0].id;

    const resolved = queue.resolve(id, { decision: 'allow' });
    expect(resolved).toBe(true);

    const result = await promise;
    expect(result.decision).toBe('allow');
    expect(queue.list()).toHaveLength(0);
  });

  it('should return false when resolving unknown prompt', () => {
    expect(queue.resolve('unknown', { decision: 'allow' })).toBe(false);
  });

  it('should handle multiple sessions independently', () => {
    queue.add(createInput({ session_id: 'session-a' }));
    queue.add(createInput({ session_id: 'session-b' }));
    const list = queue.list();
    expect(list.filter((p) => p.sessionId === 'session-a')).toHaveLength(1);
    expect(list.filter((p) => p.sessionId === 'session-b')).toHaveLength(1);
  });

  it('should auto-accept after timeout when rule matches', async () => {
    queue.updateSettings({
      rules: [createRule({ matchType: 'category', matchValue: 'execute', action: { type: 'accept-after', seconds: 5 } })],
      projects: [],
    });
    const promise = queue.add(createInput());

    vi.advanceTimersByTime(5000);

    const result = await promise;
    expect(result.decision).toBe('allow');
    expect(result.reason).toContain('Auto-accepted');
  });

  it('should not auto-accept when rule requires verification', async () => {
    queue.updateSettings({
      rules: [createRule({ matchType: 'category', matchValue: 'write', action: { type: 'require-verify' } })],
      projects: [],
    });
    const promise = queue.add(createInput({ tool_name: 'Edit' }));

    vi.advanceTimersByTime(10000);

    // Should still be pending
    expect(queue.list()).toHaveLength(1);

    // Manually resolve
    queue.resolve(queue.list()[0].id, { decision: 'allow' });
    const result = await promise;
    expect(result.decision).toBe('allow');
  });

  it('should auto-accept immediately when action is auto-accept', async () => {
    queue.updateSettings({
      rules: [createRule({ matchType: 'category', matchValue: 'read', action: { type: 'auto-accept' } })],
      projects: [],
    });
    const promise = queue.add(createInput({ tool_name: 'Read' }));

    // Should auto-accept on next tick
    vi.advanceTimersByTime(0);

    const result = await promise;
    expect(result.decision).toBe('allow');
    expect(result.reason).toContain('Auto-accepted');
  });

  it('should update timeout for existing prompts when settings change', async () => {
    queue.updateSettings({
      rules: [createRule({ matchType: 'category', matchValue: 'execute', action: { type: 'accept-after', seconds: 10 } })],
      projects: [],
    });
    const promise = queue.add(createInput());

    vi.advanceTimersByTime(3000);
    expect(queue.list()).toHaveLength(1);

    // Reduce timeout
    queue.updateSettings({
      rules: [createRule({ matchType: 'category', matchValue: 'execute', action: { type: 'accept-after', seconds: 2 } })],
      projects: [],
    });

    // Run the immediate setTimeout(0) that was scheduled
    vi.advanceTimersByTime(0);

    // Should auto-accept immediately since 3s > 2s
    const result = await promise;
    expect(result.decision).toBe('allow');
  });

  it('should match project-specific rules first', async () => {
    queue.updateSettings({
      rules: [createRule({ matchType: 'all', matchValue: '*', action: { type: 'require-verify' } })],
      projects: [{
        projectPath: '/home/user',
        rules: [createRule({ matchType: 'category', matchValue: 'execute', action: { type: 'accept-after', seconds: 3 } })],
      }],
    });
    const promise = queue.add(createInput({ cwd: '/home/user/project' }));

    vi.advanceTimersByTime(3000);

    const result = await promise;
    expect(result.decision).toBe('allow');
  });

  it('should fall back to global rules when no project matches', async () => {
    queue.updateSettings({
      rules: [createRule({ matchType: 'category', matchValue: 'execute', action: { type: 'accept-after', seconds: 5 } })],
      projects: [{
        projectPath: '/other/path',
        rules: [createRule({ matchType: 'all', matchValue: '*', action: { type: 'require-verify' } })],
      }],
    });
    const promise = queue.add(createInput({ cwd: '/home/user/project' }));

    vi.advanceTimersByTime(5000);

    const result = await promise;
    expect(result.decision).toBe('allow');
  });

  it('should call onPromptAdded callback', () => {
    const onPromptAdded = vi.fn();
    queue.setCallbacks({ onPromptAdded });
    queue.add(createInput());
    expect(onPromptAdded).toHaveBeenCalledOnce();
  });

  it('should call onPromptResolved callback', () => {
    const onPromptResolved = vi.fn();
    queue.setCallbacks({ onPromptResolved });
    queue.add(createInput());
    const id = queue.list()[0].id;
    queue.resolve(id, { decision: 'allow' });
    expect(onPromptResolved).toHaveBeenCalledWith(id, false);
  });

  it('should return default settings with rules', () => {
    const settings = queue.getSettings();
    expect(settings.rules).toBeDefined();
    expect(Array.isArray(settings.rules)).toBe(true);
    expect(settings.projects).toEqual([]);
  });

  it('should update and return new settings', () => {
    const newRules = [createRule()];
    const settings = queue.updateSettings({ rules: newRules });
    expect(settings.rules).toHaveLength(1);
  });

  it('should match by specific tool name', async () => {
    queue.updateSettings({
      rules: [
        createRule({ matchType: 'tool', matchValue: 'Bash', action: { type: 'accept-after', seconds: 2 } }),
        createRule({ matchType: 'all', matchValue: '*', action: { type: 'require-verify' } }),
      ],
      projects: [],
    });
    const promise = queue.add(createInput({ tool_name: 'Bash' }));

    vi.advanceTimersByTime(2000);

    const result = await promise;
    expect(result.decision).toBe('allow');
  });

  it('should match by pattern', async () => {
    queue.updateSettings({
      rules: [
        createRule({ matchType: 'pattern', matchValue: 'mcp__.*', action: { type: 'accept-after', seconds: 2 } }),
        createRule({ matchType: 'all', matchValue: '*', action: { type: 'require-verify' } }),
      ],
      projects: [],
    });
    const promise = queue.add(createInput({ tool_name: 'mcp__slack__send' }));

    vi.advanceTimersByTime(2000);

    const result = await promise;
    expect(result.decision).toBe('allow');
  });

  it('should skip disabled rules', async () => {
    queue.updateSettings({
      rules: [
        createRule({ matchType: 'category', matchValue: 'execute', action: { type: 'auto-accept' }, enabled: false }),
        createRule({ matchType: 'all', matchValue: '*', action: { type: 'require-verify' } }),
      ],
      projects: [],
    });
    queue.add(createInput());

    vi.advanceTimersByTime(10000);

    // Should still be pending because first rule is disabled
    expect(queue.list()).toHaveLength(1);
  });
});
