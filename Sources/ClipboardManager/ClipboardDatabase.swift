import Foundation
import SQLite
import CryptoKit
import Vision
import AppKit
import os.log

struct ClipboardEntry: Hashable {
    let id: Int64
    let timestamp: Date
    let contentType: String
    let content: String
    let imageData: Data?  // Optional - loaded on demand for performance
    let isPinned: Bool
    let sourceApp: String?  // Name of app that created this clip
    let extractedText: String?  // OCR extracted text from images

    /// Single-line preview truncated to `maxLength`. Views pass the user's preferred preview
    /// length; the `previewText` shorthand keeps the compact default used in dense lists.
    func preview(maxLength: Int) -> String {
        if contentType == "image" {
            guard let extracted = extractedText, !extracted.isEmpty else { return content }
            return "[Image with text]: " + Self.condense(extracted, maxLength: maxLength)
        }
        return Self.condense(content, maxLength: maxLength)
    }

    var previewText: String { preview(maxLength: 50) }

    private static func condense(_ text: String, maxLength: Int) -> String {
        var preview = text.replacingOccurrences(of: "\n", with: " ")
        preview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.count > maxLength {
            preview = String(preview.prefix(maxLength)) + "..."
        }
        return preview
    }

    // Entries are considered equal and have the same hash if they have the same ID
    // (they represent the same database entity even if content changed)
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ClipboardEntry, rhs: ClipboardEntry) -> Bool {
        lhs.id == rhs.id
    }
}

