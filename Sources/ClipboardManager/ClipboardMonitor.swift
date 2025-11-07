import Cocoa
import UserNotifications

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
    private var monitoringTask: Task<Void, Never>?
    private var lastChangeCount: Int
    private let pasteboard = NSPasteboard.general
    private let database: ClipboardDatabase
    private weak var appState: AppState?
    private var lastContent: String = ""
    private var isRestoringClip = false

    init(database: ClipboardDatabase, appState: AppState) {
        self.database = database
        self.appState = appState
        self.lastChangeCount = pasteboard.changeCount
    }

    nonisolated func pauseMonitoring() {
        Task { await setPauseState(true) }
    }

    nonisolated func resumeMonitoring() {
        Task { await setPauseState(false) }
    }

    private func setPauseState(_ paused: Bool) {
        isRestoringClip = paused
        if !paused {
            lastChangeCount = pasteboard.changeCount
        }
    }

    nonisolated func startMonitoring() {
        Task { await beginMonitoring() }
    }

    private func beginMonitoring() {
        // Cancel any existing monitoring task
        monitoringTask?.cancel()

        // Start new monitoring task using async/await
        monitoringTask = Task { [weak self] in
            guard let self = self else { return }

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

    private func checkClipboard() async {
        // Skip monitoring if we're restoring a clip
        guard !isRestoringClip else { return }

        // Check if clipboard has changed
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Get max clip sizes from preferences (in KB)
        let maxClipSizeKB = UserDefaults.standard.integer(forKey: "maxClipSize")
        let maxClipSizeBytes = (maxClipSizeKB > 0 ? maxClipSizeKB : 100) * 1024

        let maxImageSizeKB = UserDefaults.standard.integer(forKey: "maxImageSize")
        let maxImageSizeBytes = (maxImageSizeKB > 0 ? maxImageSizeKB : 2048) * 1024

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

            // Avoid duplicates by checking last entry
            let recent = await database.getRecentClips(limit: 1)
            if recent.isEmpty || recent[0].content != imageDescription {
                await database.saveClip(imageDescription, type: "image", image: pngData, sourceApp: source)
                lastContent = imageDescription
                await appState?.loadClips()
            }
            return
        }

        // Check for RTF first (preserves formatting)
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            let plainText = attributedString.string

            // Check size limit (use text size, not RTF data size)
            let textSizeBytes = plainText.utf8.count
            if textSizeBytes > maxClipSizeBytes {
                // Skip this clip - too large
                showSizeNotification(type: "Text", actualSize: textSizeBytes, limit: maxClipSizeBytes)
                return
            }

            if !plainText.isEmpty && plainText != lastContent {
                let recent = await database.getRecentClips(limit: 1)
                if recent.isEmpty || recent[0].content != plainText {
                    // Store RTF data separately if it has formatting
                    if attributedString.length > 0 && attributedString.containsAttachments == false {
                        await database.saveClip(plainText, type: "rtf", rtfData: rtfData, sourceApp: source)
                    } else {
                        await database.saveClip(plainText, sourceApp: source)
                    }
                    lastContent = plainText
                    await appState?.loadClips()
                }
                return
            }
        }

        // Get plain text content as fallback
        guard let content = pasteboard.string(forType: .string),
              !content.isEmpty,
              content != lastContent else { return }

        // Check size limit
        let textSizeBytes = content.utf8.count
        if textSizeBytes > maxClipSizeBytes {
            // Skip this clip - too large
            showSizeNotification(type: "Text", actualSize: textSizeBytes, limit: maxClipSizeBytes)
            return
        }

        // Avoid duplicates by checking last entry
        let recent = await database.getRecentClips(limit: 1)
        if recent.isEmpty || recent[0].content != content {
            await database.saveClip(content, sourceApp: source)
            lastContent = content
            await appState?.loadClips()
        }
    }

    private func showSizeNotification(type: String, actualSize: Int, limit: Int) {
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
