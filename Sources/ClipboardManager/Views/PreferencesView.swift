import SwiftUI
import ServiceManagement
import os.log

private let logger = Logger(subsystem: "com.clipboardmanager", category: "PreferencesView")

/// Compact grouped settings with the same tab spacing and content sizing as Window Switcher.
struct PreferencesView: View {
    @State private var selectedTab: PreferencesTab

    init(selection: PreferencesTab = .general) {
        _selectedTab = State(initialValue: selection)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(PreferencesTab.general)
            HistoryPreferencesView()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(PreferencesTab.history)
            AppearancePreferencesView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(PreferencesTab.appearance)
            SnippetsPreferencesView()
                .tabItem { Label("Snippets", systemImage: "text.badge.plus") }
                .tag(PreferencesTab.snippets)
            ShortcutsPreferencesView()
                .tabItem { Label("Shortcuts", systemImage: "command") }
                .tag(PreferencesTab.shortcuts)
            AdvancedPreferencesView()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag(PreferencesTab.advanced)
        }
        .padding(.top, 12)
        // Constrain the form itself on smaller displays so its contents can scroll.
        .frame(width: 540, height: min(selectedTab.contentHeight + 12, availableHeight))
    }

    private var availableHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) * 0.9
    }
}

enum PreferencesTab: CaseIterable {
    case general, history, appearance, snippets, shortcuts, advanced

    var contentHeight: CGFloat {
        switch self {
        case .general: return 340
        case .history: return 640
        case .appearance: return 550
        case .snippets: return 590
        case .shortcuts: return 550
        case .advanced: return 740
        }
    }
}

// MARK: - General

struct GeneralPreferencesView: View {
    @AppStorage(Preferences.launchAtLogin) private var launchAtLogin: Bool = false
    @AppStorage(Preferences.autoClearOnLogout) private var autoClearOnLogout: Bool = false
    @AppStorage(Preferences.enableNotifications) private var enableNotifications: Bool = true

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
            } footer: {
                SettingsFooter("Automatically start Clipboard Manager when you log in.")
            }

            Section {
                Toggle("Clear history on logout", isOn: $autoClearOnLogout)
            } footer: {
                SettingsFooter("Unpinned clips are cleared when you log out or shut down.")
            }

            Section {
                Toggle("Notify when a clip is captured", isOn: $enableNotifications)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: syncLaunchAtLoginToggle)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            syncLaunchAtLoginToggle()
        }
    }

    private func setLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            logger.error("Failed to \(enable ? "enable" : "disable") launch at login: \(error.localizedDescription)")
            DispatchQueue.main.async {
                syncLaunchAtLoginToggle()
            }
        }
    }

    private func syncLaunchAtLoginToggle() {
        let registered = SMAppService.mainApp.status == .enabled
        if launchAtLogin != registered {
            launchAtLogin = registered
        }
    }
}

// MARK: - History

