#!/usr/bin/env npx tsx
/**
 * Claude Code PreToolUse hook that sends prompts to UI server
 */

interface HookInput {
  session_id: string;
  tool_name: string;
  tool_input: Record<string, unknown>;
  hook_event_name: string;
  cwd: string;
}

interface ServerResponse {
  decision: 'allow' | 'deny' | 'ask';
  reason?: string;
  updatedInput?: Record<string, unknown>;
}

interface HookOutput {
  hookSpecificOutput: {
    hookEventName: string;
    permissionDecision: 'allow' | 'deny' | 'ask';
    permissionDecisionReason?: string;
    updatedInput?: Record<string, unknown>;
  };
}

const SERVER_URL = process.env.CLAUDE_PROMPT_UI_SERVER ?? 'http://127.0.0.1:8888';
const TIMEOUT_MS = parseInt(process.env.CLAUDE_PROMPT_UI_TIMEOUT ?? '120000', 10);

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf-8');
}

function output(data: HookOutput): void {
  console.log(JSON.stringify(data));
}

function fallbackToTerminal(reason: string): void {
  output({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'ask',
      permissionDecisionReason: reason,
    },
  });
}

async function main(): Promise<void> {
  let inputJson: string;

  try {
    inputJson = await readStdin();
    JSON.parse(inputJson) as HookInput; // Validate JSON
  } catch {
    fallbackToTerminal('Failed to parse hook input');
    return;
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const response = await fetch(`${SERVER_URL}/api/prompt`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: inputJson,
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      fallbackToTerminal(`Server returned ${response.status}`);
      return;
    }

    const result = (await response.json()) as ServerResponse;

    if (result.decision === 'allow') {
      output({
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          permissionDecision: 'allow',
          ...(result.updatedInput && { updatedInput: result.updatedInput }),
        },
      });
    } else if (result.decision === 'deny') {
      output({
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          permissionDecision: 'deny',
          permissionDecisionReason: result.reason ?? 'Denied by user',
        },
      });
    } else {
      fallbackToTerminal('User chose to decide in terminal');
    }
  } catch (err) {
    clearTimeout(timeoutId);
    const message = err instanceof Error && err.name === 'AbortError'
      ? 'Request timeout - UI server not responding'
      : `Server unreachable: ${err}`;
    fallbackToTerminal(message);
  }
}

main();
