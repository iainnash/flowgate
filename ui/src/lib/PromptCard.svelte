<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import CountdownButton from './CountdownButton.svelte';
  import OtherModal from './OtherModal.svelte';
  import CodeDiff from './CodeDiff.svelte';
  import { resolvePrompt, getSessionColor, settings, findMatchingRule, autoAccepted, deviceConnected, prompts, getPromptDisplayIndex } from './stores';
  import type { Prompt, RuleAction } from './types';
  import { isCodeChange } from './types';

  export let prompt: Prompt;

  let countdown = 0;
  let intervalId: ReturnType<typeof setInterval> | null = null;
  let showModal = false;
  let expanded = false;

  $: sessionColor = getSessionColor(prompt.sessionId);
  $: matchingRule = findMatchingRule($settings, prompt.toolName, prompt.cwd);
  $: action = matchingRule?.action ?? { type: 'require-verify' } as RuleAction;
  $: shouldAutoAccept = action.type === 'auto-accept' || action.type === 'accept-after';
  $: timeoutMs = action.type === 'accept-after' ? action.seconds * 1000 : 0;
  $: isAutoAccepted = $autoAccepted.has(prompt.id);
  $: displayIndex = $deviceConnected ? getPromptDisplayIndex(prompt.id, $prompts) : undefined;

  $: description = getDescription(prompt.toolInput);

  function getDescription(input: Record<string, unknown>): string {
    if ('command' in input && typeof input.command === 'string') {
      return input.command;
    }
    if ('description' in input && typeof input.description === 'string') {
      return input.description;
    }
    if ('file_path' in input && typeof input.file_path === 'string') {
      return input.file_path;
    }
    return JSON.stringify(input).slice(0, 100);
  }

  function truncatePath(path: string): string {
    const home = '~';
    const parts = path.split('/');
    if (parts.length > 4) {
      return home + '/.../' + parts.slice(-2).join('/');
    }
    return path.replace(/^\/Users\/[^/]+/, home);
  }

  onMount(() => {
    if (shouldAutoAccept && timeoutMs > 0) {
      const startTime = prompt.createdAt;
      const updateCountdown = () => {
        const elapsed = Date.now() - startTime;
        countdown = Math.min(100, (elapsed / timeoutMs) * 100);
        if (countdown >= 100) {
          clearInterval(intervalId!);
        }
      };
      updateCountdown();
      intervalId = setInterval(updateCountdown, 100);
    }
  });

  onDestroy(() => {
    if (intervalId) clearInterval(intervalId);
  });

  async function handleYes() {
    await resolvePrompt(prompt.id, { decision: 'allow' });
  }

  async function handleNo() {
    await resolvePrompt(prompt.id, { decision: 'deny', reason: 'Denied by user' });
  }

  function handleOther() {
    showModal = true;
  }

  async function handleDeny(e: CustomEvent<{ reason: string }>) {
    showModal = false;
    await resolvePrompt(prompt.id, { decision: 'deny', reason: e.detail.reason });
  }

  async function handleModify(e: CustomEvent<{ updatedInput: Record<string, unknown> }>) {
    showModal = false;
    await resolvePrompt(prompt.id, { decision: 'allow', updatedInput: e.detail.updatedInput });
  }
</script>

<div class="card" class:auto-accepted={isAutoAccepted}>
  <div class="header">
    {#if displayIndex}
      <span class="device-index" class:overflow={displayIndex === '5+'}>
        {displayIndex}
      </span>
    {/if}
    <span class="session-badge" style="background: {sessionColor}">
      {prompt.sessionId.slice(0, 8)}
    </span>
    <span class="tool-name">{prompt.toolName}</span>
    <span class="cwd">{truncatePath(prompt.cwd)}</span>
  </div>

  <button class="description" class:expanded on:click={() => (expanded = !expanded)}>
    {#if expanded}
      {#if isCodeChange(prompt.toolName)}
        <CodeDiff toolName={prompt.toolName} toolInput={prompt.toolInput} />
      {:else}
        <pre>{JSON.stringify(prompt.toolInput, null, 2)}</pre>
      {/if}
    {:else}
      {description}
    {/if}
  </button>

  <div class="actions">
    <CountdownButton
      label="Yes"
      variant="yes"
      countdown={shouldAutoAccept ? countdown : 0}
      pulse={!shouldAutoAccept}
      on:click={handleYes}
    />
    <CountdownButton label="No" variant="no" on:click={handleNo} />
    <CountdownButton label="Other" variant="other" on:click={handleOther} />
  </div>

  {#if isAutoAccepted}
    <div class="countdown-label accepted">Auto-accepted</div>
  {:else if action.type === 'accept-after' && timeoutMs > 0}
    <div class="countdown-label" data-testid="countdown">
      {Math.max(0, Math.ceil((action.seconds * (100 - countdown)) / 100))}s
    </div>
  {:else if action.type === 'auto-accept'}
    <div class="countdown-label auto">Auto-accepting...</div>
  {:else}
    <div class="countdown-label muted">Manual approval</div>
  {/if}
</div>

<OtherModal
  {prompt}
  open={showModal}
  on:deny={handleDeny}
  on:modify={handleModify}
  on:close={() => (showModal = false)}
/>

<style>
  .card {
    background: var(--card-bg, #2a2a3e);
    border-radius: 10px;
    padding: 14px;
    margin-bottom: 12px;
  }

  .header {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-bottom: 10px;
    font-size: 13px;
  }

  .device-index {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
    background: #3b82f6;
    border-radius: 6px;
    font-size: 14px;
    font-weight: 700;
    color: white;
  }

  .device-index.overflow {
    background: #6b7280;
    font-size: 11px;
  }

  .session-badge {
    padding: 2px 8px;
    border-radius: 12px;
    font-size: 11px;
    font-weight: 500;
    color: white;
  }

  .tool-name {
    font-weight: 600;
    color: var(--text-primary, #fff);
  }

  .cwd {
    color: var(--text-muted, #888);
    margin-left: auto;
    font-size: 12px;
  }

  .description {
    display: block;
    width: 100%;
    background: var(--input-bg, #1a1a2e);
    border: 1px solid var(--input-border, #333);
    border-radius: 6px;
    padding: 10px;
    margin-bottom: 12px;
    color: var(--text-secondary, #ccc);
    font-size: 13px;
    font-family: 'SF Mono', Monaco, monospace;
    text-align: left;
    cursor: pointer;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .description.expanded {
    white-space: normal;
    overflow: visible;
    padding: 0;
    background: transparent;
    border: none;
  }

  .description:not(.expanded):hover {
    border-color: var(--border-color, #444);
  }

  .description pre {
    margin: 0;
    white-space: pre-wrap;
    word-break: break-word;
  }

  .actions {
    display: flex;
    gap: 8px;
  }

  .countdown-label {
    margin-top: 8px;
    font-size: 12px;
    color: var(--text-muted, #888);
    text-align: center;
  }

  .countdown-label.muted {
    color: var(--text-muted, #555);
    font-style: italic;
  }

  .countdown-label.auto {
    color: #22c55e;
  }

  .countdown-label.accepted {
    color: #22c55e;
    font-weight: 500;
  }

  .card.auto-accepted {
    opacity: 0.7;
    border: 1px solid #22c55e;
    transition: opacity 0.3s ease-out;
  }

  .card.auto-accepted .actions {
    pointer-events: none;
    opacity: 0.5;
  }
</style>
