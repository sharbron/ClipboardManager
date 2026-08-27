import Foundation
import SQLite
import os.log

/// Represents a text snippet/template
struct Snippet: Identifiable, Hashable {
    let id: Int64
    let trigger: String          // e.g., ";email"
    let content: String          // The expanded text
    let description: String      // User-friendly description
    let createdAt: Date
    let usageCount: Int         // Track how often it's used

    // For quick preview in UI
    var previewContent: String {
        var preview = content.replacingOccurrences(of: "\n", with: " ")
        preview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if preview.count > 100 {
            preview = String(preview.prefix(100)) + "..."
        }
        return preview
    }

    /// Content with dynamic tokens resolved. Resolution happens at expansion time rather than
    /// when the snippet is stored, so a "today's date" snippet stays current instead of
    /// freezing the day it was created.
    var expandedContent: String {
        Snippet.resolvingTokens(in: content)
    }

    static let dateToken = "{{date}}"
    static let timeToken = "{{time}}"
    static let dateTimeToken = "{{datetime}}"

    static func resolvingTokens(in content: String, now: Date = Date()) -> String {
        guard content.contains("{{") else { return content }

        let date = now.formatted(date: .long, time: .omitted)
        let time = now.formatted(date: .omitted, time: .shortened)

        return content
            .replacingOccurrences(of: dateTimeToken, with: "\(date) \(time)")
            .replacingOccurrences(of: dateToken, with: date)
            .replacingOccurrences(of: timeToken, with: time)
    }
}

