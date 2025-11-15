import SwiftUI
import UserNotifications

/// Central state management for the app
@MainActor
class AppState: ObservableObject {
    @Published var clips: [ClipboardEntry] = []
    @Published var snippets: [Snippet] = []

    let database: ClipboardDatabase
    let snippetDatabase: SnippetDatabase
    let snippetManager: SnippetManager
    weak var clipboardMonitor: ClipboardMonitor?
    private var loadTask: Task<Void, Never>?
    private var snippetLoadTask: Task<Void, Never>?

    init(database: ClipboardDatabase, snippetDatabase: SnippetDatabase, snippetManager: SnippetManager) {
        self.database = database
        self.snippetDatabase = snippetDatabase
        self.snippetManager = snippetManager
        Task {
            await loadClips()
            await loadSnippets()
        }
    }

    func loadClips() async {
        // Cancel any pending load task to prevent race conditions
        loadTask?.cancel()

        let limit = UserDefaults.standard.integer(forKey: "menuBarClipCount")
        clips = await database.getRecentClips(limit: limit > 0 ? limit : 15)
    }

    func togglePin(clipId: Int64) async {
        _ = await database.togglePin(clipId: clipId)
        await loadClips()
    }

    func deleteClip(clipId: Int64) async {
        _ = await database.deleteClip(clipId: clipId)
        await loadClips()
    }

    func deleteAllClips() async {
        _ = await database.clearAllHistory(keepPinned: true)
        await loadClips()
    }

    func deleteClipsFromLast24Hours() async {
        _ = await database.clearLast24Hours()
        await loadClips()
    }

    func copyToClipboard(clip: ClipboardEntry) async {
        // Pause monitoring to prevent duplicate
        clipboardMonitor?.pauseMonitoring()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if clip.contentType == "image" {
            if let imageData = await database.getImageData(for: clip.id),
               let image = NSImage(data: imageData) {
                pasteboard.writeObjects([image])
            }
        } else if clip.contentType == "rtf" {
            if let rtfData = await database.getImageData(for: clip.id) {
                pasteboard.setData(rtfData, forType: .rtf)
                pasteboard.setString(clip.content, forType: .string)
            }
        } else {
            pasteboard.setString(clip.content, forType: .string)
        }

        // Resume monitoring after a brief delay
        try? await Task.sleep(nanoseconds: 100_000_000)
        clipboardMonitor?.resumeMonitoring()

        // Show notification if enabled
        let enableNotifications = UserDefaults.standard.bool(forKey: "enableNotifications")
        if enableNotifications || !UserDefaults.standard.dictionaryRepresentation().keys.contains("enableNotifications") {
            let notification = UNMutableNotificationContent()
            notification.title = "Copied"
            notification.body = "Clip copied to clipboard"
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: notification, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Snippet Management

    func loadSnippets() async {
        snippetLoadTask?.cancel()

        snippets = await snippetDatabase.getAllSnippets()
        await snippetManager.loadSnippets()
    }

    func saveSnippet(trigger: String, content: String, description: String) async {
        let success = await snippetDatabase.saveSnippet(
            trigger: trigger,
            content: content,
            description: description
        )
        if success {
            await loadSnippets()
        }
    }

    func deleteSnippet(id: Int64) async {
        _ = await snippetDatabase.deleteSnippet(id: id)
        await loadSnippets()
    }

    func expandSnippet(_ snippet: Snippet) async {
        // Pause monitoring
        clipboardMonitor?.pauseMonitoring()

        // Copy expanded content to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet.content, forType: .string)

        // Resume monitoring
        try? await Task.sleep(nanoseconds: 100_000_000)
        clipboardMonitor?.resumeMonitoring()

        // Increment usage count
        await snippetDatabase.incrementUsageCount(trigger: snippet.trigger)

        // Show notification
        let enableNotifications = UserDefaults.standard.bool(forKey: "enableNotifications")
        if enableNotifications || !UserDefaults.standard.dictionaryRepresentation().keys.contains("enableNotifications") {
            let notification = UNMutableNotificationContent()
            notification.title = "Snippet Expanded"
            notification.body = "'\(snippet.trigger)' copied to clipboard"
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: notification, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    func createDefaultSnippets() async {
        await snippetDatabase.createDefaultSnippets()
        await loadSnippets()
    }

    func exportSnippets() async -> [ExportableSnippet] {
        return await snippetDatabase.exportSnippets()
    }

    func importSnippets(_ snippets: [ExportableSnippet], replaceExisting: Bool = false) async {
        _ = await snippetDatabase.importSnippets(snippets, replaceExisting: replaceExisting)
        await loadSnippets()
    }
}