struct HistoryPreferencesView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage(Preferences.cleanupDays) private var cleanupDays: Double = 30
    @AppStorage(Preferences.maxClips) private var maxClips: Double = 15
    @AppStorage(Preferences.maxClipSize) private var maxClipSize: Double = 100
    @AppStorage(Preferences.maxImageSize) private var maxImageSize: Double = 10240
    @AppStorage(Preferences.ocrEnabled) private var ocrEnabled: Bool = true

    var body: some View {
        Form {
            Section {
                ValueSlider(
                    "Keep history for",
                    value: $cleanupDays,
                    in: 1...365,
                    step: 1,
                    readout: "\(Int(cleanupDays)) days"
                )
            } header: {
                Text("Storage")
            } footer: {
                SettingsFooter("Older clips are removed automatically.")
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

            Section {
                ValueSlider(
                    "Maximum text",
                    value: $maxClipSize,
                    in: 10...1000,
                    step: 10,
                    readout: "\(Int(maxClipSize)) KB"
                )
            } header: {
                Text("Text Size Limit")
            } footer: {
                SettingsFooter("Roughly \(estimatePages(Int(maxClipSize))). Larger text clips are skipped.")
            }

            Section {
                ValueSlider(
                    "Maximum image",
                    value: $maxImageSize,
                    in: 100...10240,
                    step: 256,
                    readout: formatImageSize(Int(maxImageSize))
                )
            } header: {
                Text("Image Size Limit")
            } footer: {
                SettingsFooter("Larger images are skipped.")
            }

            Section {
                Toggle("Extract text from images (OCR)", isOn: $ocrEnabled)
            } header: {
                Text("Image Recognition")
            } footer: {
                SettingsFooter("Makes image contents searchable. May slow capture on older Macs.")
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
            Section {
                ClipboardAppearancePreview(
                    previewLength: Int(previewLength),
                    showTypeIcons: showTypeIcons,
                    compactMode: compactMode
                )
            }

            Section("Menu Display") {
                Toggle("Show content type icons", isOn: $showTypeIcons)
                Toggle("Compact spacing", isOn: $compactMode)
            }

            Section {
                ValueSlider(
                    "Preview length",
                    value: $previewLength,
                    in: Preferences.previewLengthRange,
                    step: 10,
                    readout: "\(Int(previewLength)) chars"
                )
            } header: {
                Text("Preview")
            } footer: {
                SettingsFooter("Applies to the menu bar list and to search results.")
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

            Section {
                LabeledContent("Encryption", value: "AES-256-GCM")
                LabeledContent("Key storage", value: "System Keychain")
            } header: {
                Text("Security")
            } footer: {
                SettingsFooter("Clip contents, OCR text, images and snippet bodies are all encrypted at rest.")
            }

            Section {
                LabeledContent("Preferences file") {
                    HStack {
                        Button("Export…") { showingExportPanel = true }
                        Button("Import…") { showingImportPanel = true }
                    }
                }
            } header: {
                Text("Settings Backup")
            } footer: {
                SettingsFooter("Backs up preferences only, not your clipboard history.")
            }

            Section {
                LabeledContent("Delete clips") {
                    HStack {
                        Button("Last 24 Hours") { showingClear24Confirmation = true }
                        Button("All") { showingClearAllConfirmation = true }
                    }
                }
            } header: {
                Text("Clear History")
            } footer: {
                SettingsFooter("Pinned clips are always preserved. This cannot be undone.")
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
            let statistics = await appState.database.getStatistics()
            let size = await appState.database.getDatabaseSize()

            await MainActor.run {
                totalClips = statistics.total
                textCount = statistics.text
                imageCount = statistics.images
                pinnedCount = statistics.pinned
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

    private var snappedValue: Binding<Double> {
        Binding(
            get: { value },
            set: { value = Self.snap($0, to: step, in: range) }
        )
    }

    /// Rounds to the nearest step counted from the range's lower bound, clamped to the range.
    /// The upper bound counts as a stop too, since a range needn't end on a whole step
    /// (100...10240 in steps of 256).
    static func snap(_ raw: Double, to step: Double, in range: ClosedRange<Double>) -> Double {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        guard step > 0 else { return clamped }
        let steps = ((clamped - range.lowerBound) / step).rounded()
        let snapped = min(range.lowerBound + steps * step, range.upperBound)
        return range.upperBound - clamped < abs(snapped - clamped) ? range.upperBound : snapped
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                // Passing `step` to Slider makes macOS draw a tick mark for every step, which
                // for ranges like 1...365 fills the track with a dense bar. Snap the value
                // ourselves instead so the slider stays a clean track.
                Slider(value: snappedValue, in: range) {
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

// MARK: - Shortcuts

struct ShortcutsPreferencesView: View {
    var body: some View {
        Form {
            Section {
                ShortcutFormRows(shortcuts: ClipboardShortcuts.global)
            } header: {
                Text("Global")
            } footer: {
                SettingsFooter("Works in any app. Requires Accessibility access in System Settings.")
            }

            Section {
                ShortcutFormRows(shortcuts: ClipboardShortcuts.menu)
            } header: {
                Text("Clipboard Menu")
            } footer: {
                SettingsFooter("Available while the clipboard menu is open.")
            }

            Section("Search") {
                ShortcutFormRows(shortcuts: ClipboardShortcuts.search)
            }
        }
        .formStyle(.grouped)
    }
}
