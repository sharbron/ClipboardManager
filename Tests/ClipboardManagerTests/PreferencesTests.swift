import XCTest
@testable import ClipboardManager

/// Covers the preference layer that replaced the ad-hoc `UserDefaults` reads: the single
/// menu-bar clip count key, and the validation applied to imported settings files.
final class PreferencesTests: XCTestCase {
    private var touchedKeys: [String] = []

    override func tearDown() async throws {
        for key in touchedKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        touchedKeys = []
        try await super.tearDown()
    }

    private func set(_ value: Any, forKey key: String) {
        touchedKeys.append(key)
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: - Legacy key migration

    func testLegacyMenuBarClipCountIsAdoptedAsMaxClips() throws {
        touchedKeys.append(Preferences.maxClips)
        touchedKeys.append("menuBarClipCount")
        UserDefaults.standard.set(42, forKey: "menuBarClipCount")

        Preferences.register()

        XCTAssertEqual(Preferences.menuBarClipCount, 42, "The value that used to drive the menu should carry over")
        XCTAssertNil(
            UserDefaults.standard.object(forKey: "menuBarClipCount"),
            "The duplicate key should be removed once migrated"
        )
    }

    func testMenuBarClipCountFallsBackWhenUnset() {
        touchedKeys.append(Preferences.maxClips)
        UserDefaults.standard.removeObject(forKey: Preferences.maxClips)

        XCTAssertEqual(Preferences.menuBarClipCount, 15, "Should fall back to the documented default")
    }

    // MARK: - Import validation

    func testCoerceImportedAcceptsMatchingTypes() throws {
        let boolean = try XCTUnwrap(Preferences.coerceImported(true, forKey: Preferences.ocrEnabled) as? Bool)
        XCTAssertTrue(boolean)

        let number = try XCTUnwrap(Preferences.coerceImported(45, forKey: Preferences.cleanupDays) as? Double)
        XCTAssertEqual(number, 45)
    }

    func testCoerceImportedRejectsMismatchedTypes() {
        // JSON hands back NSNumber for both booleans and numbers, so these are the cases
        // a naive `is Bool` check would wave through.
        XCTAssertNil(Preferences.coerceImported(30, forKey: Preferences.ocrEnabled), "A number is not a toggle")
        XCTAssertNil(Preferences.coerceImported(true, forKey: Preferences.cleanupDays), "A toggle is not a number")
        XCTAssertNil(Preferences.coerceImported("lots", forKey: Preferences.maxClips), "A string is not a number")
    }

    func testCoerceImportedRejectsUnknownKeys() {
        XCTAssertNil(Preferences.coerceImported(true, forKey: "someInternalFlag"))
        XCTAssertFalse(Preferences.importable.contains("someInternalFlag"))
    }
}
