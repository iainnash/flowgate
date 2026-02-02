import type { Decision, Prompt } from '../types.js';
import type { InputDevicePlugin, PromptSlot } from './types.js';
import { BUTTON_COLORS, STREAMDECK_LAYOUT } from './types.js';

// Dynamic import for optional dependency
let streamDeckModule: typeof import('@elgato-stream-deck/node') | null = null;

async function loadStreamDeckModule() {
  if (streamDeckModule) return streamDeckModule;
  try {
    streamDeckModule = await import('@elgato-stream-deck/node');
    return streamDeckModule;
  } catch {
    return null;
  }
}

// Type for Stream Deck instance - use generic type to avoid version-specific issues
type StreamDeckDevice = {
  PRODUCT_NAME?: string;
  ICON_SIZE?: number;
  NUM_KEYS?: number;
  KEY_COLUMNS?: number;
  KEY_ROWS?: number;
  CONTROLS?: Array<{ type: string; row: number; column: number; index: number; pixelSize?: { width: number; height: number } }>;
  clearPanel(): Promise<void>;
  close(): Promise<void>;
  fillKeyBuffer(keyIndex: number, buffer: Buffer, options?: { format?: string }): Promise<void>;
  on(event: 'down', handler: (control: unknown) => void): void;
  on(event: 'up', handler: (control: unknown) => void): void;
  on(event: 'error', handler: (err: unknown) => void): void;
};

/**
 * Stream Deck plugin for prompt resolution.
 *
 * Layout (15-key: 5 wide x 3 tall):
 * ┌─────┬─────┬─────┬─────┬─────┐
 * │ 1-Y │ 2-Y │ 3-Y │ 4-Y │ ALL │  ← Row 0: Yes (global = accept all)
 * ├─────┼─────┼─────┼─────┼─────┤
 * │ 1-N │ 2-N │ 3-N │ 4-N │     │  ← Row 1: No (middle global TBD)
 * ├─────┼─────┼─────┼─────┼─────┤
 * │ 1-O │ 2-O │ 3-O │ 4-O │PAUSE│  ← Row 2: Other (global = pause/play toggle)
 * └─────┴─────┴─────┴─────┴─────┘
 *   #1    #2    #3    #4   Global
 */
export class StreamDeckPlugin implements InputDevicePlugin {
  name = 'Stream Deck';

  private device: StreamDeckDevice | null = null;
  private prompts: Prompt[] = [];
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private _isConnected = false;
  private iconSize = 72; // Default icon size for most Stream Decks
  private _isPaused = false;

  onResolve: (id: string, decision: Decision) => void = () => {};
  onResolveAll: (decision: 'allow' | 'deny') => void = () => {};
  onTogglePauseAll: () => void = () => {};

  async init(): Promise<void> {
    await this.connect();
  }

  async destroy(): Promise<void> {
    this.stopReconnectTimer();
    await this.disconnect();
  }

  onPromptsChanged(prompts: Prompt[]): void {
    this.prompts = prompts;
    this.updateDisplay();
  }

  onPromptResolved(_id: string): void {
    // Display will be updated when onPromptsChanged is called
  }

  onPauseStateChanged(isPaused: boolean): void {
    this._isPaused = isPaused;
    this.updateDisplay();
  }

  isConnected(): boolean {
    return this._isConnected;
  }

  private async connect(): Promise<void> {
    const module = await loadStreamDeckModule();
    if (!module) {
      console.log('[StreamDeck] @elgato-stream-deck/node not installed, skipping');
      return;
    }

    try {
      // List available devices
      const devices = await module.listStreamDecks();
      if (devices.length === 0) {
        console.log('[StreamDeck] No devices found');
        this.scheduleReconnect();
        return;
      }

      // Open the first device
      const rawDevice = await module.openStreamDeck(devices[0].path);
      this.device = rawDevice as unknown as StreamDeckDevice;
      this._isConnected = true;

      // Get device info based on available properties
      const productName = this.device.PRODUCT_NAME ?? 'Unknown';
      const numKeys = this.device.NUM_KEYS ?? this.device.CONTROLS?.filter(c => c.type === 'button').length ?? 15;
      console.log(`[StreamDeck] Connected: ${productName} (${numKeys} keys)`);

      // Determine icon size from device or controls
      if (this.device.ICON_SIZE) {
        this.iconSize = this.device.ICON_SIZE;
      } else if (this.device.CONTROLS) {
        const firstButton = this.device.CONTROLS.find(c => c.type === 'button' && c.pixelSize);
        if (firstButton?.pixelSize) {
          this.iconSize = firstButton.pixelSize.width;
        }
      }

      // Clear all buttons
      await this.device.clearPanel();

      // Set up button press handler
      this.device.on('down', (control: unknown) => {
        const keyIndex = this.getKeyIndex(control);
        if (keyIndex !== undefined) {
          this.handleButtonPress(keyIndex);
        }
      });

      // Handle disconnect
      this.device.on('error', (err: unknown) => {
        const message = err instanceof Error ? err.message : String(err);
        console.error('[StreamDeck] Device error:', message);
        this.handleDisconnect();
      });

      // Initial display update
      this.updateDisplay();
    } catch (err) {
      console.error('[StreamDeck] Failed to connect:', err);
      this.scheduleReconnect();
    }
  }

