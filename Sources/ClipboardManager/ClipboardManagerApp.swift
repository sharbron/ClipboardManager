import SwiftUI
import UserNotifications
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.clipboardmanager", category: "AppLifecycle")

@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState: AppState

    init() {
        Preferences.register()

        let database = ClipboardDatabase()
        let snippetDatabase = SnippetDatabase()
        let snippetManager = SnippetManager(database: snippetDatabase)
        let appState = AppState(
            database: database,
            snippetDatabase: snippetDatabase,
            snippetManager: snippetManager
        )
        _appState = StateObject(wrappedValue: appState)

        // Hand the state to the app delegate so it can start monitoring as soon as the app
        // finishes launching. This used to hang off a SwiftUI `onChange` on the scene, which
        // only fired if the scene happened to be re-evaluated after launch - when it wasn't,
        // the app sat in the menu bar capturing nothing.
        AppDelegate.launchAppState = appState
    }

    var body: some Scene {
        // MenuBarExtra provides the menu bar integration
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: "clipboard")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// AppDelegate to handle app lifecycle and setup
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var clipboardMonitor: ClipboardMonitor?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cleanupTask: Task<Void, Never>?
    private var logoutObserver: NSObjectProtocol?
    private var logoutCleanupTask: Task<Void, Never>?
    private var isLoggingOut = false
    private var isWaitingToTerminate = false

    /// Set by `ClipboardManagerApp.init`, which runs before the app finishes launching.
    static var launchAppState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.debug("ClipboardManager launched")

        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        guard let appState = Self.launchAppState else {
            logger.error("No app state available at launch - clipboard monitoring not started")
            return
        }
        initialize(with: appState)
    }

    func initialize(with appState: AppState) {
        // Prevent double initialization
        guard clipboardMonitor == nil else {
            logger.debug("initialize() called but already initialized - skipping")
            return
        }

        // Both databases finish initialising synchronously in their own init, so their status
        // is already final here. An earlier version polled these flags in a loop, which meant
        // a failed database left the app spinning forever behind a menu bar icon that looked
        // healthy but did nothing.
        guard appState.database.isInitialized else {
            reportFatalStartupError(
                "Clipboard Manager can't open its history database.",
                detail: appState.database.initializationError
            )
            return
        }

        guard appState.snippetDatabase.isInitialized else {
            reportFatalStartupError(
                "Clipboard Manager can't open its snippets database.",
                detail: appState.snippetDatabase.initializationError
            )
            return
        }

        Task {
            // Schema migrations run off the main thread so a large history doesn't stall launch
            await appState.database.prepare()
            await appState.snippetDatabase.prepare()
            appState.loadClips()
            appState.loadSnippets()

            // Initialize clipboard monitor with snippet manager
            let monitor = ClipboardMonitor(
                database: appState.database,
                appState: appState,
                snippetManager: appState.snippetManager
            )
            clipboardMonitor = monitor
            appState.clipboardMonitor = monitor
            monitor.startMonitoring()

            // Setup global hotkey (Cmd+Shift+Space)
            setupGlobalHotkey(appState: appState)

            // Enforce the configured retention period
            startPeriodicCleanup(appState: appState)

            // Honour "clear history on logout"
            observeLogout(appState: appState)
        }
    }

    /// Shows a blocking alert and quits: without a database there is nothing the app can do,
    /// and failing silently would leave a menu bar icon that captures nothing.
    private func reportFatalStartupError(_ message: String, detail: String?) {
        logger.error("Fatal startup error: \(message) \(detail ?? "")")

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = message
        alert.informativeText = [
            detail,
            "If this persists, check permissions on ~/.clipboard_history.db or remove it to start fresh."
        ].compactMap { $0 }.joined(separator: "\n\n")
        alert.addButton(withTitle: "Quit")
        alert.runModal()

        NSApplication.shared.terminate(nil)
    }

    /// Clears unpinned history when the user logs out or shuts down, if they've asked for it.
    private func observeLogout(appState: AppState) {
        logoutObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                self.isLoggingOut = true
                guard Preferences.clearsHistoryOnLogout, self.logoutCleanupTask == nil else { return }
                self.logoutCleanupTask = Task {
                    let deleted = await appState.database.clearAllHistory(keepPinned: true)
                    logger.info("Cleared \(deleted) clip(s) on logout")
                }
            }
        }
    }

    /// Keep the process alive until the privacy cleanup requested for logout has committed.
    /// Returning `terminateLater` is AppKit's supported way to finish asynchronous shutdown work.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard isLoggingOut,
              Preferences.clearsHistoryOnLogout,
              let logoutCleanupTask else {
            return .terminateNow
        }

        guard !isWaitingToTerminate else { return .terminateLater }
        isWaitingToTerminate = true
        Task {
            await logoutCleanupTask.value
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Runs clip retention cleanup immediately, then once every 24 hours.
    /// Reads the retention preference fresh each cycle so changes take effect
    /// without restarting the app.
    private func startPeriodicCleanup(appState: AppState) {
        cleanupTask?.cancel()
        cleanupTask = Task {
            while !Task.isCancelled {
                let days = Preferences.retentionDays

                let deleted = await appState.database.cleanupOldClips(days: days)
                if deleted > 0 {
                    logger.info("Auto-cleanup removed \(deleted) clip(s) older than \(days) day(s)")
                    await MainActor.run {
                        appState.loadClips()
                    }
                }

                try? await Task.sleep(nanoseconds: 24 * 60 * 60 * 1_000_000_000)
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stopMonitoring()
        cleanupTask?.cancel()

        // Remove event monitors to prevent leaks
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let logoutObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(logoutObserver)
        }
    }

    private func setupGlobalHotkey(appState: AppState) {
        // Check for Accessibility permissions (required for global hotkeys)
        // This will show macOS's built-in permission dialog if needed
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessibilityEnabled {
            logger.warning("Accessibility permission needed - macOS prompt shown. Please grant permission and restart.")
        } else {
            logger.debug("Accessibility permissions granted - global hotkey enabled")
        }

        // Store monitor references for cleanup
        // Global monitor: captures events when app is NOT active
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // Cmd+Shift+Space (keyCode 49)
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 49 {
                Task { @MainActor in
                    WindowManager.shared.openSearch(appState: appState)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Cmd+Shift+Space (keyCode 49)
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 49 {
                Task { @MainActor in
                    WindowManager.shared.openSearch(appState: appState)
                }
                return nil
            }
            return event
        }
    }
}
