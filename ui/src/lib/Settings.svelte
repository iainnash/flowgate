<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import { get } from 'svelte/store';
  import { settings, saveSettings, TOOL_CATEGORIES, getToolCategory } from './stores';
  import type { Settings, PermissionRule, RuleMatchType, RuleAction, ToolCategory, ProjectConfig } from './types';

  export let open: boolean = false;

  const dispatch = createEventDispatcher<{ close: void }>();

  // Local state
  let localRules: PermissionRule[] = [];
  let localProjects: ProjectConfig[] = [];
  let activeTab: 'global' | string = 'global';
  let editingRule: PermissionRule | null = null;
  let editingProjectPath: string = '';
  let showNewProjectDialog = false;
  let newProjectPath = '';

  // Rule editor state
  let editName = '';
  let editMatchType: RuleMatchType = 'category';
  let editMatchValue = '';
  let editActionType: 'auto-accept' | 'accept-after' | 'require-verify' = 'require-verify';
  let editActionSeconds = 10;
  let editEnabled = true;

  // Categories for dropdown
  const categories: ToolCategory[] = ['read', 'write', 'execute', 'web', 'mcp', 'interactive', 'other'];
  const categoryColors: Record<ToolCategory, string> = {
    read: '#22c55e',
    write: '#ef4444',
    execute: '#f59e0b',
    web: '#3b82f6',
    interactive: '#8b5cf6',
    mcp: '#06b6d4',
    other: '#6b7280',
  };

  // Known tools for dropdown
  const knownTools = [
    ...Array.from(TOOL_CATEGORIES.read),
    ...Array.from(TOOL_CATEGORIES.write),
    ...Array.from(TOOL_CATEGORIES.execute),
    ...Array.from(TOOL_CATEGORIES.web),
    ...Array.from(TOOL_CATEGORIES.interactive),
  ].sort();

  // Reset when dialog opens
  let wasOpen = false;
  $: {
    if (open && !wasOpen) {
      const current = get(settings);
      localRules = current.rules.map(r => ({ ...r }));
      localProjects = current.projects.map(p => ({
        ...p,
        rules: p.rules.map(r => ({ ...r })),
      }));
      activeTab = 'global';
      editingRule = null;
      showNewProjectDialog = false;
    }
    wasOpen = open;
  }

  function getCurrentRules(): PermissionRule[] {
    if (activeTab === 'global') {
      return localRules;
    }
    const project = localProjects.find(p => p.projectPath === activeTab);
    return project?.rules ?? [];
  }

  function setCurrentRules(rules: PermissionRule[]): void {
    if (activeTab === 'global') {
      localRules = rules;
    } else {
      localProjects = localProjects.map(p =>
        p.projectPath === activeTab ? { ...p, rules } : p
      );
    }
  }

  function startEditRule(rule: PermissionRule): void {
    editingRule = rule;
    editName = rule.name;
    editMatchType = rule.matchType;
    editMatchValue = rule.matchValue;
    editEnabled = rule.enabled;
    if (rule.action.type === 'auto-accept') {
      editActionType = 'auto-accept';
      editActionSeconds = 0;
    } else if (rule.action.type === 'accept-after') {
      editActionType = 'accept-after';
      editActionSeconds = rule.action.seconds;
    } else {
      editActionType = 'require-verify';
      editActionSeconds = 10;
    }
  }

  function addNewRule(): void {
    const newRule: PermissionRule = {
      id: crypto.randomUUID(),
      name: 'New Rule',
      matchType: 'category',
      matchValue: 'read',
      action: { type: 'require-verify' },
      enabled: true,
    };
    const rules = getCurrentRules();
    // Insert before the last catch-all rule if there is one
    const lastRule = rules[rules.length - 1];
    if (lastRule?.matchType === 'all') {
      setCurrentRules([...rules.slice(0, -1), newRule, lastRule]);
    } else {
      setCurrentRules([...rules, newRule]);
    }
    startEditRule(newRule);
  }

  function saveRule(): void {
    if (!editingRule) return;

    let action: RuleAction;
    if (editActionType === 'auto-accept') {
      action = { type: 'auto-accept' };
    } else if (editActionType === 'accept-after') {
      action = { type: 'accept-after', seconds: editActionSeconds };
    } else {
      action = { type: 'require-verify' };
    }

    // Set matchValue to '*' for 'all' match type
    const matchValue = editMatchType === 'all' ? '*' : editMatchValue;

    const updatedRule: PermissionRule = {
      ...editingRule,
      name: editName,
      matchType: editMatchType,
      matchValue,
      action,
      enabled: editEnabled,
    };

    const rules = getCurrentRules();
    setCurrentRules(rules.map(r => r.id === editingRule!.id ? updatedRule : r));
    editingRule = null;
  }

  function deleteRule(id: string): void {
    const rules = getCurrentRules();
    setCurrentRules(rules.filter(r => r.id !== id));
    if (editingRule?.id === id) {
      editingRule = null;
    }
  }

  function moveRule(id: string, direction: 'up' | 'down'): void {
    const rules = getCurrentRules();
    const idx = rules.findIndex(r => r.id === id);
    if (idx === -1) return;
    if (direction === 'up' && idx > 0) {
      const newRules = [...rules];
      const temp = newRules[idx - 1];
      newRules[idx - 1] = newRules[idx];
      newRules[idx] = temp;
      setCurrentRules(newRules);
    } else if (direction === 'down' && idx < rules.length - 1) {
      const newRules = [...rules];
      const temp = newRules[idx];
      newRules[idx] = newRules[idx + 1];
      newRules[idx + 1] = temp;
      setCurrentRules(newRules);
    }
  }

  function toggleRule(id: string): void {
    const rules = getCurrentRules();
    setCurrentRules(rules.map(r => r.id === id ? { ...r, enabled: !r.enabled } : r));
  }

  function addProject(): void {
    if (!newProjectPath.trim()) return;
    const path = newProjectPath.trim();
    if (localProjects.some(p => p.projectPath === path)) return;

    localProjects = [...localProjects, { projectPath: path, rules: [] }];
    activeTab = path;
    showNewProjectDialog = false;
    newProjectPath = '';
  }

  function removeProject(path: string): void {
    localProjects = localProjects.filter(p => p.projectPath !== path);
    if (activeTab === path) {
      activeTab = 'global';
    }
  }

  async function handleSave() {
    const newSettings: Settings = {
      rules: localRules,
      projects: localProjects,
    };
    settings.set(newSettings);
    try {
      await saveSettings(newSettings);
    } catch (e) {
      console.error('Failed to save settings:', e);
    }
    dispatch('close');
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      if (editingRule) {
        editingRule = null;
      } else if (showNewProjectDialog) {
        showNewProjectDialog = false;
      } else {
        dispatch('close');
      }
    }
  }

  function getActionLabel(action: RuleAction): string {
    if (action.type === 'auto-accept') return 'Auto-accept';
    if (action.type === 'accept-after') return `Accept after ${action.seconds}s`;
    return 'Require verify';
  }

  function getMatchLabel(rule: PermissionRule): string {
    switch (rule.matchType) {
      case 'all': return 'All tools';
      case 'category': return `Category: ${rule.matchValue}`;
      case 'tool': return `Tool: ${rule.matchValue}`;
      case 'pattern': return `Pattern: ${rule.matchValue}`;
      default: return rule.matchValue;
    }
  }
