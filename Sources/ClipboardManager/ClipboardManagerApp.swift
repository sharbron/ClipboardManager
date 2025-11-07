import SwiftUI
import UserNotifications
import ApplicationServices

@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState: AppState

    init() {
        let database = ClipboardDatabase()
        let snippetDatabase = SnippetDatabase()
        let snippetManager = SnippetManager(database: snippetDatabase)
        _appState = StateObject(wrappedValue: AppState(
            database: database,
            snippetDatabase: snippetDatabase,
            snippetManager: snippetManager
        ))
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
        .onChange(of: appDelegate.isReady) { isReady in
            if isReady {
                appDelegate.initialize(with: appState)
            }
        }
    }
}

/// AppDelegate to handle app lifecycle and setup
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var clipboardMonitor: ClipboardMonitor?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    @Published var isReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("🚀 ClipboardManager launched - applicationDidFinishLaunching()")

        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Signal that we're ready to initialize
        isReady = true
        NSLog("✅ isReady = true")
    }

    func initialize(with appState: AppState) {
        // Prevent double initialization
        guard clipboardMonitor == nil else {
            NSLog("⚠️ initialize() called but already initialized - skipping")
            return
        }

        NSLog("🟢 AppDelegate.initialize() called - starting setup")

        // Wait for database initialization
        Task {
            var initialized = appState.database.isInitialized
            while !initialized {
                try? await Task.sleep(nanoseconds: 100_000_000)
                initialized = appState.database.isInitialized
            }

            NSLog("✅ Database initialized")

            // Wait for snippet database initialization
            var snippetInitialized = appState.snippetDatabase.isInitialized
            while !snippetInitialized {
                try? await Task.sleep(nanoseconds: 100_000_000)
                snippetInitialized = appState.snippetDatabase.isInitialized
            }

            NSLog("✅ Snippet database initialized")

            // Initialize clipboard monitor with snippet manager
            let monitor = ClipboardMonitor(database: appState.database, appState: appState, snippetManager: appState.snippetManager)
            clipboardMonitor = monitor
            appState.clipboardMonitor = monitor
            monitor.startMonitoring()

            NSLog("✅ Clipboard monitor started")

            // Setup global hotkey (Cmd+Shift+Space)
            setupGlobalHotkey(appState: appState)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stopMonitoring()

        // Remove event monitors to prevent leaks
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private func setupGlobalHotkey(appState: AppState) {
        // Check for Accessibility permissions (required for global hotkeys)
        // This will show macOS's built-in permission dialog if needed
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)

        NSLog("ClipboardManager: Setting up global hotkey (Cmd+Shift+Space)")

        if !accessibilityEnabled {
            NSLog("⚠️ Accessibility permission needed - macOS prompt shown. Please grant permission and restart the app.")
        } else {
            NSLog("✅ Accessibility permissions granted - global hotkey enabled")
        }

        // Store monitor references for cleanup
        // Global monitor: captures events when app is NOT active
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // Cmd+Shift+Space (keyCode 49)
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 49 {
                NSLog("🔵 Global monitor triggered: Cmd+Shift+Space")
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
