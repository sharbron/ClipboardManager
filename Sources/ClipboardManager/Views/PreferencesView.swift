import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "slider.horizontal.3")
                }
                .tag(0)

            HistoryPreferencesView()
                .environmentObject(appState)
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(1)

            AppearancePreferencesView()
                .environmentObject(appState)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(2)

            SnippetsPreferencesView()
                .environmentObject(appState)
                .tabItem {
                    Label("Snippets", systemImage: "text.badge.plus")
                }
                .tag(3)

            AdvancedPreferencesView()
                .environmentObject(appState)
                .tabItem {
                    Label("Advanced", systemImage: "wand.and.stars")
                }
                .tag(4)
        }
        .frame(minWidth: 700, idealWidth: 800, maxWidth: 1000, minHeight: 500, idealHeight: 650, maxHeight: 850)
    }
}

// MARK: - General Preferences Tab

struct GeneralPreferencesView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("autoClearOnLogout") private var autoClearOnLogout: Bool = false
    @AppStorage("enableNotifications") private var enableNotifications: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Startup Section
                PreferenceSection(title: "Startup", icon: "power") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Launch at login", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { newValue in
                                setLaunchAtLogin(newValue)
                            }

                        Text("Automatically start Clipboard Manager when you log in.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Privacy Section
                PreferenceSection(title: "Privacy", icon: "lock.shield") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Clear history on logout", isOn: $autoClearOnLogout)

                        Text("Automatically wipe all clipboard history when you log out of macOS.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Notifications Section
                PreferenceSection(title: "Notifications", icon: "bell.badge") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable notifications", isOn: $enableNotifications)

                        Text("Display system notifications when clipboard items are captured.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Keyboard Shortcuts Section
                PreferenceSection(title: "Keyboard Shortcuts", icon: "command") {
                    VStack(alignment: .leading, spacing: 10) {
                        KeyboardShortcutRow(label: "Open search window", shortcut: "⌘⇧Space")
                        KeyboardShortcutRow(label: "Quick paste", shortcut: "⌘1 - ⌘9")

                        Text("Keyboard shortcuts are global and work in any application.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(20)
        }
    }

    private func setLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enable ? "enable" : "disable") launch at login: \(error)")
        }
    }
}

// MARK: - History Preferences Tab

