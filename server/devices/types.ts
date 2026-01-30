import type { Decision, Prompt } from '../types.js';

/**
 * Input device plugin interface.
 * Plugins handle external input devices (Stream Deck, etc.) for prompt resolution.
 */
export interface InputDevicePlugin {
  /** Human-readable name for the device/plugin */
  name: string;

  /** Initialize the plugin, connect to hardware */
  init(): Promise<void>;

  /** Cleanup and disconnect */
  destroy(): Promise<void>;

  /** Called when the list of pending prompts changes */
  onPromptsChanged(prompts: Prompt[]): void;

  /** Called when a specific prompt is resolved */
  onPromptResolved(id: string): void;

  /** Callback to resolve a single prompt */
  onResolve: (id: string, decision: Decision) => void;

  /** Callback to resolve all pending prompts with allow/deny */
  onResolveAll: (decision: 'allow' | 'deny') => void;

  /** Whether the device is currently connected */
  isConnected(): boolean;
}

/**
 * Device connection status for UI feedback
 */
export interface DeviceStatus {
  name: string;
  connected: boolean;
  deviceModel?: string;
}

/**
 * Prompt slot info for Stream Deck display
 * Maps prompts to button positions (1-4)
 */
export interface PromptSlot {
  index: number;  // 1-4, displayed on button
  prompt: Prompt;
}

/**
 * Stream Deck button layout:
 *
 * Row 0: Yes buttons (1-Y, 2-Y, 3-Y, 4-Y, ALL-Y)
 * Row 1: No buttons  (1-N, 2-N, 3-N, 4-N, empty)
 * Row 2: Other btns  (1-O, 2-O, 3-O, 4-O, ALL-N)
 *
 * Column mapping:
 * - Columns 0-3: Prompt slots 1-4
 * - Column 4: Global actions
 */
export const STREAMDECK_LAYOUT = {
  ROWS: 3,
  COLS: 5,
  PROMPT_SLOTS: 4,

  // Button indices on 15-key Stream Deck (5x3)
  // Row 0
  YES_1: 0,
  YES_2: 1,
  YES_3: 2,
  YES_4: 3,
  YES_ALL: 4,

  // Row 1
  NO_1: 5,
  NO_2: 6,
  NO_3: 7,
  NO_4: 8,
  EMPTY: 9,

  // Row 2
  OTHER_1: 10,
  OTHER_2: 11,
  OTHER_3: 12,
  OTHER_4: 13,
  NO_ALL: 14,
} as const;

/**
 * Button colors (RGB arrays)
 */
export const BUTTON_COLORS = {
  YES: [34, 197, 94] as const,      // Green
  NO: [239, 68, 68] as const,       // Red
  OTHER: [59, 130, 246] as const,   // Blue
  EMPTY: [30, 30, 40] as const,     // Dark gray
  PENDING: [60, 60, 80] as const,   // Lighter gray for pending
  GLOBAL_YES: [22, 163, 74] as const,  // Darker green
  GLOBAL_NO: [185, 28, 28] as const,   // Darker red
} as const;
