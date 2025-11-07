#!/bin/bash
# Create a DMG installer for distribution

set -e

APP_NAME="ClipboardManager"
VERSION="2.0"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
VOLUME_NAME="${APP_NAME} ${VERSION}"
SOURCE_APP="${APP_NAME}.app"

# Make sure app exists
if [ ! -d "$SOURCE_APP" ]; then
    echo "Error: ${SOURCE_APP} not found. Run ./create_app.sh first."
    exit 1
fi

# Remove any existing DMG
rm -f "$DMG_NAME"

# Create temporary directory
TMP_DIR=$(mktemp -d)
echo "Creating DMG in temporary directory: $TMP_DIR"

# Copy app to temp directory
cp -R "$SOURCE_APP" "$TMP_DIR/"

# Clear quarantine attributes to avoid "damaged" warnings
xattr -cr "$TMP_DIR/$SOURCE_APP"

# Copy install instructions
cp DMG_README.txt "$TMP_DIR/⚠️ READ ME FIRST.txt"

# Create symbolic link to Applications folder
ln -s /Applications "$TMP_DIR/Applications"

# Create DMG
echo "Creating DMG..."
hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$TMP_DIR" \
    -ov -format UDZO \
    "$DMG_NAME"

# Clear quarantine attribute from the DMG itself
xattr -cr "$DMG_NAME"

# Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "✅ DMG created: $DMG_NAME"
echo ""
echo "To distribute:"
echo "  1. Upload ${DMG_NAME} to GitHub releases or file sharing"
echo "  2. Users download and open the DMG"
echo "  3. Users drag ${APP_NAME}.app to Applications folder"
echo ""
