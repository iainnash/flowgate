import { randomUUID } from 'crypto';
import type { Decision, HookInput, PendingPrompt, Prompt, Settings, PermissionRule, RuleAction, PromptAcceptType } from './types.js';
import { findMatchingRule, createDefaultRules } from './types.js';

export class PromptQueue {
  private prompts = new Map<string, PendingPrompt>();
  private settings: Settings = {
    rules: createDefaultRules(),
    projects: [],
  };
  private onPromptAdded?: (prompt: Prompt) => void;
  private onPromptResolved?: (id: string, autoAccepted: boolean) => void;
  private _isPaused = false;
  private pausedAt: number | null = null;
  // Track remaining time when paused: Map<id, remainingMs>
  private pausedRemaining = new Map<string, number>();

  private onPromptUpdated?: (prompt: Prompt) => void;

  setCallbacks(callbacks: {
    onPromptAdded?: (prompt: Prompt) => void;
    onPromptResolved?: (id: string, autoAccepted: boolean) => void;
    onPromptUpdated?: (prompt: Prompt) => void;
  }) {
    this.onPromptAdded = callbacks.onPromptAdded;
    this.onPromptResolved = callbacks.onPromptResolved;
    this.onPromptUpdated = callbacks.onPromptUpdated;
  }

  add(input: HookInput): Promise<Decision> {
    const id = randomUUID();

    // Find matching rule to determine auto-accept timing
    const rule = findMatchingRule(this.settings, input.tool_name, input.cwd);
    const action = rule?.action ?? { type: 'require-verify' };

    // Determine acceptance type and timing
    const now = Date.now();
    let acceptType: PromptAcceptType;
    let autoAcceptIn: number | undefined;
    let autoAcceptAt: number | undefined;

    if (action.type === 'auto-accept') {
      acceptType = 'auto-accept';
      autoAcceptAt = now;  // Accept immediately
    } else if (action.type === 'accept-after' && action.seconds > 0) {
      acceptType = 'accept-after';
      autoAcceptIn = action.seconds;
      // Only set autoAcceptAt if not paused
      if (!this._isPaused) {
        autoAcceptAt = now + action.seconds * 1000;
      }
    } else {
      acceptType = 'manual';
    }

    const prompt: Prompt = {
      id,
      sessionId: input.session_id,
      toolName: input.tool_name,
      toolInput: input.tool_input,
      hookEventName: input.hook_event_name,
      cwd: input.cwd,
      createdAt: now,
      acceptType,
      autoAcceptIn,
      autoAcceptAt,
    };

    return new Promise((resolve) => {
      const pending: PendingPrompt = { ...prompt, resolve };

      this.setupTimer(id, pending, action);

      this.prompts.set(id, pending);
      this.onPromptAdded?.(prompt);
    });
  }

  private setupTimer(id: string, pending: PendingPrompt, action: RuleAction): void {
    // Clear existing timer
    if (pending.timeoutId) {
      clearTimeout(pending.timeoutId);
      pending.timeoutId = undefined;
    }

    // Handle immediate auto-accept
    if (action.type === 'auto-accept') {
      // Auto-accept on next tick (allows UI to briefly show the prompt)
      pending.timeoutId = setTimeout(() => {
        this.resolve(id, { decision: 'allow', reason: 'Auto-accepted immediately' }, true);
      }, 0);
      return;
    }

    // Only set up timer for accept-after rules
    if (action.type !== 'accept-after' || action.seconds <= 0) {
      return;
    }

    // Don't start timer if globally paused
    if (this._isPaused) {
      this.pausedRemaining.set(id, action.seconds * 1000);
      return;
    }

    const timeoutMs = action.seconds * 1000;
    pending.timeoutId = setTimeout(() => {
      // Auto-accept when timer expires
      this.resolve(id, { decision: 'allow', reason: 'Auto-accepted by timer' }, true);
    }, timeoutMs);
  }

  get isPaused(): boolean {
    return this._isPaused;
  }

  setPaused(paused: boolean): void {
    if (this._isPaused === paused) return;

    this._isPaused = paused;

    if (paused) {
      // Pausing: save remaining time for each prompt and clear timers
      this.pausedAt = Date.now();
      for (const [id, pending] of this.prompts) {
        if (pending.timeoutId) {
          // Calculate remaining time based on autoAcceptAt
          if (pending.autoAcceptAt) {
            const remaining = Math.max(0, pending.autoAcceptAt - Date.now());
            this.pausedRemaining.set(id, remaining);
            // Update autoAcceptIn to show remaining seconds
            pending.autoAcceptIn = Math.ceil(remaining / 1000);
          }
          clearTimeout(pending.timeoutId);
          pending.timeoutId = undefined;
        }
        // Clear autoAcceptAt when paused (clients will see undefined = paused)
        pending.autoAcceptAt = undefined;
        // Broadcast the updated prompt to all clients
        const { resolve, timeoutId, ...prompt } = pending;
        this.onPromptUpdated?.(prompt);
      }
    } else {
      // Resuming: restart timers with remaining time and update autoAcceptAt
      this.pausedAt = null;
      const now = Date.now();
      for (const [id, pending] of this.prompts) {
        const remaining = this.pausedRemaining.get(id);
        if (remaining !== undefined && remaining > 0) {
          // Update autoAcceptAt to new time
          pending.autoAcceptAt = now + remaining;
          pending.timeoutId = setTimeout(() => {
            this.resolve(id, { decision: 'allow', reason: 'Auto-accepted by timer' }, true);
          }, remaining);
          // Broadcast the updated prompt
          const { resolve, timeoutId, ...prompt } = pending;
          this.onPromptUpdated?.(prompt);
        }
        this.pausedRemaining.delete(id);
      }
    }
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
