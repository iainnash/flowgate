#!/usr/bin/env npx tsx
/**
 * Install hooks into Claude Code settings
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { homedir } from 'os';

const __dirname = dirname(fileURLToPath(import.meta.url));

interface ClaudeSettings {
  hooks?: {
    PreToolUse?: Array<{
      matcher: string;
      hooks: Array<{
        type: string;
        command: string;
        timeout: number;
      }>;
    }>;
  };
  [key: string]: unknown;
}

const hookScript = join(__dirname, 'run-hook.sh');
const settingsDir = join(homedir(), '.claude');
const settingsFile = join(settingsDir, 'settings.json');

// Ensure .claude directory exists
mkdirSync(settingsDir, { recursive: true });

// Read existing settings or create empty object
let settings: ClaudeSettings = {};
if (existsSync(settingsFile)) {
  try {
    settings = JSON.parse(readFileSync(settingsFile, 'utf-8'));
  } catch {
    console.warn('Could not parse existing settings, starting fresh');
  }
}

// Add hook configuration
settings.hooks = settings.hooks ?? {};
settings.hooks.PreToolUse = [
  {
    matcher: '*',
    hooks: [
      {
        type: 'command',
        command: hookScript,
        timeout: 120,
      },
    ],
  },
];

// Write settings
writeFileSync(settingsFile, JSON.stringify(settings, null, 2));
console.log(`Hooks installed to ${settingsFile}`);
console.log(`Hook command: ${hookScript}`);
