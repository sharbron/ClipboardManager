import SwiftUI
import ServiceManagement
import os.log

private let logger = Logger(subsystem: "com.clipboardmanager", category: "PreferencesView")

// Every tab uses SwiftUI's grouped Form - the same grouped-row layout System Settings uses.
// This replaces a hand-rolled `PreferenceSection` card that wrapped each group in a tinted
// background with its own icon and headline, so a section holding a single checkbox rendered
// as a large coloured box containing one checkbox. Explanatory captions are kept only where
// they say something the control's own label doesn't.

struct PreferencesView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)

            HistoryPreferencesView()
                .environmentObject(appState)
                .tabItem { Label("History", systemImage: "clock") }
                .tag(1)

            AppearancePreferencesView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(2)

            SnippetsPreferencesView()
                .environmentObject(appState)
                .tabItem { Label("Snippets", systemImage: "text.badge.plus") }
                .tag(3)

            AdvancedPreferencesView()
                .environmentObject(appState)
                .tabItem { Label("Advanced", systemImage: "wand.and.stars") }
                .tag(4)
        }
        .frame(minWidth: 540, idealWidth: 620, minHeight: 400, idealHeight: 560)
    }
}

// MARK: - General

struct GeneralPreferencesView: View {
    @AppStorage(Preferences.launchAtLogin) private var launchAtLogin: Bool = false
    @AppStorage(Preferences.autoClearOnLogout) private var autoClearOnLogout: Bool = false
    @AppStorage(Preferences.enableNotifications) private var enableNotifications: Bool = true

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("Privacy") {
                Toggle("Clear history on logout", isOn: $autoClearOnLogout)
                FormCaption("Unpinned clips are wiped when you log out or shut down.")
            }

            Section("Notifications") {
                Toggle("Notify when a clip is captured", isOn: $enableNotifications)
            }

            // The single home for the shortcut reference - it used to be duplicated in the
            // About window with different styling.
            Section("Keyboard Shortcuts") {
                ShortcutRow("Open clipboard history", "⌘⇧Space")
                ShortcutRow("Copy recent item from menu", "⌘1 – ⌘9")
                ShortcutRow("Navigate search results", "↑ ↓")
                ShortcutRow("Copy selected and close", "↵")
                ShortcutRow("Close search", "esc")
                FormCaption("The first two work globally, in any application.")
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Failed to \(enable ? "enable" : "disable") launch at login: \(error.localizedDescription)")
        }
    }
}

// MARK: - History

struct HistoryPreferencesView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage(Preferences.cleanupDays) private var cleanupDays: Double = 30
    @AppStorage(Preferences.maxClips) private var maxClips: Double = 15
    @AppStorage(Preferences.maxClipSize) private var maxClipSize: Double = 100
    @AppStorage(Preferences.maxImageSize) private var maxImageSize: Double = 2048
    @AppStorage(Preferences.ocrEnabled) private var ocrEnabled: Bool = true

    var body: some View {
        Form {
            Section("Storage") {
                ValueSlider(
                    "Keep history for",
                    value: $cleanupDays,
                    in: 1...365,
                    step: 1,
                    readout: "\(Int(cleanupDays)) days"
                )
                FormCaption("Older clips are removed automatically.")
            }

            Section("Menu Bar") {
                ValueSlider(
                    "Show in menu",
                    value: $maxClips,
                    in: 5...50,
                    step: 1,
                    readout: "\(Int(maxClips)) clips"
                )
                .onChange(of: maxClips) { _ in
                    appState.loadClips()
                }
            }

            Section("Size Limits") {
                ValueSlider(
                    "Maximum text",
                    value: $maxClipSize,
                    in: 10...1000,
                    step: 10,
                    readout: "\(Int(maxClipSize)) KB"
                )
                FormCaption("Roughly \(estimatePages(Int(maxClipSize))). Larger text clips are skipped.")

                ValueSlider(
                    "Maximum image",
                    value: $maxImageSize,
                    in: 100...10240,
                    step: 256,
                    readout: formatImageSize(Int(maxImageSize))
                )
                FormCaption("Larger images are skipped.")
            }

            Section("Image Recognition") {
                Toggle("Extract text from images (OCR)", isOn: $ocrEnabled)
                FormCaption("Makes image contents searchable. May slow capture on older Macs.")
            }
        }
        .formStyle(.grouped)
    }

    private func estimatePages(_ kilobytes: Int) -> String {
        let approximateChars = kilobytes * 1024 / 2  // Rough estimate: 2 bytes per char
        let pages = max(1, approximateChars / (250 * 5))  // 250 words/page, 5 chars/word
        return pages > 1 ? "\(pages) pages" : "under a page"
    }

    private func formatImageSize(_ kilobytes: Int) -> String {
        kilobytes >= 1024
            ? String(format: "%.1f MB", Double(kilobytes) / 1024.0)
            : "\(kilobytes) KB"
    }
}

