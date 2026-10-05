#!/bin/bash
# Create a DMG installer for ClipboardManager distribution

set -e

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

APP_NAME="ClipboardManager"
SOURCE_APP="${APP_NAME}.app"

# Make sure app exists
if [ ! -d "$SOURCE_APP" ]; then
    echo "Error: ${SOURCE_APP} not found. Run ./create_app.sh first."
    exit 1
fi

# The signed bundle is the source of truth for the installer version.
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SOURCE_APP/Contents/Info.plist")
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "Error: Invalid app version: $VERSION" >&2
    exit 1
fi
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
VOLUME_NAME="${APP_NAME} ${VERSION}"

# Stage the contents and image together. A failed build leaves the previous DMG intact.
DMG_WORK_DIR=$(mktemp -d)
cleanup() { rm -rf "$DMG_WORK_DIR"; }
trap cleanup EXIT
TMP_DIR="$DMG_WORK_DIR/contents"
mkdir "$TMP_DIR"
echo "Creating DMG in temporary directory: $TMP_DIR"

# Copy app to temp directory
ditto "$SOURCE_APP" "$TMP_DIR/$SOURCE_APP"

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
    "$DMG_WORK_DIR/$DMG_NAME"

xattr -cr "$DMG_WORK_DIR/$DMG_NAME"
mv -f "$DMG_WORK_DIR/$DMG_NAME" "$DMG_NAME"

echo ""
echo "✅ DMG created: $DMG_NAME"
echo ""
echo "To distribute:"
echo "  1. Upload ${DMG_NAME} to GitHub releases or file sharing"
echo "  2. Users download and open the DMG"
echo "  3. Users drag ${APP_NAME}.app to Applications folder"
echo "  4. Users grant Accessibility permissions on first launch"
echo ""
echo "Note: For distribution outside the Mac App Store, consider:"
echo "  - Getting a Developer ID certificate for proper code signing"
echo "  - Notarizing the app with Apple"
echo ""
