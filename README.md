# Clipboard Manager

A secure, native macOS clipboard history manager built with Swift.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2013.0%2B-lightgrey.svg)
![Swift](https://img.shields.io/badge/swift-5.9-orange.svg)

## Features

- 🔐 **Encrypted Storage** - AES-256 encryption via CryptoKit and macOS Keychain
- 📋 **Menu Bar App** - Native macOS menu bar interface with smart date grouping
- ⌨️ **Global Hotkey** - Press Cmd+Shift+V to open menu from anywhere
- 🔢 **Quick Access** - Use Cmd+1 through Cmd+9 for recent items
- 🔍 **Enhanced Search** - Powerful search window with filters, sorting, and bulk actions
- 📌 **Pin Items** - Pin important clips to keep them at the top
- 🖼️ **Image Support** - Captures and displays images with thumbnails
- 👁️ **Quick Preview** - Hover over items to see preview tooltips
- 🗑️ **Smart Cleanup** - Auto-cleanup with options to clear last 24 hours or all history
- ⚡ **Native Performance** - Lightning fast, uses only ~20MB RAM
- 🎨 **Beautiful Icon** - Professional app and menu bar icons
- 🔔 **Smart Notifications** - Modern notification system

## Installation

### Download (Easiest)

1. Download [ClipboardManager-1.0.dmg](../../releases)
2. Open the DMG file
3. Drag ClipboardManager to Applications
4. **IMPORTANT:** Run this command in Terminal:
   ```bash
   xattr -cr /Applications/ClipboardManager.app
   ```
5. Launch from Applications
6. Grant permissions if prompted

⚠️ **This app is unsigned.** macOS will block it without the command above. See [INSTALL.md](INSTALL.md) for detailed instructions and alternatives.

**Why unsigned?** Code signing requires a $99/year Apple Developer account. For an open-source project, the command above is a simple alternative that tells macOS "I trust this app."

### Build from Source

#### Prerequisites
- Xcode 15.0+
- macOS 13.0 (Ventura) or later

#### Building

```bash
cd ClipboardManager
swift build -c release
./create_app.sh
```

This creates and signs `ClipboardManager.app`, then installs it to `/Applications`
(use `./create_app.sh --no-install` to skip the install).

## Usage

1. **Copy text or images** - Clipboard Manager automatically saves them
2. **Click the menu bar icon** - View your clipboard history organized by day
3. **Press Cmd+Shift+V** - Open clipboard menu from anywhere
4. **Use Cmd+1 to Cmd+9** - Quickly paste recent items
5. **Select a clip** - Restores it to your clipboard
6. **Hover over items** - See preview tooltips
7. **Right-click items** - Pin or delete clips
8. **Search** - Open enhanced search window with filters and sorting
9. **Preferences** - Adjust retention period and manage history

## Security & Privacy

- ✅ **AES-256-GCM encryption** - Military-grade encryption for all clipboard data
- ✅ **macOS Keychain** - Encryption key stored securely in system keychain
- ✅ **Secure file permissions** - Database restricted to owner-only access (0600)
- ✅ **Local only** - No network access, all data stays on your Mac
- ✅ **Your data only** - Only accessible by your user account
- ✅ **Authenticated encryption** - Prevents tampering with encrypted data

Database location: `~/.clipboard_history.db`

For detailed security architecture, see [CLAUDE.md](CLAUDE.md).

## Performance

| Metric | Value |
|--------|-------|
| Memory Usage | ~20 MB |
| Startup Time | <0.1s |
| App Size | 600 KB (DMG) |
| CPU Impact | Minimal |

## Development

### Code Quality & Testing

This project uses [SwiftLint](https://github.com/realm/SwiftLint) to ensure code quality and consistency.

**Install SwiftLint:**
```bash
brew install swiftlint
```

SwiftLint runs automatically during builds via `create_app.sh`. You can also run it manually:
```bash
swiftlint
```

**Running Tests:**
```bash
# Run all tests
swift test

# Run with verbose output
swift test -v

# Run specific test suite
swift test --filter ClipboardDatabaseTests
```

**Test Coverage:**
- ✅ 75+ unit tests covering core functionality
- ✅ Encryption/decryption tests
- ✅ Database operations (CRUD, FTS search)
- ✅ State management tests
- ✅ Automated CI/CD via GitHub Actions

### Project Structure

```
ClipboardManager/
├── Package.swift              # Swift Package Manager config
├── Info.plist                # App bundle configuration
├── .swiftlint.yml            # SwiftLint configuration
├── create_app.sh             # App bundle creation script (includes linting)
├── create_dmg.sh             # DMG creation script
├── Sources/
│   └── ClipboardManager/
│       ├── main.swift                # Entry point
│       ├── AppDelegate.swift         # App logic and menu
│       ├── ClipboardDatabase.swift   # Database and encryption
│       └── ClipboardMonitor.swift    # Clipboard monitoring
├── AppIcon.icns              # Application icon
├── icon.png                  # Menu bar icon
└── README.md
```

### Building for Distribution

```bash
# Build release version
swift build -c release

# Create app bundle
./create_app.sh

# Create DMG installer
./create_dmg.sh
```

#### Code Signing (Optional)

For distribution outside the Mac App Store, sign your app:

```bash
codesign --deep --force --sign "Developer ID Application: Your Name" \
  ClipboardManager.app
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Troubleshooting

**App won't open?**
- Right-click → Open → Open Anyway (first time only)
- Or: System Settings → Privacy & Security → Open Anyway

**Clips not saving?**
- Make sure the app is running (check Activity Monitor)
- Copy some new text to test

**Menu bar icon not showing?**
- Check if app is running
- Try restarting the app

## Support

Found a bug or have a feature request? Please open an issue on GitHub.

## Author

**Steven Harbron**
- Email: steve.harbron@icloud.com
- GitHub: [@sharbron](https://github.com/sharbron)

## License

MIT License

Copyright (c) 2025 Steven Harbron

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Acknowledgments

Built with:
- [Swift](https://swift.org/) - Programming language
- [SQLite.swift](https://github.com/stephencelis/SQLite.swift) - Database wrapper
- Apple's CryptoKit - Encryption framework

---

*Last Updated: 2025-11-06*
