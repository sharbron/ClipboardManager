import Foundation
import Cocoa

/// Manages snippet expansion and detection
actor SnippetManager {
    private let database: SnippetDatabase
    private var cachedSnippets: [String: Snippet] = [:]

    /// Read live rather than cached at init, so toggling snippets in Preferences takes effect
    /// immediately instead of waiting for the next launch.
    private var isEnabled: Bool { Preferences.areSnippetsEnabled }

    init(database: SnippetDatabase) {
        self.database = database
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
            await database.incrementUsageCount(trigger: snippet.trigger)
            return snippet.expandedContent
        }

        // Check if content ends with a trigger (for typing expansion).
        // Only the trigger itself is replaced - any text before it is preserved,
        // so copying "See you on ;date" doesn't discard "See you on ".
        // Pick the longest matching trigger for determinism when triggers overlap.
        let suffixMatch = cachedSnippets
            .filter { trigger, _ in !trigger.isEmpty && trimmedContent.hasSuffix(trigger) }
            .max { $0.key.count < $1.key.count }

        if let (trigger, snippet) = suffixMatch {
            await database.incrementUsageCount(trigger: trigger)

            let prefix = String(trimmedContent.dropLast(trigger.count))
            return prefix + snippet.expandedContent
        }

        return nil
    }

    /// Refresh cache when snippets are added, edited or removed
    func refreshCache() async {
        await loadSnippets()
    }
}
