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
        // Resolve lazy payloads before clearing the pasteboard. A corrupt or missing image/RTF
        // blob must not destroy whatever the user currently has copied.
        let payload: ClipboardPayload
        if clip.contentType == "image" {
            guard let imageData = await database.getImageData(for: clip.id),
                  let image = NSImage(data: imageData) else {
                await Self.notify(title: "Copy Failed", body: "The stored image could not be read.")
                return
            }
            payload = .image(image)
        } else if clip.contentType == "rtf" {
            guard let rtfData = await database.getImageData(for: clip.id) else {
                await Self.notify(title: "Copy Failed", body: "The stored rich text could not be read.")
                return
            }
            payload = .richText(data: rtfData, plainText: clip.content)
        } else {
            payload = .text(clip.content)
        }

        // Pause monitoring before writing, so our own write isn't captured as a new clip.
        await clipboardMonitor?.pauseMonitoring()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let copied: Bool
        switch payload {
        case .image(let image):
            copied = pasteboard.writeObjects([image])
        case let .richText(data, plainText):
            copied = pasteboard.setData(data, forType: .rtf)
                && pasteboard.setString(plainText, forType: .string)
        case .text(let text):
            copied = pasteboard.setString(text, forType: .string)
        }

        // Skip exactly this write; anything copied after it is still captured.
        await clipboardMonitor?.resumeMonitoring(afterOwnWriteAt: pasteboard.changeCount)

        await Self.notify(
            title: copied ? "Copied" : "Copy Failed",
            body: copied ? "Clip copied to clipboard" : "The clip could not be written to the clipboard."
        )
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

        await clipboardMonitor?.resumeMonitoring(afterOwnWriteAt: pasteboard.changeCount)

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

private enum ClipboardPayload {
    case image(NSImage)
    case richText(data: Data, plainText: String)
    case text(String)
}
