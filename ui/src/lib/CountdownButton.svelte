<script lang="ts">
  export let label: string;
  export let countdown: number = 0; // 0-100 percentage
  export let variant: 'yes' | 'no' | 'other' = 'yes';
  export let disabled: boolean = false;
  export let pulse: boolean = false;
</script>

<button
  class="countdown-btn {variant}"
  class:pulse
  style="--fill: {countdown}%"
  {disabled}
  on:click
>
  {label}
</button>

<style>
  .countdown-btn {
    position: relative;
    overflow: hidden;
    padding: 8px 20px;
    border: none;
    border-radius: 6px;
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    color: white;
    transition: opacity 0.15s, transform 0.1s;
    min-width: 80px;
  }

  .countdown-btn:hover:not(:disabled) {
    opacity: 0.9;
    transform: translateY(-1px);
  }

  .countdown-btn:active:not(:disabled) {
    transform: translateY(0);
  }

  .countdown-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .countdown-btn::before {
    content: '';
    position: absolute;
    left: 0;
    top: 0;
    height: 100%;
    width: var(--fill);
    background: rgba(255, 255, 255, 0.25);
    transition: width 100ms linear;
    pointer-events: none;
  }

  .countdown-btn.yes {
    background: #22c55e;
  }

  .countdown-btn.no {
    background: #ef4444;
  }

  .countdown-btn.other {
    background: #6b7280;
  }

  .countdown-btn.pulse {
    animation: pulse 1.5s ease-in-out infinite;
  }

  @keyframes pulse {
    0%, 100% {
      box-shadow: 0 0 0 0 rgba(34, 197, 94, 0.6);
    }
    50% {
      box-shadow: 0 0 0 8px rgba(34, 197, 94, 0);
    }
  }
</style>
