import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { spawn } from 'child_process';
import { createServer, type Server, type IncomingMessage, type ServerResponse } from 'http';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const hookPath = join(__dirname, '..', 'prompt-hook.ts');

describe('prompt-hook', () => {
  let mockServer: Server;
  let serverPort: number;

  beforeEach(async () => {
    mockServer = createServer((req: IncomingMessage, res: ServerResponse) => {
      let body = '';
      req.on('data', (chunk: Buffer) => (body += chunk));
      req.on('end', () => {
        const input = JSON.parse(body);

        if (input.tool_name === 'DangerousTool') {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ decision: 'deny', reason: 'Blocked' }));
        } else if (input.tool_name === 'ModifyTool') {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(
            JSON.stringify({
              decision: 'allow',
              updatedInput: { ...input.tool_input, modified: true },
            })
          );
        } else if (input.tool_name === 'AskTool') {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ decision: 'ask' }));
        } else {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ decision: 'allow' }));
        }
      });
    });

    await new Promise<void>((resolve) => {
      mockServer.listen(0, '127.0.0.1', () => {
        const addr = mockServer.address() as { port: number };
        serverPort = addr.port;
        resolve();
      });
    });
  });

  afterEach(() => {
    mockServer?.close();
  });

  function runHook(
    input: object
  ): Promise<{ stdout: string; stderr: string; code: number }> {
    return new Promise((resolve) => {
      const child = spawn('npx', ['tsx', hookPath], {
        env: {
          ...process.env,
          CLAUDE_PROMPT_UI_SERVER: `http://127.0.0.1:${serverPort}`,
        },
      });

      let stdout = '';
      let stderr = '';

      child.stdout.on('data', (data: Buffer) => (stdout += data));
      child.stderr.on('data', (data: Buffer) => (stderr += data));
      child.stdin.write(JSON.stringify(input));
      child.stdin.end();

      child.on('close', (code) =>
        resolve({ stdout, stderr, code: code ?? 0 })
      );
    });
  }

  it('should return allow decision for normal tools', async () => {
    const result = await runHook({
      session_id: 'test',
      tool_name: 'Bash',
      tool_input: { command: 'ls' },
      hook_event_name: 'PreToolUse',
      cwd: '/tmp',
    });

    expect(result.code).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe('allow');
  });

  it('should return deny decision with reason', async () => {
    const result = await runHook({
      session_id: 'test',
      tool_name: 'DangerousTool',
      tool_input: {},
      hook_event_name: 'PreToolUse',
      cwd: '/tmp',
    });

    expect(result.code).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe('deny');
    expect(output.hookSpecificOutput.permissionDecisionReason).toBe('Blocked');
  });

  it('should include updatedInput when server modifies input', async () => {
    const result = await runHook({
      session_id: 'test',
      tool_name: 'ModifyTool',
      tool_input: { original: 'value' },
      hook_event_name: 'PreToolUse',
      cwd: '/tmp',
    });

    expect(result.code).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe('allow');
    expect(output.hookSpecificOutput.updatedInput.modified).toBe(true);
  });

  it('should fallback to ask when server returns ask', async () => {
    const result = await runHook({
      session_id: 'test',
      tool_name: 'AskTool',
      tool_input: {},
      hook_event_name: 'PreToolUse',
      cwd: '/tmp',
    });

    expect(result.code).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe('ask');
  });

  it('should fallback to ask when server is unreachable', async () => {
    mockServer.close();

    const result = await runHook({
      session_id: 'test',
      tool_name: 'Bash',
      tool_input: {},
      hook_event_name: 'PreToolUse',
      cwd: '/tmp',
    });

    expect(result.code).toBe(0);
    const output = JSON.parse(result.stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe('ask');
    expect(output.hookSpecificOutput.permissionDecisionReason).toContain(
      'unreachable'
    );
  });

  it('should handle malformed stdin gracefully', async () => {
    const child = spawn('npx', ['tsx', hookPath], {
      env: {
        ...process.env,
        CLAUDE_PROMPT_UI_SERVER: `http://127.0.0.1:${serverPort}`,
      },
    });

    let stdout = '';
    child.stdout.on('data', (data: Buffer) => (stdout += data));
    child.stdin.write('not valid json');
    child.stdin.end();

    await new Promise((resolve) => child.on('close', resolve));

    const output = JSON.parse(stdout);
    expect(output.hookSpecificOutput.permissionDecision).toBe('ask');
    expect(output.hookSpecificOutput.permissionDecisionReason).toContain(
      'parse'
    );
  });
});
