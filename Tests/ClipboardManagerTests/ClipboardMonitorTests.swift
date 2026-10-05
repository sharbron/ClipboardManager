import XCTest
import AppKit
@testable import ClipboardManager

/// End-to-end capture tests: a monitor watching a private pasteboard and saving to a temp database
final class ClipboardMonitorTests: XCTestCase {
    var pasteboard: NSPasteboard!
    var database: ClipboardDatabase!
    var snippetDatabase: SnippetDatabase!
    var monitor: ClipboardMonitor!
    var testPaths: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        Preferences.register()

        let tempDir = FileManager.default.temporaryDirectory
        let clipPath = tempDir.appendingPathComponent("test_monitor_\(UUID().uuidString).db").path
        let snippetPath = tempDir.appendingPathComponent("test_monitor_snippets_\(UUID().uuidString).db").path
        testPaths = [clipPath, snippetPath]

        database = ClipboardDatabase(path: clipPath)
        snippetDatabase = SnippetDatabase(databasePath: snippetPath)
        await database.prepare()
        await snippetDatabase.prepare()

        pasteboard = NSPasteboard.withUniqueName()
        monitor = ClipboardMonitor(
            database: database,
            appState: nil,
            snippetManager: SnippetManager(database: snippetDatabase),
            pasteboard: pasteboard
        )
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        for path in testPaths {
            try? FileManager.default.removeItem(atPath: path)
        }
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func copyImage() throws {
        pasteboard.clearContents()
        pasteboard.setData(try blankTIFF(width: 2, height: 2), forType: .tiff)
    }

    private func copyRichText(_ text: String) throws {
        let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        let rtf = try XCTUnwrap(attributed.rtf(from: NSRange(location: 0, length: attributed.length)))
        pasteboard.clearContents()
        pasteboard.setData(rtf, forType: .rtf)
        pasteboard.setString(text, forType: .string)
    }

    private func savedContents() async -> [String] {
        await database.getRecentClips(limit: 50).map(\.content)
    }

    // MARK: - Re-copies

    func testCheckClipboard_RecopyAfterDifferentType_SavesAgain() async throws {
        copy("A")
        await monitor.checkClipboard()
        try copyImage()
        await monitor.checkClipboard()
        copy("A")
        await monitor.checkClipboard()

        let clips = await database.getRecentClips(limit: 50)
        XCTAssertEqual(clips.count, 3, "Re-copying A after an image must not be dropped as a duplicate")
        XCTAssertEqual(clips.filter { $0.content == "A" }.count, 2)
    }

    func testCheckClipboard_RecopyAfterDeletingClip_SavesAgain() async throws {
        copy("secret-ish")
        await monitor.checkClipboard()
        let recent = await database.getRecentClips(limit: 1)
        let saved = try XCTUnwrap(recent.first)
        _ = await database.deleteClip(clipId: saved.id)

        copy("secret-ish")
        await monitor.checkClipboard()

        let contents = await savedContents()
        XCTAssertEqual(contents, ["secret-ish"])
    }

    func testCheckClipboard_SameContentCopiedTwiceInARow_SavesOnce() async {
        copy("same")
        await monitor.checkClipboard()
        copy("same")
        await monitor.checkClipboard()

        let contents = await savedContents()
        XCTAssertEqual(contents, ["same"])
    }

    // MARK: - App's own writes

    func testResumeMonitoring_SkipsOwnWriteButCapturesLaterCopy() async {
        await monitor.pauseMonitoring()
        copy("restored from history")
        await monitor.resumeMonitoring(afterOwnWriteAt: pasteboard.changeCount)
        await monitor.checkClipboard()

        var contents = await savedContents()
        XCTAssertEqual(contents, [], "The app's own write must not be captured")

        // The user copies something before the next poll.
        copy("user copy")
        await monitor.checkClipboard()
        contents = await savedContents()
        XCTAssertEqual(contents, ["user copy"])
    }

    func testCheckClipboard_WhilePaused_CapturesNothing() async {
        await monitor.pauseMonitoring()
        copy("during pause")
        await monitor.checkClipboard()

        let contents = await savedContents()
        XCTAssertEqual(contents, [])
    }

    // MARK: - Snippets

    func testCheckClipboard_TriggerCopiedAsRichText_Expands() async throws {
        let saved = await snippetDatabase.saveSnippet(trigger: ";tst", content: "Expanded body", description: "")
        XCTAssertTrue(saved)

        try copyRichText(";tst")
        await monitor.checkClipboard()

        XCTAssertEqual(pasteboard.string(forType: .string), "Expanded body")
        let clips = await database.getRecentClips(limit: 50)
        XCTAssertEqual(clips.map(\.content), ["Expanded body"])
        XCTAssertEqual(clips.first?.contentType, "text")

        // The expansion itself is the app's write and must not be captured a second time.
        await monitor.checkClipboard()
        let count = await database.getRecentClips(limit: 50).count
        XCTAssertEqual(count, 1)
    }

    func testCheckClipboard_TriggerCopiedAsPlainText_Expands() async {
        _ = await snippetDatabase.saveSnippet(trigger: ";tst", content: "Expanded body", description: "")

        copy(";tst")
        await monitor.checkClipboard()

        XCTAssertEqual(pasteboard.string(forType: .string), "Expanded body")
        let contents = await savedContents()
        XCTAssertEqual(contents, ["Expanded body"])
    }
}
