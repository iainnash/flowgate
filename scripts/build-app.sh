#!/bin/bash
set -e

# Build script for Flowgate macOS app with embedded server
# This script builds universal binaries (arm64 + x86_64) of the Go components
# and bundles everything into the Swift app

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GO_SERVER_DIR="$PROJECT_ROOT/go-server"
HOOKS_DIR="$PROJECT_ROOT/hooks"
NATIVE_APP_DIR="$PROJECT_ROOT/native-app/ClaudePrompt"
BUILD_DIR="$PROJECT_ROOT/build"

echo "=== Flowgate Build Script ==="
echo ""

# Create build directory
mkdir -p "$BUILD_DIR"

# Step 1: Build Go server (universal binary)
echo "Step 1: Building Go server..."
cd "$GO_SERVER_DIR"

echo "  Building for arm64..."
GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o "$BUILD_DIR/flowgate-server-arm64"

echo "  Building for amd64..."
GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o "$BUILD_DIR/flowgate-server-amd64"

echo "  Creating universal binary..."
lipo -create \
    "$BUILD_DIR/flowgate-server-arm64" \
    "$BUILD_DIR/flowgate-server-amd64" \
    -output "$BUILD_DIR/flowgate-server"

# Clean up architecture-specific binaries
rm "$BUILD_DIR/flowgate-server-arm64" "$BUILD_DIR/flowgate-server-amd64"

# Make executable
chmod +x "$BUILD_DIR/flowgate-server"

echo "  Server binary: $BUILD_DIR/flowgate-server"
echo ""

# Step 2: Build prompt-hook (universal binary)
echo "Step 2: Building prompt-hook..."
cd "$HOOKS_DIR"

echo "  Building for arm64..."
GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o "$BUILD_DIR/prompt-hook-arm64" prompt-hook.go

echo "  Building for amd64..."
GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o "$BUILD_DIR/prompt-hook-amd64" prompt-hook.go

echo "  Creating universal binary..."
lipo -create \
    "$BUILD_DIR/prompt-hook-arm64" \
    "$BUILD_DIR/prompt-hook-amd64" \
    -output "$BUILD_DIR/prompt-hook"

# Clean up architecture-specific binaries
rm "$BUILD_DIR/prompt-hook-arm64" "$BUILD_DIR/prompt-hook-amd64"

# Make executable
chmod +x "$BUILD_DIR/prompt-hook"

echo "  Hook binary: $BUILD_DIR/prompt-hook"
echo ""

# Step 3: Build Web UI
echo "Step 3: Building Web UI..."
cd "$PROJECT_ROOT/ui"
pnpm build
echo ""

# Step 4: Build Swift app
echo "Step 4: Building Swift app..."
cd "$NATIVE_APP_DIR"

# Build release version
swift build -c release

# Find the built app
SWIFT_BUILD_DIR="$NATIVE_APP_DIR/.build/release"
APP_BINARY="$SWIFT_BUILD_DIR/ClaudePrompt"
if [ ! -f "$APP_BINARY" ]; then
    APP_BINARY="$SWIFT_BUILD_DIR/Flowgate"
fi

if [ ! -f "$APP_BINARY" ]; then
    echo "Error: Swift build failed - binary not found at $APP_BINARY"
    exit 1
fi

echo "  Swift binary: $APP_BINARY"
echo ""

# Step 5: Create app bundle
echo "Step 5: Creating app bundle..."
APP_BUNDLE="$BUILD_DIR/Flowgate.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Remove old bundle if exists
rm -rf "$APP_BUNDLE"

# Create directory structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$APP_BINARY" "$MACOS_DIR/Flowgate"

# Copy server binary to Resources
cp "$BUILD_DIR/flowgate-server" "$RESOURCES_DIR/flowgate-server"
chmod +x "$RESOURCES_DIR/flowgate-server"

# Copy hook binary to Resources (for Claude Code integration)
cp "$BUILD_DIR/prompt-hook" "$RESOURCES_DIR/prompt-hook"
chmod +x "$RESOURCES_DIR/prompt-hook"
echo "  Hook binary: $RESOURCES_DIR/prompt-hook"

