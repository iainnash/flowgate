import type { Decision, Prompt } from '../types.js';
import type { DeviceStatus, InputDevicePlugin } from './types.js';
import { StreamDeckPlugin } from './streamdeck.js';

/**
 * Device plugin manager.
 * Handles registration, lifecycle, and communication with input device plugins.
 */
export class DeviceManager {
  private plugins: InputDevicePlugin[] = [];
  private resolveCallback?: (id: string, decision: Decision) => void;
  private resolveAllCallback?: (decision: 'allow' | 'deny') => void;

  /**
   * Set the callbacks for prompt resolution.
   * Must be called before plugins are initialized.
   */
  setCallbacks(callbacks: {
    onResolve: (id: string, decision: Decision) => void;
    onResolveAll: (decision: 'allow' | 'deny') => void;
  }): void {
    this.resolveCallback = callbacks.onResolve;
    this.resolveAllCallback = callbacks.onResolveAll;

    // Update existing plugins
    for (const plugin of this.plugins) {
      plugin.onResolve = callbacks.onResolve;
      plugin.onResolveAll = callbacks.onResolveAll;
    }
  }

  /**
   * Register a device plugin.
   */
  register(plugin: InputDevicePlugin): void {
    if (this.resolveCallback && this.resolveAllCallback) {
      plugin.onResolve = this.resolveCallback;
      plugin.onResolveAll = this.resolveAllCallback;
    }
    this.plugins.push(plugin);
  }

  /**
   * Initialize all registered plugins.
   * Errors are logged but don't prevent other plugins from initializing.
   */
  async init(): Promise<void> {
    for (const plugin of this.plugins) {
      try {
        await plugin.init();
        console.log(`[DeviceManager] Initialized plugin: ${plugin.name}`);
      } catch (err) {
        console.error(`[DeviceManager] Failed to initialize ${plugin.name}:`, err);
      }
    }
  }

  /**
   * Destroy all plugins and cleanup.
   */
  async destroy(): Promise<void> {
    for (const plugin of this.plugins) {
      try {
        await plugin.destroy();
        console.log(`[DeviceManager] Destroyed plugin: ${plugin.name}`);
      } catch (err) {
        console.error(`[DeviceManager] Failed to destroy ${plugin.name}:`, err);
      }
    }
    this.plugins = [];
  }

  /**
   * Notify all plugins of prompt list changes.
   */
  onPromptsChanged(prompts: Prompt[]): void {
    for (const plugin of this.plugins) {
      try {
        plugin.onPromptsChanged(prompts);
      } catch (err) {
        console.error(`[DeviceManager] Error in ${plugin.name}.onPromptsChanged:`, err);
      }
    }
  }

  /**
   * Notify all plugins that a prompt was resolved.
   */
  onPromptResolved(id: string): void {
    for (const plugin of this.plugins) {
      try {
        plugin.onPromptResolved(id);
      } catch (err) {
        console.error(`[DeviceManager] Error in ${plugin.name}.onPromptResolved:`, err);
      }
    }
  }

  /**
   * Get status of all connected devices.
   */
  getStatus(): DeviceStatus[] {
    return this.plugins.map((plugin) => ({
      name: plugin.name,
      connected: plugin.isConnected(),
    }));
  }

  /**
   * Check if any device is connected.
   */
  hasConnectedDevice(): boolean {
    return this.plugins.some((plugin) => plugin.isConnected());
  }
}

/**
 * Create and configure the device manager with default plugins.
 */
export function createDeviceManager(): DeviceManager {
  const manager = new DeviceManager();

  // Register Stream Deck plugin
  manager.register(new StreamDeckPlugin());

  return manager;
}

export { StreamDeckPlugin } from './streamdeck.js';
export type { DeviceStatus, InputDevicePlugin } from './types.js';
