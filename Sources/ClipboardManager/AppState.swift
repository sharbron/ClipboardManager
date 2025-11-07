import SwiftUI
import UserNotifications

/// Central state management for the app
@MainActor
class AppState: ObservableObject {
    @Published var clips: [ClipboardEntry] = []

    let database: ClipboardDatabase
    weak var clipboardMonitor: ClipboardMonitor?
    private var loadTask: Task<Void, Never>?

    init(database: ClipboardDatabase) {
        self.database = database
        loadClips()
    }

    func loadClips() {
        // Cancel any pending load task to prevent race conditions
        loadTask?.cancel()

        loadTask = Task {
            let limit = UserDefaults.standard.integer(forKey: "menuBarClipCount")
            clips = await database.getRecentClips(limit: limit > 0 ? limit : 15)
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
}
