<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import { get } from 'svelte/store';
  import { settings, updateSettings, TOOL_CATEGORIES } from './stores';
  import type { Settings, Rule, RuleAction, ToolCategory } from './types';

  export let open: boolean = false;

  const dispatch = createEventDispatcher<{ close: void }>();

  // Local state for editing
  let localRules: Rule[] = [];
  let editingRule: Rule | null = null;
  let showRuleEditor = false;

  // Rule editor state
  let editName = '';
  let editToolName = '';
  let editCategory: ToolCategory | '' = '';
  let editPattern = '';
  let editActionType: 'manual' | 'auto-accept' | 'accept-after' = 'manual';
  let editActionSeconds = 5;
  let editEnabled = true;

  // Categories for dropdown
  const categories: (ToolCategory | '')[] = ['', 'read', 'write', 'execute', 'task', 'web', 'interactive', 'mcp', 'other'];

  // Known tools from TOOL_CATEGORIES
  const knownTools = [
    '',
    ...Array.from(TOOL_CATEGORIES.read),
    ...Array.from(TOOL_CATEGORIES.write),
    ...Array.from(TOOL_CATEGORIES.execute),
    ...Array.from(TOOL_CATEGORIES.task),
    ...Array.from(TOOL_CATEGORIES.web),
    ...Array.from(TOOL_CATEGORIES.interactive),
  ].sort();

  // Load current settings when dialog opens
  let wasOpen = false;
  $: {
    if (open && !wasOpen) {
      const current = get(settings);
      localRules = current.rules.map(r => ({ ...r }));
      editingRule = null;
      showRuleEditor = false;
    }
    wasOpen = open;
  }

  function close() {
    open = false;
    dispatch('close');
  }

  function addNewRule(): void {
    const newRule: Rule = {
      name: 'New Rule',
      toolName: '',
      category: undefined,
      pattern: undefined,
      action: { type: 'manual' },
      enabled: true,
      matchCount: 0,
    };
    localRules = [...localRules, newRule];
    startEditRule(newRule);
  }

  function startEditRule(rule: Rule): void {
    editingRule = rule;
    editName = rule.name;
    editToolName = rule.toolName || '';
    editCategory = (rule.category as ToolCategory) || '';
    editPattern = rule.pattern || '';
    editEnabled = rule.enabled;

    if (rule.action.type === 'auto-accept') {
      editActionType = 'auto-accept';
      editActionSeconds = 0;
    } else if (rule.action.type === 'accept-after') {
      editActionType = 'accept-after';
      editActionSeconds = rule.action.seconds || 5;
    } else {
      editActionType = 'manual';
      editActionSeconds = 5;
    }

    showRuleEditor = true;
  }

  function saveRule(): void {
    if (!editingRule) return;

    let action: RuleAction;
    if (editActionType === 'auto-accept') {
      action = { type: 'auto-accept' };
    } else if (editActionType === 'accept-after') {
      action = { type: 'accept-after', seconds: editActionSeconds };
    } else {
      action = { type: 'manual' };
    }

    const updatedRule: Rule = {
      ...editingRule,
      name: editName,
      toolName: editToolName || '',
      category: editCategory || undefined,
      pattern: editPattern || undefined,
      action,
      enabled: editEnabled,
    };

    const index = localRules.findIndex(r => r.name === editingRule.name);
    if (index !== -1) {
      localRules = [...localRules.slice(0, index), updatedRule, ...localRules.slice(index + 1)];
    }

    cancelEdit();
  }

  function cancelEdit(): void {
    editingRule = null;
    showRuleEditor = false;
  }

  function deleteRule(name: string): void {
    localRules = localRules.filter(r => r.name !== name);
    if (editingRule?.name === name) {
      cancelEdit();
    }
  }

  function moveRule(name: string, direction: 'up' | 'down'): void {
    const idx = localRules.findIndex(r => r.name === name);
    if (idx === -1) return;

    if (direction === 'up' && idx > 0) {
      const newRules = [...localRules];
      const temp = newRules[idx - 1];
      newRules[idx - 1] = newRules[idx];
      newRules[idx] = temp;
      localRules = newRules;
    } else if (direction === 'down' && idx < localRules.length - 1) {
      const newRules = [...localRules];
      const temp = newRules[idx];
      newRules[idx] = newRules[idx + 1];
      newRules[idx + 1] = temp;
      localRules = newRules;
    }
  }

  function toggleRule(name: string): void {
    localRules = localRules.map(r =>
      r.name === name ? { ...r, enabled: !r.enabled } : r
    );
  }

  function saveSettings(): void {
    const newSettings: Settings = {
      ...$settings,
      rules: localRules,
    };
    updateSettings(newSettings);
    settings.set(newSettings);
  }

  function getCategoryColor(category?: string): string {
    switch (category) {
      case 'read': return '#22c55e';
      case 'write': return '#ef4444';
      case 'execute': return '#f59e0b';
      case 'task': return '#a855f7';
      case 'web': return '#3b82f6';
      case 'interactive': return '#8b5cf6';
      case 'mcp': return '#06b6d4';
      case 'other': return '#6b7280';
      default: return '#888';
    }
  }

  function getActionLabel(action: RuleAction): string {
    if (action.type === 'auto-accept') return 'Auto-accept';
    if (action.type === 'accept-after') return `Accept after ${action.seconds}s`;
    return 'Manual';
  }
