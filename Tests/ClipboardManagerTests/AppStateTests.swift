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

        // Wait for database to be fully initialized
        var initialized = await database.isInitialized
        while !initialized {
            try await Task.sleep(nanoseconds: 10_000_000)
            initialized = await database.isInitialized
        }

        // Create snippet database and manager
        snippetDatabase = SnippetDatabase()
        var snippetsInitialized = await snippetDatabase.isInitialized
        while !snippetsInitialized {
            try await Task.sleep(nanoseconds: 10_000_000)
            snippetsInitialized = await snippetDatabase.isInitialized
        }
        snippetManager = SnippetManager(database: snippetDatabase)

        // Create app state with all dependencies
        appState = AppState(database: database, snippetDatabase: snippetDatabase, snippetManager: snippetManager)

        // Wait for init Task to complete
        try await Task.sleep(nanoseconds: 50_000_000)

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
        await appState.loadClips()

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
        await appState.loadClips()

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
        await appState.loadClips()

        // Verify default limit is used
        XCTAssertEqual(appState.clips.count, 15, "Should use default limit of 15")
    }

    @MainActor
    func testLoadClipsEmpty() async throws {
        // Ensure database is empty
        _ = await database.clearAllHistory(keepPinned: false)

        // Load clips
        await appState.loadClips()

        // Verify no clips loaded
        XCTAssertEqual(appState.clips.count, 0, "Should have no clips")
    }

    // MARK: - Toggle Pin Tests

    @MainActor
    func testTogglePin() async throws {
        // Save a clip
        await database.saveClip("Pin test")

        // Load clips
        await appState.loadClips()

        guard let clipId = appState.clips.first?.id else {
            XCTFail("No clips loaded")
            return
        }

        // Verify initially not pinned
        XCTAssertFalse(appState.clips.first?.isPinned ?? true, "Should not be pinned initially")

        // Toggle pin
        await appState.togglePin(clipId: clipId)

        // Verify pinned
        XCTAssertTrue(appState.clips.first?.isPinned ?? false, "Should be pinned after toggle")

        // Toggle again
        await appState.togglePin(clipId: clipId)

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
        await appState.loadClips()

        // Get the last clip (oldest)
        guard let lastClip = appState.clips.last else {
            XCTFail("No clips loaded")
            return
        }

        // Pin the oldest clip
        await appState.togglePin(clipId: lastClip.id)

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
        await appState.loadClips()

        let initialCount = appState.clips.count
        guard let clipToDelete = appState.clips.first(where: { $0.content == "Delete me" }) else {
            XCTFail("Clip not found")
            return
        }

        // Delete clip
        await appState.deleteClip(clipId: clipToDelete.id)

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
        await appState.loadClips()

        XCTAssertEqual(appState.clips.count, 5, "Should have 5 clips")

        // Delete all clips
        await appState.deleteAllClips()

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
        await appState.loadClips()

        if let pinnedClip = appState.clips.first(where: { $0.content == "Pinned clip" }) {
            await appState.togglePin(clipId: pinnedClip.id)
        }

        // Delete all (keeps pinned by default)
        await appState.deleteAllClips()

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
        await appState.loadClips()

        XCTAssertGreaterThan(appState.clips.count, 0, "Should have clips")

        // Delete clips from last 24 hours
        await appState.deleteClipsFromLast24Hours()

        // Verify deletion (recent clips should be removed)
        XCTAssertEqual(appState.clips.count, 0, "Recent clips should be deleted")
    }

    // MARK: - Copy to Clipboard Tests

    @MainActor
    func testCopyToClipboardText() async throws {
        // Save a text clip
        await database.saveClip("Test copy")

        // Load clips
        await appState.loadClips()

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
        await appState.loadClips()

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
        await appState.loadClips()

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

        // Load clips multiple times - the final one should succeed
        await appState.loadClips()
        await appState.loadClips()
        await appState.loadClips()

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
        await appState.loadClips()

        XCTAssertGreaterThan(appState.clips.count, 0, "Should load clips even without monitor")
    }

    // MARK: - Performance Tests

    @MainActor
    func testPerformanceLoadClips() async throws {
        // Seed database with many clips
        for i in 1...100 {
            await database.saveClip("Performance clip \(i)")
        }

        measure {
            let expectation = self.expectation(description: "Load clips")
            Task { @MainActor in
                await appState.loadClips()
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 2.0)
        }
    }
}
