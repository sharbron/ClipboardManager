import AppKit
import XCTest
@testable import ClipboardManager

final class MenuTitleTests: XCTestCase {
    private let font = NSFont.menuFont(ofSize: 0)

    private func width(_ string: String) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    func testShortTitleIsUnchanged() {
        XCTAssertEqual(MenuTitle.fitted("Short clip"), "Short clip")
    }

    func testLongTitleIsCutToMaximumWidth() {
        let long = String(repeating: "W", count: 120)
        let fitted = MenuTitle.fitted(long)

        XCTAssertTrue(fitted.hasSuffix("…"))
        XCTAssertLessThanOrEqual(width(fitted), MenuTitle.maximumWidth)
        // Should use the available width, not truncate far short of it.
        XCTAssertGreaterThan(width(fitted), MenuTitle.maximumWidth - 2 * width("W"))
    }

    func testDoesNotStackEllipsisOnExistingMarker() {
        let preview = String(repeating: "m", count: 119) + "..."
        let fitted = MenuTitle.fitted(preview, maxWidth: width(preview) - 1)

        XCTAssertFalse(fitted.contains("."))
        XCTAssertTrue(fitted.hasSuffix("m…"))
    }

    func testWideGlyphsStillFit() {
        let emoji = String(repeating: "👨‍👩‍👧‍👦", count: 80)
        XCTAssertLessThanOrEqual(width(MenuTitle.fitted(emoji)), MenuTitle.maximumWidth)
    }
}
