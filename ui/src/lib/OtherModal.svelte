<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import type { Prompt } from './types';

  export let prompt: Prompt;
  export let open: boolean = false;

  const dispatch = createEventDispatcher<{
    deny: { reason: string };
    modify: { updatedInput: Record<string, unknown> };
    close: void;
  }>();

  let mode: 'deny' | 'modify' = 'deny';
  let denyReason = '';
  let modifiedInput = '';

  $: if (open) {
    modifiedInput = JSON.stringify(prompt.toolInput, null, 2);
    denyReason = '';
  }

  function handleDeny() {
    dispatch('deny', { reason: denyReason || 'Denied by user' });
  }

  function handleModify() {
    try {
      const parsed = JSON.parse(modifiedInput);
      dispatch('modify', { updatedInput: parsed });
    } catch {
      alert('Invalid JSON');
    }
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      dispatch('close');
    }
  }
</script>

<svelte:window on:keydown={handleKeydown} />

{#if open}
  <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-noninteractive-element-interactions -->
  <div class="overlay" on:click={() => dispatch('close')} role="presentation">
    <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-noninteractive-element-interactions -->
    <div class="modal" on:click|stopPropagation role="dialog" aria-modal="true">
      <h3>Custom Response</h3>

      <div class="tabs">
        <button
          class:active={mode === 'deny'}
          on:click={() => (mode = 'deny')}
        >
          Deny with reason
        </button>
        <button
          class:active={mode === 'modify'}
          on:click={() => (mode = 'modify')}
        >
          Modify & approve
        </button>
      </div>

      {#if mode === 'deny'}
        <div class="form-group">
          <label for="deny-reason">Denial reason:</label>
          <input
            id="deny-reason"
            type="text"
            bind:value={denyReason}
            placeholder="Enter reason for denial..."
            autofocus
          />
        </div>
        <div class="actions">
          <button class="btn cancel" on:click={() => dispatch('close')}>
            Cancel
          </button>
          <button class="btn deny" on:click={handleDeny}>
            Deny
          </button>
        </div>
      {:else}
        <div class="form-group">
          <label for="modified-input">Modified input (JSON):</label>
          <textarea
            id="modified-input"
            bind:value={modifiedInput}
            rows="8"
          ></textarea>
        </div>
        <div class="actions">
          <button class="btn cancel" on:click={() => dispatch('close')}>
            Cancel
          </button>
          <button class="btn approve" on:click={handleModify}>
            Approve with changes
          </button>
        </div>
      {/if}
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
    background: #2a2a3e;
    border-radius: 12px;
    padding: 20px;
    width: 90%;
    max-width: 500px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
  }

  h3 {
    margin: 0 0 16px;
    font-size: 18px;
  }

  .tabs {
    display: flex;
    gap: 8px;
    margin-bottom: 16px;
  }

  .tabs button {
    flex: 1;
    padding: 8px 12px;
    border: 1px solid #444;
    background: transparent;
    color: #aaa;
    border-radius: 6px;
    cursor: pointer;
    font-size: 13px;
  }

  .tabs button.active {
    background: #3b82f6;
    border-color: #3b82f6;
    color: white;
  }

  .form-group {
    margin-bottom: 16px;
  }

  label {
    display: block;
    margin-bottom: 6px;
    font-size: 13px;
    color: #aaa;
  }

  input,
  textarea {
    width: 100%;
    padding: 10px;
    border: 1px solid #444;
    border-radius: 6px;
    background: #1a1a2e;
    color: #eee;
    font-size: 14px;
    font-family: inherit;
  }

  textarea {
    font-family: monospace;
    resize: vertical;
  }

  input:focus,
  textarea:focus {
    outline: none;
    border-color: #3b82f6;
  }

  .actions {
    display: flex;
    gap: 8px;
    justify-content: flex-end;
  }

  .btn {
    padding: 8px 16px;
    border: none;
    border-radius: 6px;
    font-size: 14px;
    cursor: pointer;
  }

  .btn.cancel {
    background: #444;
    color: #eee;
  }

  .btn.deny {
    background: #ef4444;
    color: white;
  }

  .btn.approve {
    background: #22c55e;
    color: white;
  }
</style>
