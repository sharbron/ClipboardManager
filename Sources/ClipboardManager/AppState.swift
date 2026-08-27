import SwiftUI
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.clipboardmanager", category: "AppState")

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
        loadClips()
        loadSnippets()
    }

    func loadClips() {
        // Cancel any pending load task to prevent race conditions
        loadTask?.cancel()

        loadTask = Task {
            clips = await database.getRecentClips(limit: Preferences.menuBarClipCount)
        }
    }

    func togglePin(clipId: Int64) {
        Task {
            _ = await database.togglePin(clipId: clipId)
            loadClips()
        }
    }

    func deleteClip(clipId: Int64) {
        Task {
            _ = await database.deleteClip(clipId: clipId)
            loadClips()
        }
    }

    func deleteAllClips() {
        Task {
            _ = await database.clearAllHistory(keepPinned: true)
            loadClips()
        }
    }

    func deleteClipsFromLast24Hours() {
        Task {
            _ = await database.clearLast24Hours()
            loadClips()
        }
    }

    func copyToClipboard(clip: ClipboardEntry) async {
        // Pause monitoring before writing, so our own write isn't captured as a new clip.
        await clipboardMonitor?.pauseMonitoring()

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
        do {
            try await Task.sleep(nanoseconds: 100_000_000)
        } catch {
            logger.debug("Task sleep was cancelled in copyToClipboard")
        }
        await clipboardMonitor?.resumeMonitoring()

        await Self.notify(title: "Copied", body: "Clip copied to clipboard")
    }

    /// Posts a user notification, honouring the preference and staying silent under XCTest.
    private static func notify(title: String, body: String) async {
        guard !ProcessInfo.processInfo.processName.contains("xctest") else { return }
        guard Preferences.areNotificationsEnabled else { return }

        let notification = UNMutableNotificationContent()
        notification.title = title
        notification.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: notification, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Snippet Management

    func loadSnippets() {
        snippetLoadTask?.cancel()

        snippetLoadTask = Task {
            snippets = await snippetDatabase.getAllSnippets()
            await snippetManager.loadSnippets()
        }
    }

    func saveSnippet(trigger: String, content: String, description: String) {
        Task {
            let success = await snippetDatabase.saveSnippet(
                trigger: trigger,
                content: content,
                description: description
            )
            if success {
                loadSnippets()
            }
        }
    }

    func deleteSnippet(id: Int64) {
        Task {
            _ = await snippetDatabase.deleteSnippet(id: id)
            loadSnippets()
        }
    }

    func expandSnippet(_ snippet: Snippet) async {
        await clipboardMonitor?.pauseMonitoring()

        // Copy expanded content to clipboard, resolving date/time tokens at expansion time
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet.expandedContent, forType: .string)

        // Resume monitoring
        do {
            try await Task.sleep(nanoseconds: 100_000_000)
        } catch {
            logger.debug("Task sleep was cancelled in expandSnippet")
        }
        await clipboardMonitor?.resumeMonitoring()

        // Increment usage count
        await snippetDatabase.incrementUsageCount(trigger: snippet.trigger)

        await Self.notify(title: "Snippet Expanded", body: "'\(snippet.trigger)' copied to clipboard")
    }

    func createDefaultSnippets() {
        Task {
            await snippetDatabase.createDefaultSnippets()
            loadSnippets()
        }
    }

    func exportSnippets() async -> [ExportableSnippet] {
        return await snippetDatabase.exportSnippets()
    }

    func importSnippets(_ snippets: [ExportableSnippet], replaceExisting: Bool = false) {
        Task {
            _ = await snippetDatabase.importSnippets(snippets, replaceExisting: replaceExisting)
            loadSnippets()
        }
    }
}
