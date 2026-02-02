# Claude Code Hooks

This directory contains hooks for Claude Code integration.

## Go Hook (Recommended)

The Go hook (`prompt-hook.go`) is a standalone binary that communicates with the Go server using camelCase JSON fields.

### Building

```bash
cd hooks
make build
```

Or build with optimizations:
```bash
make build-release
```

### Configuration

Add to your Claude Code settings (`~/.config/claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": "/absolute/path/to/claude-prompt-ui/hooks/prompt-hook"
  }
}
```

### Environment Variables

- `CLAUDE_PROMPT_UI_SERVER`: Server URL (default: `http://127.0.0.1:8888`)
- `CLAUDE_PROMPT_UI_TIMEOUT`: Request timeout in milliseconds (default: `120000`)

## TypeScript Hook (Legacy)

The TypeScript hook (`prompt-hook.ts`) requires Node.js and pnpm. It uses snake_case fields for compatibility with older servers.

### Usage

```bash
pnpm install
npx tsx prompt-hook.ts
```

### Configuration

Same as Go hook, but use the TypeScript file:

```json
{
  "hooks": {
    "PreToolUse": "/absolute/path/to/claude-prompt-ui/hooks/prompt-hook.ts"
  }
}
```

Note: Ensure the shebang line (`#!/usr/bin/env npx tsx`) is present and the file is executable.
