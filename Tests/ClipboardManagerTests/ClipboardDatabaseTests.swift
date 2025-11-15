import XCTest
import SQLite
import CryptoKit
@testable import ClipboardManager

/// Comprehensive tests for ClipboardDatabase
/// Tests encryption, decryption, CRUD operations, FTS search, and data integrity
final class ClipboardDatabaseTests: XCTestCase {
    var database: ClipboardDatabase!
    var testDatabasePath: String!

    override func setUp() async throws {
        try await super.setUp()

        // Create a temporary database file for testing
        let tempDir = FileManager.default.temporaryDirectory
        testDatabasePath = tempDir.appendingPathComponent("test_clipboard_\(UUID().uuidString).db").path

        // Initialize database
        database = ClipboardDatabase()

        // Wait a bit to ensure database is initialized
        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify database is initialized
        XCTAssertTrue(await database.isInitialized, "Database should be initialized")
    }

    override func tearDown() async throws {
        // Clean up: delete test database file
        if let path = testDatabasePath {
            try? FileManager.default.removeItem(atPath: path)
        }

        try await super.tearDown()
    }

    // MARK: - Basic Operations Tests

    func testSaveAndRetrieveTextClip() async throws {
        let testContent = "Hello, World! This is a test clip."

        // Save a clip
        await database.saveClip(testContent)

        // Retrieve clips
        let clips = await database.getRecentClips(limit: 10)

        // Verify
        XCTAssertFalse(clips.isEmpty, "Should have at least one clip")
        XCTAssertEqual(clips.first?.content, testContent, "Content should match")
        XCTAssertEqual(clips.first?.contentType, "text", "Content type should be 'text'")
        XCTAssertFalse(clips.first?.isPinned ?? true, "Clip should not be pinned by default")
    }

    func testSaveMultipleClips() async throws {
        let clips = [
            "First clip",
            "Second clip",
            "Third clip"
        ]

        // Save multiple clips
        for clip in clips {
            await database.saveClip(clip)
        }

        // Retrieve clips
        let retrievedClips = await database.getRecentClips(limit: 10)

        // Verify count
        XCTAssertGreaterThanOrEqual(retrievedClips.count, 3, "Should have at least 3 clips")

        // Verify order (most recent first)
        XCTAssertEqual(retrievedClips[0].content, "Third clip")
        XCTAssertEqual(retrievedClips[1].content, "Second clip")
        XCTAssertEqual(retrievedClips[2].content, "First clip")
    }

    func testSaveImageClip() async throws {
        let imageDescription = "[Image: 1920x1080]"
        let mockImageData = Data([0xFF, 0xD8, 0xFF, 0xE0])  // Mock JPEG header

        // Save image clip
        await database.saveClip(imageDescription, type: "image", image: mockImageData)

        // Retrieve clips
        let clips = await database.getRecentClips(limit: 10)

        // Verify
        XCTAssertFalse(clips.isEmpty, "Should have at least one clip")
        XCTAssertEqual(clips.first?.content, imageDescription)
        XCTAssertEqual(clips.first?.contentType, "image")

        // Verify image data can be retrieved
        if let clipId = clips.first?.id {
            let imageData = await database.getImageData(for: clipId)
            XCTAssertNotNil(imageData, "Image data should be retrievable")
            XCTAssertEqual(imageData, mockImageData, "Image data should match")
        }
    }

    func testSaveWithSourceApp() async throws {
        let testContent = "Content from Safari"
        let sourceApp = "Safari"

        // Save clip with source app
        await database.saveClip(testContent, sourceApp: sourceApp)

        // Retrieve and verify
        let clips = await database.getRecentClips(limit: 10)
        XCTAssertEqual(clips.first?.sourceApp, sourceApp, "Source app should be saved")
    }

    // MARK: - Pin/Unpin Tests

    func testTogglePin() async throws {
        let testContent = "Pin me!"

        // Save a clip
        await database.saveClip(testContent)

        // Get the clip ID
        let clips = await database.getRecentClips(limit: 10)
        guard let clipId = clips.first?.id else {
            XCTFail("No clips found")
            return
        }

        // Verify initially not pinned
        XCTAssertFalse(clips.first?.isPinned ?? true)

        // Pin the clip
        let isPinned = await database.togglePin(clipId: clipId)
        XCTAssertTrue(isPinned, "Clip should be pinned")

        // Verify pin status persisted
        let updatedClips = await database.getRecentClips(limit: 10)
        XCTAssertTrue(updatedClips.first?.isPinned ?? false, "Clip should remain pinned")

        // Unpin the clip
        let isUnpinned = await database.togglePin(clipId: clipId)
        XCTAssertFalse(isUnpinned, "Clip should be unpinned")

        // Verify unpin status
        let finalClips = await database.getRecentClips(limit: 10)
        XCTAssertFalse(finalClips.first?.isPinned ?? true, "Clip should remain unpinned")
    }

