import Cocoa
import UserNotifications
import os.log

/// Modern async/await clipboard monitor using Swift Concurrency
actor ClipboardMonitor {
    private static let logger = Logger(subsystem: "com.clipboardmanager", category: "ClipboardMonitor")

    /// Polling only compares a counter, so it is cheap; a short interval keeps copies made in
    /// quick succession from collapsing into one, and keeps the source app attribution close.
    private static let pollInterval: UInt64 = 500_000_000

    private var monitoringTask: Task<Void, Never>?
    private var lastChangeCount: Int
    private let pasteboard: NSPasteboard
    private let database: ClipboardDatabase
    private weak var appState: AppState?
    private var snippetManager: SnippetManager?
    private var isPaused = false

    init(
        database: ClipboardDatabase,
        appState: AppState?,
        snippetManager: SnippetManager? = nil,
        pasteboard: NSPasteboard = .general
    ) {
        self.database = database
        self.appState = appState
        self.snippetManager = snippetManager
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    func setSnippetManager(_ manager: SnippetManager) {
        self.snippetManager = manager
    }

    /// Pause monitoring before the app modifies the clipboard itself.
    ///
    /// Callers must `await` this before touching the pasteboard. An earlier version fired the
    /// state change into a detached `Task` and claimed to be synchronous, which let the
    /// pasteboard write land first and get re-captured as a brand new clip.
    func pauseMonitoring() {
        isPaused = true
    }

    /// Resume monitoring after the app's own write.
    ///
    /// Pass the pasteboard's `changeCount` read straight after that write. Only that change is
    /// skipped; anything the user copies after it is still captured, which re-reading the
    /// counter here (after a delay) would silently swallow.
    func resumeMonitoring(afterOwnWriteAt changeCount: Int) {
        isPaused = false
        lastChangeCount = changeCount
    }

    nonisolated func startMonitoring() {
        Task { await beginMonitoring() }
    }

    private func beginMonitoring() {
        // Cancel any existing monitoring task
        monitoringTask?.cancel()

        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    ClipboardMonitor.logger.debug("self was deallocated, stopping monitoring task")
                    return
                }
                await self.checkClipboard()
                try? await Task.sleep(nanoseconds: ClipboardMonitor.pollInterval)
            }
        }
    }

    nonisolated func stopMonitoring() {
        Task { await cancelMonitoring() }
    }

    private func cancelMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    /// Ask the UI to reload after a new clip lands.
    private func notifyClipsChanged() {
        guard let appState else { return }
        Task { @MainActor in appState.loadClips() }
    }

    /// Captures the pasteboard if it changed since the last check. Internal for tests.
    func checkClipboard() async {
        guard !isPaused else { return }

        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        // Everything is read from the pasteboard before the first suspension point, so a
        // write that lands while this capture is saving can't be mixed into it.
        let decision = ClipboardCapture.decide(for: pasteboard, limits: .current)
        let source = NSWorkspace.shared.frontmostApplication?.localizedName

        switch decision {
        case .ignore:
            return
        case let .tooLarge(kind, size, limit):
            showSizeNotification(type: kind, actualSize: size, limit: limit)
        case let .image(description, png):
            await save(description, type: "image", binary: png, sourceApp: source)
        case let .richText(plainText, rtf):
            if let expanded = await expandSnippet(in: plainText, capturedAt: changeCount) {
                await saveText(expanded, sourceApp: source)
            } else {
                await save(plainText, type: "rtf", binary: rtf, sourceApp: source)
            }
        case .text(let text):
            let expanded = await expandSnippet(in: text, capturedAt: changeCount)
            await saveText(expanded ?? text, sourceApp: source)
        }
    }

    /// Replaces a copied snippet trigger on the pasteboard with its expansion.
    private func expandSnippet(in text: String, capturedAt changeCount: Int) async -> String? {
        guard let snippetManager,
              let expanded = await snippetManager.checkAndExpandSnippet(content: text) else {
            return nil
        }

        // The lookup above suspends; if the user or the app wrote to the pasteboard meanwhile,
        // don't overwrite that newer content with a stale expansion.
        guard !isPaused, pasteboard.changeCount == changeCount else { return nil }

        pasteboard.clearContents()
        pasteboard.setString(expanded, forType: .string)
        lastChangeCount = pasteboard.changeCount
        return expanded
    }

    private func saveText(_ text: String, sourceApp: String?) async {
        let limit = Preferences.maxClipSizeBytes
        guard text.utf8.count <= limit else {
            showSizeNotification(type: "Text", actualSize: text.utf8.count, limit: limit)
            return
        }
        await save(text, type: "text", binary: nil, sourceApp: sourceApp)
    }

    private func save(_ text: String, type: String, binary: Data?, sourceApp: String?) async {
        let image = type == "image" ? binary : nil
        let rtf = type == "rtf" ? binary : nil
        let isDuplicate = await database.isDuplicate(text: text, type: type, imageBytes: image, rtfBytes: rtf)
        guard !isDuplicate else { return }

        await database.saveClip(text, type: type, image: image, rtfData: rtf, sourceApp: sourceApp)
        notifyClipsChanged()
    }

    private func showSizeNotification(type: String, actualSize: Int, limit: Int) {
        guard Preferences.areNotificationsEnabled else { return }

        Task { @MainActor in
            let notification = UNMutableNotificationContent()
            notification.title = "Clip Too Large"
            let actualMB = Double(actualSize) / 1024.0 / 1024.0
            let limitMB = Double(limit) / 1024.0 / 1024.0

            if actualMB >= 1.0 || limitMB >= 1.0 {
                notification.body = String(format: "%@ too large (%.1f MB > %.1f MB limit)", type, actualMB, limitMB)
            } else {
                let actualKB = Double(actualSize) / 1024.0
                let limitKB = Double(limit) / 1024.0
                notification.body = String(format: "%@ too large (%.0f KB > %.0f KB limit)", type, actualKB, limitKB)
            }

            notification.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: notification,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    deinit {
        monitoringTask?.cancel()
    }
}
