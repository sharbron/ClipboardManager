import Foundation

/// Every user-facing preference key, with its default.
///
/// Defaults are registered once at launch so that reads are a plain `UserDefaults` lookup.
/// Before this existed, call sites hedged with
/// `UserDefaults.standard.dictionaryRepresentation().keys.contains(key)` to tell "unset" from
/// "set to false" - which built a dictionary of every default in the domain on each check,
/// on paths as hot as saving a clip.
enum Preferences {
    static let launchAtLogin = "launchAtLogin"
    static let autoClearOnLogout = "autoClearOnLogout"
    static let enableNotifications = "enableNotifications"
    static let cleanupDays = "cleanupDays"
    static let maxClips = "maxClips"
    static let maxClipSize = "maxClipSize"
    static let maxImageSize = "maxImageSize"
    static let ocrEnabled = "ocrEnabled"
    static let snippetsEnabled = "snippetsEnabled"
    static let previewLength = "previewLength"
    static let showTypeIcons = "showTypeIcons"
    static let compactMode = "compactMode"

    /// Preference keys a settings file is allowed to set. Deliberately excludes internal
    /// state, which must only ever be written by the app's own logic.
    static let importable: Set<String> = [
        launchAtLogin, autoClearOnLogout, enableNotifications, cleanupDays, maxClips,
        maxClipSize, maxImageSize, ocrEnabled, snippetsEnabled, previewLength,
        showTypeIcons, compactMode
    ]

    private static let defaults: [String: Any] = [
        launchAtLogin: false,
        autoClearOnLogout: false,
        enableNotifications: true,
        cleanupDays: 30.0,
        maxClips: 15.0,
        maxClipSize: 100.0,
        maxImageSize: 10240.0,
        ocrEnabled: true,
        snippetsEnabled: true,
        previewLength: 60.0,
        showTypeIcons: true,
        compactMode: false
    ]

    /// Legacy key that duplicated `maxClips`: the slider wrote both, but only this one was
    /// read, so importing a settings file moved the slider without changing the menu.
    private static let legacyMenuBarClipCount = "menuBarClipCount"

    static func register() {
        UserDefaults.standard.register(defaults: defaults)
        migrateLegacyKeys()
    }

    /// Internal flags from superseded schemes, left behind in existing installs. Migration
    /// state now lives in the databases themselves, and the FTS index is gone, so nothing
    /// reads these any more.
    private static let obsoleteKeys = [
        "extractedTextEncrypted", "imageDataEncrypted",
        "ftsRecoveryCompleted", "ftsPlaintextPurged"
    ]

    private static func migrateLegacyKeys() {
        let store = UserDefaults.standard

        if store.object(forKey: legacyMenuBarClipCount) != nil {
            // The legacy key was the one actually driving the menu, so it wins on upgrade.
            let legacyValue = store.integer(forKey: legacyMenuBarClipCount)
            if legacyValue > 0 {
                store.set(Double(legacyValue), forKey: maxClips)
            }
            store.removeObject(forKey: legacyMenuBarClipCount)
        }

        for key in obsoleteKeys {
            store.removeObject(forKey: key)
        }

        // An earlier build let this range up to 300 while nothing consumed the value. Anyone
        // who dragged that slider has a stored length that would stretch the menu bar dropdown
        // across the screen, so bring it back into the supported range.
        if store.object(forKey: previewLength) != nil {
            let stored = store.double(forKey: previewLength)
            let clamped = min(max(stored, previewLengthRange.lowerBound), previewLengthRange.upperBound)
            if clamped != stored {
                store.set(clamped, forKey: previewLength)
            }
        }
    }

    /// Supported preview lengths. The upper bound is deliberately modest: a native menu sizes
    /// itself to its widest item.
    static let previewLengthRange: ClosedRange<Double> = 30...120

    /// Validates a value read from a settings file against the type this key expects,
    /// returning it normalised or nil if it doesn't belong. JSON gives back `NSNumber` for
    /// both booleans and numbers, so the check goes through CoreFoundation rather than
    /// `is Bool`, which every `NSNumber` satisfies through bridging.
    static func coerceImported(_ value: Any, forKey key: String) -> Any? {
        guard let expected = defaults[key] else { return nil }
        let valueIsBool = CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()

        if expected is Bool {
            return valueIsBool ? value : nil
        }
        if expected is Double {
            guard !valueIsBool, let number = value as? NSNumber else { return nil }
            return number.doubleValue
        }
        return nil
    }

    // MARK: - Typed accessors

    static var menuBarClipCount: Int {
        let value = UserDefaults.standard.integer(forKey: maxClips)
        return value > 0 ? value : 15
    }

    static var retentionDays: Int {
        let value = UserDefaults.standard.integer(forKey: cleanupDays)
        return value > 0 ? value : 30
    }

    static var maxClipSizeBytes: Int {
        let value = UserDefaults.standard.integer(forKey: maxClipSize)
        return (value > 0 ? value : 100) * 1024
    }

    static var maxImageSizeBytes: Int {
        let value = UserDefaults.standard.integer(forKey: maxImageSize)
        return (value > 0 ? value : 10240) * 1024
    }

    /// Upper bound is deliberately modest: this drives the menu bar dropdown, and a native
    /// menu sizes itself to its longest item, so a long preview stretches the menu across
    /// the screen.
    static var previewCharacterLimit: Int {
        let value = UserDefaults.standard.double(forKey: previewLength)
        guard value > 0 else { return 60 }
        return Int(min(max(value, previewLengthRange.lowerBound), previewLengthRange.upperBound))
    }

    static var isOCREnabled: Bool { UserDefaults.standard.bool(forKey: ocrEnabled) }
    static var areNotificationsEnabled: Bool { UserDefaults.standard.bool(forKey: enableNotifications) }
    static var areSnippetsEnabled: Bool { UserDefaults.standard.bool(forKey: snippetsEnabled) }
    static var showsTypeIcons: Bool { UserDefaults.standard.bool(forKey: showTypeIcons) }
    static var isCompactMode: Bool { UserDefaults.standard.bool(forKey: compactMode) }
    static var clearsHistoryOnLogout: Bool { UserDefaults.standard.bool(forKey: autoClearOnLogout) }
}
