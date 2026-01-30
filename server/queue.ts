import { randomUUID } from 'crypto';
import type { Decision, HookInput, PendingPrompt, Prompt, Settings, PermissionRule, RuleAction } from './types.js';
import { findMatchingRule, createDefaultRules } from './types.js';

export class PromptQueue {
  private prompts = new Map<string, PendingPrompt>();
  private settings: Settings = {
    rules: createDefaultRules(),
    projects: [],
  };
  private onPromptAdded?: (prompt: Prompt) => void;
  private onPromptResolved?: (id: string, autoAccepted: boolean) => void;

  setCallbacks(callbacks: {
    onPromptAdded?: (prompt: Prompt) => void;
    onPromptResolved?: (id: string, autoAccepted: boolean) => void;
  }) {
    this.onPromptAdded = callbacks.onPromptAdded;
    this.onPromptResolved = callbacks.onPromptResolved;
  }

  add(input: HookInput): Promise<Decision> {
    const id = randomUUID();

    // Find matching rule to determine auto-accept timing
    const rule = findMatchingRule(this.settings, input.tool_name, input.cwd);
    const action = rule?.action ?? { type: 'require-verify' };

    // Calculate auto-accept timing
    let autoAcceptIn: number | undefined;
    if (action.type === 'accept-after' && action.seconds > 0) {
      autoAcceptIn = action.seconds;
    }

    const prompt: Prompt = {
      id,
      sessionId: input.session_id,
      toolName: input.tool_name,
      toolInput: input.tool_input,
      hookEventName: input.hook_event_name,
      cwd: input.cwd,
      createdAt: Date.now(),
      autoAcceptIn,
    };

    return new Promise((resolve) => {
      const pending: PendingPrompt = { ...prompt, resolve };

      this.setupTimer(id, pending, action);

      this.prompts.set(id, pending);
      this.onPromptAdded?.(prompt);
    });
  }

  private setupTimer(_id: string, _pending: PendingPrompt, _action: RuleAction): void {
    // Timer is now handled client-side
    // Server just provides autoAcceptIn timing info
    // Clients run their own countdowns and resolve when ready
    // First client to resolve wins (race-safe)
  }

  resolve(id: string, decision: Decision, autoAccepted = false): boolean {
    const pending = this.prompts.get(id);
    if (!pending) return false;

    if (pending.timeoutId) {
      clearTimeout(pending.timeoutId);
    }

    this.prompts.delete(id);
    pending.resolve(decision);
    this.onPromptResolved?.(id, autoAccepted);
    return true;
  }

  pauseTimer(id: string): boolean {
    const pending = this.prompts.get(id);
    if (!pending) return false;

    if (pending.timeoutId) {
      clearTimeout(pending.timeoutId);
      pending.timeoutId = undefined;
    }

    return true;
  }

  get(id: string): Prompt | undefined {
    const pending = this.prompts.get(id);
    if (!pending) return undefined;
    const { resolve, timeoutId, ...prompt } = pending;
    return prompt;
  }

  list(): Prompt[] {
    return Array.from(this.prompts.values()).map(({ resolve, timeoutId, ...prompt }) => prompt);
  }

  getSettings(): Settings {
    return {
      rules: [...this.settings.rules],
      projects: this.settings.projects.map(p => ({
        ...p,
        rules: [...p.rules],
      })),
    };
  }

  updateSettings(partial: Partial<Settings>): Settings {
    if (partial.rules) {
      this.settings.rules = partial.rules;
    }
    if (partial.projects) {
      this.settings.projects = partial.projects;
    }

    // Re-evaluate timeouts for existing prompts with new rules
    for (const [id, pending] of this.prompts) {
      const rule = findMatchingRule(this.settings, pending.toolName, pending.cwd);
      const action = rule?.action ?? { type: 'require-verify' };
      this.setupTimer(id, pending, action);
    }

    return this.getSettings();
  }
}
