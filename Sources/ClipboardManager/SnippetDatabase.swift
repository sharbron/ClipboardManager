import Foundation
import SQLite

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
}

/// Thread-safe database actor for managing snippets
actor SnippetDatabase {
    private var db: Connection?
    private let snippets = Table("snippets")

    private let id = Expression<Int64>("id")
    private let trigger = Expression<String>("trigger")
    private let content = Expression<String>("content")
    private let description = Expression<String>("description")
    private let createdAt = Expression<String>("created_at")
    private let usageCount = Expression<Int>("usage_count")

    private var isInitialized = false

    // Reuse ISO8601DateFormatter for better performance
    private let isoFormatter = ISO8601DateFormatter()

    init(databasePath: String? = nil) {
        // Initialize all properties first before any method calls to satisfy Swift 6 concurrency
        do {
            let path = databasePath ?? (NSHomeDirectory() + "/.clipboard_snippets.db")
            let connection = try Connection(path)
            db = connection

            // Set restrictive file permissions (owner read/write only)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: path
            )

            // Initialize database schema inline
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

            isInitialized = true
        } catch {
            print("Failed to initialize snippet database: \(error)")
            isInitialized = false
        }
    }

    private func initializeDatabase() throws {
        try db?.run(snippets.create(ifNotExists: true) { table in
            table.column(id, primaryKey: .autoincrement)
            table.column(trigger, unique: true)
            table.column(content)
            table.column(description)
            table.column(createdAt)
            table.column(usageCount, defaultValue: 0)
        })

        // Create index for faster trigger lookups
        try db?.run(snippets.createIndex(trigger, ifNotExists: true))
    }

    // MARK: - CRUD Operations

    func saveSnippet(trigger: String, content: String, description: String) async -> Bool {
        do {
            let now = isoFormatter.string(from: Date())

            // Check if trigger already exists
            if let existing = try db?.pluck(snippets.filter(self.trigger == trigger)) {
                // Update existing snippet
                try db?.run(snippets.filter(self.trigger == trigger).update(
                    self.content <- content,
                    self.description <- description
                ))
                return true
            } else {
                // Insert new snippet
                try db?.run(snippets.insert(
                    self.trigger <- trigger,
                    self.content <- content,
                    self.description <- description,
                    createdAt <- now,
                    usageCount <- 0
                ))
                return true
            }
        } catch {
            print("Failed to save snippet: \(error)")
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
                let date = isoFormatter.date(from: row[createdAt]) ?? Date()
                let snippet = Snippet(
                    id: row[id],
                    trigger: row[trigger],
                    content: row[content],
                    description: row[description],
                    createdAt: date,
                    usageCount: row[usageCount]
                )
                results.append(snippet)
            }
        } catch {
            print("Failed to fetch snippets: \(error)")
        }

        return results
    }

    func getSnippet(byTrigger trigger: String) async -> Snippet? {
        do {
            guard let row = try db?.pluck(snippets.filter(self.trigger == trigger)) else {
                return nil
            }

            let date = isoFormatter.date(from: row[createdAt]) ?? Date()
            return Snippet(
                id: row[id],
                trigger: row[trigger],
                content: row[content],
                description: row[description],
                createdAt: date,
                usageCount: row[usageCount]
            )
        } catch {
            print("Failed to fetch snippet: \(error)")
            return nil
        }
    }

    func deleteSnippet(id: Int64) async -> Bool {
        do {
            let snippet = snippets.filter(self.id == id)
            try db?.run(snippet.delete())
            return true
        } catch {
            print("Failed to delete snippet: \(error)")
            return false
        }
    }

    func deleteSnippet(trigger: String) async -> Bool {
        do {
            let snippet = snippets.filter(self.trigger == trigger)
            try db?.run(snippet.delete())
            return true
        } catch {
            print("Failed to delete snippet: \(error)")
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
            print("Failed to increment usage count: \(error)")
        }
    }

    func getSnippetCount() async -> Int {
        do {
            return try db?.scalar(snippets.count) ?? 0
        } catch {
            return 0
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

    func importSnippets(_ snippets: [ExportableSnippet], replaceExisting: Bool = false) async -> Int {
        if replaceExisting {
            // Clear all existing snippets
            do {
                try db?.run(self.snippets.delete())
            } catch {
                print("Failed to clear snippets: \(error)")
                return 0
            }
        }

        var importedCount = 0
        for snippet in snippets {
            let success = await saveSnippet(
                trigger: snippet.trigger,
                content: snippet.content,
                description: snippet.description
            )
            if success {
                importedCount += 1
            }
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
            (";date", Date().formatted(date: .long, time: .omitted), "Today's date"),
            (";time", Date().formatted(date: .omitted, time: .shortened), "Current time")
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
