import Foundation
import Cocoa

/// Manages snippet expansion and detection
actor SnippetManager {
    private let database: SnippetDatabase
    private var cachedSnippets: [String: Snippet] = [:]
    private var isEnabled: Bool

    init(database: SnippetDatabase) {
        self.database = database
        self.isEnabled = UserDefaults.standard.bool(forKey: "snippetsEnabled")
        // If never set, enable by default
        if !UserDefaults.standard.dictionaryRepresentation().keys.contains("snippetsEnabled") {
            self.isEnabled = true
        }
    }

    /// Load all snippets into cache for fast lookup
    func loadSnippets() async {
        let snippets = await database.getAllSnippets()
        cachedSnippets = Dictionary(uniqueKeysWithValues: snippets.map { ($0.trigger, $0) })
    }

    /// Check if clipboard content contains a snippet trigger and expand it
    func checkAndExpandSnippet(content: String) async -> String? {
        guard isEnabled else { return nil }

        // Refresh cache if empty
        if cachedSnippets.isEmpty {
            await loadSnippets()
        }

        // Check if the content exactly matches a trigger
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if let snippet = cachedSnippets[trimmedContent] {
            // Increment usage count
            await database.incrementUsageCount(trigger: snippet.trigger)

            // Return expanded content
            return snippet.content
        }

        // Check if content ends with a trigger (for typing expansion)
        for (trigger, snippet) in cachedSnippets {
            if trimmedContent.hasSuffix(trigger) {
                // Increment usage count
                await database.incrementUsageCount(trigger: trigger)

                // Return expanded content
                return snippet.content
            }
        }

        return nil
    }

    /// Manually expand a snippet trigger
    func expandSnippet(trigger: String) async -> String? {
        guard isEnabled else { return nil }

        if let snippet = cachedSnippets[trigger] {
            await database.incrementUsageCount(trigger: trigger)
            return snippet.content
        }

        // Try to fetch from database if not in cache
        if let snippet = await database.getSnippet(byTrigger: trigger) {
            cachedSnippets[trigger] = snippet
            await database.incrementUsageCount(trigger: trigger)
            return snippet.content
        }

        return nil
    }

    /// Get all available snippet triggers
    func getAllTriggers() async -> [String] {
        if cachedSnippets.isEmpty {
            await loadSnippets()
        }
        return Array(cachedSnippets.keys).sorted()
    }

    /// Enable or disable snippet expansion
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "snippetsEnabled")
    }

    /// Check if snippets are enabled
    func getEnabled() -> Bool {
        return isEnabled
    }

    /// Refresh cache when snippets are added/removed
    func refreshCache() async {
        await loadSnippets()
    }
}
