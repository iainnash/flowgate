#!/bin/bash
set -e

# Release script for Flowgate
# Creates a GitHub release and uploads the DMG

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"
DMG_PATH="$BUILD_DIR/Flowgate.dmg"

# Get version from Info.plist or use argument
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    # Try to get from git tag
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
fi

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "  e.g., $0 v1.0.0"
    exit 1
fi

# Ensure version starts with 'v'
if [[ ! "$VERSION" =~ ^v ]]; then
    VERSION="v$VERSION"
fi

echo "=== Flowgate Release Script ==="
echo ""
echo "Version: $VERSION"
echo ""

# Check if DMG exists
if [ ! -f "$DMG_PATH" ]; then
    echo "DMG not found at $DMG_PATH"
    echo "Run ./scripts/build-app.sh first"
    exit 1
fi

# Check if gh CLI is available
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) not found. Install with: brew install gh"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo "Not authenticated with GitHub. Run: gh auth login"
    exit 1
fi

# Create git tag if it doesn't exist
if ! git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo "Creating git tag $VERSION..."
    git tag -a "$VERSION" -m "Release $VERSION"
    git push origin "$VERSION"
else
    echo "Tag $VERSION already exists"
fi

# Check if release already exists
if gh release view "$VERSION" &>/dev/null; then
    echo "Release $VERSION already exists."
    read -p "Do you want to update it? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
    echo "Deleting existing release..."
    gh release delete "$VERSION" --yes
fi

# Create release notes
RELEASE_NOTES=$(cat <<EOF
## Flowgate $VERSION

### Installation

1. Download \`Flowgate.dmg\` below
2. Open the DMG and drag Flowgate to Applications
3. Launch Flowgate from Applications

### First Launch Setup

On first launch, Flowgate will show setup instructions with the path to the Claude Code hook.

Add to \`~/.config/claude/settings.json\`:

\`\`\`json
{
  "hooks": {
    "PreToolUse": "/Applications/Flowgate.app/Contents/Resources/prompt-hook"
  }
}
\`\`\`

### What's New

See [CHANGES.md](docs/CHANGES.md) for full changelog.
EOF
)

# Create release
echo "Creating GitHub release $VERSION..."
gh release create "$VERSION" \
    --title "Flowgate $VERSION" \
    --notes "$RELEASE_NOTES" \
    "$DMG_PATH"

echo ""
echo "=== Release Complete ==="
echo ""
echo "Release URL: $(gh release view "$VERSION" --json url -q .url)"
echo ""