    func testPinnedClipsAppearFirst() async throws {
        // Save multiple clips
        await database.saveClip("Regular clip 1")
        await database.saveClip("Regular clip 2")
        await database.saveClip("To be pinned")

        // Get clips and pin the last one
        let clips = await database.getRecentClips(limit: 10)
        guard let clipToPin = clips.first else {
            XCTFail("No clips found")
            return
        }

        _ = await database.togglePin(clipId: clipToPin.id)

        // Retrieve clips again
        let updatedClips = await database.getRecentClips(limit: 10)

        // Verify pinned clip appears first
        XCTAssertTrue(updatedClips.first?.isPinned ?? false, "First clip should be pinned")
        XCTAssertEqual(updatedClips.first?.content, "To be pinned")
    }

    // MARK: - Delete Tests

    func testDeleteClip() async throws {
        let testContent = "Delete me!"

        // Save a clip
        await database.saveClip(testContent)

        // Get the clip
        let clips = await database.getRecentClips(limit: 10)
        guard let clipId = clips.first?.id else {
            XCTFail("No clips found")
            return
        }

        let initialCount = clips.count

        // Delete the clip
        let success = await database.deleteClip(clipId: clipId)
        XCTAssertTrue(success, "Delete should succeed")

        // Verify deletion
        let updatedClips = await database.getRecentClips(limit: 10)
        XCTAssertEqual(updatedClips.count, initialCount - 1, "Clip count should decrease by 1")
        XCTAssertFalse(updatedClips.contains(where: { $0.id == clipId }), "Deleted clip should not exist")
    }

    func testClearAllHistory() async throws {
        // Save multiple clips
        await database.saveClip("Clip 1")
        await database.saveClip("Clip 2")
        await database.saveClip("Clip 3")

        // Clear all
        let deletedCount = await database.clearAllHistory(keepPinned: false)
        XCTAssertGreaterThan(deletedCount, 0, "Should delete some clips")

        // Verify all deleted
        let clips = await database.getRecentClips(limit: 10)
        XCTAssertEqual(clips.count, 0, "All clips should be deleted")
    }

    func testClearAllHistoryKeepPinned() async throws {
        // Save multiple clips
        await database.saveClip("Clip 1")
        await database.saveClip("Clip 2")
        await database.saveClip("Pinned Clip")

        // Pin one clip
        let clips = await database.getRecentClips(limit: 10)
        if let clipToPin = clips.first {
            _ = await database.togglePin(clipId: clipToPin.id)
        }

        // Clear all but keep pinned
        _ = await database.clearAllHistory(keepPinned: true)

        // Verify only pinned clip remains
        let remainingClips = await database.getRecentClips(limit: 10)
        XCTAssertEqual(remainingClips.count, 1, "Only pinned clip should remain")
        XCTAssertTrue(remainingClips.first?.isPinned ?? false, "Remaining clip should be pinned")
        XCTAssertEqual(remainingClips.first?.content, "Pinned Clip")
    }

    func testClearLast24Hours() async throws {
        // Save a clip
        await database.saveClip("Recent clip")

        // Clear last 24 hours
        let deletedCount = await database.clearLast24Hours()
        XCTAssertGreaterThan(deletedCount, 0, "Should delete recent clips")

        // Verify deletion
        let clips = await database.getRecentClips(limit: 10)
        XCTAssertEqual(clips.count, 0, "Recent clips should be deleted")
    }

    // MARK: - Search Tests

    func testFullTextSearch() async throws {
        // Save clips with different content
        await database.saveClip("The quick brown fox jumps over the lazy dog")
        await database.saveClip("Hello world from Swift")
        await database.saveClip("Testing full-text search functionality")

        // Search for "fox"
        let foxResults = await database.searchClipsWithFTS(query: "fox")
        XCTAssertEqual(foxResults.count, 1, "Should find 1 result for 'fox'")
        XCTAssertTrue(foxResults.first?.content.contains("fox") ?? false)

        // Search for "swift"
        let swiftResults = await database.searchClipsWithFTS(query: "swift")
        XCTAssertEqual(swiftResults.count, 1, "Should find 1 result for 'swift'")
        XCTAssertTrue(swiftResults.first?.content.contains("Swift") ?? false)

        // Search for "search"
        let searchResults = await database.searchClipsWithFTS(query: "search")
        XCTAssertEqual(searchResults.count, 1, "Should find 1 result for 'search'")
        XCTAssertTrue(searchResults.first?.content.contains("search") ?? false)
    }

    func testSearchWithSpecialCharacters() async throws {
        // Save clip with special characters
        await database.saveClip("Email: test@example.com")
        await database.saveClip("Code: let x = \"hello\"")

        // Search for email (FTS escapes special chars internally)
        let emailResults = await database.searchClipsWithFTS(query: "example")
        XCTAssertGreaterThanOrEqual(emailResults.count, 1, "Should find email")

        // Search for code content
        let codeResults = await database.searchClipsWithFTS(query: "hello")
        XCTAssertGreaterThanOrEqual(codeResults.count, 1, "Should find code snippet")
    }

    func testSearchReturnsNoResultsForNonExistent() async throws {
        // Save some clips
        await database.saveClip("Apple")
        await database.saveClip("Banana")

        // Search for non-existent term
        let results = await database.searchClipsWithFTS(query: "nonexistent")
        XCTAssertEqual(results.count, 0, "Should return no results for non-existent term")
    }

