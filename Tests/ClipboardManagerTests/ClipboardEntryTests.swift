import XCTest
@testable import ClipboardManager

/// Tests for ClipboardEntry struct
/// Verifies preview text generation and other utility functions
final class ClipboardEntryTests: XCTestCase {

    // MARK: - Preview Text Tests

    func testPreviewTextShortContent() {
        let entry = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: "Short text",
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        XCTAssertEqual(entry.previewText, "Short text", "Short text should not be truncated")
    }

    func testPreviewTextLongContent() {
        let longText = String(repeating: "A", count: 100)
        let entry = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: longText,
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        XCTAssertTrue(entry.previewText.hasSuffix("..."), "Long text should be truncated with ellipsis")
        XCTAssertLessThanOrEqual(entry.previewText.count, 53, "Preview should be max 50 chars + '...'")
        XCTAssertEqual(entry.previewText.count, 53, "Preview should be exactly 50 chars + '...' = 53")
    }

    func testPreviewTextExactly50Chars() {
        let text = String(repeating: "A", count: 50)
        let entry = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: text,
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        // 50 characters exactly should not be truncated
        XCTAssertEqual(entry.previewText, text, "Exactly 50 chars should not be truncated")
        XCTAssertFalse(entry.previewText.hasSuffix("..."), "Should not have ellipsis")
    }

    func testPreviewTextMultiline() {
        let multiline = "Line 1\nLine 2\nLine 3"
        let entry = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: multiline,
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        XCTAssertFalse(entry.previewText.contains("\n"), "Preview should not contain newlines")
        XCTAssertTrue(entry.previewText.contains(" "), "Newlines should be replaced with spaces")
        XCTAssertEqual(entry.previewText, "Line 1 Line 2 Line 3", "Newlines should become spaces")
    }

    func testPreviewTextWhitespace() {
        let whitespaceText = "   Text with spaces   \n\n"
        let entry = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: whitespaceText,
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        XCTAssertEqual(entry.previewText, "Text with spaces", "Whitespace should be trimmed")
    }

    func testPreviewTextImage() {
        let imageDescription = "[Image: 1920x1080]"
        let entry = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "image",
            content: imageDescription,
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        XCTAssertEqual(entry.previewText, imageDescription, "Image description should be used as-is")
    }

    func testPreviewTextEmpty() {
        let entry = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: "",
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        XCTAssertEqual(entry.previewText, "", "Empty content should have empty preview")
    }

    func testPreviewTextOnlyNewlines() {
        let entry = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: "\n\n\n",
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        XCTAssertEqual(entry.previewText, "", "Only newlines should result in empty preview")
    }

    // MARK: - Hashable Tests

    func testHashableSameId() {
        let entry1 = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: "Test",
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        let entry2 = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: "Different content",
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        XCTAssertEqual(entry1, entry2, "Entries with same ID should be equal")
    }

    func testHashableDifferentId() {
        let entry1 = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: "Test",
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        let entry2 = ClipboardEntry(
            id: 2,
            timestamp: Date(),
            contentType: "text",
            content: "Test",
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        XCTAssertNotEqual(entry1, entry2, "Entries with different IDs should not be equal")
    }

    func testHashableInSet() {
        let entry1 = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: "Test",
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        let entry2 = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: "Test",
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        let entry3 = ClipboardEntry(
            id: 2,
            timestamp: Date(),
            contentType: "text",
            content: "Test",
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        var set: Set<ClipboardEntry> = []
        set.insert(entry1)
        set.insert(entry2)  // Should not increase count (same ID)
        set.insert(entry3)  // Should increase count (different ID)

        XCTAssertEqual(set.count, 2, "Set should contain 2 unique entries")
    }

    // MARK: - Field Tests

    func testAllFields() {
        let timestamp = Date()
        let imageData = Data([0x01, 0x02, 0x03])

        let entry = ClipboardEntry(
            id: 42,
            timestamp: timestamp,
            contentType: "image",
            content: "[Image: 100x100]",
            imageData: imageData,
            isPinned: true,
            sourceApp: "Safari"
        )

        XCTAssertEqual(entry.id, 42)
        XCTAssertEqual(entry.timestamp, timestamp)
        XCTAssertEqual(entry.contentType, "image")
        XCTAssertEqual(entry.content, "[Image: 100x100]")
        XCTAssertEqual(entry.imageData, imageData)
        XCTAssertTrue(entry.isPinned)
        XCTAssertEqual(entry.sourceApp, "Safari")
    }

    func testOptionalFields() {
        let entry = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: "Test",
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        XCTAssertNil(entry.imageData, "imageData should be optional")
        XCTAssertNil(entry.sourceApp, "sourceApp should be optional")
    }

    // MARK: - Unicode and Special Characters

    func testPreviewTextUnicode() {
        let unicodeText = "Hello 世界 🌍 émojis"
        let entry = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: unicodeText,
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        XCTAssertEqual(entry.previewText, unicodeText, "Unicode should be preserved")
    }

    func testPreviewTextLongWithUnicode() {
        let unicodeText = String(repeating: "🌍", count: 30)  // Each emoji counts as multiple chars
        let entry = ClipboardEntry(
            id: 1,
            timestamp: Date(),
            contentType: "text",
            content: unicodeText,
            imageData: nil,
            isPinned: false,
            sourceApp: nil
        )

        XCTAssertTrue(entry.previewText.count <= 53, "Unicode text should be truncated properly")
    }
}
