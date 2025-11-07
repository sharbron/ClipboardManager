# ClipboardManager - Development Notes

## Project Overview

ClipboardManager is a secure, native macOS menu bar application that monitors and stores clipboard history with full-text search capabilities and AES-256 encryption.

**Platform**: macOS 13.0+ (Ventura and later)
**Language**: Swift 5.9
**Framework**: SwiftUI
**Build System**: Swift Package Manager

## Architecture

### Core Components

1. **ClipboardManagerApp** - Main app entry point and menu bar integration
2. **AppDelegate** - App lifecycle, global hotkeys, and initialization
3. **AppState** - Global state management for database, preferences, and windows
4. **ClipboardDatabase** - SQLite database with AES-256-GCM encryption via CryptoKit
5. **ClipboardMonitor** - Monitors clipboard changes and saves to database
6. **WindowManager** - Manages search and preferences windows
7. **MenuBarView** - Menu bar interface with smart date grouping
8. **SearchView** - Enhanced search window with filters and bulk actions

### File Structure

```
Sources/ClipboardManager/
├── ClipboardManagerApp.swift    # App entry, menu bar, lifecycle
├── AppState.swift               # State management
├── ClipboardDatabase.swift      # Database & encryption
├── ClipboardMonitor.swift       # Clipboard monitoring
├── WindowManager.swift          # Window management
├── Info.plist                   # Bundle configuration
└── Views/
    ├── MenuBarView.swift        # Menu bar UI with date grouping
    ├── SearchView.swift         # Enhanced search interface
    ├── PreferencesView.swift    # Settings window
    └── AboutView.swift          # About window
```

## Key Features

### Clipboard Management
- **Auto-Capture**: Monitors clipboard every 0.5 seconds for changes
- **Smart Filtering**: Filters out duplicate consecutive entries
- **Image Support**: Captures and displays images with thumbnails
- **Pin Items**: Pin important clips to keep them at the top
- **Date Grouping**: Organizes clips by "Today", "Yesterday", "This Week", etc.

### Security & Encryption
- **AES-256-GCM**: Military-grade authenticated encryption
- **macOS Keychain**: Encryption key stored securely in system keychain
- **Secure Permissions**: Database file restricted to owner-only (0600)
- **Local Only**: No network access, all data stays on your Mac
- **Authenticated Encryption**: Prevents tampering with encrypted data

### User Experience
- **Global Hotkey**: Cmd+Shift+V to open menu from anywhere
- **Quick Access**: Cmd+1 through Cmd+9 for recent items
- **Enhanced Search**: Powerful search with filters, sorting, and bulk actions
- **Smart Cleanup**: Auto-cleanup with options for last 24 hours or all history
- **Quick Preview**: Hover tooltips for item previews
- **Launch at Login**: Optional auto-start using SMAppService

### Permissions
- **Accessibility**: Required for global hotkey (Cmd+Shift+V)
- Uses native macOS permission prompts only

## Recent Improvements

### Features Implemented
1. ✅ **AES-256-GCM Encryption** - All clipboard data encrypted at rest
2. ✅ **Enhanced Search** - Full window with filters, sorting, and bulk actions
3. ✅ **Pin Items** - Keep important clips at the top
4. ✅ **Image Support** - Capture and display images with thumbnails
5. ✅ **Smart Date Grouping** - Organize by Today, Yesterday, This Week, etc.
6. ✅ **Quick Access Shortcuts** - Cmd+1 through Cmd+9 for recent items
7. ✅ **Launch at Login** - Implemented using SMAppService
8. ✅ **Smart Notifications** - Modern notification system
9. ✅ **Preview Tooltips** - Hover to see quick previews

### Code Quality
- SwiftLint integration with passing checks
- Proper error handling with OSLog Logger
- Clean separation of concerns
- No force unwraps or force casts

## Building the App

### Requirements
- Xcode 15.0+
- macOS 13.0+ (Ventura)
- SwiftLint (optional): `brew install swiftlint`

### Build Commands

```bash
# Using build script (recommended)
./create_app.sh

# Manual build
swift build -c release

# Create DMG for distribution
./create_dmg.sh
```

### Build Output
- **App Bundle**: `ClipboardManager.app` (~600 KB)
- **DMG**: `ClipboardManager-1.0.dmg` (for distribution)

## Configuration

### User Preferences (via UserDefaults)

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `launchAtLogin` | Bool | false | Auto-start on login |
| `retentionDays` | Int | 30 | Days to keep clipboard history |