  /**
   * Extract key index from control object (handles different API versions)
   */
  private getKeyIndex(control: unknown): number | undefined {
    if (typeof control === 'number') {
      return control;
    }
    if (typeof control === 'object' && control !== null) {
      const obj = control as Record<string, unknown>;
      if (typeof obj.index === 'number') {
        return obj.index;
      }
      // For newer API with row/column
      if (typeof obj.row === 'number' && typeof obj.column === 'number') {
        const columns = this.device?.KEY_COLUMNS ?? 5;
        return obj.row * columns + obj.column;
      }
    }
    return undefined;
  }

  private async disconnect(): Promise<void> {
    if (this.device) {
      try {
        await this.device.clearPanel();
        await this.device.close();
      } catch {
        // Ignore close errors
      }
      this.device = null;
    }
    this._isConnected = false;
  }

  private handleDisconnect(): void {
    this._isConnected = false;
    this.device = null;
    console.log('[StreamDeck] Disconnected');
    this.scheduleReconnect();
  }

  private scheduleReconnect(): void {
    this.stopReconnectTimer();
    this.reconnectTimer = setTimeout(() => {
      console.log('[StreamDeck] Attempting reconnect...');
      this.connect();
    }, 5000);
  }

  private stopReconnectTimer(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  /**
   * Map prompts to display slots (1-4).
   * Shows all prompts - even those with auto-accept timers need user attention
   * (they can still be manually approved/denied before the timer expires).
   */
  private getPromptSlots(): PromptSlot[] {
    return this.prompts.slice(0, STREAMDECK_LAYOUT.PROMPT_SLOTS).map((prompt, i) => ({
      index: i + 1,
      prompt,
    }));
  }

  /**
   * Handle button press events
   */
  private handleButtonPress(keyIndex: number): void {
    const slots = this.getPromptSlots();
    const L = STREAMDECK_LAYOUT;

    // Map button index to action
    switch (keyIndex) {
      // Yes buttons (row 0, columns 0-3)
      case L.YES_1:
        this.resolveSlot(slots, 0, 'allow');
        break;
      case L.YES_2:
        this.resolveSlot(slots, 1, 'allow');
        break;
      case L.YES_3:
        this.resolveSlot(slots, 2, 'allow');
        break;
      case L.YES_4:
        this.resolveSlot(slots, 3, 'allow');
        break;
      case L.YES_ALL:
        this.onResolveAll('allow');
        break;

      // No buttons (row 1, columns 0-3)
      case L.NO_1:
        this.resolveSlot(slots, 0, 'deny');
        break;
      case L.NO_2:
        this.resolveSlot(slots, 1, 'deny');
        break;
      case L.NO_3:
        this.resolveSlot(slots, 2, 'deny');
        break;
      case L.NO_4:
        this.resolveSlot(slots, 3, 'deny');
        break;

      // Other buttons (row 2, columns 0-3) - treated as deny for now
      case L.OTHER_1:
        this.resolveSlot(slots, 0, 'deny', 'Other action from Stream Deck');
        break;
      case L.OTHER_2:
        this.resolveSlot(slots, 1, 'deny', 'Other action from Stream Deck');
        break;
      case L.OTHER_3:
        this.resolveSlot(slots, 2, 'deny', 'Other action from Stream Deck');
        break;
      case L.OTHER_4:
        this.resolveSlot(slots, 3, 'deny', 'Other action from Stream Deck');
        break;
      case L.PAUSE_PLAY:
        this.onTogglePauseAll();
        break;
    }
  }

  private resolveSlot(slots: PromptSlot[], index: number, decision: 'allow' | 'deny', reason?: string): void {
    const slot = slots[index];
    if (slot) {
      this.onResolve(slot.prompt.id, { decision, reason });
    }
  }

  /**
   * Update all button displays
   */
  private async updateDisplay(): Promise<void> {
    if (!this.device) return;

    const slots = this.getPromptSlots();
    const L = STREAMDECK_LAYOUT;

    try {
      // Update prompt slot buttons (columns 0-3)
      for (let col = 0; col < L.PROMPT_SLOTS; col++) {
        const slot = slots[col];

        if (slot) {
          // Has a prompt - show active buttons
          await this.setButtonImage(L.YES_1 + col, this.createButtonImage(
            String(slot.index),
            'YES',
            slot.prompt.toolName,
            BUTTON_COLORS.YES
          ));
          await this.setButtonImage(L.NO_1 + col, this.createButtonImage(
            String(slot.index),
            'NO',
            '',
            BUTTON_COLORS.NO
          ));
          await this.setButtonImage(L.OTHER_1 + col, this.createButtonImage(
            String(slot.index),
            '...',
            '',
            BUTTON_COLORS.OTHER
          ));
        } else {
          // No prompt - show empty buttons
          await this.setButtonImage(L.YES_1 + col, this.createButtonImage(
            String(col + 1),
            '',
            '',
            BUTTON_COLORS.EMPTY
          ));
          await this.setButtonImage(L.NO_1 + col, this.createButtonImage(
            '',
            '',
            '',
            BUTTON_COLORS.EMPTY
          ));
          await this.setButtonImage(L.OTHER_1 + col, this.createButtonImage(
            '',
            '',
            '',
            BUTTON_COLORS.EMPTY
          ));
        }
      }

      // Update global buttons (column 4)
      const hasPrompts = slots.length > 0;

      // Accept All button (top-right)
      await this.setButtonImage(L.YES_ALL, this.createButtonImage(
        'ALL',
        'YES',
        '',
        hasPrompts ? BUTTON_COLORS.GLOBAL_YES : BUTTON_COLORS.EMPTY
      ));

      // Empty middle-right button
      await this.setButtonImage(L.EMPTY, this.createButtonImage(
        '',
        '',
        '',
        BUTTON_COLORS.EMPTY
      ));

      // Pause/Play toggle button (bottom-right)
      await this.setButtonImage(L.PAUSE_PLAY, this.createButtonImage(
        '',
        this._isPaused ? 'PLAY' : 'PAUSE',
        '',
        this._isPaused ? BUTTON_COLORS.PLAY : BUTTON_COLORS.PAUSE
      ));
    } catch (err) {
      console.error('[StreamDeck] Failed to update display:', err);
    }
  }

  /**
   * Create a button image buffer.
   * Uses simple RGB fill since we don't have canvas in Node.js by default.
   */
  private createButtonImage(
    number: string,
    action: string,
    _toolName: string,
    color: readonly [number, number, number]
  ): Buffer {
    if (!this.device) return Buffer.alloc(0);

    const size = this.iconSize;
    const pixels = size * size;
    const buffer = Buffer.alloc(pixels * 3);

    // Fill with background color
    for (let i = 0; i < pixels; i++) {
      buffer[i * 3] = color[0];
      buffer[i * 3 + 1] = color[1];
      buffer[i * 3 + 2] = color[2];
    }

    // Add simple text rendering using pixel patterns
    // This is a basic implementation - for better text, use canvas or sharp
    if (number) {
      this.drawText(buffer, size, number, size / 2, size / 3, 20);
    }
    if (action) {
      this.drawText(buffer, size, action, size / 2, size * 2 / 3, 12);
    }

    return buffer;
  }

  /**
   * Simple text rendering using predefined pixel patterns.
   * Limited to numbers and basic text.
   */
  private drawText(buffer: Buffer, size: number, text: string, x: number, y: number, fontSize: number): void {
    // Simple 5x7 pixel font for numbers and basic letters
    const FONT: Record<string, number[]> = {
      '1': [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
      '2': [0b01110, 0b10001, 0b00001, 0b00110, 0b01000, 0b10000, 0b11111],
      '3': [0b11110, 0b00001, 0b00001, 0b01110, 0b00001, 0b00001, 0b11110],
      '4': [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010],
      '5': [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110],
      'A': [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
      'L': [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111],
      'Y': [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100],
      'E': [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111],
      'S': [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110],
      'N': [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001],
      'O': [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
      'P': [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000],
      'U': [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
      '.': [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b01100, 0b01100],
    };

    const scale = Math.max(1, Math.floor(fontSize / 7));
    const charWidth = 5 * scale + scale; // Extra spacing between chars

    // Center the text
    const totalWidth = text.length * charWidth - scale;
    let startX = Math.floor(x - totalWidth / 2);
    const startY = Math.floor(y - (7 * scale) / 2);

    for (const char of text.toUpperCase()) {
      const pattern = FONT[char];
      if (pattern) {
        for (let row = 0; row < 7; row++) {
          for (let col = 0; col < 5; col++) {
            if (pattern[row] & (1 << (4 - col))) {
              // Draw scaled pixel
              for (let sy = 0; sy < scale; sy++) {
                for (let sx = 0; sx < scale; sx++) {
                  const px = startX + col * scale + sx;
                  const py = startY + row * scale + sy;
                  if (px >= 0 && px < size && py >= 0 && py < size) {
                    const idx = (py * size + px) * 3;
                    buffer[idx] = 255;
                    buffer[idx + 1] = 255;
                    buffer[idx + 2] = 255;
                  }
                }
              }
            }
          }
        }
      }
      startX += charWidth;
    }
  }

  /**
   * Set a button's image
   */
  private async setButtonImage(keyIndex: number, buffer: Buffer): Promise<void> {
    if (!this.device || buffer.length === 0) return;

    try {
      await this.device.fillKeyBuffer(keyIndex, buffer, { format: 'rgb' });
    } catch {
      // Ignore individual button update errors
    }
  }
}