struct HistoryPreferencesView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("cleanupDays") private var cleanupDays: Double = 30
    @AppStorage("maxClips") private var maxClips: Double = 15
    @AppStorage("maxClipSize") private var maxClipSize: Double = 100
    @AppStorage("maxImageSize") private var maxImageSize: Double = 2048
    @AppStorage("ocrEnabled") private var ocrEnabled: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Retention Period Section
                PreferenceSection(title: "Storage", icon: "internaldrive") {
                    VStack(alignment: .leading, spacing: 12) {
                        SliderWithLabel(
                            label: "Keep clipboard history for",
                            value: $cleanupDays,
                            in: 1...365,
                            step: 1,
                            suffix: "days"
                        )

                        Text("Clips older than this will be automatically removed.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Menu Bar Display Section
                PreferenceSection(title: "Menu Bar Display", icon: "menubar.rectangle") {
                    VStack(alignment: .leading, spacing: 12) {
                        SliderWithLabel(
                            label: "Show in menu bar",
                            value: $maxClips,
                            in: 5...50,
                            step: 1,
                            suffix: "clips"
                        )
                        .onChange(of: maxClips) { newValue in
                            UserDefaults.standard.set(Int(newValue), forKey: "menuBarClipCount")
                            Task { @MainActor in appState.loadClips() }
                        }

                        Text("Number of recent clips to display in the menu bar.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // OCR Section
                PreferenceSection(title: "Image Recognition", icon: "doc.text.viewfinder") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Extract text from images (OCR)", isOn: $ocrEnabled)

                        Text("Use optical character recognition to extract and search text from captured images.")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("⚠️ OCR processing may slow down image capture on older Macs.", comment: "Warning")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                // Size Limits Section
                PreferenceSection(title: "Size Limits", icon: "ruler") {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            SliderWithLabel(
                                label: "Maximum text size",
                                value: $maxClipSize,
                                in: 10...1000,
                                step: 10,
                                suffix: "KB"
                            )

                            Text(
                                """
                                Text clips larger than this will be skipped. \
                                (Approximately \(estimatePages(Int(maxClipSize))) pages)
                                """
                            )
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            SliderWithLabel(
                                label: "Maximum image size",
                                value: $maxImageSize,
                                in: 100...10240,
                                step: 256,
                                suffix: formatImageSize(Int(maxImageSize))
                            )

                            Text("Images larger than this will be skipped.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func estimatePages(_ kb: Int) -> String {
        let approximateChars = kb * 1024 / 2  // Rough estimate: 2 bytes per char
        let wordsPerPage = 250
        let charsPerWord = 5
        let pages = max(1, approximateChars / (wordsPerPage * charsPerWord))
        return pages > 1 ? "\(pages) pages" : "< 1 page"
    }

    private func formatImageSize(_ kb: Int) -> String {
        if kb >= 1024 {
            return String(format: "%.1f MB", Double(kb) / 1024.0)
        }
        return "\(kb)"
    }
}

// MARK: - Appearance Preferences Tab

struct AppearancePreferencesView: View {
    @AppStorage("previewLength") private var previewLength: Double = 150
    @AppStorage("showTypeIcons") private var showTypeIcons: Bool = true
    @AppStorage("compactMode") private var compactMode: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Menu Display Section
                PreferenceSection(title: "Menu Display", icon: "list.bullet") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Show content type icons", isOn: $showTypeIcons)

                        Text("Display icons indicating text, image, or RTF content type.")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Divider()
                            .padding(.vertical, 4)

                        Toggle("Compact mode", isOn: $compactMode)

                        Text("Reduce spacing between menu items for a denser layout.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Preview Section
                PreferenceSection(title: "Text Preview", icon: "text.alignleft") {
                    VStack(alignment: .leading, spacing: 12) {
                        SliderWithLabel(
                            label: "Preview length",
                            value: $previewLength,
                            in: 50...300,
                            step: 25,
                            suffix: "characters"
                        )

                        Text("Maximum characters to display in menu item previews.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Tips Section
                PreferenceSection(title: "Tips", icon: "lightbulb") {
                    VStack(alignment: .leading, spacing: 10) {
                        TipRow(icon: "calendar", text: "The menu bar displays clipboard history grouped by date")
                        TipRow(icon: "pin.fill", text: "Pinned items always stay at the top")
                        TipRow(icon: "hand.point.right.fill", text: "Right-click any item for more options")
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Advanced Preferences Tab

struct AdvancedPreferencesView: View {
    @EnvironmentObject var appState: AppState
    @State private var totalClips: Int = 0
    @State private var textCount: Int = 0
    @State private var imageCount: Int = 0
    @State private var pinnedCount: Int = 0
    @State private var databaseSize: String = "Calculating..."
    @State private var showingClear24Confirmation = false
    @State private var showingClearAllConfirmation = false
    @State private var showingSuccessMessage = false
    @State private var successMessage = ""
    @State private var showingExportPanel = false
    @State private var showingImportPanel = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Database Statistics Section
                PreferenceSection(title: "Database Statistics", icon: "cylinder") {
                    VStack(alignment: .leading, spacing: 16) {
                        // Stats Grid
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 20) {
                                StatCard(label: "Total", value: "\(totalClips)", icon: "doc.on.doc")
                                StatCard(label: "Text", value: "\(textCount)", icon: "doc.text")
                            }
                            HStack(spacing: 20) {
                                StatCard(label: "Images", value: "\(imageCount)", icon: "photo")
                                StatCard(label: "Pinned", value: "\(pinnedCount)", icon: "pin.fill")
                            }
                        }

                        Divider()

                        // Database Info
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Database size")
                                    .font(.body)
                                Spacer()
                                Text(databaseSize)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.semibold)
                            }

                            HStack {
                                Text("Location")
                                    .font(.body)
                                Spacer()
                                Text("~/.clipboard_history.db")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Button(action: revealDatabaseInFinder) {
                                Label("Reveal in Finder", systemImage: "folder")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                // Backup & Restore Section
                PreferenceSection(title: "Backup & Restore", icon: "arrow.triangle.2.circlepath") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Button(action: { showingExportPanel = true }) {
                                Label("Export", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button(action: { showingImportPanel = true }) {
                                Label("Import", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Back up your preferences or transfer to another Mac.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Clear History Section
                PreferenceSection(title: "Danger Zone", icon: "exclamationmark.triangle", isDanger: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Button(action: { showingClear24Confirmation = true }) {
                                Label("Clear 24h", systemImage: "clock")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)

                            Button(action: { showingClearAllConfirmation = true }) {
                                Label("Clear All", systemImage: "trash.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }

                        Text("Pinned items will be preserved. This action cannot be undone.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Security Section
                PreferenceSection(title: "Security Status", icon: "lock.shield") {
                    VStack(alignment: .leading, spacing: 12) {
                        SecurityFeatureRow(
                            icon: "checkmark.shield.fill",
                            color: .green,
                            title: "AES-256-GCM Encryption",
                            subtitle: "Military-grade encryption enabled"
                        )

                        SecurityFeatureRow(
                            icon: "key.fill",
                            color: .blue,
                            title: "Keychain Protection",
                            subtitle: "Encryption key secured in system keychain"
                        )
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            loadStats()
        }
        .alert("Clear Last 24 Hours?", isPresented: $showingClear24Confirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearLast24Hours()
            }
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
            Button("Delete All", role: .destructive) {
                clearAllHistory()
            }
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

            await MainActor.run {
                totalClips = allClips.count
                textCount = allClips.filter { $0.contentType == "text" || $0.contentType == "rtf" }.count
                imageCount = allClips.filter { $0.contentType == "image" }.count
                pinnedCount = allClips.filter { $0.isPinned }.count

                // Calculate database size
                let dbPath = NSHomeDirectory() + "/.clipboard_history.db"
                if let attributes = try? FileManager.default.attributesOfItem(atPath: dbPath),
                   let fileSize = attributes[.size] as? Int64 {
                    databaseSize = formatFileSize(fileSize)
                }
            }
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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
            successMessage = "Settings exported successfully!"
            showingSuccessMessage = true
        case .failure(let error):
            successMessage = "Export failed: \(error.localizedDescription)"
            showingSuccessMessage = true
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            if importSettings(from: url) {
                successMessage = "Settings imported successfully! Restart the app to apply changes."
                showingSuccessMessage = true
            }
        case .failure(let error):
            successMessage = "Import failed: \(error.localizedDescription)"
            showingSuccessMessage = true
        }
    }

    private func importSettings(from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }

            // Import settings into UserDefaults
            for (key, value) in json {
                // Skip system keys that shouldn't be imported
                guard !key.hasPrefix("NS") && !key.hasPrefix("Apple") else { continue }

                UserDefaults.standard.set(value, forKey: key)
            }

            // Reload UI by resetting appearance and reloading clips
            DispatchQueue.main.async {
                appState.loadClips()
            }

            return true
        } catch {
            return false
        }
    }
}

// MARK: - Helper Views

struct PreferenceSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    var isDanger: Bool = false

    init(title: String, icon: String, isDanger: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.isDanger = isDanger
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.primary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            isDanger
                ? Color.red.opacity(0.08)
                : Color.gray.opacity(0.05)
        )
        .cornerRadius(8)
    }
}

struct StatCard: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(8)
    }
}

struct SecurityFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

struct SliderWithLabel: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    init(
        label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double = 1,
        suffix: String
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.suffix = suffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.body)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(Int(value))")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                    Text(suffix)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Slider(value: $value, in: range, step: step) {
                Text(label)
            }
            .tint(.blue)
        }
    }
}

struct KeyboardShortcutRow: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6))
                .cornerRadius(6)
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Preferences Document

import UniformTypeIdentifiers

struct PreferencesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var settings: [String: Any] = [:]

    init() {
        // Export current UserDefaults
        if let defaults = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") {
            self.settings = defaults
        }
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.settings = json
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted])
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Snippets Preferences Tab

struct SnippetsPreferencesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        SnippetsView(appState: appState)
    }
}