/// Thread-safe database actor for managing snippets.
///
/// Snippet bodies are encrypted at rest with the same key as the clipboard history: the
/// stock snippets are email address, phone number, mailing address and signature, so the
/// contents are at least as sensitive as an average clip. Triggers stay in plaintext because
/// they are the indexed lookup key and are not themselves revealing.
actor SnippetDatabase {
    /// See `ClipboardDatabase.schemaVersion` - migration state lives in the database itself.
    private static let schemaVersion: Int64 = 1

    private let logger = Logger(subsystem: "com.clipboardmanager", category: "SnippetDatabase")

    nonisolated(unsafe) private var db: Connection?
    nonisolated(unsafe) private let snippets = Table("snippets")

    nonisolated(unsafe) private let id = Expression<Int64>("id")
    nonisolated(unsafe) private let trigger = Expression<String>("trigger")
    nonisolated(unsafe) private let content = Expression<String>("content")
    nonisolated(unsafe) private let description = Expression<String>("description")
    nonisolated(unsafe) private let createdAt = Expression<String>("created_at")
    nonisolated(unsafe) private let usageCount = Expression<Int>("usage_count")

    nonisolated(unsafe) private var cipher: Cipher?

    /// Why startup failed, or nil if the database is usable. Written only in init.
    nonisolated(unsafe) private(set) var initializationError: String?

    nonisolated var isInitialized: Bool { initializationError == nil }

    // Reuse ISO8601DateFormatter for better performance
    private let isoFormatter = ISO8601DateFormatter()

    init(databasePath: String? = nil) {
        do {
            let path = databasePath ?? (NSHomeDirectory() + "/.clipboard_snippets.db")
            let connection = try Connection(path)
            db = connection

            // Set restrictive file permissions (owner read/write only)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: path
            )

            try connection.run(snippets.create(ifNotExists: true) { table in
                table.column(id, primaryKey: .autoincrement)
                table.column(trigger, unique: true)
                table.column(content)
                table.column(description)
                table.column(createdAt)
                table.column(usageCount, defaultValue: 0)
            })

            // Create index for faster trigger lookups
            try connection.run(snippets.createIndex(trigger, ifNotExists: true))

            cipher = Cipher(key: try KeychainKeyStore.loadOrCreateKey(
                service: "clipboard_manager_swift",
                account: "encryption_key"
            ))
        } catch {
            logger.error("Failed to initialize snippet database: \(error.localizedDescription)")
            initializationError = error.localizedDescription
        }
    }

    // MARK: - Migration

    /// Encrypts snippet bodies left in plaintext by earlier versions. Values that already
    /// decrypt are skipped, so this is safe to run repeatedly.
    func prepare() async {
        guard let connection = db, let cipher else { return }

        do {
            let version = try connection.scalar("PRAGMA user_version") as? Int64 ?? 0
            guard version < Self.schemaVersion else { return }

            var migrated = 0
            for row in try connection.prepare(snippets) {
                var setters: [Setter] = []

                let storedContent = row[content]
                if !cipher.isEncrypted(storedContent), let encrypted = cipher.encrypt(storedContent) {
                    setters.append(content <- encrypted)
                }

                let storedDescription = row[description]
                if !cipher.isEncrypted(storedDescription), let encrypted = cipher.encrypt(storedDescription) {
                    setters.append(description <- encrypted)
                }

                guard !setters.isEmpty else { continue }
                try connection.run(snippets.filter(id == row[id]).update(setters))
                migrated += 1
            }

            try connection.run("PRAGMA user_version = \(Self.schemaVersion)")
            if migrated > 0 {
                logger.info("Encrypted \(migrated) snippet(s) previously stored in plaintext")
            }
        } catch {
            logger.error("Snippet migration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Encryption helpers

    /// Falls back to the raw value so a snippet stays usable if it hasn't been migrated yet
    /// or its ciphertext is damaged - unlike a clip, losing one here is immediately visible
    /// to the user and there is nothing to gain from hiding it.
    private func decrypted(_ value: String) -> String {
        cipher?.decrypt(value) ?? value
    }

    // MARK: - CRUD Operations

    func saveSnippet(trigger: String, content: String, description: String) async -> Bool {
        guard let encryptedContent = cipher?.encrypt(content),
              let encryptedDescription = cipher?.encrypt(description) else {
            logger.error("Failed to encrypt snippet - not saved")
            return false
        }

        do {
            let now = isoFormatter.string(from: Date())

            // Check if trigger already exists
            if (try db?.pluck(snippets.filter(self.trigger == trigger))) != nil {
                // Update existing snippet
                try db?.run(snippets.filter(self.trigger == trigger).update(
                    self.content <- encryptedContent,
                    self.description <- encryptedDescription
                ))
            } else {
                // Insert new snippet
                try db?.run(snippets.insert(
                    self.trigger <- trigger,
                    self.content <- encryptedContent,
                    self.description <- encryptedDescription,
                    createdAt <- now,
                    usageCount <- 0
                ))
            }
            return true
        } catch {
            logger.error("Failed to save snippet: \(error.localizedDescription)")
            return false
        }
    }

    func getAllSnippets() async -> [Snippet] {
        var results: [Snippet] = []

        do {
            guard let rows = try db?.prepare(snippets.order(usageCount.desc, trigger.asc)) else {
                return results
            }

            for row in rows {
                results.append(makeSnippet(from: row))
            }
        } catch {
            logger.error("Failed to fetch snippets: \(error.localizedDescription)")
        }

        return results
    }

    private func makeSnippet(from row: Row) -> Snippet {
        Snippet(
            id: row[id],
            trigger: row[trigger],
            content: decrypted(row[content]),
            description: decrypted(row[description]),
            createdAt: isoFormatter.date(from: row[createdAt]) ?? Date(),
            usageCount: row[usageCount]
        )
    }

    func deleteSnippet(id: Int64) async -> Bool {
        do {
            let snippet = snippets.filter(self.id == id)
            try db?.run(snippet.delete())
            return true
        } catch {
            logger.error("Failed to delete snippet: \(error.localizedDescription)")
            return false
        }
    }

    func incrementUsageCount(trigger: String) async {
        do {
            let snippet = snippets.filter(self.trigger == trigger)
            if let row = try db?.pluck(snippet) {
                let currentCount = row[usageCount]
                try db?.run(snippet.update(usageCount <- currentCount + 1))
            }
        } catch {
            logger.error("Failed to increment usage count: \(error.localizedDescription)")
        }
    }

    // MARK: - Import/Export

    func exportSnippets() async -> [ExportableSnippet] {
        let allSnippets = await getAllSnippets()
        return allSnippets.map { snippet in
            ExportableSnippet(
                trigger: snippet.trigger,
                content: snippet.content,
                description: snippet.description
            )
        }
    }

    /// Imports snippets atomically: with `replaceExisting` the wipe and the refill share one
    /// transaction, so a failure part-way through can't leave the user with nothing.
    func importSnippets(_ incoming: [ExportableSnippet], replaceExisting: Bool = false) async -> Int {
        guard let db, let cipher else { return 0 }

        var importedCount = 0
        do {
            try db.transaction {
                if replaceExisting {
                    try db.run(snippets.delete())
                }

                let now = isoFormatter.string(from: Date())
                for snippet in incoming {
                    guard let encryptedContent = cipher.encrypt(snippet.content),
                          let encryptedDescription = cipher.encrypt(snippet.description) else { continue }

                    if (try db.pluck(snippets.filter(trigger == snippet.trigger))) != nil {
                        try db.run(snippets.filter(trigger == snippet.trigger).update(
                            content <- encryptedContent,
                            description <- encryptedDescription
                        ))
                    } else {
                        try db.run(snippets.insert(
                            trigger <- snippet.trigger,
                            content <- encryptedContent,
                            description <- encryptedDescription,
                            createdAt <- now,
                            usageCount <- 0
                        ))
                    }
                    importedCount += 1
                }
            }
        } catch {
            logger.error("Failed to import snippets: \(error.localizedDescription)")
            return 0
        }

        return importedCount
    }

    // MARK: - Default Snippets

    func createDefaultSnippets() async {
        let defaults: [(String, String, String)] = [
            (";email", "your.email@example.com", "Your email address"),
            (";phone", "+1 (555) 123-4567", "Your phone number"),
            (";addr", """
            123 Main Street
            City, State 12345
            United States
            """, "Your mailing address"),
            (";sig", """
            Best regards,
            Your Name
            Your Title
            Company Name
            """, "Email signature"),
            (";meeting", """
            Hi team,

            Let's schedule a meeting to discuss:
            -
            -
            -

            Available times:
            -
            -

            Thanks!
            """, "Meeting template"),
            (";date", Snippet.dateToken, "Today's date"),
            (";time", Snippet.timeToken, "Current time")
        ]

        for (trigger, content, desc) in defaults {
            _ = await saveSnippet(trigger: trigger, content: content, description: desc)
        }
    }
}

/// Codable version for import/export
struct ExportableSnippet: Codable {
    let trigger: String
    let content: String
    let description: String
}