</script>

{#if open}
  <div class="settings-overlay" on:click={close} role="presentation">
    <div class="settings-dialog" on:click|stopPropagation role="dialog" aria-label="Settings">
      <div class="settings-header">
        <h2>Rules Configuration</h2>
        <button class="close-btn" on:click={close} aria-label="Close">×</button>
      </div>

      <div class="settings-content">
        <!-- Rule editor panel -->
        {#if showRuleEditor && editingRule}
          <div class="rule-editor">
            <h3>Edit Rule</h3>

            <div class="form-grid">
              <div class="form-group">
                <label for="rule-name">Rule Name</label>
                <input
                  id="rule-name"
                  type="text"
                  bind:value={editName}
                  placeholder="e.g., Auto-accept Read operations"
                />
              </div>

              <div class="form-group">
                <label for="rule-enabled">
                  <input id="rule-enabled" type="checkbox" bind:checked={editEnabled} />
                  Enabled
                </label>
              </div>
            </div>

            <div class="form-section">
              <h4>Match Conditions</h4>
              <p class="hint">Rules match if ANY condition is met (toolName OR category OR pattern)</p>

              <div class="form-group">
                <label for="rule-tool">Specific Tool</label>
                <select id="rule-tool" bind:value={editToolName}>
                  {#each knownTools as tool}
                    <option value={tool}>{tool || '(any tool)'}</option>
                  {/each}
                </select>
                <span class="field-hint">Match a specific tool like "Bash" or "Edit"</span>
              </div>

              <div class="form-group">
                <label for="rule-category">Tool Category</label>
                <select id="rule-category" bind:value={editCategory}>
                  {#each categories as cat}
                    <option value={cat}>{cat || '(any category)'}</option>
                  {/each}
                </select>
                <span class="field-hint">Match all tools in a category like "read" or "write"</span>
              </div>

              <div class="form-group">
                <label for="rule-pattern">Pattern (regex, advanced)</label>
                <input
                  id="rule-pattern"
                  type="text"
                  bind:value={editPattern}
                  placeholder="e.g., ^npm (install|test)"
                />
                <span class="field-hint">Regular expression matched against tool input (Bash commands, file paths, etc.)</span>
              </div>
            </div>

            <div class="form-section">
              <h4>Action</h4>

              <div class="form-group">
                <label>
                  <input type="radio" bind:group={editActionType} value="manual" />
                  Manual - Always require user approval
                </label>
              </div>

              <div class="form-group">
                <label>
                  <input type="radio" bind:group={editActionType} value="auto-accept" />
                  Auto-accept - Accept immediately without delay
                </label>
              </div>

              <div class="form-group">
                <label>
                  <input type="radio" bind:group={editActionType} value="accept-after" />
                  Accept after delay
                </label>
                {#if editActionType === 'accept-after'}
                  <div class="inline-input">
                    <input
                      type="number"
                      bind:value={editActionSeconds}
                      min="1"
                      max="60"
                      style="width: 80px;"
                    />
                    <span>seconds</span>
                  </div>
                {/if}
              </div>
            </div>

            <div class="editor-actions">
              <button class="btn-secondary" on:click={cancelEdit}>Cancel</button>
              <button class="btn-primary" on:click={saveRule}>Save Rule</button>
            </div>
          </div>
        {:else}
          <!-- Rules list -->
          <div class="rules-section">
            <div class="section-header">
              <h3>Rules ({localRules.length})</h3>
              <button class="btn-add" on:click={addNewRule}>
                <span>+</span> Add Rule
              </button>
            </div>

            <p class="info-box">
              Rules are evaluated in order. The first matching rule determines how a prompt is handled.
              You can drag rules to reorder them.
            </p>

            {#if localRules.length === 0}
              <div class="empty-state">
                <p>No rules configured</p>
                <p class="hint">Add a rule to auto-accept or customize prompt handling</p>
              </div>
            {:else}
              <div class="rules-list">
                {#each localRules as rule, idx (rule.name)}
                  <div class="rule-card" class:disabled={!rule.enabled}>
                    <div class="rule-main">
                      <div class="rule-info">
                        <div class="rule-header-line">
                          <span class="rule-name">{rule.name}</span>
                          {#if !rule.enabled}
                            <span class="rule-badge disabled">Disabled</span>
                          {/if}
                          <span class="rule-badge" style="background: {getCategoryColor(rule.category)}">
                            {getActionLabel(rule.action)}
                          </span>
                        </div>

                        <div class="rule-details">
                          {#if rule.toolName}
                            <div class="rule-detail">
                              <span class="label">Tool:</span>
                              <code>{rule.toolName}</code>
                            </div>
                          {/if}
                          {#if rule.category}
                            <div class="rule-detail">
                              <span class="label">Category:</span>
                              <span class="category-badge" style="background: {getCategoryColor(rule.category)}">
                                {rule.category}
                              </span>
                            </div>
                          {/if}
                          {#if rule.pattern}
                            <div class="rule-detail">
                              <span class="label">Pattern:</span>
                              <code class="pattern">{rule.pattern}</code>
                            </div>
                          {/if}
                          <div class="rule-detail">
                            <span class="label">Matched:</span>
                            <span>{rule.matchCount} times</span>
                          </div>
                        </div>
                      </div>

                      <div class="rule-actions">
                        <button
                          class="icon-btn"
                          on:click={() => toggleRule(rule.name)}
                          title={rule.enabled ? 'Disable' : 'Enable'}
                        >
                          {rule.enabled ? '◉' : '○'}
                        </button>
                        <button
                          class="icon-btn"
                          on:click={() => moveRule(rule.name, 'up')}
                          disabled={idx === 0}
                          title="Move up"
                        >
                          ↑
                        </button>
                        <button
                          class="icon-btn"
                          on:click={() => moveRule(rule.name, 'down')}
                          disabled={idx === localRules.length - 1}
                          title="Move down"
                        >
                          ↓
                        </button>
                        <button
                          class="icon-btn"
                          on:click={() => startEditRule(rule)}
                          title="Edit"
                        >
                          ✎
                        </button>
                        <button
                          class="icon-btn danger"
                          on:click={() => deleteRule(rule.name)}
                          title="Delete"
                        >
                          ✕
                        </button>
                      </div>
                    </div>
                  </div>
                {/each}
              </div>
            {/if}
          </div>

          <!-- Native settings -->
          <div class="native-section">
            <h3>Native App Settings</h3>
            <div class="native-settings">
              <label>
                <input type="checkbox" checked={$settings.native.showAutoAccept} disabled />
                Show auto-accept prompts
              </label>
              <label>
                <input type="checkbox" checked={$settings.native.enableAnimations} disabled />
                Enable animations
              </label>
            </div>
            <p class="hint">Native settings can only be changed from the native app</p>
          </div>

          <!-- Save button -->
          <div class="save-section">
            <button class="btn-save" on:click={saveSettings}>
              Save Changes
            </button>
            <p class="hint">Changes are saved to the server and applied immediately</p>
          </div>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .settings-overlay {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0, 0, 0, 0.75);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    animation: fadeIn 0.2s ease-out;
  }

  @keyframes fadeIn {
    from {
      opacity: 0;
    }
    to {
      opacity: 1;
    }
  }

  .settings-dialog {
    background: var(--bg-secondary, #2a2a3e);
    border-radius: 16px;
    max-width: 900px;
    max-height: 90vh;
    width: 90%;
    display: flex;
    flex-direction: column;
    box-shadow: 0 25px 70px rgba(0, 0, 0, 0.4);
    animation: slideUp 0.3s ease-out;
  }

  @keyframes slideUp {
    from {
      transform: translateY(20px);
      opacity: 0;
    }
    to {
      transform: translateY(0);
      opacity: 1;
    }
  }

  .settings-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 24px 28px;
    border-bottom: 1px solid var(--border-color, #333);
  }

  .settings-header h2 {
    margin: 0;
    font-size: 24px;
    font-weight: 600;
    color: var(--text-primary, #fff);
  }

  .close-btn {
    background: none;
    border: none;
    font-size: 32px;
    line-height: 1;
    color: var(--text-secondary, #888);
    cursor: pointer;
    padding: 0;
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 6px;
    transition: all 0.15s;
  }

  .close-btn:hover {
    background: var(--hover-bg, #333);
    color: var(--text-primary, #fff);
  }

  .settings-content {
    padding: 24px 28px;
    overflow-y: auto;
  }

  .info-box {
    background: var(--bg-tertiary, #1a1a2e);
    padding: 12px 16px;
    border-radius: 8px;
    margin-bottom: 20px;
    color: var(--text-secondary, #aaa);
    font-size: 14px;
    border-left: 3px solid var(--accent-color, #3b82f6);
  }

  /* Rule Editor */
  .rule-editor {
    background: var(--bg-tertiary, #1a1a2e);
    border-radius: 12px;
    padding: 24px;
    margin-bottom: 20px;
  }

  .rule-editor h3 {
    margin: 0 0 20px 0;
    font-size: 20px;
    color: var(--text-primary, #fff);
  }

  .form-grid {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 16px;
    align-items: end;
    margin-bottom: 24px;
  }

  .form-section {
    margin-bottom: 24px;
    padding-bottom: 24px;
    border-bottom: 1px solid var(--border-color, #333);
  }

  .form-section:last-of-type {
    border-bottom: none;
  }

  .form-section h4 {
    margin: 0 0 8px 0;
    font-size: 16px;
    font-weight: 600;
    color: var(--text-primary, #fff);
  }

  .form-section .hint {
    font-size: 13px;
    color: var(--text-muted, #666);
    margin-bottom: 16px;
  }

  .form-group {
    margin-bottom: 16px;
  }

  .form-group:last-child {
    margin-bottom: 0;
  }

  .form-group label {
    display: block;
    font-size: 14px;
    font-weight: 500;
    color: var(--text-secondary, #ccc);
    margin-bottom: 6px;
  }

  .form-group input[type="checkbox"] {
    margin-right: 8px;
  }

  .form-group input[type="text"],
  .form-group input[type="number"],
  .form-group select {
    width: 100%;
    padding: 10px 12px;
    background: var(--input-bg, #1a1a2e);
    border: 1px solid var(--input-border, #444);
    border-radius: 6px;
    color: var(--text-primary, #fff);
    font-size: 14px;
    transition: border-color 0.15s;
  }

  .form-group input[type="text"]:focus,
  .form-group input[type="number"]:focus,
  .form-group select:focus {
    outline: none;
    border-color: var(--accent-color, #3b82f6);
  }

  .field-hint {
    display: block;
    font-size: 12px;
    color: var(--text-muted, #666);
    margin-top: 4px;
  }

  .inline-input {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 8px;
    margin-left: 24px;
  }

  .editor-actions {
    display: flex;
    gap: 12px;
    justify-content: flex-end;
    margin-top: 24px;
    padding-top: 24px;
    border-top: 1px solid var(--border-color, #333);
  }

  /* Rules List */
  .rules-section {
    margin-bottom: 32px;
  }

  .section-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 16px;
  }

  .section-header h3 {
    margin: 0;
    font-size: 20px;
    font-weight: 600;
    color: var(--text-primary, #fff);
  }

  .btn-add {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 8px 16px;
    background: var(--accent-color, #3b82f6);
    color: white;
    border: none;
    border-radius: 6px;
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    transition: opacity 0.15s;
  }

  .btn-add:hover {
    opacity: 0.9;
  }

  .btn-add span {
    font-size: 18px;
    font-weight: 700;
  }

  .empty-state {
    text-align: center;
    padding: 60px 20px;
    color: var(--text-secondary, #888);
  }

  .empty-state p {
    margin: 0;
  }

  .empty-state .hint {
    font-size: 14px;
    margin-top: 8px;
    color: var(--text-muted, #666);
  }

  .rules-list {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .rule-card {
    background: var(--bg-tertiary, #1a1a2e);
    border: 1px solid var(--border-color, #333);
    border-radius: 10px;
    padding: 16px;
    transition: all 0.15s;
  }

  .rule-card:hover {
    border-color: var(--accent-color, #3b82f6);
  }

  .rule-card.disabled {
    opacity: 0.5;
  }

  .rule-main {
    display: flex;
    justify-content: space-between;
    gap: 16px;
  }

  .rule-info {
    flex: 1;
  }

  .rule-header-line {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-bottom: 12px;
  }

  .rule-name {
    font-weight: 600;
    font-size: 16px;
    color: var(--text-primary, #fff);
  }

  .rule-badge {
    font-size: 11px;
    padding: 3px 8px;
    border-radius: 4px;
    color: white;
    font-weight: 600;
  }

  .rule-badge.disabled {
    background: #6b7280;
  }

  .rule-details {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .rule-detail {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 14px;
  }

  .rule-detail .label {
    color: var(--text-muted, #666);
    min-width: 70px;
  }

  .rule-detail code {
    background: var(--input-bg, #0f0f1a);
    padding: 2px 6px;
    border-radius: 4px;
    font-family: 'SF Mono', 'Monaco', 'Cascadia Code', monospace;
    font-size: 13px;
    color: var(--accent-color, #3b82f6);
  }

  .rule-detail code.pattern {
    color: #f59e0b;
  }

  .category-badge {
    padding: 2px 8px;
    border-radius: 4px;
    font-size: 12px;
    color: white;
    font-weight: 500;
  }

  .rule-actions {
    display: flex;
    gap: 4px;
  }

  .icon-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    background: transparent;
    border: 1px solid var(--border-color, #444);
    border-radius: 6px;
    color: var(--text-secondary, #888);
    cursor: pointer;
    font-size: 14px;
    transition: all 0.15s;
  }

  .icon-btn:hover:not(:disabled) {
    background: var(--hover-bg, #333);
    border-color: var(--accent-color, #3b82f6);
    color: var(--text-primary, #fff);
  }

  .icon-btn:disabled {
    opacity: 0.3;
    cursor: not-allowed;
  }

  .icon-btn.danger:hover {
    border-color: #ef4444;
    color: #ef4444;
  }

  /* Native settings */
  .native-section {
    margin-bottom: 32px;
  }

  .native-section h3 {
    margin: 0 0 16px 0;
    font-size: 18px;
    font-weight: 600;
    color: var(--text-primary, #fff);
  }

  .native-settings {
    display: flex;
    flex-direction: column;
    gap: 12px;
    margin-bottom: 12px;
  }

  .native-settings label {
    display: flex;
    align-items: center;
    gap: 8px;
    color: var(--text-secondary, #ccc);
    cursor: not-allowed;
  }

  .native-settings input[type="checkbox"] {
    cursor: not-allowed;
  }

  .hint {
    font-size: 13px;
    color: var(--text-muted, #666);
  }

  /* Buttons */
  .save-section {
    padding-top: 24px;
    border-top: 1px solid var(--border-color, #333);
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 8px;
  }

  .btn-primary,
  .btn-secondary,
  .btn-save {
    padding: 10px 24px;
    border-radius: 6px;
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    transition: opacity 0.15s;
    border: none;
  }

  .btn-primary {
    background: var(--accent-color, #3b82f6);
    color: white;
  }

  .btn-secondary {
    background: transparent;
    color: var(--text-secondary, #ccc);
    border: 1px solid var(--border-color, #444);
  }

  .btn-save {
    background: #22c55e;
    color: white;
    font-size: 16px;
    padding: 12px 32px;
  }

  .btn-primary:hover,
  .btn-secondary:hover,
  .btn-save:hover {
    opacity: 0.9;
  }
</style>