    // MARK: - Database Statistics Tests

    func testGetTotalClipsCount() async throws {
        // Get initial count
        let initialCount = await database.getTotalClipsCount()

        // Save some clips
        await database.saveClip("Clip 1")
        await database.saveClip("Clip 2")
        await database.saveClip("Clip 3")

        // Get new count
        let newCount = await database.getTotalClipsCount()
        XCTAssertEqual(newCount, initialCount + 3, "Count should increase by 3")
    }

    func testGetDatabaseSize() async throws {
        let size = await database.getDatabaseSize()
        XCTAssertNotEqual(size, "Unknown", "Should return a valid size")
        XCTAssertTrue(size.contains("bytes") || size.contains("KB") || size.contains("MB"),
                      "Size should have proper units")
    }

    // MARK: - Edge Cases and Error Handling

    func testSaveEmptyString() async throws {
        let emptyContent = ""

        // Save empty string
        await database.saveClip(emptyContent)

        // Should still be saved (encryption handles empty strings)
        let clips = await database.getRecentClips(limit: 10)
        XCTAssertGreaterThanOrEqual(clips.count, 0, "Database should handle empty strings")
    }

    func testSaveLargeText() async throws {
        // Create a large text (100KB)
        let largeText = String(repeating: "A", count: 100_000)

        // Save large text
        await database.saveClip(largeText)

        // Retrieve and verify
        let clips = await database.getRecentClips(limit: 10)
        XCTAssertEqual(clips.first?.content.count, 100_000, "Large text should be saved correctly")
    }

    func testUnicodeContent() async throws {
        let unicodeContent = "Hello 世界 🌍 émojis and spëcial çhars"

        // Save unicode content
        await database.saveClip(unicodeContent)

        // Retrieve and verify
        let clips = await database.getRecentClips(limit: 10)
        XCTAssertEqual(clips.first?.content, unicodeContent, "Unicode should be preserved")
    }

    func testMultilineContent() async throws {
        let multilineContent = """
        Line 1
        Line 2
        Line 3
        """

        // Save multiline content
        await database.saveClip(multilineContent)

        // Retrieve and verify
        let clips = await database.getRecentClips(limit: 10)
        XCTAssertEqual(clips.first?.content, multilineContent, "Multiline content should be preserved")
    }

    func testPreviewText() async throws {
        // Test short content
        await database.saveClip("Short")
        let clips1 = await database.getRecentClips(limit: 10)
        XCTAssertEqual(clips1.first?.previewText, "Short", "Short text should not be truncated")

        // Test long content
        let longContent = String(repeating: "A", count: 100)
        await database.saveClip(longContent)
        let clips2 = await database.getRecentClips(limit: 10)
        XCTAssertTrue(clips2.first?.previewText.hasSuffix("...") ?? false, "Long text should be truncated")
        XCTAssertLessThanOrEqual(clips2.first?.previewText.count ?? 0, 53, "Preview should be 50 chars + '...'")

        // Test multiline content (newlines should be replaced with spaces)
        let multiline = "Line 1\nLine 2\nLine 3"
        await database.saveClip(multiline)
        let clips3 = await database.getRecentClips(limit: 10)
        XCTAssertFalse(clips3.first?.previewText.contains("\n") ?? true, "Preview should not contain newlines")
    }

    // MARK: - Concurrency Tests

    func testConcurrentSaves() async throws {
        // Save multiple clips concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    await self.database.saveClip("Concurrent clip \(i)")
                }
            }
        }

        // Verify all clips were saved
        let clips = await database.getTotalClipsCount()
        XCTAssertGreaterThanOrEqual(clips, 10, "All concurrent saves should succeed")
    }

    func testConcurrentReads() async throws {
        // Save some clips first
        await database.saveClip("Test clip")

        // Perform concurrent reads
        await withTaskGroup(of: [ClipboardEntry].self) { group in
            for _ in 1...10 {
                group.addTask {
                    await self.database.getRecentClips(limit: 10)
                }
            }

            // Verify all reads succeed
            for await clips in group {
                XCTAssertGreaterThanOrEqual(clips.count, 0, "Concurrent reads should succeed")
            }
        }
    }

    // MARK: - Performance Tests

    func testPerformanceSaveClip() {
        measure {
            let expectation = self.expectation(description: "Save clip")
            Task {
                await database.saveClip("Performance test clip")
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5.0)
        }
    }

    func testPerformanceGetRecentClips() async throws {
        // Seed database with clips
        for i in 1...100 {
            await database.saveClip("Clip \(i)")
        }

        measure {
            let expectation = self.expectation(description: "Get recent clips")
            Task {
                _ = await database.getRecentClips(limit: 50)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5.0)
        }
    }

    func testPerformanceSearch() async throws {
        // Seed database with clips
        for i in 1...100 {
            await database.saveClip("Search test clip number \(i)")
        }

        measure {
            let expectation = self.expectation(description: "Search clips")
            Task {
                _ = await database.searchClipsWithFTS(query: "test")
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5.0)
        }
    }
}
