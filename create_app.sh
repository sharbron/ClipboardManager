#!/bin/bash
# Script to create a macOS app bundle for ClipboardManager

set -e

# Resolve relative paths from this project even when invoked by absolute path elsewhere.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

APP_NAME="ClipboardManager"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

# Release automation can supply the tag version before the bundle is signed.
if [ -n "${APP_VERSION:-}" ] && [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "Error: Invalid APP_VERSION: $APP_VERSION" >&2
    exit 1
fi

# Installing to /Applications is part of a normal build. Skip it with either:
#   ./create_app.sh --no-install
#   SKIP_INSTALL=1 ./create_app.sh
if [ "${1:-}" = "--no-install" ]; then
    SKIP_INSTALL=1
fi

echo "Building ${APP_NAME}..."
echo ""

# Run SwiftLint if available
if command -v swiftlint &> /dev/null; then
    echo "🔍 Running SwiftLint..."
    swiftlint --config .swiftlint.yml
    echo "✅ SwiftLint passed"
    echo ""
else
    echo "⚠️  SwiftLint not found - skipping code quality checks"
    echo "   Install with: brew install swiftlint"
    echo ""
fi

# Build release version using Swift Package Manager
echo "Building release version..."
swift build -c release

# Create app bundle structure
APP_BUNDLE="${APP_NAME}.app"
APP_DIR="$APP_BUNDLE/Contents"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

# Copy executable
echo "Creating app bundle..."
cp .build/release/$APP_NAME "$APP_DIR/MacOS/"

# Copy Info.plist
cp Info.plist "$APP_DIR/"
if [ -n "${APP_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_DIR/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$APP_DIR/Info.plist"
fi

# Copy app icon
if [ -f "AppIcon.icns" ]; then
    echo "Copying app icon..."
    cp AppIcon.icns "$APP_DIR/Resources/"
fi

# Clear quarantine attributes to avoid "damaged" warnings
xattr -cr "$APP_BUNDLE"

# ---------------------------------------------------------------------------
# Code signing
# ---------------------------------------------------------------------------
#
# A real certificate matters for more than distribution. TCC binds an app's Accessibility
# grant to its *designated requirement*, and an ad-hoc signature's requirement is literally
# the content hash:
#
#   ad-hoc:  designated => cdhash H"5a568b52..."      (changes every build)
#   signed:  designated => identifier "com.clipboard.manager" and anchor apple generic
#                          and certificate leaf[subject.CN] = "Apple Development: ..."
#
# So an ad-hoc build looks like a brand new app to macOS every single time and silently
# loses its permission. A signed build keeps it.
#
# Override the choice with: SIGN_IDENTITY="Developer ID Application: ..." ./create_app.sh
detect_signing_identity() {
    if [ -n "${SIGN_IDENTITY:-}" ]; then
        printf '%s' "$SIGN_IDENTITY"
        return
    fi
    # Developer ID first (the only one that can be notarized for distribution), then a
    # development certificate, which is enough to keep permissions on this machine.
    local available prefix found
    available=$(security find-identity -v -p codesigning 2>/dev/null || true)
    for prefix in "Developer ID Application" "Apple Development" "Mac Developer"; do
        found=$(printf '%s' "$available" | sed -n "s/.*\"\($prefix[^\"]*\)\".*/\1/p" | head -1)
        if [ -n "$found" ]; then
            printf '%s' "$found"
            return
        fi
    done
    printf '%s' "-"
}

SIGN_ID=$(detect_signing_identity)

if [ "$SIGN_ID" = "-" ]; then
    echo "⚠️  No signing certificate found — using an ad-hoc signature."
    echo "   Accessibility permission will need re-granting after every build."
    codesign --force --sign - "$APP_BUNDLE"
    SIGNED_PROPERLY=0
else
    echo "Code signing as: $SIGN_ID"
    # Hardened runtime is required for notarization later and costs nothing now.
    # --timestamp needs the network and is only required for distribution, so it is
    # limited to Developer ID builds.
    if [[ "$SIGN_ID" == "Developer ID Application"* ]]; then
        codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP_BUNDLE"
    else
        codesign --force --options runtime --sign "$SIGN_ID" "$APP_BUNDLE"
    fi
    SIGNED_PROPERLY=1
fi

# Fail loudly rather than shipping a bundle that will not launch.
codesign --verify --strict "$APP_BUNDLE"

echo ""
echo "✅ App bundle created: $APP_BUNDLE"
echo ""

# ---------------------------------------------------------------------------
# Install to /Applications
# ---------------------------------------------------------------------------
#
# macOS resolves launches by bundle identifier, so launching from Spotlight, the Dock or a
# login item runs the installed copy, not the one just built here. Installing on every
# build keeps the two in step.

INSTALLED_APP="$INSTALL_DIR/$APP_BUNDLE"

if [ "${SKIP_INSTALL:-0}" = "1" ]; then
    echo "⏭️  Skipping install (--no-install). Copy manually with:"
    echo "     ditto $APP_BUNDLE $INSTALLED_APP"
    echo ""
    exit 0
fi

if [ ! -w "$INSTALL_DIR" ]; then
    echo "⚠️  $INSTALL_DIR is not writable — leaving the bundle in place."
    echo "   Install it yourself with:"
    echo "     sudo ditto $APP_BUNDLE $INSTALLED_APP"
    echo ""
    exit 0
fi

# Refuse to replace an app that isn't ours, rather than clobbering a name collision.
if [ -d "$INSTALLED_APP" ]; then
    EXISTING_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
        "$INSTALLED_APP/Contents/Info.plist" 2>/dev/null || echo "")
    OUR_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
        "$APP_BUNDLE/Contents/Info.plist")
    if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "$OUR_ID" ]; then
        echo "⚠️  $INSTALLED_APP already exists and is a different app ($EXISTING_ID)."
        echo "   Not replacing it. Move it aside first, or use --no-install."
        echo ""
        exit 1
    fi
