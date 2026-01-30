#!/bin/bash

set -e

cd "$(dirname "$0")"

echo "Building ClaudePrompt..."

# Build for release
swift build -c release

echo ""
echo "Build complete!"
echo "Executable: .build/release/ClaudePrompt"
echo ""
echo "To run: swift run ClaudePrompt"
echo "Or directly: .build/release/ClaudePrompt"
