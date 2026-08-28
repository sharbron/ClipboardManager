#!/bin/bash
# Script to create a macOS app bundle
#
# The bundle is built here in the repo, but macOS resolves launches by bundle identifier -
# so if a copy is also installed in /Applications, launching from Spotlight, the Dock or a
# login item runs THAT one, whatever you just built here. Use --install to keep them in step;
# without it, this script warns when the installed copy has fallen behind.

set -euo pipefail

APP_NAME="ClipboardManager.app"
APP_DIR="$APP_NAME/Contents"
INSTALLED="/Applications/$APP_NAME"
BINARY_PATH="Contents/MacOS/ClipboardManager"

INSTALL=false
RUN=false

usage() {
    cat <<'USAGE'
Usage: ./create_app.sh [--install] [--run]

  --install   Replace /Applications/ClipboardManager.app with the build produced here.
              Quits the app first if it is running.
  --run       Launch the app when finished (the installed copy if --install was used).
  -h, --help  Show this message.

With no options the bundle is built in the repo only, and the script warns if the
copy in /Applications no longer matches.
USAGE
}

for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --run)     RUN=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; echo >&2; usage >&2; exit 1 ;;
    esac
done

quit_if_running() {
    if pgrep -f "$BINARY_PATH" >/dev/null 2>&1; then
        echo "Quitting the running instance..."
        osascript -e 'quit app "ClipboardManager"' >/dev/null 2>&1 || true
        for _ in 1 2 3 4 5; do
            pgrep -f "$BINARY_PATH" >/dev/null 2>&1 || break
            sleep 1
        done
    fi
}

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

if [ "$INSTALL" = true ]; then
    echo ""
    quit_if_running
    echo "Installing to $INSTALLED ..."
    ditto "$APP_NAME" "$INSTALLED"
    echo "✅ Installed"
    echo ""
    echo "Note: replacing an unsigned app can reset its Accessibility permission."
    echo "If the ⌘⇧Space hotkey stops working, re-approve it in"
    echo "System Settings > Privacy & Security > Accessibility."
elif [ -d "$INSTALLED" ]; then
    # Guard against the trap this script used to leave open: a stale installed copy that
    # wins the launch even though a newer build sits right here.
    if cmp -s "$APP_NAME/$BINARY_PATH" "$INSTALLED/$BINARY_PATH"; then
        echo "   /Applications copy is up to date."
    else
        echo ""
        echo "⚠️  /Applications/$APP_NAME differs from this build."
        echo "   Launching from Spotlight, the Dock, or a login item will run the OLD one."
        echo "   Run './create_app.sh --install' to update it."
    fi
fi

if [ "$RUN" = true ]; then
    echo ""
    if [ "$INSTALL" = true ]; then
        quit_if_running
        echo "Launching installed app..."
        open -a "$INSTALLED"
    else
        quit_if_running
        echo "Launching local build..."
        open "./$APP_NAME"
    fi
fi

echo ""
if [ "$INSTALL" != true ]; then
    echo "To install: ./create_app.sh --install"
fi
echo "To start at login: System Settings > General > Login Items"
echo ""