</script>

<svelte:window on:keydown={handleKeydown} />

{#if open}
  <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-noninteractive-element-interactions -->
  <div class="overlay" on:click={() => dispatch('close')} role="presentation">
    <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-noninteractive-element-interactions -->
    <div class="modal" on:click|stopPropagation role="dialog" aria-modal="true">
      <h3>Permission Rules</h3>
      <p class="description">Rules are evaluated top-to-bottom. First matching rule wins.</p>

      <!-- Tabs -->
      <div class="tabs">
        <button
          class="tab"
          class:active={activeTab === 'global'}
          on:click={() => { activeTab = 'global'; editingRule = null; }}
        >
          Global
        </button>
        {#each localProjects as project}
          <button
            class="tab project-tab"
            class:active={activeTab === project.projectPath}
            on:click={() => { activeTab = project.projectPath; editingRule = null; }}
          >
            <span class="project-name">{project.projectPath.split('/').pop()}</span>
            <button
              class="remove-project"
              on:click|stopPropagation={() => removeProject(project.projectPath)}
              title="Remove project"
            >×</button>
          </button>
        {/each}
        <button class="tab add-tab" on:click={() => { showNewProjectDialog = true; }}>
          + Project
        </button>
      </div>

      {#if showNewProjectDialog}
        <div class="new-project-dialog">
          <input
            type="text"
            placeholder="/path/to/project"
            bind:value={newProjectPath}
            on:keydown={(e) => e.key === 'Enter' && addProject()}
          />
          <button class="btn small" on:click={addProject}>Add</button>
          <button class="btn small cancel" on:click={() => { showNewProjectDialog = false; newProjectPath = ''; }}>Cancel</button>
        </div>
      {/if}

      <!-- Rules List -->
      <div class="rules-list">
        {#each getCurrentRules() as rule, idx (rule.id)}
          <div class="rule-item" class:disabled={!rule.enabled} class:editing={editingRule?.id === rule.id}>
            <div class="rule-controls">
              <button
                class="move-btn"
                disabled={idx === 0}
                on:click={() => moveRule(rule.id, 'up')}
                title="Move up"
              >↑</button>
              <button
                class="move-btn"
                disabled={idx === getCurrentRules().length - 1}
                on:click={() => moveRule(rule.id, 'down')}
                title="Move down"
              >↓</button>
            </div>
            <div class="rule-content" on:click={() => startEditRule(rule)} role="button" tabindex="0" on:keydown={(e) => e.key === 'Enter' && startEditRule(rule)}>
              <div class="rule-header">
                <span class="rule-name">{rule.name}</span>
                <span class="rule-action" class:auto={rule.action.type !== 'require-verify'}>
                  {getActionLabel(rule.action)}
                </span>
              </div>
              <div class="rule-match">{getMatchLabel(rule)}</div>
            </div>
            <div class="rule-actions">
              <label class="toggle">
                <input type="checkbox" checked={rule.enabled} on:change={() => toggleRule(rule.id)} />
                <span class="toggle-slider"></span>
              </label>
              <button class="delete-btn" on:click={() => deleteRule(rule.id)} title="Delete rule">×</button>
            </div>
          </div>
        {/each}

        {#if getCurrentRules().length === 0}
          <div class="empty-rules">No rules configured. Add a rule to get started.</div>
        {/if}
      </div>

      <button class="add-rule-btn" on:click={addNewRule}>+ Add Rule</button>

      <!-- Rule Editor -->
      {#if editingRule}
        <div class="rule-editor">
          <h4>Edit Rule</h4>

          <div class="form-row">
            <label>Name</label>
            <input type="text" bind:value={editName} placeholder="Rule name" />
          </div>

          <div class="form-row">
            <label>Match Type</label>
            <select bind:value={editMatchType}>
              <option value="category">Category</option>
              <option value="tool">Specific Tool</option>
              <option value="pattern">Pattern (regex)</option>
              <option value="all">All Tools</option>
            </select>
          </div>

          {#if editMatchType === 'category'}
            <div class="form-row">
              <label>Category</label>
              <select bind:value={editMatchValue}>
                {#each categories as cat}
                  <option value={cat}>{cat}</option>
                {/each}
              </select>
            </div>
          {:else if editMatchType === 'tool'}
            <div class="form-row">
              <label>Tool</label>
              <select bind:value={editMatchValue}>
                {#each knownTools as tool}
                  <option value={tool}>{tool}</option>
                {/each}
              </select>
            </div>
          {:else if editMatchType === 'pattern'}
            <div class="form-row">
              <label>Pattern</label>
              <input type="text" bind:value={editMatchValue} placeholder="e.g., mcp__slack.*" />
            </div>
          {:else if editMatchType === 'all'}
            <div class="form-row">
              <label>Match Value</label>
              <input type="text" value="*" disabled />
            </div>
          {/if}

          <div class="form-row">
            <label>Action</label>
            <select bind:value={editActionType}>
              <option value="auto-accept">Auto-accept (immediately)</option>
              <option value="accept-after">Accept after delay</option>
              <option value="require-verify">Always require verification</option>
            </select>
          </div>

          {#if editActionType === 'accept-after'}
            <div class="form-row">
              <label>Delay (seconds)</label>
              <input type="number" bind:value={editActionSeconds} min="1" max="120" />
            </div>
          {/if}

          <div class="editor-actions">
            <button class="btn cancel" on:click={() => { editingRule = null; }}>Cancel</button>
            <button class="btn save" on:click={saveRule}>Apply</button>
          </div>
        </div>
      {/if}

      <div class="actions">
        <button class="btn cancel" on:click={() => dispatch('close')}>
          Cancel
        </button>
        <button class="btn save" on:click={handleSave}>
          Save All
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.6);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
  }

  .modal {
    background: var(--card-bg, #2a2a3e);
    border-radius: 12px;
    padding: 20px;
    width: 90%;
    max-width: 600px;
    max-height: 90vh;
    overflow-y: auto;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
  }

  h3 {
    margin: 0 0 4px;
    font-size: 18px;
    color: var(--text-primary, #eee);
  }

  h4 {
    margin: 0 0 12px;
    font-size: 14px;
    color: var(--text-secondary, #ccc);
  }

  .description {
    margin: 0 0 16px;
    font-size: 12px;
    color: var(--text-muted, #888);
  }

  /* Tabs */
  .tabs {
    display: flex;
    gap: 4px;
    margin-bottom: 16px;
    flex-wrap: wrap;
  }

  .tab {
    padding: 6px 12px;
    border: none;
    border-radius: 6px;
    background: var(--input-bg, #1a1a2e);
    color: var(--text-muted, #888);
    font-size: 12px;
    cursor: pointer;
    transition: all 0.15s;
  }

  .tab:hover {
    background: var(--hover-bg, #333);
    color: var(--text-secondary, #ccc);
  }

  .tab.active {
    background: var(--accent-color, #3b82f6);
    color: white;
  }

  .tab.add-tab {
    background: transparent;
    border: 1px dashed var(--input-border, #444);
    color: var(--text-muted, #666);
  }

  .tab.add-tab:hover {
    border-color: var(--accent-color, #3b82f6);
    color: var(--accent-color, #3b82f6);
  }

  .project-tab {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .project-name {
    max-width: 100px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .remove-project {
    background: none;
    border: none;
    color: var(--text-muted, #666);
    cursor: pointer;
    padding: 0;
    font-size: 14px;
    line-height: 1;
  }

  .remove-project:hover {
    color: #ef4444;
  }

  .new-project-dialog {
    display: flex;
    gap: 8px;
    margin-bottom: 16px;
    padding: 12px;
    background: var(--input-bg, #1a1a2e);
    border-radius: 8px;
  }

  .new-project-dialog input {
    flex: 1;
    padding: 8px;
    border: 1px solid var(--input-border, #444);
    border-radius: 4px;
    background: var(--card-bg, #2a2a3e);
    color: var(--text-primary, #eee);
    font-size: 13px;
  }

  /* Rules List */
  .rules-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-bottom: 12px;
    max-height: 300px;
    overflow-y: auto;
  }

  .rule-item {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 10px;
    background: var(--input-bg, #1a1a2e);
    border-radius: 8px;
    border: 1px solid transparent;
    transition: all 0.15s;
  }

  .rule-item:hover {
    background: var(--hover-bg, #222238);
  }

  .rule-item.editing {
    border-color: var(--accent-color, #3b82f6);
  }

  .rule-item.disabled {
    opacity: 0.5;
  }

  .rule-controls {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .move-btn {
    background: none;
    border: none;
    color: var(--text-muted, #666);
    cursor: pointer;
    padding: 0;
    font-size: 10px;
    line-height: 1;
  }

  .move-btn:hover:not(:disabled) {
    color: var(--accent-color, #3b82f6);
  }

  .move-btn:disabled {
    opacity: 0.3;
    cursor: not-allowed;
  }

  .rule-content {
    flex: 1;
    cursor: pointer;
    min-width: 0;
  }

  .rule-header {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 2px;
  }

  .rule-name {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary, #eee);
  }

  .rule-action {
    font-size: 10px;
    padding: 2px 6px;
    border-radius: 4px;
    background: var(--input-border, #444);
    color: var(--text-muted, #aaa);
  }

  .rule-action.auto {
    background: #22c55e33;
    color: #22c55e;
  }

  .rule-match {
    font-size: 11px;
    color: var(--text-muted, #666);
  }

  .rule-actions {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .toggle {
    position: relative;
    display: inline-block;
    width: 32px;
    height: 18px;
  }

  .toggle input {
    opacity: 0;
    width: 0;
    height: 0;
  }

  .toggle-slider {
    position: absolute;
    cursor: pointer;
    inset: 0;
    background: var(--input-border, #444);
    border-radius: 18px;
    transition: 0.2s;
  }

  .toggle-slider:before {
    position: absolute;
    content: "";
    height: 14px;
    width: 14px;
    left: 2px;
    bottom: 2px;
    background: white;
    border-radius: 50%;
    transition: 0.2s;
  }

  .toggle input:checked + .toggle-slider {
    background: var(--accent-color, #3b82f6);
  }

  .toggle input:checked + .toggle-slider:before {
    transform: translateX(14px);
  }

  .delete-btn {
    background: none;
    border: none;
    color: var(--text-muted, #666);
    cursor: pointer;
    padding: 4px;
    font-size: 16px;
    line-height: 1;
  }

  .delete-btn:hover {
    color: #ef4444;
  }

  .empty-rules {
    padding: 24px;
    text-align: center;
    color: var(--text-muted, #666);
    font-size: 13px;
  }

  .add-rule-btn {
    width: 100%;
    padding: 10px;
    border: 1px dashed var(--input-border, #444);
    border-radius: 8px;
    background: transparent;
    color: var(--text-muted, #666);
    font-size: 13px;
    cursor: pointer;
    transition: all 0.15s;
  }

  .add-rule-btn:hover {
    border-color: var(--accent-color, #3b82f6);
    color: var(--accent-color, #3b82f6);
  }

  /* Rule Editor */
  .rule-editor {
    margin-top: 16px;
    padding: 16px;
    background: var(--input-bg, #1a1a2e);
    border-radius: 8px;
    border: 1px solid var(--accent-color, #3b82f6);
  }

  .form-row {
    margin-bottom: 12px;
  }

  .form-row label {
    display: block;
    margin-bottom: 4px;
    font-size: 12px;
    color: var(--text-muted, #888);
  }

  .form-row input,
  .form-row select {
    width: 100%;
    padding: 8px 10px;
    border: 1px solid var(--input-border, #444);
    border-radius: 6px;
    background: var(--card-bg, #2a2a3e);
    color: var(--text-primary, #eee);
    font-size: 13px;
  }

  .form-row input:focus,
  .form-row select:focus {
    outline: none;
    border-color: var(--accent-color, #3b82f6);
  }

  .editor-actions {
    display: flex;
    gap: 8px;
    justify-content: flex-end;
    margin-top: 16px;
  }

  /* Actions */
  .actions {
    display: flex;
    gap: 8px;
    justify-content: flex-end;
    margin-top: 20px;
    padding-top: 16px;
    border-top: 1px solid var(--border-color, #333);
  }

  .btn {
    padding: 8px 16px;
    border: none;
    border-radius: 6px;
    font-size: 13px;
    cursor: pointer;
    transition: all 0.15s;
  }

  .btn.small {
    padding: 6px 12px;
    font-size: 12px;
  }

  .btn.cancel {
    background: var(--input-border, #444);
    color: var(--text-primary, #eee);
  }

  .btn.cancel:hover {
    background: var(--hover-bg, #555);
  }

  .btn.save {
    background: var(--accent-color, #3b82f6);
    color: white;
  }

  .btn.save:hover {
    background: #2563eb;
  }
</style>