### Database Schema

**clips_fts** (FTS5 virtual table for full-text search):
- `id` - INTEGER PRIMARY KEY
- `content_encrypted` - BLOB (AES-256-GCM encrypted)
- `nonce` - BLOB (12-byte nonce for GCM)
- `timestamp` - INTEGER (Unix timestamp)
- `is_pinned` - INTEGER (0 or 1)
- `image_data` - BLOB (optional, for images)

Database location: `~/.clipboard_history.db`

### Encryption Details

- **Algorithm**: AES-256-GCM (Galois/Counter Mode)
- **Key Storage**: macOS Keychain with service "com.clipboardmanager.encryption"
- **Key Generation**: CryptoKit SymmetricKey (256-bit)
- **Nonce**: Random 12-byte nonce per entry (stored unencrypted)
- **Authentication**: GCM provides built-in authentication tag
- **File Permissions**: Database file set to 0600 (owner read/write only)

## Known Limitations

1. **Accessibility Permission**: Required for global hotkey. Prompts on first launch.
2. **Large Images**: Very large images may impact performance
3. **Text Only Search**: FTS5 search works on text content only, not images
4. **No Cloud Sync**: Local-only storage by design for security

## Troubleshooting

### Global Hotkey Not Working
- Check Accessibility permission: System Settings > Privacy & Security > Accessibility
- Restart the app after granting permission
- Check Console.app for error logs

### Clips Not Saving
- Make sure the app is running (check menu bar icon)
- Copy some new text to test
- Check database file exists at `~/.clipboard_history.db`

### Database Errors
- Check file permissions: `ls -la ~/.clipboard_history.db`
- Should show `-rw-------` (0600)
- If corrupted, delete database and restart app (will regenerate)

## Development Workflow

### Git Workflow
```bash
# Current branch structure
main  # Production-ready code

# Make changes and commit
git add .
git commit -m "Description of changes"
git push origin main
```

### Testing
```bash
# Run the app locally
open ClipboardManager.app

# View logs
log stream --predicate 'subsystem == "com.clipboardmanager"' --level debug

# Check for memory leaks
leaks -atExit -- .build/release/ClipboardManager
```

### Code Style
- SwiftLint enforced
- No force unwraps or force casts
- Proper error handling with os.log Logger
- Swift concurrency (@MainActor, async/await) where appropriate

## Distribution

### Unsigned Distribution (Current)
1. Build with `./create_app.sh`
2. Clear quarantine: `xattr -cr ClipboardManager.app`
3. Ad-hoc code signature applied automatically

Users must run: `xattr -cr /Applications/ClipboardManager.app` on first install.

### Signed Distribution (Future)
1. Obtain Apple Developer ID certificate ($99/year)
2. Sign: `codesign --deep --force --sign "Developer ID Application: Name" ClipboardManager.app`
3. Notarize: `xcrun notarytool submit ClipboardManager.zip`
4. Staple: `xcrun stapler staple ClipboardManager.app`

## Future Enhancements

### Potential Features
- [ ] Customizable global hotkey
- [ ] iCloud sync (optional)
- [ ] Clipboard formatting preservation
- [ ] Multi-device clipboard sharing
- [ ] Clipboard templates/snippets
- [ ] Tag/categorize clips
- [ ] Export/import clipboard history
- [ ] Password-protected clips

### Technical Debt
- Add unit tests for ClipboardDatabase encryption/decryption
- Add integration tests for clipboard monitoring
- Consider performance optimization for large databases (>10k entries)
- Document public APIs with doc comments

## Resources

### Documentation
- [Swift Package Manager](https://swift.org/package-manager/)
- [Apple CryptoKit](https://developer.apple.com/documentation/cryptokit)
- [SQLite.swift](https://github.com/stephencelis/SQLite.swift)
- [FTS5 Full-Text Search](https://www.sqlite.org/fts5.html)

### Similar Projects
- [Maccy](https://github.com/p0deje/Maccy) - Open source clipboard manager
- [Paste](https://pasteapp.io/) - Commercial clipboard manager
- [CopyClip](https://apps.apple.com/us/app/copyclip-clipboard-history/id595191960) - Mac App Store clipboard manager

## Contact

**Author**: Steven Harbron
**Email**: steve.harbron@icloud.com
**GitHub**: [@sharbron](https://github.com/sharbron)
**License**: MIT

---

*Last Updated: 2025-11-06*
*Project Version: 1.0*