// MARK: - Appearance

struct AppearancePreferencesView: View {
    @AppStorage(Preferences.previewLength) private var previewLength: Double = 60
    @AppStorage(Preferences.showTypeIcons) private var showTypeIcons: Bool = true
    @AppStorage(Preferences.compactMode) private var compactMode: Bool = false

    var body: some View {
        Form {
            Section("Menu Display") {
                Toggle("Show content type icons", isOn: $showTypeIcons)
                Toggle("Compact spacing", isOn: $compactMode)
            }

            Section("Preview") {
                ValueSlider(
                    "Preview length",
                    value: $previewLength,
                    in: Preferences.previewLengthRange,
                    step: 10,
                    readout: "\(Int(previewLength)) chars"
                )
                FormCaption("Applies to the menu bar list and to search results.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Snippets

struct SnippetsPreferencesView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage(Preferences.snippetsEnabled) private var snippetsEnabled: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Expand snippet triggers on copy", isOn: $snippetsEnabled)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            SnippetsView(appState: appState)
                .disabled(!snippetsEnabled)
                .opacity(snippetsEnabled ? 1 : 0.5)
        }
    }
}

// MARK: - Advanced

struct AdvancedPreferencesView: View {
    @EnvironmentObject var appState: AppState
    @State private var totalClips: Int = 0
    @State private var textCount: Int = 0
    @State private var imageCount: Int = 0
    @State private var pinnedCount: Int = 0
    @State private var databaseSize: String = "Calculating…"
    @State private var showingClear24Confirmation = false
    @State private var showingClearAllConfirmation = false
    @State private var showingSuccessMessage = false
    @State private var successMessage = ""
    @State private var showingExportPanel = false
    @State private var showingImportPanel = false

    var body: some View {
        Form {
            Section("Database") {
                LabeledContent("Clips stored", value: "\(totalClips)")
                LabeledContent("Text", value: "\(textCount)")
                LabeledContent("Images", value: "\(imageCount)")
                LabeledContent("Pinned", value: "\(pinnedCount)")
                LabeledContent("Size on disk", value: databaseSize)
                LabeledContent("Location") {
                    Button("Reveal in Finder", action: revealDatabaseInFinder)
                }
            }

            Section("Security") {
                LabeledContent("Encryption", value: "AES-256-GCM")
                LabeledContent("Key storage", value: "System Keychain")
                FormCaption("Clip contents, OCR text, images and snippet bodies are all encrypted at rest.")
            }

            Section("Settings Backup") {
                LabeledContent("Preferences file") {
                    HStack {
                        Button("Export…") { showingExportPanel = true }
                        Button("Import…") { showingImportPanel = true }
                    }
                }
                FormCaption("Backs up preferences only, not your clipboard history.")
            }

            Section("Clear History") {
                LabeledContent("Delete clips") {
                    HStack {
                        Button("Last 24 Hours") { showingClear24Confirmation = true }
                        Button("All") { showingClearAllConfirmation = true }
                    }
                }
                FormCaption("Pinned clips are always preserved. This cannot be undone.")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadStats)
        .alert("Clear Last 24 Hours?", isPresented: $showingClear24Confirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive, action: clearLast24Hours)
        } message: {
            Text(
                """
                This will permanently delete all clips from the last 24 hours \
                (except pinned clips). This cannot be undone.
                """
            )
        }
        .alert("Clear All Clipboard History?", isPresented: $showingClearAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive, action: clearAllHistory)
        } message: {
            Text(
                """
                This will permanently delete ALL clipboard history \
                (except pinned clips). This action cannot be undone.
                """
            )
        }
        .alert("Success", isPresented: $showingSuccessMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(successMessage)
        }
        .fileExporter(
            isPresented: $showingExportPanel,
            document: PreferencesDocument(),
            contentType: .json,
            defaultFilename: "ClipboardManager-Settings.json"
        ) { result in
            handleExportResult(result)
        }
        .fileImporter(
            isPresented: $showingImportPanel,
            allowedContentTypes: [.json]
        ) { result in
            handleImportResult(result)
        }
    }

    private func loadStats() {
        Task {
            let allClips = await appState.database.getRecentClips(limit: 10000)
            let size = await appState.database.getDatabaseSize()

            await MainActor.run {
                totalClips = allClips.count
                textCount = allClips.filter { $0.contentType == "text" || $0.contentType == "rtf" }.count
                imageCount = allClips.filter { $0.contentType == "image" }.count
                pinnedCount = allClips.filter { $0.isPinned }.count
                databaseSize = size
            }
        }
    }

    private func revealDatabaseInFinder() {
        let dbPath = NSHomeDirectory() + "/.clipboard_history.db"
        NSWorkspace.shared.selectFile(dbPath, inFileViewerRootedAtPath: NSHomeDirectory())
    }

    private func clearLast24Hours() {
        Task {
            let deleted = await appState.database.clearLast24Hours()
            await MainActor.run {
                appState.loadClips()
                successMessage = "Removed \(deleted) clip\(deleted == 1 ? "" : "s") from the last 24 hours."
                showingSuccessMessage = true
            }
            loadStats()
        }
    }

    private func clearAllHistory() {
        Task {
            let deleted = await appState.database.clearAllHistory(keepPinned: true)
            await MainActor.run {
                appState.loadClips()
                let clipWord = deleted == 1 ? "clip" : "clips"
                successMessage = "Removed \(deleted) \(clipWord). Pinned clips were preserved."
                showingSuccessMessage = true
            }
            loadStats()
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            successMessage = "Settings exported successfully."
        case .failure(let error):
            successMessage = "Export failed: \(error.localizedDescription)"
        }
        showingSuccessMessage = true
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            successMessage = importSettings(from: url)
                ? "Settings imported successfully."
                : "Could not read that settings file."
        case .failure(let error):
            successMessage = "Import failed: \(error.localizedDescription)"
        }
        showingSuccessMessage = true
    }

