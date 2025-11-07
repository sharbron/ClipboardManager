#!/bin/bash
# Script to create a macOS app bundle

set -e

echo "Building ClipboardManager..."

# Run SwiftLint
if command -v swiftlint &> /dev/null; then
    echo "Running SwiftLint..."
    swiftlint
    echo ""
else
    echo "⚠️  SwiftLint not installed. Install with: brew install swiftlint"
    echo ""
fi

# Build release version
swift build -c release

# Create app bundle structure
APP_NAME="ClipboardManager.app"
APP_DIR="$APP_NAME/Contents"

rm -rf "$APP_NAME"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

# Copy executable
cp .build/release/ClipboardManager "$APP_DIR/MacOS/"

# Copy Info.plist
cp Info.plist "$APP_DIR/"

# Copy app icon (ICNS)
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_DIR/Resources/AppIcon.icns"
    echo "Copied app icon"
fi

# Copy menu bar icon (PNG) - still needed for the status bar
if [ -f "icon.png" ]; then
    cp icon.png "$APP_DIR/Resources/icon.png"
fi

echo ""
echo "✅ App bundle created: $APP_NAME"
echo ""
echo "To install:"
echo "  1. Open $APP_NAME to test"
echo "  2. Copy to Applications: cp -r $APP_NAME /Applications/"
echo "  3. Add to Login Items in System Settings"
echo ""