# Copy web UI public files to Resources (for embedded server)
cp -r "$GO_SERVER_DIR/public" "$RESOURCES_DIR/public"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Flowgate</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.flowgate.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Flowgate</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
EOF

echo "  App bundle: $APP_BUNDLE"
echo ""

# Step 6: Create app icon
echo "Step 6: Creating app icon..."
ICON_SOURCE="$PROJECT_ROOT/docs/flowgate-icon-1024x1024.png"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

# Function to create icon with padding and rounded corners (Apple HIG compliant)
# - ~10% padding on each side (icon content is 80% of canvas)
# - ~22% corner radius relative to content size
create_rounded_icon() {
    local size=$1
    local output=$2
    local content_size=$(echo "$size * 0.80" | bc | cut -d. -f1)
    local radius=$(echo "$content_size * 0.2237" | bc | cut -d. -f1)
    local tmp_resized="/tmp/icon_resized_$size.png"
    local tmp_mask="/tmp/icon_mask_$size.png"
    local tmp_content="/tmp/icon_content_$size.png"

    # Step 1: Resize source image
    magick "$ICON_SOURCE" -resize ${content_size}x${content_size} "$tmp_resized"

    # Step 2: Create rounded rectangle mask
    magick -size ${content_size}x${content_size} xc:none \
        -fill white -draw "roundrectangle 0,0,$((content_size-1)),$((content_size-1)),$radius,$radius" \
        "$tmp_mask"

    # Step 3: Apply mask as alpha channel
    magick "$tmp_resized" \( "$tmp_mask" -alpha copy \) -compose CopyOpacity -composite "$tmp_content"

    # Step 4: Center on transparent canvas for padding
    magick "$tmp_content" -gravity center -background none -extent ${size}x${size} PNG32:"$output"

    # Cleanup temp files
    rm -f "$tmp_resized" "$tmp_mask" "$tmp_content"
}

if [ -f "$ICON_SOURCE" ]; then
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    # Generate all required icon sizes with rounded corners
    echo "  Generating rounded icons..."
    create_rounded_icon 16   "$ICONSET_DIR/icon_16x16.png"
    create_rounded_icon 32   "$ICONSET_DIR/icon_16x16@2x.png"
    create_rounded_icon 32   "$ICONSET_DIR/icon_32x32.png"
    create_rounded_icon 64   "$ICONSET_DIR/icon_32x32@2x.png"
    create_rounded_icon 128  "$ICONSET_DIR/icon_128x128.png"
    create_rounded_icon 256  "$ICONSET_DIR/icon_128x128@2x.png"
    create_rounded_icon 256  "$ICONSET_DIR/icon_256x256.png"
    create_rounded_icon 512  "$ICONSET_DIR/icon_256x256@2x.png"
    create_rounded_icon 512  "$ICONSET_DIR/icon_512x512.png"
    create_rounded_icon 1024 "$ICONSET_DIR/icon_512x512@2x.png"

    # Convert to icns
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
    rm -rf "$ICONSET_DIR"

    echo "  App icon: $RESOURCES_DIR/AppIcon.icns"
else
    echo "  Warning: Icon source not found at $ICON_SOURCE"
fi
echo ""

# Step 7: Create DMG
echo "Step 7: Creating DMG..."
DMG_NAME="Flowgate"
DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"

# Remove old DMG if exists
rm -f "$DMG_PATH"

# Create temporary DMG directory
DMG_TEMP="$BUILD_DIR/dmg-temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to temp directory
cp -r "$APP_BUNDLE" "$DMG_TEMP/"

# Create symlink to Applications
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG
hdiutil create -volname "$DMG_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH"

# Clean up temp directory
rm -rf "$DMG_TEMP"

echo "  DMG: $DMG_PATH"
echo ""

# Step 8: Summary
echo "=== Build Complete ==="
echo ""
echo "App bundle: $APP_BUNDLE"
echo "DMG: $DMG_PATH"
echo ""
echo "To install:"
echo "  open \"$DMG_PATH\""
echo "  Drag 'Flowgate' to Applications"
echo ""
echo "To run directly:"
echo "  open \"$APP_BUNDLE\""
echo ""
