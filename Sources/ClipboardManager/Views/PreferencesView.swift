import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gearshape")
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

            AdvancedPreferencesView()
                .environmentObject(appState)
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                .tag(3)
        }
        .frame(width: 650, height: 550)
    }
}

// MARK: - General Preferences Tab

struct GeneralPreferencesView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("autoClearOnLogout") private var autoClearOnLogout: Bool = false
    @AppStorage("showNotifications") private var showNotifications: Bool = true
    @AppStorage("playSounds") private var playSounds: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Startup Section
                PreferenceSection(title: "Startup", icon: "power") {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            setLaunchAtLogin(newValue)
                        }

                    Text("Automatically start Clipboard Manager when you log in.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Privacy Section
                PreferenceSection(title: "Privacy", icon: "lock.shield") {
                    Toggle("Clear history on logout", isOn: $autoClearOnLogout)

                    Text("Automatically wipe all clipboard history when you log out of macOS.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Notifications Section
                PreferenceSection(title: "Notifications", icon: "bell.badge") {
                    Toggle("Show notifications", isOn: $showNotifications)

                    Text("Display system notifications when clipboard items are captured.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Play sound effects", isOn: $playSounds)
                        .disabled(!showNotifications)

                    Text("Play a subtle sound when copying to clipboard.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Keyboard Shortcuts Section
                PreferenceSection(title: "Keyboard Shortcuts", icon: "command") {
                    HStack {
                        Text("Show clipboard menu:")
                        Spacer()
                        Text("⌘⇧V")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }

                    HStack {
                        Text("Quick paste (recent items):")
                        Spacer()
                        Text("⌘1 - ⌘9")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }

                    Text("Keyboard shortcuts are global and work in any application.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
        }
    }

    private func setLaunchAtLogin(_ enable: Bool) {
        // Placeholder - would use ServiceManagement framework in production
        print("Launch at login \(enable ? "enabled" : "disabled")")
    }
}

// MARK: - History Preferences Tab

struct HistoryPreferencesView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("cleanupDays") private var cleanupDays: Double = 30
    @AppStorage("maxClips") private var maxClips: Double = 15
    @AppStorage("maxClipSize") private var maxClipSize: Double = 100
    @AppStorage("maxImageSize") private var maxImageSize: Double = 2048

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Retention Period Section
                PreferenceSection(title: "Storage", icon: "internaldrive") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Keep clipboard history for:")
                            Spacer()
                            Text("\(Int(cleanupDays)) days")
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }

                        Slider(value: $cleanupDays, in: 1...365, step: 1) {
                            Text("Retention Period")
                        } minimumValueLabel: {
                            Text("1")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } maximumValueLabel: {
                            Text("365")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("Clips older than this will be automatically removed.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Show in menu bar:")
                            Spacer()
                            Text("\(Int(maxClips)) clips")
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }

                        Slider(value: $maxClips, in: 5...50, step: 1) {
                            Text("Menu Bar Items")
                        } minimumValueLabel: {
                            Text("5")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } maximumValueLabel: {
                            Text("50")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .onChange(of: maxClips) { newValue in
                            UserDefaults.standard.set(Int(newValue), forKey: "menuBarClipCount")
                            appState.loadClips()
                        }

                        Text("Number of recent clips to display in the menu bar.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Size Limits Section
                PreferenceSection(title: "Size Limits", icon: "ruler") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Maximum text size:")
                            Spacer()
                            Text("\(Int(maxClipSize)) KB")
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }

                        Slider(value: $maxClipSize, in: 10...1000, step: 10) {
                            Text("Max Text Size")
                        } minimumValueLabel: {
                            Text("10")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } maximumValueLabel: {
                            Text("1 MB")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("Text clips larger than this will be skipped.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Maximum image size:")
                            Spacer()
                            Text("\(formatImageSize(Int(maxImageSize))) KB")
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }

                        Slider(value: $maxImageSize, in: 100...10240, step: 256) {
                            Text("Max Image Size")
                        } minimumValueLabel: {
                            Text("100")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } maximumValueLabel: {
                            Text("10 MB")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("Images larger than this will be skipped.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(24)
        }
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
            VStack(alignment: .leading, spacing: 24) {
                // Menu Display Section
                PreferenceSection(title: "Menu Display", icon: "list.bullet") {
                    Toggle("Show content type icons", isOn: $showTypeIcons)

                    Text("Display icons indicating text, image, or RTF content type.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()
                        .padding(.vertical, 8)

                    Toggle("Compact mode", isOn: $compactMode)

                    Text("Reduce spacing between menu items for a denser layout.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Preview Section
                PreferenceSection(title: "Text Preview", icon: "text.alignleft") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Preview length:")
                            Spacer()
                            Text("\(Int(previewLength)) characters")
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }

                        Slider(value: $previewLength, in: 50...300, step: 25) {
                            Text("Preview Length")
                        } minimumValueLabel: {
                            Text("50")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } maximumValueLabel: {
                            Text("300")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("Maximum characters to display in menu item previews.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Info Section
                PreferenceSection(title: "About", icon: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The menu bar displays clipboard history grouped by date.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("• Today's clips appear first")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("• Pinned items always stay at the top")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("• Right-click any item for more options")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(24)
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
    @State private var showingFinalConfirmation = false
    @State private var showingSuccessMessage = false
    @State private var successMessage = ""
    @State private var showingExportPanel = false
    @State private var showingImportPanel = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Database Statistics Section
                PreferenceSection(title: "Database", icon: "cylinder") {
                    VStack(alignment: .leading, spacing: 12) {
                        StatRow(label: "Total clips", value: "\(totalClips)")
                        StatRow(label: "Text clips", value: "\(textCount)")
                        StatRow(label: "Image clips", value: "\(imageCount)")
                        StatRow(label: "Pinned clips", value: "\(pinnedCount)")
                        StatRow(label: "Database size", value: databaseSize)

                        Divider()
                            .padding(.vertical, 4)

                        HStack {
                            Text("Location:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("~/.clipboard_history.db")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fontDesign(.monospaced)
                        }

                        Button("Reveal in Finder") {
                            revealDatabaseInFinder()
                        }
                        .buttonStyle(.link)
                    }
                }

                Divider()

                // Backup & Restore Section
                PreferenceSection(title: "Backup & Restore", icon: "arrow.triangle.2.circlepath") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                showingExportPanel = true
                            } label: {
                                Label("Export Settings", systemImage: "square.and.arrow.up")
                            }
                            .frame(maxWidth: .infinity)

                            Button {
                                showingImportPanel = true
                            } label: {
                                Label("Import Settings", systemImage: "square.and.arrow.down")
                            }
                            .frame(maxWidth: .infinity)
                        }

                        Text("Export your preferences to back them up or transfer to another Mac.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Clear History Section
                PreferenceSection(title: "Clear History", icon: "trash.circle") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                showingClear24Confirmation = true
                            } label: {
                                Label("Clear Last 24 Hours", systemImage: "clock")
                            }
                            .frame(maxWidth: .infinity)

                            Button {
                                showingClearAllConfirmation = true
                            } label: {
                                Label("Clear All History", systemImage: "trash")
                            }
                            .frame(maxWidth: .infinity)
                        }

                        Text("Pinned items will not be deleted.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Security Section
                PreferenceSection(title: "Security Status", icon: "lock.shield") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                            Text("AES-256-GCM encryption enabled")
                                .font(.subheadline)
                        }

                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                            Text("Encryption key secured in Keychain")
                                .font(.subheadline)
                        }

                        Text("All clipboard data is encrypted at rest using military-grade encryption.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(24)
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
            Text("This will permanently delete all clips from the last 24 hours (except pinned clips). This cannot be undone.")
        }
        .alert("Clear All History?", isPresented: $showingClearAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                showingFinalConfirmation = true
            }
        } message: {
            Text("This will permanently delete ALL clipboard history (except pinned clips). This cannot be undone.\n\nAre you absolutely sure?")
        }
        .alert("Final Confirmation", isPresented: $showingFinalConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Yes, Delete All", role: .destructive) {
                clearAllHistory()
            }
        } message: {
            Text("Really delete all clipboard history? This action is permanent.")
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
            appState.loadClips()
            loadStats()

            successMessage = "Removed \(deleted) clip\(deleted == 1 ? "" : "s") from the last 24 hours."
            showingSuccessMessage = true
        }
    }

    private func clearAllHistory() {
        Task {
            let deleted = await appState.database.clearAllHistory(keepPinned: true)
            appState.loadClips()
            loadStats()

            let clipWord = deleted == 1 ? "clip" : "clips"
            successMessage = "Removed \(deleted) \(clipWord). Pinned clips were preserved."
            showingSuccessMessage = true
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
        // Placeholder for settings import logic
        return true
    }
}

// MARK: - Helper Views

struct PreferenceSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.primary)

            content
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.secondary)
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
