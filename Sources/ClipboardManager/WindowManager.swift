import SwiftUI
import AppKit

@MainActor
class WindowManager {
    static let shared = WindowManager()

    private var searchWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private var aboutWindow: NSWindow?

    private init() {}

    func openSearch(appState: AppState) {
        if let window = searchWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let contentView = SearchView()
                .environmentObject(appState)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Search Clipboard History"
            window.center()
            window.contentView = NSHostingView(rootView: contentView)
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            searchWindow = window
        }
    }

    func openPreferences(appState: AppState) {
        if let window = preferencesWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let contentView = PreferencesView()
                .environmentObject(appState)

            let window = makeSettingsWindow(title: "Clipboard Manager Settings", content: contentView)
            preferencesWindow = window
        }
    }

    func openAbout(appState: AppState) {
        if let window = aboutWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let contentView = AboutView()
                .environmentObject(appState)

            let window = makeSettingsWindow(title: "About Clipboard Manager", content: contentView)
            aboutWindow = window
        }
    }

    /// Let AppKit follow the SwiftUI content size, including changes between settings tabs.
    private func makeSettingsWindow<Content: View>(title: String, content: Content) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = title
        window.isReleasedWhenClosed = false
        if let visible = NSScreen.main?.visibleFrame.size {
            window.contentMaxSize = NSSize(width: visible.width * 0.9, height: visible.height * 0.9)
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
}
