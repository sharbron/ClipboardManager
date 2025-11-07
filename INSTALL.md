# Clipboard Manager - Installation Guide

A secure, native macOS clipboard history manager.

## Features
- 🔐 AES-256 encrypted clipboard storage
- 📋 Menu bar access to clipboard history with date grouping
- ⌨️ Global hotkey (Cmd+Shift+V) and quick access (Cmd+1-9)
- 🔍 Enhanced search with filters and sorting
- 📌 Pin important clips to keep them at the top
- 🖼️ Image support with thumbnails
- 🗑️ Smart cleanup options
- ⚡ Native Swift - fast and lightweight

## Installation

### Easy Install (Recommended)

1. **Download** `ClipboardManager-1.0.dmg`
2. **Open** the DMG file (double-click)
3. **Drag** `ClipboardManager.app` to your Applications folder
4. **IMPORTANT:** Don't double-click the app yet! Follow step 5 first.
5. **Remove quarantine** (required for unsigned apps):
   - Open Terminal
   - Run: `xattr -cr /Applications/ClipboardManager.app`
   - Or right-click the app → Open → Open Anyway (when macOS warns)
6. **Open** ClipboardManager from Applications
7. **Grant permissions** if macOS asks (the app needs accessibility access)

### Why the Extra Step?

This app is not code-signed (which requires a $99/year Apple Developer account). macOS blocks unsigned apps downloaded from the internet as a security measure. The `xattr -cr` command simply tells macOS "I trust this app."

### Auto-Start on Login (Optional)

To have Clipboard Manager start automatically when you log in:

1. Open **System Settings** → **General** → **Login Items**
2. Click the **+** button
3. Select **ClipboardManager** from Applications
4. Done! It will now start automatically

**OR** use the terminal:

```bash
# Copy this launch agent file
cat > ~/Library/LaunchAgents/com.clipboard.manager.swift.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.clipboard.manager.swift</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/ClipboardManager.app/Contents/MacOS/ClipboardManager</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

# Load it
launchctl load ~/Library/LaunchAgents/com.clipboard.manager.swift.plist
```

## Usage

1. **Click the clipboard icon** in your menu bar (or press Cmd+Shift+V)
2. **Select a clip** to restore it to your clipboard
3. **Use Cmd+1 to Cmd+9** for quick access to recent items
4. **Right-click items** to pin or delete them
5. **Hover over items** to see preview tooltips
6. **Search** to find specific clips with filters and sorting
7. **Preferences** to adjust retention period and manage history

## System Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac

## Security & Privacy

- All clipboard data is encrypted with AES-256
- Encryption key stored securely in macOS Keychain
- Database location: `~/.clipboard_history.db`
- Only accessible by your user account

## Uninstallation

1. **Remove from Login Items** (if added)
2. **Quit** the app from menu bar
3. **Delete** from Applications folder
4. **Optional**: Remove data
   ```bash
   rm ~/.clipboard_history.db
   launchctl unload ~/Library/LaunchAgents/com.clipboard.manager.swift.plist
   rm ~/Library/LaunchAgents/com.clipboard.manager.swift.plist
   ```

## Troubleshooting

**Icon not showing in menu bar?**
- Make sure the app is running (check Activity Monitor)
- Try restarting the app

**"App can't be opened because it is from an unidentified developer" or "App is damaged"?**

This is normal for unsigned apps. Two solutions:

**Option 1 (Easiest):**
```bash
xattr -cr /Applications/ClipboardManager.app
```
Then open the app normally.

**Option 2:**
- Right-click the app → Open → Open Anyway
- Or go to System Settings → Privacy & Security → Open Anyway

**Clips not appearing?**
- Copy some text first
- Click the menu bar icon to refresh

## Support

Found a bug or have a feature request? Please open an issue on GitHub.

## License

MIT License - Free to use and modify
