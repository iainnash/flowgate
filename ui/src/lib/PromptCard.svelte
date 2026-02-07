<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import CountdownButton from './CountdownButton.svelte';
  import OtherModal from './OtherModal.svelte';
  import CodeDiff from './CodeDiff.svelte';
  import { resolvePrompt, getSessionColor, autoAccepted, deviceConnected, prompts, getPromptDisplayIndex, globalPaused } from './stores';
  import type { Prompt } from './types';
  import { isCodeChange } from './types';

  export let prompt: Prompt;

  let countdown = 0;  // 0-100 percentage
  let remainingSeconds = 0;
  let intervalId: ReturnType<typeof setInterval> | null = null;
  let showModal = false;
  let expanded = false;
  let shouldDismiss = false;
  let dismissTimeoutId: ReturnType<typeof setTimeout> | null = null;

  $: sessionColor = getSessionColor(prompt.sessionId);
  // Use server-provided acceptType
  $: isImmediateAutoAccept = prompt.acceptType === 'auto-accept';
  $: isAcceptAfter = prompt.acceptType === 'accept-after';
  $: isManual = prompt.acceptType === 'manual';
  $: shouldAutoAccept = isImmediateAutoAccept || isAcceptAfter;
  $: isAutoAccepted = $autoAccepted.has(prompt.id);
  $: displayIndex = $deviceConnected ? getPromptDisplayIndex(prompt.id, $prompts) : undefined;
  $: isPaused = isAcceptAfter && prompt.autoAcceptAt === undefined;

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
    // Update countdown based on server-provided autoAcceptAt
    const updateCountdown = () => {
      if (prompt.autoAcceptAt && prompt.autoAcceptIn && prompt.autoAcceptIn > 0) {
        const now = Date.now();
        const remaining = Math.max(0, prompt.autoAcceptAt - now);
        const totalMs = prompt.autoAcceptIn * 1000;
        const elapsed = totalMs - remaining;
        countdown = Math.min(100, (elapsed / totalMs) * 100);
        remainingSeconds = Math.ceil(remaining / 1000);
      } else if (prompt.autoAcceptIn !== undefined && prompt.autoAcceptIn > 0) {
        // Paused - show last known remaining time or full time
        remainingSeconds = prompt.autoAcceptIn;
        // Keep countdown at whatever it was
      }
    };
    updateCountdown();
    intervalId = setInterval(updateCountdown, 100);

    // Auto-dismiss after 3 seconds for immediate auto-accept prompts
    if (isImmediateAutoAccept) {
      dismissTimeoutId = setTimeout(() => {
        shouldDismiss = true;
      }, 3000);
    }
  });

  onDestroy(() => {
    if (intervalId) clearInterval(intervalId);
    if (dismissTimeoutId) clearTimeout(dismissTimeoutId);
  });

  function handleYes() {
    resolvePrompt(prompt.id, { decision: 'allow' });
  }

  function handleNo() {
    resolvePrompt(prompt.id, { decision: 'deny', reason: 'Denied by user' });
  }

  function handleOther() {
    showModal = true;
  }

  function handleDeny(e: CustomEvent<{ reason: string }>) {
    showModal = false;
    resolvePrompt(prompt.id, { decision: 'deny', reason: e.detail.reason });
  }

  function handleModify(e: CustomEvent<{ updatedInput: Record<string, unknown> }>) {
    showModal = false;
    resolvePrompt(prompt.id, { decision: 'allow', updatedInput: e.detail.updatedInput });
  }
</script>

<div class="card" class:auto-accepted={isAutoAccepted} class:dismissing={shouldDismiss}>
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

  {#if !isImmediateAutoAccept}
    <div class="actions">
      <CountdownButton
        label="Yes"
        variant="yes"
        countdown={isAcceptAfter ? countdown : 0}
        pulse={isManual}
        on:click={handleYes}
      />
      <CountdownButton label="No" variant="no" on:click={handleNo} />
      <CountdownButton label="Other" variant="other" on:click={handleOther} />
    </div>
  {/if}

  {#if isAutoAccepted}
    <div class="countdown-label accepted">Auto-accepted</div>
  {:else if isAcceptAfter}
    <div class="countdown-label" class:paused={isPaused} data-testid="countdown">
      {remainingSeconds}s
      {#if isPaused}(paused){/if}
    </div>
  {:else if isImmediateAutoAccept}
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
    transition: opacity 0.3s ease-out, transform 0.3s ease-out;
  }

  .card.dismissing {
    opacity: 0;
    transform: translateY(-20px) scale(0.95);
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

  .countdown-label.paused {
    color: #f97316;
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
