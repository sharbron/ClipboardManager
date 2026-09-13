import Cocoa
import UserNotifications
import os.log

extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }
}

/// Modern async/await clipboard monitor using Swift Concurrency
actor ClipboardMonitor {
    private static let logger = Logger(subsystem: "com.clipboardmanager", category: "ClipboardMonitor")
    private var monitoringTask: Task<Void, Never>?
    private var lastChangeCount: Int
    private let pasteboard = NSPasteboard.general
    private let database: ClipboardDatabase
    private weak var appState: AppState?
    private var snippetManager: SnippetManager?
    private var lastContent: String = ""
    private var isRestoringClip = false

    init(database: ClipboardDatabase, appState: AppState, snippetManager: SnippetManager? = nil) {
        self.database = database
        self.appState = appState
        self.snippetManager = snippetManager
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
        isRestoringClip = true
    }

    /// Resume monitoring after the clipboard has been restored, resynchronising the change
    /// count so the app's own write isn't mistaken for user activity.
    func resumeMonitoring() {
        isRestoringClip = false
        lastChangeCount = pasteboard.changeCount
    }

    nonisolated func startMonitoring() {
        Task { await beginMonitoring() }
    }

    private func beginMonitoring() {
        // Cancel any existing monitoring task
        monitoringTask?.cancel()

        // Start new monitoring task using async/await
        monitoringTask = Task { [weak self] in
            guard let self = self else {
                ClipboardMonitor.logger.debug("self was deallocated, stopping monitoring task")
                return
            }

            // Use AsyncStream for periodic checking
            while !Task.isCancelled {
                await self.checkClipboard()

                // Wait 1.5 seconds before next check (reduced CPU usage)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
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
        guard let appState else {
            ClipboardMonitor.logger.debug("appState was deallocated, clips not reloaded")
            return
        }
        Task { @MainActor in appState.loadClips() }
    }

    private func checkClipboard() async {
        // Skip monitoring if we're restoring a clip
        guard !isRestoringClip else { return }

        // Check if clipboard has changed
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let maxClipSizeBytes = Preferences.maxClipSizeBytes
        let maxImageSizeBytes = Preferences.maxImageSizeBytes

        // Get the name of the app that owns the clipboard
        let source = NSWorkspace.shared.frontmostApplication?.localizedName

        // Check for image first
        if let imageData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: imageData),
           let pngData = image.pngData() {
            // Check size limit (use image-specific limit)
            if pngData.count > maxImageSizeBytes {
                // Skip this clip - too large
                showSizeNotification(type: "Image", actualSize: pngData.count, limit: maxImageSizeBytes)
                return
            }

            // Save image with a placeholder text
            let imageDescription = "[Image: \(Int(image.size.width))x\(Int(image.size.height))]"

            // Avoid duplicates by checking if the same image data was recently saved
            let isDuplicate = await database.isDuplicate(
                text: imageDescription,
                type: "image",
                imageBytes: pngData
            )
            if !isDuplicate {
                await database.saveClip(imageDescription, type: "image", image: pngData, sourceApp: source)
                lastContent = imageDescription
                notifyClipsChanged()
            }
            return
        }

        // Check for RTF first (preserves formatting)
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            let plainText = attributedString.string

            // Bound both the visible text and the representation stored in the database. RTF
            // can contain a small amount of text but a very large formatting payload.
            let textSizeBytes = plainText.utf8.count
            let rtfSizeBytes = rtfData.count
            if textSizeBytes > maxClipSizeBytes || rtfSizeBytes > maxClipSizeBytes {
                // Skip this clip - too large
                showSizeNotification(
                    type: "Rich text",
                    actualSize: max(textSizeBytes, rtfSizeBytes),
                    limit: maxClipSizeBytes
                )
                return
            }

            if !plainText.isEmpty && plainText != lastContent {
                // Check for duplicates - for RTF, compare both text and RTF data
                let isDuplicate: Bool
                if attributedString.length > 0 && attributedString.containsAttachments == false {
                    isDuplicate = await database.isDuplicate(
                        text: plainText,
                        type: "rtf",
                        rtfBytes: rtfData
                    )
                } else {
                    isDuplicate = await database.isDuplicate(text: plainText, type: "text")
                }
                
                if !isDuplicate {
                    // Store RTF data separately if it has formatting
                    if attributedString.length > 0 && attributedString.containsAttachments == false {
                        await database.saveClip(plainText, type: "rtf", rtfData: rtfData, sourceApp: source)
                    } else {
                        await database.saveClip(plainText, sourceApp: source)
                    }
                    lastContent = plainText
                    notifyClipsChanged()
                }
                return
            }
        }

        // Get plain text content as fallback
        guard let originalContent = pasteboard.string(forType: .string),
              !originalContent.isEmpty,
              originalContent != lastContent else { return }

        // Check for snippet expansion
        var contentToSave = originalContent
        if let snippetManager = snippetManager,
           let expandedContent = await snippetManager.checkAndExpandSnippet(content: originalContent) {
            // Snippet matched! Replace clipboard with expanded content
            isRestoringClip = true  // Pause monitoring during expansion

            pasteboard.clearContents()
            pasteboard.setString(expandedContent, forType: .string)

            // Use expanded content for saving
            contentToSave = expandedContent

            // Brief delay before resuming
            try? await Task.sleep(nanoseconds: 200_000_000)
            isRestoringClip = false
            lastChangeCount = pasteboard.changeCount
        }

        // Check size limit
        let textSizeBytes = contentToSave.utf8.count
        if textSizeBytes > maxClipSizeBytes {
            // Skip this clip - too large
            showSizeNotification(type: "Text", actualSize: textSizeBytes, limit: maxClipSizeBytes)
            return
        }

        // Avoid duplicates by checking if the same content was recently saved
        let isDuplicate = await database.isDuplicate(text: contentToSave, type: "text")
        if !isDuplicate {
            await database.saveClip(contentToSave, sourceApp: source)
            lastContent = contentToSave
            notifyClipsChanged()
        }
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
