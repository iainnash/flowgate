#!/usr/bin/env bash
# Hook entrypoint - fast Node.js environment setup

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

# Use NVM if available (most common setup)
if [[ -n "${NVM_DIR:-}" && -s "$NVM_DIR/nvm.sh" ]]; then
  source "$NVM_DIR/nvm.sh" --no-use
  nvm use default --silent 2>/dev/null || true
elif [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  export NVM_DIR="$HOME/.nvm"
  source "$NVM_DIR/nvm.sh" --no-use
  nvm use default --silent 2>/dev/null || true
fi

# Run the hook using local tsx
exec "$HOOK_DIR/node_modules/.bin/tsx" "$HOOK_DIR/prompt-hook.ts"
