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

    init() {
        // Initialize all properties first before any method calls to satisfy Swift 6 concurrency
        do {
            let path = NSHomeDirectory() + "/.clipboard_history.db"
            let connection = try Connection(path)
            db = connection

            // Set restrictive file permissions (owner read/write only)
            // This prevents other users from reading the encrypted database
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: path
            )

            // Initialize database schema inline
            try connection.run(clips.create(ifNotExists: true) { table in
                table.column(id, primaryKey: .autoincrement)
                table.column(timestamp)
                table.column(contentType)
                table.column(content)
                table.column(imageData)
                table.column(isPinned, defaultValue: false)
            })

            // Create indexes for faster searches and filtering
            try connection.run(clips.createIndex(timestamp, ifNotExists: true))
            try connection.run(clips.createIndex(isPinned, ifNotExists: true))
            try connection.run(clips.createIndex(contentType, ifNotExists: true))

            // Create FTS4 virtual table for full-text search
            try connection.run(clipsFTS.create(.FTS4([ftsContent]), ifNotExists: true))

            // Migrate database inline
            let tableInfo = try connection.prepare("PRAGMA table_info(clips)")
            var hasImageDataColumn = false
            var hasPinnedColumn = false
            var hasSourceAppColumn = false
            var hasExtractedTextColumn = false

            for row in tableInfo {
                if let columnName = row[1] as? String {
                    if columnName == "image_data" {
                        hasImageDataColumn = true
                    }
                    if columnName == "is_pinned" {
                        hasPinnedColumn = true
                    }
                    if columnName == "source_app" {
                        hasSourceAppColumn = true
                    }
                    if columnName == "extracted_text" {
                        hasExtractedTextColumn = true
                    }
                }
            }

            if !hasImageDataColumn {
                try connection.run("ALTER TABLE clips ADD COLUMN image_data BLOB")
                print("Database migrated: added image_data column")
            }

            if !hasPinnedColumn {
                try connection.run("ALTER TABLE clips ADD COLUMN is_pinned INTEGER DEFAULT 0")
                print("Database migrated: added is_pinned column")
            }

            if !hasSourceAppColumn {
                try connection.run("ALTER TABLE clips ADD COLUMN source_app TEXT")
                print("Database migrated: added source_app column")
            }

            if !hasExtractedTextColumn {
                try connection.run("ALTER TABLE clips ADD COLUMN extracted_text TEXT")
                print("Database migrated: added extracted_text column")
            }

            // Populate FTS index inline
            let count = try connection.scalar(clipsFTS.count)
            if count == 0 {
                // Get all clips and populate FTS
                let allClips = try connection.prepare(clips)
                for row in allClips {
                    // Inline decryption - get or create key first
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

                    let key: SymmetricKey
                    if status == errSecSuccess, let keyData = result as? Data {
                        key = SymmetricKey(data: keyData)
                    } else {
                        // Create new key
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
                        key = newKey
                    }

                    // Set encryption key property
                    encryptionKey = key

                    // Now decrypt and populate FTS
                    let encryptedText = row[content]
                    if let encKey = encryptionKey,
                       let data = Data(base64Encoded: encryptedText) {
                        do {
                            let sealedBox = try AES.GCM.SealedBox(combined: data)
                            let decryptedData = try AES.GCM.open(sealedBox, using: encKey)
                            if let decryptedContent = String(data: decryptedData, encoding: .utf8) {
                                try connection.run(clipsFTS.insert(
                                    rowid <- row[id],
                                    ftsContent <- decryptedContent
                                ))
                            }
                        } catch {
                            // Skip this entry if decryption fails
                        }
                    }
                }
            } else if encryptionKey == nil {
                // FTS already populated but we still need encryption key
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

                    _ = SecItemAdd(addQuery as CFDictionary, nil)
                    encryptionKey = newKey
                }
            }

            isInitialized = true
        } catch {
            print("Failed to initialize database: \(error)")
            isInitialized = false
        }
    }

    private func initializeDatabase() throws {
        try db?.run(clips.create(ifNotExists: true) { table in
            table.column(id, primaryKey: .autoincrement)
            table.column(timestamp)
            table.column(contentType)
            table.column(content)
            table.column(imageData)
            table.column(isPinned, defaultValue: false)
        })

        // Create indexes for faster searches and filtering
        try db?.run(clips.createIndex(timestamp, ifNotExists: true))
        try db?.run(clips.createIndex(isPinned, ifNotExists: true))
        try db?.run(clips.createIndex(contentType, ifNotExists: true))

        // Create FTS4 virtual table for full-text search
        // FTS4 provides fast full-text search capabilities
        try db?.run(clipsFTS.create(.FTS4([ftsContent]), ifNotExists: true))

        // Migrate existing database to add new columns if they don't exist
        try migrateDatabase()

        // Populate FTS table with existing data (run only once or when needed)
        try populateFTSIndex()
    }

    private func migrateDatabase() throws {
        guard let db = db else { return }

        // Check existing columns
        let tableInfo = try db.prepare("PRAGMA table_info(clips)")
        var hasImageDataColumn = false
        var hasPinnedColumn = false
        var hasSourceAppColumn = false
        var hasExtractedTextColumn = false

        for row in tableInfo {
            if let columnName = row[1] as? String {
                if columnName == "image_data" {
                    hasImageDataColumn = true
                }
                if columnName == "is_pinned" {
                    hasPinnedColumn = true
                }
                if columnName == "source_app" {
                    hasSourceAppColumn = true
                }
                if columnName == "extracted_text" {
                    hasExtractedTextColumn = true
                }
            }
        }

        // Add image_data column if it doesn't exist
        if !hasImageDataColumn {
            try db.run("ALTER TABLE clips ADD COLUMN image_data BLOB")
            print("Database migrated: added image_data column")
        }

        // Add is_pinned column if it doesn't exist
        if !hasPinnedColumn {
            try db.run("ALTER TABLE clips ADD COLUMN is_pinned INTEGER DEFAULT 0")
            print("Database migrated: added is_pinned column")
        }

        // Add source_app column if it doesn't exist
        if !hasSourceAppColumn {
            try db.run("ALTER TABLE clips ADD COLUMN source_app TEXT")
            print("Database migrated: added source_app column")
        }

        // Add extracted_text column if it doesn't exist
        if !hasExtractedTextColumn {
            try db.run("ALTER TABLE clips ADD COLUMN extracted_text TEXT")
            print("Database migrated: added extracted_text column")
        }
    }

    private func getOrCreateEncryptionKey() throws -> SymmetricKey {
        let service = "clipboard_manager_swift"  // Use different service name to avoid conflict
        let account = "encryption_key"

        // Try to retrieve existing key from Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let keyData = result as? Data {
            print("Found existing Swift encryption key")
            return SymmetricKey(data: keyData)
        }

        // Key doesn't exist, create a new one
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
            // This is critical - without keychain storage, the key is lost on app restart
            // User should be notified, but we'll still return the key for this session
        }
        return newKey
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
        guard let encryptedContent = encrypt(text) else { return }

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
                try db?.run(clipsFTS.insert(
                    rowid <- clipId,
                    ftsContent <- searchableText
                ))
            }
        } catch {
            // Silent failure
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
            // Silent failure
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

    // Removed: inefficient searchClips() method that decrypted all clips
    // Use searchClipsWithFTS() instead for fast full-text search

    func togglePin(clipId: Int64) async -> Bool {
        do {
            let clip = clips.filter(id == clipId)
            guard let row = try db?.pluck(clip) else { return false }

            let currentPinned = row[isPinned]
            try db?.run(clip.update(isPinned <- !currentPinned))
            return !currentPinned
        } catch {
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
                for row in try db.prepare(matchingClips.order(timestamp.desc)) {
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

    // Populate FTS index with existing clips (migration helper)
    private func populateFTSIndex() throws {
        guard let db = db else { return }

        // Check if FTS table is empty
        let count = try db.scalar(clipsFTS.count)
        if count > 0 {
            return  // Already populated
        }

        // Get all clips and populate FTS
        let allClips = try db.prepare(clips)
        for row in allClips {
            if let decryptedContent = decrypt(row[content]) {
                try db.run(clipsFTS.insert(
                    rowid <- row[id],
                    ftsContent <- decryptedContent
                ))
            }
        }
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
}
