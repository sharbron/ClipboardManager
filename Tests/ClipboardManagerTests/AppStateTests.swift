import XCTest
@testable import ClipboardManager

/// Tests for AppState class
/// Verifies state management and coordination between UI and database
final class AppStateTests: XCTestCase {
    var database: ClipboardDatabase!
    var snippetDatabase: SnippetDatabase!
    var snippetManager: SnippetManager!
    var appState: AppState!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        // Create database
        database = ClipboardDatabase()

        // Wait for database to initialize
        try await Task.sleep(nanoseconds: 100_000_000)

        // Create snippet database and manager
        snippetDatabase = SnippetDatabase()
        try await Task.sleep(nanoseconds: 100_000_000)
        snippetManager = SnippetManager(database: snippetDatabase)

        // Create app state with all dependencies
        appState = AppState(database: database, snippetDatabase: snippetDatabase, snippetManager: snippetManager)

        // Clear any existing clips for clean test state
        _ = await database.clearAllHistory(keepPinned: false)
    }

    @MainActor
    override func tearDown() async throws {
        // Clean up
        _ = await database.clearAllHistory(keepPinned: false)

        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    @MainActor
    func testAppStateInitialization() async throws {
        XCTAssertNotNil(appState, "AppState should initialize")
        XCTAssertNotNil(appState.database, "AppState should have database reference")
        XCTAssertEqual(appState.clips.count, 0, "Should start with no clips")
    }

    // MARK: - Load Clips Tests

    @MainActor
    func testLoadClips() async throws {
        // Save some clips to database
        await database.saveClip("Clip 1")
        await database.saveClip("Clip 2")
        await database.saveClip("Clip 3")

        // Load clips in app state
        appState.loadClips()

        // Wait for async load to complete
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify clips are loaded
        XCTAssertEqual(appState.clips.count, 3, "Should load 3 clips")
        XCTAssertEqual(appState.clips[0].content, "Clip 3", "Most recent clip should be first")
    }

    @MainActor
    func testLoadClipsWithLimit() async throws {
        // Save more clips than the default limit
        for i in 1...20 {
            await database.saveClip("Clip \(i)")
        }

        // Set a custom limit
        UserDefaults.standard.set(10, forKey: "menuBarClipCount")

        // Load clips
        appState.loadClips()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify limit is respected
        XCTAssertEqual(appState.clips.count, 10, "Should respect custom limit")
    }

    @MainActor
    func testLoadClipsDefaultLimit() async throws {
        // Clear any custom limit
        UserDefaults.standard.removeObject(forKey: "menuBarClipCount")

        // Save more clips than default limit
        for i in 1...20 {
            await database.saveClip("Clip \(i)")
        }

        // Load clips (should use default limit of 15)
        appState.loadClips()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify default limit is used
        XCTAssertEqual(appState.clips.count, 15, "Should use default limit of 15")
    }

    @MainActor
    func testLoadClipsEmpty() async throws {
        // Ensure database is empty
        _ = await database.clearAllHistory(keepPinned: false)

        // Load clips
        appState.loadClips()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify no clips loaded
        XCTAssertEqual(appState.clips.count, 0, "Should have no clips")
    }

    // MARK: - Toggle Pin Tests

    @MainActor
    func testTogglePin() async throws {
        // Save a clip
        await database.saveClip("Pin test")

        // Load clips
        appState.loadClips()
        try await Task.sleep(nanoseconds: 200_000_000)

        guard let clipId = appState.clips.first?.id else {
            XCTFail("No clips loaded")
            return
        }

        // Verify initially not pinned
        XCTAssertFalse(appState.clips.first?.isPinned ?? true, "Should not be pinned initially")

        // Toggle pin
        appState.togglePin(clipId: clipId)
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify pinned
        XCTAssertTrue(appState.clips.first?.isPinned ?? false, "Should be pinned after toggle")

        // Toggle again
        appState.togglePin(clipId: clipId)
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify unpinned
        XCTAssertFalse(appState.clips.first?.isPinned ?? true, "Should be unpinned after second toggle")
    }

    @MainActor
    func testTogglePinUpdatesOrder() async throws {
        // Save multiple clips
        await database.saveClip("Clip 1")
        await database.saveClip("Clip 2")
        await database.saveClip("Clip 3")

        // Load clips
        appState.loadClips()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Get the last clip (oldest)
        guard let lastClip = appState.clips.last else {
            XCTFail("No clips loaded")
            return
        }

        // Pin the oldest clip
        appState.togglePin(clipId: lastClip.id)
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify pinned clip is now first
        XCTAssertTrue(appState.clips.first?.isPinned ?? false, "Pinned clip should be first")
        XCTAssertEqual(appState.clips.first?.content, "Clip 1", "Pinned clip should be 'Clip 1'")
    }

    // MARK: - Delete Tests

    @MainActor
    func testDeleteClip() async throws {
        // Save clips
        await database.saveClip("Keep me")
        await database.saveClip("Delete me")

        // Load clips
        appState.loadClips()
        try await Task.sleep(nanoseconds: 200_000_000)

        let initialCount = appState.clips.count
        guard let clipToDelete = appState.clips.first(where: { $0.content == "Delete me" }) else {
            XCTFail("Clip not found")
            return
        }

        // Delete clip
        appState.deleteClip(clipId: clipToDelete.id)
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify deletion
        XCTAssertEqual(appState.clips.count, initialCount - 1, "Clip count should decrease")
        XCTAssertNil(appState.clips.first(where: { $0.content == "Delete me" }), "Deleted clip should not exist")
    }

    @MainActor
    func testDeleteAllClips() async throws {
        // Save multiple clips
        for i in 1...5 {
            await database.saveClip("Clip \(i)")
        }

        // Load clips
        appState.loadClips()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(appState.clips.count, 5, "Should have 5 clips")

        // Delete all clips
        appState.deleteAllClips()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify all deleted
        XCTAssertEqual(appState.clips.count, 0, "All clips should be deleted")
    }

    @MainActor
    func testDeleteAllClipsKeepPinned() async throws {
        // Save clips
        await database.saveClip("Regular 1")
        await database.saveClip("Pinned clip")
        await database.saveClip("Regular 2")

        // Load and pin one clip
        appState.loadClips()
        try await Task.sleep(nanoseconds: 200_000_000)

        if let pinnedClip = appState.clips.first(where: { $0.content == "Pinned clip" }) {
            appState.togglePin(clipId: pinnedClip.id)
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        // Delete all (keeps pinned by default)
        appState.deleteAllClips()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify only pinned clip remains
        XCTAssertEqual(appState.clips.count, 1, "Only pinned clip should remain")
        XCTAssertEqual(appState.clips.first?.content, "Pinned clip")
        XCTAssertTrue(appState.clips.first?.isPinned ?? false)
    }

    @MainActor
    func testDeleteClipsFromLast24Hours() async throws {
        // Save clips
        await database.saveClip("Recent clip")

        // Load clips
        appState.loadClips()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertGreaterThan(appState.clips.count, 0, "Should have clips")

        // Delete clips from last 24 hours
        appState.deleteClipsFromLast24Hours()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify deletion (recent clips should be removed)
        XCTAssertEqual(appState.clips.count, 0, "Recent clips should be deleted")
    }

    // MARK: - Copy to Clipboard Tests

    @MainActor
    func testCopyToClipboardText() async throws {
        // Save a text clip
        await database.saveClip("Test copy")

        // Load clips
        appState.loadClips()
        try await Task.sleep(nanoseconds: 200_000_000)

        guard let clip = appState.clips.first else {
            XCTFail("No clips loaded")
            return
        }

        // Copy to clipboard
        await appState.copyToClipboard(clip: clip)

        // Verify clipboard content
        let pasteboard = NSPasteboard.general
        let clipboardContent = pasteboard.string(forType: .string)
        XCTAssertEqual(clipboardContent, "Test copy", "Clipboard should contain the clip content")
    }

    @MainActor
    func testCopyToClipboardImage() async throws {
        let imageDescription = "[Image: 100x100]"
        let mockImageData = Data([0xFF, 0xD8, 0xFF, 0xE0])  // Mock JPEG header

        // Save an image clip
        await database.saveClip(imageDescription, type: "image", image: mockImageData)

        // Load clips
        appState.loadClips()
        try await Task.sleep(nanoseconds: 200_000_000)

        guard let clip = appState.clips.first else {
            XCTFail("No clips loaded")
            return
        }

        // Copy to clipboard
        await appState.copyToClipboard(clip: clip)

        // Verify image is in clipboard
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []

        // Check if pasteboard contains image data
        // Note: NSImage representation might vary, so we just verify it's not empty
        XCTAssertTrue(types.contains(.tiff) || types.contains(.png), "Clipboard should contain image data")
    }

    // MARK: - Reactive Updates Tests

    @MainActor
    func testClipsArePublished() async throws {
        // Create expectation for published value
        let expectation = XCTestExpectation(description: "Clips published")

        // Observe clips changes
        var observedClips: [ClipboardEntry]?
        let cancellable = appState.$clips.sink { clips in
            if !clips.isEmpty {
                observedClips = clips
                expectation.fulfill()
            }
        }

        // Save and load clips
        await database.saveClip("Published clip")
        appState.loadClips()

        // Wait for publication
        await fulfillment(of: [expectation], timeout: 2.0)

        // Verify
        XCTAssertNotNil(observedClips, "Clips should be published")
        XCTAssertEqual(observedClips?.first?.content, "Published clip")

        cancellable.cancel()
    }

    // MARK: - Edge Cases

    @MainActor
    func testLoadClipsCancellation() async throws {
        // Save many clips
        for i in 1...100 {
            await database.saveClip("Clip \(i)")
        }

        // Start multiple rapid loads (should cancel previous ones)
        appState.loadClips()
        appState.loadClips()
        appState.loadClips()

        // Wait for final load
        try await Task.sleep(nanoseconds: 300_000_000)

        // Should complete without issues
        XCTAssertGreaterThan(appState.clips.count, 0, "Should load clips successfully")
    }

    @MainActor
    func testLoadClipsWithoutMonitor() async throws {
        // Ensure clipboardMonitor is nil
        XCTAssertNil(appState.clipboardMonitor, "Monitor should be nil by default")

        // Save clips
        await database.saveClip("Test")

        // Load clips (should work without monitor)
        appState.loadClips()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertGreaterThan(appState.clips.count, 0, "Should load clips even without monitor")
    }

    // MARK: - Performance Tests

    func testLoadClipsWithManyEntries() async throws {
        // Seed database with many clips to test performance
        for i in 1...100 {
            await database.saveClip("Performance clip \(i)")
        }

        // Load clips and verify it completes successfully
        appState.loadClips()
        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify clips were loaded
        XCTAssertGreaterThan(appState.clips.count, 0, "Should load clips successfully")
        XCTAssertLessThanOrEqual(appState.clips.count, 100, "Should respect limit")
    }
}
