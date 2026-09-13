import XCTest
import SQLite
import CryptoKit
@testable import ClipboardManager

/// Covers the schema migration path, which previously tracked its progress in UserDefaults.
/// Because that state lived apart from the data it described, clearing preferences could
/// re-run the encryption steps over already-encrypted rows and destroy the history. These
/// tests pin down the two properties that make that impossible: migrations are versioned in
/// the database itself, and each step is individually idempotent.
final class MigrationTests: XCTestCase {
    private var databasePath: String!
    private var snippetPath: String!

    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        databasePath = tempDir.appendingPathComponent("migration_clips_\(UUID().uuidString).db").path
        snippetPath = tempDir.appendingPathComponent("migration_snippets_\(UUID().uuidString).db").path
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: databasePath)
        try? FileManager.default.removeItem(atPath: snippetPath)
        try await super.tearDown()
    }

    private func cipher() throws -> Cipher {
        Cipher(key: try KeychainKeyStore.loadOrCreateKey(
            service: "clipboard_manager_swift",
            account: "encryption_key"
        ))
    }

    // MARK: - Clipboard database

    func testPrepareIsIdempotent_RepeatedRunsDoNotCorruptClips() async throws {
        let database = ClipboardDatabase(path: databasePath)
        let imageBytes = Data(repeating: 0xAB, count: 512)
        await database.saveClip("Sensitive text", type: "image", image: imageBytes)

        // Run the migration far more often than any real upgrade would.
        for _ in 0..<5 {
            await database.prepare()
        }

        let clips = await database.getRecentClips(limit: 10)
        XCTAssertEqual(clips.count, 1, "Clip should survive repeated migrations")
        XCTAssertEqual(clips.first?.content, "Sensitive text", "Content must still decrypt to plaintext")

        guard let id = clips.first?.id else { return XCTFail("Missing clip id") }
        let storedImage = await database.getImageData(for: id)
        XCTAssertEqual(storedImage, imageBytes, "Image bytes must survive repeated migrations")
    }

    func testPrepareEncryptsLegacyPlaintextColumns() async throws {
        let cipher = try cipher()

        // Build a database shaped like an older install: content encrypted, but OCR text and
        // image bytes still sitting in plaintext.
        let legacyOCR = "one time code 123456"
        let legacyBlob = Data("legacy image bytes".utf8)
        do {
            let connection = try Connection(databasePath)
            try connection.run("""
                CREATE TABLE clips (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, content_type TEXT,
                    content TEXT, image_data BLOB, is_pinned INTEGER DEFAULT 0,
                    source_app TEXT, extracted_text TEXT
                )
            """)
            let encryptedContent = try XCTUnwrap(cipher.encrypt("[Image: 10x10]"))
            try connection.run(
                "INSERT INTO clips (timestamp, content_type, content, image_data, is_pinned, extracted_text) VALUES (?, ?, ?, ?, 0, ?)",
                ISO8601DateFormatter().string(from: Date()), "image", encryptedContent,
                Blob(bytes: [UInt8](legacyBlob)), legacyOCR
            )
        }

        let database = ClipboardDatabase(path: databasePath)
        await database.prepare()

        // Readable through the app...
        let clips = await database.getRecentClips(limit: 10)
        XCTAssertEqual(clips.first?.extractedText, legacyOCR, "OCR text should still read back as plaintext")
        let id = try XCTUnwrap(clips.first?.id)
        let recoveredBlob = await database.getImageData(for: id)
        XCTAssertEqual(recoveredBlob, legacyBlob, "Blob should still read back intact")

        // ...but no longer plaintext on disk.
        let connection = try Connection(databasePath)
        let storedOCR = try XCTUnwrap(connection.scalar("SELECT extracted_text FROM clips") as? String)
        XCTAssertNotEqual(storedOCR, legacyOCR, "OCR text must not remain in plaintext on disk")
        XCTAssertTrue(cipher.isEncrypted(storedOCR), "Stored OCR text should be ciphertext")

        let storedBlob = try XCTUnwrap(connection.scalar("SELECT image_data FROM clips") as? Blob)
        let storedBlobData = Data(storedBlob.bytes)
        XCTAssertNotEqual(storedBlobData, legacyBlob, "Blob must not remain in plaintext on disk")
        XCTAssertTrue(cipher.isEncrypted(storedBlobData), "Stored blob should be ciphertext")
    }

    func testInitializationRepairsLegacyTableBeforeCreatingIndexes() async throws {
        // This is the oldest supported shape: the index columns added in later releases do not
        // exist yet. Initialization must succeed so prepare() can finish the data migration.
        do {
            let connection = try Connection(databasePath)
            try connection.run("""
                CREATE TABLE clips (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT,
                    content_type TEXT,
                    content TEXT
                )
            """)
        }

        let database = ClipboardDatabase(path: databasePath)

        XCTAssertTrue(database.isInitialized, database.initializationError ?? "Unknown initialization error")
        await database.prepare()

        let connection = try Connection(databasePath)
        let columns = try connection.prepare("PRAGMA table_info(clips)").compactMap { row in
            row[1] as? String
        }
        XCTAssertTrue(columns.contains("is_pinned"))
        XCTAssertTrue(columns.contains("source_app"))
        XCTAssertTrue(columns.contains("extracted_text"))
    }

    func testPrepareDropsLegacyPlaintextSearchIndex() async throws {
        do {
            let connection = try Connection(databasePath)
            try connection.run("CREATE VIRTUAL TABLE clips_fts USING fts4(content)")
            try connection.run("INSERT INTO clips_fts (content) VALUES (?)", "plaintext leaked here")
        }

        let database = ClipboardDatabase(path: databasePath)
        await database.prepare()

        let connection = try Connection(databasePath)
        let remaining = try XCTUnwrap(connection.scalar(
            "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'clips_fts'"
        ) as? Int64)
        XCTAssertEqual(remaining, 0, "Legacy plaintext FTS index should be dropped")
    }

    func testPrepareRecordsSchemaVersion() async throws {
        let database = ClipboardDatabase(path: databasePath)
        await database.prepare()

        let connection = try Connection(databasePath)
        let version = try XCTUnwrap(connection.scalar("PRAGMA user_version") as? Int64)
        XCTAssertGreaterThan(version, 0, "Schema version should be stamped into the database")
    }

    // MARK: - Snippet database

    func testSnippetContentIsEncryptedAtRest() async throws {
        let database = SnippetDatabase(databasePath: snippetPath)
        let secret = "my.private.address@example.com"
        _ = await database.saveSnippet(trigger: ";email", content: secret, description: "Email")

        let connection = try Connection(snippetPath)
        let stored = try XCTUnwrap(connection.scalar("SELECT content FROM snippets") as? String)
        XCTAssertNotEqual(stored, secret, "Snippet body must not be stored in plaintext")

        let snippets = await database.getAllSnippets()
        XCTAssertEqual(snippets.first?.content, secret, "Snippet body should decrypt on read")
        XCTAssertEqual(snippets.first?.trigger, ";email", "Trigger stays plaintext for lookup")
    }

    func testSnippetPrepareIsIdempotent() async throws {
        let database = SnippetDatabase(databasePath: snippetPath)
        _ = await database.saveSnippet(trigger: ";sig", content: "Best regards", description: "Signature")

        for _ in 0..<5 {
            await database.prepare()
        }

        let snippets = await database.getAllSnippets()
        XCTAssertEqual(snippets.first?.content, "Best regards", "Repeated migrations must not corrupt snippets")
    }

    func testPrepareEncryptsLegacyPlaintextSnippets() async throws {
        let plaintext = "+1 (555) 123-4567"
        do {
            let connection = try Connection(snippetPath)
            try connection.run("""
                CREATE TABLE snippets (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, trigger TEXT UNIQUE, content TEXT,
                    description TEXT, created_at TEXT, usage_count INTEGER DEFAULT 0
                )
            """)
            try connection.run(
                "INSERT INTO snippets (trigger, content, description, created_at, usage_count) VALUES (?, ?, ?, ?, 0)",
                ";phone", plaintext, "Phone number", ISO8601DateFormatter().string(from: Date())
            )
        }

        let database = SnippetDatabase(databasePath: snippetPath)
        await database.prepare()

        let snippets = await database.getAllSnippets()
        XCTAssertEqual(snippets.first?.content, plaintext, "Legacy snippet should still read back correctly")

        let connection = try Connection(snippetPath)
        let stored = try XCTUnwrap(connection.scalar("SELECT content FROM snippets") as? String)
        XCTAssertNotEqual(stored, plaintext, "Legacy snippet body should now be encrypted")
    }
}