fi

# A running bundle cannot be replaced safely, and the old process would keep running
# the old code. Quit every copy, and note whether one was running so it can come back.
# Ask politely first so the app can close its databases, then fall back to a signal.
WAS_RUNNING=0
if pgrep -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" > /dev/null 2>&1; then
    WAS_RUNNING=1
    echo "Quitting running ${APP_NAME}..."
    osascript -e "quit app \"$APP_NAME\"" > /dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" > /dev/null 2>&1 || break
        sleep 0.3
    done
    pkill -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" || true
    # Give it a moment to exit before the bundle is swapped underneath it.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" > /dev/null 2>&1 || break
        sleep 0.3
    done
fi

# Stage alongside the target and swap, so a failed copy cannot leave a half-written
# app where the old working one used to be. ditto (not cp -r) preserves the bundle's
# extended attributes and code signature.
STAGING="$INSTALL_DIR/.${APP_BUNDLE}.staging.$$"
cleanup_staging() { rm -rf "$STAGING"; }
trap cleanup_staging EXIT

echo "Installing to $INSTALLED_APP..."
rm -rf "$STAGING"
ditto "$APP_BUNDLE" "$STAGING"
rm -rf "$INSTALLED_APP"
mv "$STAGING" "$INSTALLED_APP"
trap - EXIT

xattr -cr "$INSTALLED_APP"

echo "✅ Installed: $INSTALLED_APP"
echo ""

if [ "$WAS_RUNNING" = "1" ]; then
    echo "Relaunching ${APP_NAME}..."
    open "$INSTALLED_APP"
    echo ""
fi

if [ "$SIGNED_PROPERLY" = "1" ]; then
    echo "Signed with a stable identity, so the Accessibility grant survives rebuilds."
    echo "You only need to approve it once, in System Settings > Privacy & Security >"
    echo "Accessibility. (Approve it again if you ever switch signing certificate — the"
    echo "grant is tied to the certificate.)"
else
    echo "⚠️  Accessibility permission must be re-granted after every build."
    echo "   An ad-hoc signature's designated requirement is the code hash, so macOS treats"
    echo "   each build as a new app and drops its existing grant. Until you re-approve it in"
    echo "   System Settings > Privacy & Security > Accessibility, the ⌘⇧Space hotkey will do nothing."
fi
echo ""
echo "To start it automatically: System Settings > General > Login Items"
echo ""
