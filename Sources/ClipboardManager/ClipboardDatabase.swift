import Foundation
import SQLite
import CryptoKit
import Vision
import AppKit

struct ClipboardEntry: Hashable {
    let id: Int64
    let timestamp: Date
    let contentType: String
    let content: String
    let imageData: Data?  // Optional - loaded on demand for performance
    let isPinned: Bool
    let sourceApp: String?  // Name of app that created this clip
    let extractedText: String?  // OCR extracted text from images

    // Cached preview text for better performance
    var previewText: String {
        if contentType == "image" {
            // If we have extracted text, show it
            if let extracted = extractedText, !extracted.isEmpty {
                var preview = extracted.replacingOccurrences(of: "\n", with: " ")
                preview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
                if preview.count > 50 {
                    preview = String(preview.prefix(50)) + "..."
                }
                return "[Image with text]: " + preview
            }
            return content
        }
        var preview = content.replacingOccurrences(of: "\n", with: " ")
        preview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.count > 50 {
            preview = String(preview.prefix(50)) + "..."
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
    nonisolated(unsafe) private var db: Connection?
    nonisolated(unsafe) private let clips = Table("clips")
    nonisolated(unsafe) private let clipsFTS = VirtualTable("clips_fts")  // Full-text search table

    nonisolated(unsafe) private let id = Expression<Int64>("id")
    nonisolated(unsafe) private let timestamp = Expression<String>("timestamp")
    nonisolated(unsafe) private let contentType = Expression<String>("content_type")
    nonisolated(unsafe) private let content = Expression<String>("content")
    nonisolated(unsafe) private let imageData = Expression<Data?>("image_data")
    nonisolated(unsafe) private let isPinned = Expression<Bool>("is_pinned")
    nonisolated(unsafe) private let sourceApp = Expression<String?>("source_app")
    nonisolated(unsafe) private let extractedText = Expression<String?>("extracted_text")

    // FTS columns
    nonisolated(unsafe) private let rowid = Expression<Int64>("rowid")
    nonisolated(unsafe) private let ftsContent = Expression<String>("content")

    // Encryption key and connection are set once during init and never modified
    // Using nonisolated(unsafe) because SQLite.swift doesn't support Sendable
    // Safe because: init runs single-threaded, then all access is serialized by actor
    nonisolated(unsafe) private var encryptionKey: SymmetricKey?

    // isInitialized is written only in init, then read-only - safe for nonisolated(unsafe)
    nonisolated(unsafe) var isInitialized = false

    // Reuse ISO8601DateFormatter for better performance
    private let isoFormatter = ISO8601DateFormatter()

    // Path used by this database instance (for cleanup in tests)
    nonisolated(unsafe) private(set) var databasePath: String = ""

    init(path: String? = nil) {
        // Initialize all properties first before any method calls to satisfy Swift 6 concurrency
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

            // Initialize database schema
            try initializeSchema(connection)

            // Migrate and populate FTS
            try migrateAndPopulateFTS(connection)

            isInitialized = true
        } catch {
            print("Failed to initialize database: \(error)")
            isInitialized = false
        }
    }

    private nonisolated func initializeSchema(_ connection: Connection) throws {
        try connection.run(clips.create(ifNotExists: true) { table in
            table.column(id, primaryKey: .autoincrement)
            table.column(timestamp)
            table.column(contentType)
            table.column(content)
            table.column(imageData)
            table.column(isPinned, defaultValue: false)
        })

        try connection.run(clips.createIndex(timestamp, ifNotExists: true))
        try connection.run(clips.createIndex(isPinned, ifNotExists: true))
        try connection.run(clips.createIndex(contentType, ifNotExists: true))

        try connection.run(clipsFTS.create(.FTS4([ftsContent]), ifNotExists: true))
    }

    private nonisolated func migrateAndPopulateFTS(_ connection: Connection) throws {
        // Migrate database
        let tableInfo = try connection.prepare("PRAGMA table_info(clips)")
        var columns = Set<String>()

        for row in tableInfo where row[1] as? String != nil {
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

        // Initialize encryption key
        try initializeEncryptionKey()

        // Populate FTS if needed
        let count = try connection.scalar(clipsFTS.count)
        if count == 0 {
            let allClips = try connection.prepare(clips)
            for row in allClips {
                let encryptedText = row[content]
                if let encKey = encryptionKey,
                   let data = Data(base64Encoded: encryptedText),
                   let decrypted = decryptForMigration(data, using: encKey) {
                    try connection.run(clipsFTS.insert(
                        rowid <- row[id],
                        ftsContent <- decrypted
                    ))
                }
            }
        }
    }

    private nonisolated func initializeEncryptionKey() throws {
        let service = "clipboard_manager_swift"
        let account = "encryption_key"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let keyData = result as? Data {
            encryptionKey = SymmetricKey(data: keyData)
        } else {
            let newKey = SymmetricKey(size: .bits256)
            let keyData = newKey.withUnsafeBytes { Data($0) }

            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: keyData,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                print("Error: Failed to save encryption key to keychain (status: \(addStatus))")
            }
            encryptionKey = newKey
        }
    }

    private nonisolated func decryptForMigration(_ data: Data, using key: SymmetricKey) -> String? {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func encrypt(_ text: String) -> String? {
        guard let key = encryptionKey,
              let data = text.data(using: .utf8) else { return nil }

        do {
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { return nil }
            return combined.base64EncodedString()
        } catch {
            print("Encryption error: \(error.localizedDescription)")
            return nil
        }
    }

    private func decrypt(_ encryptedText: String) -> String? {
        guard let key = encryptionKey,
              let data = Data(base64Encoded: encryptedText) else { return nil }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            // Decryption can fail for corrupted data or wrong key
            // Don't log the error as it could expose sensitive info
            return nil
        }
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

    func saveClip(_ text: String, type: String = "text", image: Data? = nil, rtfData: Data? = nil, sourceApp: String? = nil) async {
        guard let encryptedContent = encrypt(text) else {
            print("Error: Failed to encrypt clip content - clip not saved")
            return
        }

        // Perform OCR on images if enabled
        var ocrText: String?
        let ocrEnabled = UserDefaults.standard.bool(forKey: "ocrEnabled")
        if type == "image", let imageData = image, (ocrEnabled || !UserDefaults.standard.dictionaryRepresentation().keys.contains("ocrEnabled")) {
            ocrText = await extractTextFromImage(imageData)
        }

        do {
            let now = isoFormatter.string(from: Date())
            // Use imageData field for both images and RTF data
            let binaryData = image ?? rtfData
            let clipId = try db?.run(clips.insert(
                timestamp <- now,
                contentType <- type,
                content <- encryptedContent,
                imageData <- binaryData,
                isPinned <- false,
                self.sourceApp <- sourceApp,
                extractedText <- ocrText
            ))

            // Add to FTS index for fast searching
            // Store decrypted content + extracted text in FTS for searchability
            if let clipId = clipId {
                var searchableText = text
                if let extracted = ocrText, !extracted.isEmpty {
                    searchableText += " " + extracted
                }
                do {
                    try db?.run(clipsFTS.insert(
                        rowid <- clipId,
                        ftsContent <- searchableText
                    ))
                } catch {
                    // Log FTS insertion failure but don't fail the entire save
                    // The clip is saved but won't be searchable via FTS
                    print("Warning: Failed to add clip to FTS index (clipId: \(clipId)): \(error)")
                }
            }
        } catch {
            // Log database save failures for debugging
            print("Error: Failed to save clip to database: \(error)")
        }
    }

    func getRecentClips(limit: Int = 50) async -> [ClipboardEntry] {
        var entries: [ClipboardEntry] = []

        do {
            // Order by pinned first, then by timestamp
            let query = clips.order(isPinned.desc, timestamp.desc).limit(limit)
            guard let results = try db?.prepare(query) else { return entries }

            for row in results {
                if let decryptedContent = decrypt(row[content]) {
                    let date = isoFormatter.date(from: row[timestamp]) ?? Date()

                    let entry = ClipboardEntry(
                        id: row[id],
                        timestamp: date,
                        contentType: row[contentType],
                        content: decryptedContent,
                        imageData: nil,  // Don't load image data here - load on demand for performance
                        isPinned: row[isPinned],
                        sourceApp: row[sourceApp],
                        extractedText: row[extractedText]
                    )
                    entries.append(entry)
                }
            }
        } catch {
            // Log error but return empty array (graceful degradation)
            print("Error: Failed to retrieve recent clips: \(error)")
        }

        return entries
    }

    // Get image data on demand for a specific clip (lazy loading)
    func getImageData(for clipId: Int64) async -> Data? {
        do {
            let query = clips.filter(id == clipId)
            guard let row = try db?.pluck(query) else { return nil }
            return row[imageData]
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

            // For images and RTF, compare binary data
            if type == "image", let newImageData = imageBytes {
                let storedImageData = row[imageData]
                return storedImageData == newImageData
            } else if type == "rtf", let newRtfData = rtfBytes {
                let storedRtfData = row[imageData] // RTF stored in imageData field
                return storedRtfData == newRtfData
            } else {
                // For text, compare content
                return storedContent == text
            }
        } catch {
            return false
        }
    }

    // Removed: inefficient searchClips() method that decrypted all clips
    // Use searchClipsWithFTS() instead for fast full-text search

    func togglePin(clipId: Int64) async -> Bool {
        do {
            let clip = clips.filter(id == clipId)
            guard let row = try db?.pluck(clip) else {
                print("Warning: Failed to toggle pin - clip not found (id: \(clipId))")
                return false
            }

            let currentPinned = row[isPinned]
            try db?.run(clip.update(isPinned <- !currentPinned))
            return !currentPinned
        } catch {
            print("Error: Failed to toggle pin (clipId: \(clipId)): \(error)")
            return false
        }
    }

    func deleteClip(clipId: Int64) async -> Bool {
        do {
            let clip = clips.filter(id == clipId)
            try db?.run(clip.delete())

            // Also delete from FTS index
            let ftsClip = clipsFTS.filter(rowid == clipId)
            try db?.run(ftsClip.delete())

            return true
        } catch {
            print("Error: Failed to delete clip (clipId: \(clipId)): \(error)")
            return false
        }
    }

    // Search using FTS (Full-Text Search) for better performance
    func searchClipsWithFTS(query: String) async -> [ClipboardEntry] {
        var entries: [ClipboardEntry] = []

        do {
            guard let db = db else { return entries }

            // Use FTS MATCH for fast full-text search
            // Escape special FTS characters to prevent query errors
            let escapedQuery = query.replacingOccurrences(of: "\"", with: "\"\"")
            // Select rowid explicitly from FTS results
            let ftsQuery = clipsFTS.select(rowid).filter(clipsFTS.match(escapedQuery))
            let results = try db.prepare(ftsQuery)

            var clipIds: [Int64] = []
            for row in results {
                let docid = row[rowid]
                clipIds.append(docid)
            }

            // Fetch full clip details for matching IDs
            if !clipIds.isEmpty {
                let matchingClips = clips.filter(clipIds.contains(id))
                let query = matchingClips.order(timestamp.desc)
                for row in try db.prepare(query) {
                    if let decryptedContent = decrypt(row[content]) {
                        let date = isoFormatter.date(from: row[timestamp]) ?? Date()

                        let entry = ClipboardEntry(
                            id: row[id],
                            timestamp: date,
                            contentType: row[contentType],
                            content: decryptedContent,
                            imageData: nil,  // Lazy load image data
                            isPinned: row[isPinned],
                            sourceApp: row[sourceApp],
                            extractedText: row[extractedText]
                        )
                        entries.append(entry)
                    }
                }
            }
        } catch {
            // If FTS fails, return empty results (FTS should be working)
            // This prevents falling back to inefficient full-table scan
            print("FTS search failed: \(error)")
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
        let path = NSHomeDirectory() + "/.clipboard_history.db"
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
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

    /// Recover clips from FTS table that are missing from main clips table
    /// This can happen if clips were accidentally deleted but FTS index remains
    func recoverFromFTS() async -> Int {
        guard let db = db else { return 0 }

        var recovered = 0
        do {
            // Find all FTS entries that don't have corresponding clips
            let query = """
                SELECT rowid, content FROM clips_fts
                WHERE rowid NOT IN (SELECT id FROM clips)
                ORDER BY rowid
            """

            let now = isoFormatter.string(from: Date())

            for row in try db.prepare(query) {
                guard let ftsRowId = row[0] as? Int64,
                      let textContent = row[1] as? String else { continue }

                // Skip empty content
                guard !textContent.isEmpty else { continue }

                // Encrypt the content
                guard let encryptedContent = encrypt(textContent) else { continue }

                // Insert back into clips table with recovered timestamp
                do {
                    try db.run(clips.insert(
                        id <- ftsRowId,
                        timestamp <- now,
                        contentType <- "text",
                        content <- encryptedContent,
                        imageData <- nil,
                        isPinned <- false,
                        sourceApp <- "Recovered",
                        extractedText <- nil
                    ))
                    recovered += 1
                } catch {
                    // Skip duplicates or other errors
                    continue
                }
            }

            print("Recovered \(recovered) clips from FTS index")
        } catch {
            print("FTS recovery failed: \(error)")
        }

        return recovered
    }
}