    private func importSettings(from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }

            // Import settings into UserDefaults, skipping unknown keys and values of the
            // wrong type so a hand-edited file can't leave a preference unreadable.
            for (key, value) in json {
                guard Preferences.importable.contains(key),
                      let coerced = Preferences.coerceImported(value, forKey: key) else { continue }

                UserDefaults.standard.set(coerced, forKey: key)
            }

            appState.loadClips()
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Shared form components

/// Secondary explanatory text inside a Form section. Used only where it adds something the
/// control's own label doesn't already say.
struct FormCaption: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A slider with its current value beside it, laid out as a standard labelled form row.
struct ValueSlider: View {
    private let label: String
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let readout: String

    init(
        _ label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double = 1,
        readout: String
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.readout = readout
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step) {
                    Text(label)
                }
                .labelsHidden()

                Text(readout)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 66, alignment: .trailing)
            }
        } label: {
            Text(label)
        }
    }
}

/// A read-only shortcut reference row. The key cap uses a semantic fill so it stays legible
/// in both themes - the previous version hardcoded `Color.black.opacity(0.6)`, which rendered
/// as a black blob against a dark background.
struct ShortcutRow: View {
    private let action: String
    private let keys: String

    init(_ action: String, _ keys: String) {
        self.action = action
        self.keys = keys
    }

    var body: some View {
        LabeledContent {
            Text(keys)
                .font(.callout)
                .monospaced()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        } label: {
            Text(action)
        }
    }
}
