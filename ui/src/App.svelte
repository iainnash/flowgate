<script lang="ts">
  import { onMount } from 'svelte';
  import PromptCard from './lib/PromptCard.svelte';
  import UserPromptCard from './lib/UserPromptCard.svelte';
  import Settings from './lib/Settings.svelte';
  import {
    prompts,
    connected,
    settings,
    connectWebSocket,
    requestNotificationPermission,
    updateVolume,
    startDevicePolling,
    deviceConnected,
  } from './lib/stores';
  import { isUserPrompt, isExitPlanMode } from './lib/types';
  import ExitPlanModeCard from './lib/ExitPlanModeCard.svelte';

  let showSettings = false;

  // Apply theme to document
  $: {
    document.documentElement.setAttribute('data-theme', $settings.ui.theme);
  }

  // Update volume when settings change
  $: updateVolume($settings.ui.volume);

  function toggleTheme() {
    settings.update(s => ({
      ...s,
      ui: { ...s.ui, theme: s.ui.theme === 'dark' ? 'light' : 'dark' }
    }));
  }

  function toggleMute() {
    settings.update(s => ({
      ...s,
      ui: { ...s.ui, volume: s.ui.volume > 0 ? 0 : 50 }
    }));
  }

  function handleVolumeChange(e: Event) {
    const target = e.target as HTMLInputElement;
    const volume = parseInt(target.value, 10);
    settings.update(s => ({
      ...s,
      ui: { ...s.ui, volume }
    }));
  }

  onMount(() => {
    connectWebSocket();
    requestNotificationPermission();
    startDevicePolling();
  });
</script>

<main class:light={$settings.ui.theme === 'light'}>
  <header>
    <h1>Claude Prompt UI</h1>
    <div class="header-right">
      <div class="volume-control">
        <button class="icon-btn" on:click={toggleMute} title={$settings.ui.volume > 0 ? 'Mute' : 'Unmute'}>
          {#if $settings.ui.volume === 0}
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M11 5L6 9H2v6h4l5 4V5z"/>
              <line x1="23" y1="9" x2="17" y2="15"/>
              <line x1="17" y1="9" x2="23" y2="15"/>
            </svg>
          {:else if $settings.ui.volume < 50}
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M11 5L6 9H2v6h4l5 4V5z"/>
              <path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>
            </svg>
          {:else}
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M11 5L6 9H2v6h4l5 4V5z"/>
              <path d="M19.07 4.93a10 10 0 0 1 0 14.14M15.54 8.46a5 5 0 0 1 0 7.07"/>
            </svg>
          {/if}
        </button>
        <input
          type="range"
          min="0"
          max="100"
          value={$settings.ui.volume}
          on:input={handleVolumeChange}
          class="volume-slider"
        />
      </div>
      <button class="icon-btn" on:click={toggleTheme} title="Toggle theme">
        {#if $settings.ui.theme === 'dark'}
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <circle cx="12" cy="12" r="5"/>
            <line x1="12" y1="1" x2="12" y2="3"/>
            <line x1="12" y1="21" x2="12" y2="23"/>
            <line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/>
            <line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/>
            <line x1="1" y1="12" x2="3" y2="12"/>
            <line x1="21" y1="12" x2="23" y2="12"/>
            <line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/>
            <line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>
          </svg>
        {:else}
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>
          </svg>
        {/if}
      </button>
      <span class="status" class:connected={$connected}>
        {$connected ? 'Connected' : 'Disconnected'}
      </span>
      {#if $deviceConnected}
        <span class="device-badge" title="Stream Deck connected">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <rect x="2" y="3" width="20" height="14" rx="2" ry="2"/>
            <line x1="8" y1="21" x2="16" y2="21"/>
            <line x1="12" y1="17" x2="12" y2="21"/>
          </svg>
        </span>
      {/if}
      <button class="settings-btn" on:click={() => (showSettings = true)}>
        Rules
      </button>
    </div>
  </header>

  <div class="content">
    {#if $prompts.length === 0}
      <div class="empty">
        <p>No pending prompts</p>
        <p class="hint">Prompts from Claude Code will appear here</p>
      </div>
    {:else}
      {#each $prompts as prompt (prompt.id)}
        {#if isUserPrompt(prompt)}
          <UserPromptCard {prompt} />
        {:else if isExitPlanMode(prompt)}
          <ExitPlanModeCard {prompt} />
        {:else}
          <PromptCard {prompt} />
        {/if}
      {/each}
    {/if}
  </div>
</main>

<Settings open={showSettings} on:close={() => (showSettings = false)} />

<style>
  main {
    max-width: 700px;
    margin: 0 auto;
    padding: 20px;
  }

  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 24px;
    padding-bottom: 16px;
    border-bottom: 1px solid var(--border-color, #333);
  }

  h1 {
    font-size: 22px;
    font-weight: 600;
    margin: 0;
  }

  .header-right {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .volume-control {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .volume-slider {
    width: 80px;
    height: 4px;
    -webkit-appearance: none;
    appearance: none;
    background: var(--slider-bg, #444);
    border-radius: 2px;
    cursor: pointer;
  }

  .volume-slider::-webkit-slider-thumb {
    -webkit-appearance: none;
    appearance: none;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: var(--accent-color, #3b82f6);
    cursor: pointer;
  }

  .volume-slider::-moz-range-thumb {
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: var(--accent-color, #3b82f6);
    cursor: pointer;
    border: none;
  }

  .icon-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    border: none;
    border-radius: 6px;
    background: transparent;
    color: var(--text-secondary, #888);
    cursor: pointer;
    transition: all 0.15s;
  }

  .icon-btn:hover {
    background: var(--hover-bg, #333);
    color: var(--text-primary, #eee);
  }

  .status {
    font-size: 12px;
    padding: 4px 10px;
    border-radius: 12px;
    background: #ef4444;
    color: white;
  }

  .status.connected {
    background: #22c55e;
  }

  .device-badge {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 4px 8px;
    border-radius: 12px;
    background: #3b82f6;
    color: white;
  }

  .settings-btn {
    padding: 6px 14px;
    border: 1px solid var(--border-color, #444);
    border-radius: 6px;
    background: transparent;
    color: var(--text-secondary, #ccc);
    font-size: 13px;
    cursor: pointer;
  }

  .settings-btn:hover {
    background: var(--hover-bg, #333);
  }

  .content {
    min-height: 200px;
  }

  .empty {
    text-align: center;
    padding: 60px 20px;
    color: var(--text-secondary, #888);
  }

  .empty p {
    margin: 0;
  }

  .empty .hint {
    font-size: 14px;
    margin-top: 8px;
    color: var(--text-muted, #555);
  }
</style>