/// Thread-safe database actor using Swift Concurrency
actor ClipboardDatabase {
    /// Bumped whenever the on-disk layout changes. Stored in the database itself via
    /// `PRAGMA user_version`, so migration state can never drift away from the data it
    /// describes - an earlier version tracked it in UserDefaults, where clearing preferences
    /// (or moving the database to a fresh account) re-ran the encryption migrations over
    /// already-encrypted rows and silently destroyed the history.
    private static let schemaVersion: Int64 = 1

    private let logger = Logger(subsystem: "com.clipboardmanager", category: "ClipboardDatabase")
    nonisolated(unsafe) private var db: Connection?
    nonisolated(unsafe) private let clips = Table("clips")

    nonisolated(unsafe) private let id = Expression<Int64>("id")
    nonisolated(unsafe) private let timestamp = Expression<String>("timestamp")
    nonisolated(unsafe) private let contentType = Expression<String>("content_type")
    nonisolated(unsafe) private let content = Expression<String>("content")
    nonisolated(unsafe) private let imageData = Expression<Data?>("image_data")
    nonisolated(unsafe) private let isPinned = Expression<Bool>("is_pinned")
    nonisolated(unsafe) private let sourceApp = Expression<String?>("source_app")
    nonisolated(unsafe) private let extractedText = Expression<String?>("extracted_text")

    // Cipher and connection are set once during init and never modified.
    // Using nonisolated(unsafe) because SQLite.swift doesn't support Sendable.
    // Safe because: init runs single-threaded, then all access is serialized by the actor.
    nonisolated(unsafe) private var cipher: Cipher?

    /// Why startup failed, or nil if the database is usable. Written only in init.
    nonisolated(unsafe) private(set) var initializationError: String?

    nonisolated var isInitialized: Bool { initializationError == nil }

    // Reuse ISO8601DateFormatter for better performance
    private let isoFormatter = ISO8601DateFormatter()

    // Path used by this database instance (for cleanup in tests)
    nonisolated(unsafe) private(set) var databasePath: String = ""

    /// Opens the database and loads the encryption key. Kept cheap and side-effect free -
    /// schema migrations run in `prepare()` so they don't block app launch on the main thread.
    init(path: String? = nil) {
        do {
            let dbPath = path ?? NSHomeDirectory() + "/.clipboard_history.db"
            databasePath = dbPath
            let connection = try Connection(dbPath)
            db = connection

            // Set restrictive file permissions (owner read/write only)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: dbPath
            )

            try createSchema(connection)
            cipher = Cipher(key: try KeychainKeyStore.loadOrCreateKey(
                service: "clipboard_manager_swift",
                account: "encryption_key"
            ))
        } catch {
            logger.error("Failed to initialize database: \(error.localizedDescription)")
            initializationError = error.localizedDescription
        }
    }

    private nonisolated func createSchema(_ connection: Connection) throws {
        try connection.run(clips.create(ifNotExists: true) { table in
            table.column(id, primaryKey: .autoincrement)
            table.column(timestamp)
            table.column(contentType)
            table.column(content)
            table.column(imageData)
            table.column(isPinned, defaultValue: false)
            table.column(sourceApp)
            table.column(extractedText)
        })

        try connection.run(clips.createIndex(timestamp, ifNotExists: true))
        try connection.run(clips.createIndex(isPinned, ifNotExists: true))
        try connection.run(clips.createIndex(contentType, ifNotExists: true))
    }

    // MARK: - Migration

    /// Brings an existing database up to the current schema version. Safe to call repeatedly;
    /// every step is individually idempotent.
    func prepare() async {
        guard let connection = db else { return }

        do {
            let version = try connection.scalar("PRAGMA user_version") as? Int64 ?? 0
            guard version < Self.schemaVersion else { return }

            logger.info("Migrating database from schema version \(version) to \(Self.schemaVersion)")

            try addMissingColumns(connection)
            try encryptLegacyPlaintextColumns(connection)
            try dropLegacyPlaintextIndex(connection)

            try connection.run("PRAGMA user_version = \(Self.schemaVersion)")
            logger.info("Database migration complete")
        } catch {
            logger.error("Database migration failed: \(error.localizedDescription)")
        }
    }

    private func addMissingColumns(_ connection: Connection) throws {
        let tableInfo = try connection.prepare("PRAGMA table_info(clips)")
        var columns = Set<String>()
        for row in tableInfo {
            if let columnName = row[1] as? String {
                columns.insert(columnName)
            }
        }

        if !columns.contains("image_data") {
            try connection.run("ALTER TABLE clips ADD COLUMN image_data BLOB")
        }
        if !columns.contains("is_pinned") {
            try connection.run("ALTER TABLE clips ADD COLUMN is_pinned INTEGER DEFAULT 0")
        }
        if !columns.contains("source_app") {
            try connection.run("ALTER TABLE clips ADD COLUMN source_app TEXT")
        }
        if !columns.contains("extracted_text") {
            try connection.run("ALTER TABLE clips ADD COLUMN extracted_text TEXT")
        }
    }

    /// OCR text and image/RTF blobs were both stored unencrypted in earlier versions.
    ///
    /// Rows that already decrypt cleanly are skipped, so re-running this is harmless. That
    /// check is what makes the migration safe: GCM's authentication tag means plaintext will
    /// not masquerade as valid ciphertext, and encrypting an already-encrypted value a second
    /// time would leave the data permanently unreadable.
    private func encryptLegacyPlaintextColumns(_ connection: Connection) throws {
        guard let cipher else { return }

        var migratedText = 0
        for row in try connection.prepare(clips.filter(extractedText != nil)) {
            guard let value = row[extractedText], !value.isEmpty else { continue }
            guard !cipher.isEncrypted(value) else { continue }
            guard let encrypted = cipher.encrypt(value) else { continue }
            try connection.run(clips.filter(id == row[id]).update(extractedText <- encrypted))
            migratedText += 1
        }

        var migratedBlobs = 0
        for row in try connection.prepare(clips.filter(imageData != nil)) {
            guard let value = row[imageData], !value.isEmpty else { continue }
            guard !cipher.isEncrypted(value) else { continue }
            guard let encrypted = cipher.encrypt(value) else { continue }
            try connection.run(clips.filter(id == row[id]).update(imageData <- encrypted))
            migratedBlobs += 1
        }

        if migratedText > 0 || migratedBlobs > 0 {
            logger.info("Encrypted \(migratedText) legacy OCR value(s) and \(migratedBlobs) legacy blob(s)")
        }
    }

    /// Older versions maintained a `clips_fts` index whose shadow tables held an unencrypted
    /// copy of every clip, defeating the at-rest encryption. Drop it and reclaim the freed
    /// pages so those bytes are actually overwritten rather than merely unlinked.
    private func dropLegacyPlaintextIndex(_ connection: Connection) throws {
        let existing = try connection.scalar(
            "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'clips_fts'"
        ) as? Int64 ?? 0
        guard existing > 0 else { return }

        try connection.run("DROP TABLE IF EXISTS clips_fts")
        try connection.run("VACUUM")
        logger.info("Dropped legacy plaintext FTS index")
    }

    // MARK: - Encryption helpers

    private func encrypt(_ text: String) -> String? {
        guard let encrypted = cipher?.encrypt(text) else {
            logger.error("Encryption failed - no key available")
            return nil
        }
        return encrypted
    }

    // Decryption failures are not logged: the message could echo sensitive material, and a
    // failure just means corrupted data or a key mismatch.
    private func decrypt(_ encryptedText: String) -> String? {
        cipher?.decrypt(encryptedText)
    }

    private func encryptBinary(_ data: Data) -> Data? {
        cipher?.encrypt(data)
    }

    private func decryptBinary(_ data: Data) -> Data? {
        cipher?.decrypt(data)
    }

    // MARK: - OCR

    /// Extract text from image data using Vision framework
    private func extractTextFromImage(_ imageData: Data) async -> String? {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: recognizedText.isEmpty ? nil : recognizedText)
            }

            // Configure for accurate text recognition
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    func saveClip(
        _ text: String,
        type: String = "text",
        image: Data? = nil,
        rtfData: Data? = nil,
        sourceApp: String? = nil
    ) async {
        guard let encryptedContent = encrypt(text) else {
            logger.error("Failed to encrypt clip content - clip not saved")
            return
        }

        // Perform OCR on images if enabled
        var ocrText: String?
        if type == "image", let imageData = image, Preferences.isOCREnabled {
            ocrText = await extractTextFromImage(imageData)
        }

        // OCR text can contain anything visible in a screenshot (passwords, codes, documents),
        // so it must be encrypted the same as the clip content itself.
        let encryptedOcrText = ocrText.flatMap { encrypt($0) }

        // Use imageData field for both images and RTF data
        let binaryData = image ?? rtfData
        let encryptedBinaryData: Data?
        if let binaryData {
            guard let encrypted = encryptBinary(binaryData) else {
                logger.error("Failed to encrypt image/RTF data - clip not saved")
                return
            }
            encryptedBinaryData = encrypted
        } else {
            encryptedBinaryData = nil
        }

        do {
            let now = isoFormatter.string(from: Date())
            _ = try db?.run(clips.insert(
                timestamp <- now,
                contentType <- type,
                content <- encryptedContent,
                imageData <- encryptedBinaryData,
                isPinned <- false,
                self.sourceApp <- sourceApp,
                extractedText <- encryptedOcrText
            ))
        } catch {
            // Log database save failures for debugging
            logger.error("Failed to save clip to database: \(error.localizedDescription)")
        }
    }

    func getRecentClips(limit: Int = 50) async -> [ClipboardEntry] {
        var entries: [ClipboardEntry] = []

        do {
            // Order by pinned first, then by timestamp
            let query = clips.order(isPinned.desc, timestamp.desc).limit(limit)
            guard let results = try db?.prepare(query) else { return entries }

            for row in results {
                if let entry = makeEntry(from: row) {
                    entries.append(entry)
                }
            }
        } catch {
            // Log error but return empty array (graceful degradation)
            logger.error("Failed to retrieve recent clips: \(error.localizedDescription)")
        }

        return entries
    }

    private func makeEntry(from row: Row) -> ClipboardEntry? {
        guard let decryptedContent = decrypt(row[content]) else { return nil }
        return ClipboardEntry(
            id: row[id],
            timestamp: isoFormatter.date(from: row[timestamp]) ?? Date(),
            contentType: row[contentType],
            content: decryptedContent,
            imageData: nil,  // Don't load image data here - load on demand for performance
            isPinned: row[isPinned],
            sourceApp: row[sourceApp],
            extractedText: row[extractedText].flatMap { decrypt($0) }
        )
    }

    // Get image data on demand for a specific clip (lazy loading)
    func getImageData(for clipId: Int64) async -> Data? {
        do {
            let query = clips.filter(id == clipId)
            guard let row = try db?.pluck(query), let encrypted = row[imageData] else { return nil }
            return decryptBinary(encrypted)
        } catch {
            return nil
        }
    }

    // Check if the most recent clip matches the given content/data
    // This is used to prevent duplicate entries
    func isDuplicate(text: String, type: String, imageBytes: Data? = nil, rtfBytes: Data? = nil) async -> Bool {
        do {
            // Get the most recent clip of the same type
            let query = clips.filter(contentType == type)
                .order(timestamp.desc)
                .limit(1)
            guard let row = try db?.pluck(query) else { return false }

            // Decrypt the stored content
            guard let storedContent = decrypt(row[content]) else { return false }

            // For images and RTF, compare decrypted binary data
            if type == "image", let newImageData = imageBytes {
                let storedImageData = row[imageData].flatMap { decryptBinary($0) }
                return storedImageData == newImageData
            } else if type == "rtf", let newRtfData = rtfBytes {
                let storedRtfData = row[imageData].flatMap { decryptBinary($0) } // RTF stored in imageData field
                return storedRtfData == newRtfData
            } else {
                // For text, compare content
                return storedContent == text
            }
        } catch {
            return false
        }
    }

    func togglePin(clipId: Int64) async -> Bool {
        do {
            let clip = clips.filter(id == clipId)
            guard let row = try db?.pluck(clip) else {
                logger.warning("Failed to toggle pin - clip not found (id: \(clipId))")
                return false
            }

            let currentPinned = row[isPinned]
            try db?.run(clip.update(isPinned <- !currentPinned))
            return !currentPinned
        } catch {
            logger.error("Failed to toggle pin (clipId: \(clipId)): \(error.localizedDescription)")
            return false
        }
    }

    func deleteClip(clipId: Int64) async -> Bool {
        do {
            let clip = clips.filter(id == clipId)
            try db?.run(clip.delete())
            return true
        } catch {
            logger.error("Failed to delete clip (clipId: \(clipId)): \(error.localizedDescription)")
            return false
        }
    }

    // Search by decrypting clips in memory and filtering - nothing plaintext ever touches disk.
    // (Previously used a SQLite FTS index, but FTS shadow tables store an unencrypted copy of
    // every clip's content, which defeated the at-rest encryption entirely.)
    //
    // Cancellation is honoured between rows so a superseded keystroke stops decrypting
    // immediately instead of racing the query the user actually cares about.
    func searchClips(query: String, limit: Int = 5000) async -> [ClipboardEntry] {
        var entries: [ClipboardEntry] = []
        guard !query.isEmpty else { return entries }

        do {
            let searchQuery = clips.order(isPinned.desc, timestamp.desc).limit(limit)
            guard let results = try db?.prepare(searchQuery) else { return entries }

            for row in results {
                if Task.isCancelled { return [] }

                guard let decryptedContent = decrypt(row[content]) else { continue }
                let extracted = row[extractedText].flatMap { decrypt($0) }

                let matches = decryptedContent.localizedCaseInsensitiveContains(query)
                    || (extracted?.localizedCaseInsensitiveContains(query) ?? false)
                guard matches else { continue }

                entries.append(ClipboardEntry(
                    id: row[id],
                    timestamp: isoFormatter.date(from: row[timestamp]) ?? Date(),
                    contentType: row[contentType],
                    content: decryptedContent,
                    imageData: nil,  // Lazy load image data
                    isPinned: row[isPinned],
                    sourceApp: row[sourceApp],
                    extractedText: extracted
                ))
            }
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
        }

        return entries
    }

    func cleanupOldClips(days: Int) async -> Int {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) else {
            return 0
        }

        let cutoffString = isoFormatter.string(from: cutoffDate)

        do {
            let deleted = try db?.run(clips.filter(timestamp < cutoffString).delete()) ?? 0
            return deleted
        } catch {
            return 0
        }
    }

    func clearLast24Hours() async -> Int {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .hour, value: -24, to: Date()) else {
            return 0
        }

        let cutoffString = isoFormatter.string(from: cutoffDate)

        do {
            // Delete clips from last 24 hours (newer than cutoff), but keep pinned ones
            let deleted = try db?.run(clips.filter(timestamp >= cutoffString && isPinned == false).delete()) ?? 0
            return deleted
        } catch {
            return 0
        }
    }

    func clearAllHistory(keepPinned: Bool = true) async -> Int {
        do {
            if keepPinned {
                // Delete all except pinned
                let deleted = try db?.run(clips.filter(isPinned == false).delete()) ?? 0
                return deleted
            } else {
                // Delete everything
                let deleted = try db?.run(clips.delete()) ?? 0
                return deleted
            }
        } catch {
            return 0
        }
    }

    func getTotalClipsCount() async -> Int {
        do {
            return try db?.scalar(clips.count) ?? 0
        } catch {
            return 0
        }
    }

    func getDatabaseSize() async -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: databasePath)
            if let fileSize = attributes[.size] as? Int64 {
                let bytes = Double(fileSize)
                if bytes < 1024 {
                    return "\(Int(bytes)) bytes"
                } else if bytes < 1024 * 1024 {
                    return String(format: "%.1f KB", bytes / 1024.0)
                } else {
                    return String(format: "%.2f MB", bytes / (1024.0 * 1024.0))
                }
            }
        } catch {
            return "Unknown"
        }
        return "Unknown"
    }
}
