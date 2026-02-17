<script lang="ts">
  import { onMount } from 'svelte';
  import PromptCard from './lib/PromptCard.svelte';
  import UserPromptCard from './lib/UserPromptCard.svelte';
  import Settings from './lib/Settings.svelte';
  import {
    prompts,
    connected,
    settings,
    uiPrefs,
    connectWebSocket,
    requestNotificationPermission,
    updateVolume,
    startDevicePolling,
    deviceConnected,
    globalPaused,
    togglePauseAll,
    resolvePrompt,
  } from './lib/stores';
  import { isUserPrompt, isExitPlanMode } from './lib/types';
  import type { Prompt } from './lib/types';

  // Sort prompts: manual (no autoAcceptIn) first, auto-accept last
  function sortPrompts(prompts: Prompt[]): Prompt[] {
    return [...prompts].sort((a, b) => {
      const aIsManual = !('autoAcceptIn' in a) || a.autoAcceptIn === undefined;
      const bIsManual = !('autoAcceptIn' in b) || b.autoAcceptIn === undefined;
      if (aIsManual !== bIsManual) {
        return aIsManual ? -1 : 1; // Manual prompts come first
      }
      return a.createdAt - b.createdAt; // Then by creation time
    });
  }

  $: sortedPrompts = sortPrompts($prompts);
  import ExitPlanModeCard from './lib/ExitPlanModeCard.svelte';

  let showSettings = false;

  // Apply theme to document
  $: {
    document.documentElement.setAttribute('data-theme', $uiPrefs.theme);
  }

  // Update volume when UI prefs change
  $: updateVolume($uiPrefs.volume);

  function toggleTheme() {
    uiPrefs.update(prefs => ({
      ...prefs,
      theme: prefs.theme === 'dark' ? 'light' : 'dark'
    }));
  }

  function toggleMute() {
    uiPrefs.update(prefs => ({
      ...prefs,
      volume: prefs.volume > 0 ? 0 : 50
    }));
  }

  function handleVolumeChange(e: Event) {
    const target = e.target as HTMLInputElement;
    const volume = parseInt(target.value, 10);
    uiPrefs.update(prefs => ({
      ...prefs,
      volume
    }));
  }

  onMount(() => {
    connectWebSocket();
    requestNotificationPermission();
    startDevicePolling();
  });

  function handleKeydown(e: KeyboardEvent) {
    // Ignore if typing in an input
    if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
    // Ignore if settings modal is open
    if (showSettings) return;

    const sorted = sortPrompts($prompts);
    if (sorted.length === 0) return;

    // Number keys 1-4 accept prompts by position
    if (e.key >= '1' && e.key <= '4') {
      const index = parseInt(e.key) - 1;
      if (index < sorted.length) {
        const prompt = sorted[index];
        // Don't allow keyboard accept for immediate auto-accept
        if (prompt.acceptType !== 'auto-accept') {
          resolvePrompt(prompt.id, { decision: 'allow' });
        }
      }
      return;
    }

    // 'y' accepts first prompt, 'n' denies first prompt
    const firstPrompt = sorted[0];
    if (firstPrompt.acceptType === 'auto-accept') return;

    if (e.key === 'y' || e.key === 'Y') {
      resolvePrompt(firstPrompt.id, { decision: 'allow' });
    } else if (e.key === 'n' || e.key === 'N') {
      resolvePrompt(firstPrompt.id, { decision: 'deny', reason: 'Denied by keyboard' });
    }
  }
</script>

<svelte:window on:keydown={handleKeydown} />

<main class:light={$uiPrefs.theme === 'light'}>
  <header>
    <h1 class="logo"><span class="flow">flow</span>gate</h1>
    <div class="header-right">
      <div class="volume-control">
        <button class="icon-btn" on:click={toggleMute} title={$uiPrefs.volume > 0 ? 'Mute' : 'Unmute'}>
          {#if $uiPrefs.volume === 0}
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M11 5L6 9H2v6h4l5 4V5z"/>
              <line x1="23" y1="9" x2="17" y2="15"/>
              <line x1="17" y1="9" x2="23" y2="15"/>
            </svg>
          {:else if $uiPrefs.volume < 50}
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
          value={$uiPrefs.volume}
          on:input={handleVolumeChange}
          class="volume-slider"
        />
      </div>
      <button class="icon-btn pause-btn" class:paused={$globalPaused} on:click={togglePauseAll} title={$globalPaused ? 'Resume auto-accept' : 'Pause auto-accept'}>
        {#if $globalPaused}
          <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
            <polygon points="5,3 19,12 5,21"/>
          </svg>
        {:else}
          <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
            <rect x="6" y="4" width="4" height="16"/>
            <rect x="14" y="4" width="4" height="16"/>
          </svg>
        {/if}
      </button>
      <button class="icon-btn" on:click={toggleTheme} title="Toggle theme">
        {#if $uiPrefs.theme === 'dark'}
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
      {#each sortedPrompts as prompt (prompt.id)}
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

<Settings bind:open={showSettings} on:close={() => (showSettings = false)} />

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

  h1.logo {
    font-family: 'IBM Plex Mono', ui-monospace, SFMono-Regular, Menlo, Monaco, 'Cascadia Mono', monospace;
    font-size: 22px;
    font-weight: 600;
    letter-spacing: -0.5px;
    margin: 0;
  }

  h1.logo .flow {
    color: #22c55e;
  }

  :global([data-theme="light"]) h1.logo .flow {
    color: #16a34a;
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

  .pause-btn {
    color: #22c55e;
  }

  .pause-btn.paused {
    color: #f97316;
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
