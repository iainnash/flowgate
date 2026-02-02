<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import { getSessionColor, resolvePrompt } from './stores';
  import type { Prompt, ExitPlanModeInput } from './types';

  export let prompt: Prompt;

  const dispatch = createEventDispatcher<{ resolved: void }>();

  $: input = prompt.toolInput as ExitPlanModeInput;
  $: sessionColor = getSessionColor(prompt.sessionId);
  $: allowedPrompts = input.allowedPrompts || [];

  function handleApprove() {
    resolvePrompt(prompt.id, { decision: 'allow' });
    dispatch('resolved');
  }

  function handleDeny() {
    resolvePrompt(prompt.id, {
      decision: 'deny',
      reason: 'User declined to exit plan mode',
    });
    dispatch('resolved');
  }

  function handleAskInTerminal() {
    resolvePrompt(prompt.id, {
      decision: 'ask',
      reason: 'User wants to decide in terminal',
    });
    dispatch('resolved');
  }
</script>

<div class="plan-mode-card">
  <div class="header">
    <span class="session-badge" style="background-color: {sessionColor}">
      {prompt.sessionId.slice(0, 10)}
    </span>
    <span class="tool-badge">Exit Plan Mode</span>
  </div>

  <div class="content">
    <div class="icon">📋</div>
    <h3>Ready to implement?</h3>
    <p class="description">
      Claude has finished planning and wants to start implementing the solution.
    </p>

    {#if allowedPrompts.length > 0}
      <div class="permissions">
        <h4>Requested permissions:</h4>
        <ul>
          {#each allowedPrompts as perm}
            <li>
              <span class="perm-tool">{perm.tool}</span>
              <span class="perm-desc">{perm.prompt}</span>
            </li>
          {/each}
        </ul>
      </div>
    {/if}

    {#if input.launchSwarm}
      <div class="swarm-info">
        <span class="swarm-badge">🐝 Swarm Mode</span>
        {#if input.teammateCount}
          <span class="teammate-count">{input.teammateCount} teammates</span>
        {/if}
      </div>
    {/if}
  </div>

  <div class="actions">
    <button class="btn terminal" on:click={handleAskInTerminal}>
      Decide in Terminal
    </button>
    <button class="btn deny" on:click={handleDeny}>
      Keep Planning
    </button>
    <button class="btn approve" on:click={handleApprove}>
      Start Implementing
    </button>
  </div>
</div>

<style>
  .plan-mode-card {
    background: #1e1e2e;
    border: 2px solid #22c55e;
    border-radius: 12px;
    padding: 16px;
    margin-bottom: 12px;
  }

  .header {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 16px;
  }

  .session-badge {
    font-size: 11px;
    padding: 2px 8px;
    border-radius: 10px;
    color: white;
    font-weight: 500;
  }

  .tool-badge {
    font-size: 12px;
    padding: 2px 8px;
    border-radius: 6px;
    background: #22c55e;
    color: white;
    font-weight: 600;
  }

  .content {
    text-align: center;
    padding: 20px 0;
  }

  .icon {
    font-size: 48px;
    margin-bottom: 12px;
  }

  h3 {
    margin: 0 0 8px;
    font-size: 20px;
    color: #fff;
  }

  .description {
    color: #aaa;
    font-size: 14px;
    margin: 0 0 16px;
  }

  .permissions {
    background: #252538;
    border-radius: 8px;
    padding: 12px;
    text-align: left;
    margin-top: 16px;
  }

  .permissions h4 {
    margin: 0 0 8px;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: #888;
  }

  .permissions ul {
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .permissions li {
    display: flex;
    gap: 8px;
    align-items: center;
    padding: 6px 0;
    border-bottom: 1px solid #333;
  }

  .permissions li:last-child {
    border-bottom: none;
  }

  .perm-tool {
    font-size: 11px;
    padding: 2px 6px;
    border-radius: 4px;
    background: #3b82f6;
    color: white;
    font-weight: 500;
  }

  .perm-desc {
    font-size: 13px;
    color: #ccc;
  }

  .swarm-info {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 12px;
    margin-top: 16px;
  }

  .swarm-badge {
    font-size: 13px;
    padding: 4px 10px;
    border-radius: 6px;
    background: #f59e0b;
    color: #000;
    font-weight: 600;
  }

  .teammate-count {
    font-size: 13px;
    color: #aaa;
  }

  .actions {
    display: flex;
    gap: 8px;
    justify-content: flex-end;
    margin-top: 16px;
    padding-top: 16px;
    border-top: 1px solid #333;
  }

  .btn {
    padding: 10px 20px;
    border: none;
    border-radius: 6px;
    font-size: 14px;
    cursor: pointer;
    font-weight: 500;
  }

  .btn.terminal {
    background: #444;
    color: #ccc;
  }

  .btn.deny {
    background: #ef4444;
    color: white;
  }

  .btn.approve {
    background: #22c55e;
    color: white;
  }

  .btn:hover {
    opacity: 0.9;
  }
</style>
