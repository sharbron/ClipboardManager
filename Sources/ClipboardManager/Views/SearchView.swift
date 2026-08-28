import SwiftUI

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var caseSensitive = false
    @State private var filterType: FilterType = .all
    @State private var filterPinned: FilterPinned = .all
    @State private var sortOrder: SortOrder = .newest
    @State private var selectedClip: ClipboardEntry?
    @State private var searchResults: [ClipboardEntry] = []
    @State private var eventMonitor: Any?
    @State private var searchTask: Task<Void, Never>?
    @State private var hostWindow: NSWindow?
    @FocusState private var isSearchFocused: Bool

    enum FilterType: String, CaseIterable {
        case all = "All"
        case text = "Text"
        case images = "Images"
    }

    enum FilterPinned: String, CaseIterable {
        case all = "All Clips"
        case pinned = "Pinned Only"
        case unpinned = "Unpinned Only"
    }

    enum SortOrder: String, CaseIterable {
        case newest = "Newest First"
        case oldest = "Oldest First"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field with better styling
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                TextField("Search clipboard history...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        isSearchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Filter controls with better spacing
            HStack(spacing: 12) {
                Toggle("Case sensitive", isOn: $caseSensitive)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)

                HStack(spacing: 4) {
                    Text("Type:")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    Picker("", selection: $filterType) {
                        ForEach(FilterType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)

                HStack(spacing: 4) {
                    Text("Show:")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    Picker("", selection: $filterPinned) {
                        ForEach(FilterPinned.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 4)

                HStack(spacing: 4) {
                    Text("Sort:")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    Picker("", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Main content with split view
            GeometryReader { _ in
                HSplitView {
                    // Left pane - Results list
                    VStack(spacing: 0) {
                        if searchResults.isEmpty {
                            VStack {
                                Spacer()
                                Image(systemName: searchText.isEmpty ? "clipboard" : "magnifyingglass")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .padding(.bottom, 8)
                                Text(searchText.isEmpty ? "No clips in history" : "No results found")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 13))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List(searchResults, id: \.id, selection: $selectedClip) { clip in
                                ClipListItemView(clip: clip)
                                    .tag(clip)
                            }
                            .listStyle(.sidebar)

                            // Results count footer
                            HStack(spacing: 4) {
                                Text("Found \(searchResults.count)")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 11))
                                Text(searchResults.count == 1 ? "result" : "results")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 11))
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .windowBackgroundColor))
                        }
                    }
                    .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)

                    // Right pane - Preview
                    if let clip = selectedClip {
                        ClipPreviewView(clip: clip)
                            .frame(minWidth: 400)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("Select a clip to view details")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            Divider()

            // Bottom button
            HStack {
                Spacer()
                Button("Close") {
                    hostWindow?.close()
                }
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
            }
            .padding(8)
        }
        .frame(width: 900, height: 600)
        .background(WindowAccessor { window in
            // Only assign on a real change - `updateNSView` fires on every render, and
            // writing @State unconditionally from there risks an update loop.
            if hostWindow !== window { hostWindow = window }
        })
        .onChange(of: searchText) { _ in performSearch() }
        .onChange(of: caseSensitive) { _ in performSearch() }
        .onChange(of: filterType) { _ in performSearch() }
        .onChange(of: filterPinned) { _ in performSearch() }
        .onChange(of: sortOrder) { _ in performSearch() }
        .onChange(of: appState.clips) { _ in performSearch() }
        .onAppear {
            performSearch()
            isSearchFocused = true
            setupKeyboardShortcuts()
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil

            // Clean up event monitor to prevent memory leak
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }

    /// Debounced so a burst of keystrokes triggers one query instead of one per character -
    /// each query decrypts the whole history, so the old undebounced version also let several
    /// searches run concurrently and race to assign `searchResults`, letting a stale query's
    /// results land last.
    private func performSearch() {
        searchTask?.cancel()

        let query = searchText
        searchTask = Task {
            if !query.isEmpty {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
            }

            var results: [ClipboardEntry]

            if !query.isEmpty {
                results = await appState.database.searchClips(query: query)
            } else {
                // Use a reasonable limit (1000) instead of 10,000 for better performance
                results = await appState.database.getRecentClips(limit: 1000)
            }

            guard !Task.isCancelled else { return }

            // Apply filters
            results = results.filter { clip in
                // The query itself matches case-insensitively, so narrow it here when asked
                if caseSensitive && !query.isEmpty {
                    let contentMatches = clip.content.contains(query)
                    let extractedMatches = clip.extractedText?.contains(query) ?? false
                    if !contentMatches && !extractedMatches { return false }
                }

                // Type filter - text includes both "text" and "rtf"
                if filterType == .text && clip.contentType == "image" { return false }
                if filterType == .images && clip.contentType != "image" { return false }

                // Pin filter
                if filterPinned == .pinned && !clip.isPinned { return false }
                if filterPinned == .unpinned && clip.isPinned { return false }

                return true
            }

            // Sort, keeping pinned clips above the rest as everywhere else in the app
            results.sort { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return sortOrder == .oldest
                    ? lhs.timestamp < rhs.timestamp
                    : lhs.timestamp > rhs.timestamp
            }

            searchResults = results

            // Clear selection if selected clip no longer exists in results
            if let selected = selectedClip, !results.contains(where: { $0.id == selected.id }) {
                selectedClip = nil
            }

            // Select first result if available and no current selection
            if selectedClip == nil, let first = results.first {
                selectedClip = first
            }
        }
    }

    private func navigateUp() {
        guard !searchResults.isEmpty else { return }

        if let currentIndex = searchResults.firstIndex(where: { $0.id == selectedClip?.id }) {
            if currentIndex > 0 {
                selectedClip = searchResults[currentIndex - 1]
            }
        }
    }

    private func navigateDown() {
        guard !searchResults.isEmpty else { return }

        if let currentIndex = searchResults.firstIndex(where: { $0.id == selectedClip?.id }) {
            if currentIndex < searchResults.count - 1 {
                selectedClip = searchResults[currentIndex + 1]
            }
        } else {
            selectedClip = searchResults.first
        }
    }

    private func setupKeyboardShortcuts() {
        // Remove existing monitor if any to prevent memory leak
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Add local event monitor for keyboard navigation
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Only handle keys aimed at the search window. Without this the monitor swallows
            // bare arrows and Return in every window of the app - including text fields in
            // Preferences and the snippet editor - for as long as search stays open.
            guard let window = hostWindow, event.window === window else { return event }

            // Up arrow key
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 126 && modifiers.isEmpty {
                navigateUp()
                return nil
            }
            // Down arrow key
            if event.keyCode == 125 && modifiers.isEmpty {
                navigateDown()
                return nil
            }
            // Return key - copy selected and close
            if event.keyCode == 36 && modifiers.isEmpty {
                if let selected = selectedClip {
                    Task {
                        await appState.copyToClipboard(clip: selected)
                        await MainActor.run { hostWindow?.close() }
                    }
                }
                return nil
            }
            return event
        }
    }
}

struct ClipListItemView: View {
    let clip: ClipboardEntry
    @EnvironmentObject var appState: AppState
    @AppStorage(Preferences.showTypeIcons) private var showTypeIcons: Bool = true
    @AppStorage(Preferences.compactMode) private var compactMode: Bool = false
    @AppStorage(Preferences.previewLength) private var previewLength: Double = 60

    // Cached date formatters for better performance
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var body: some View {
        HStack(spacing: compactMode ? 6 : 10) {
            if showTypeIcons {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .frame(width: 18, height: 18)
                    .font(.system(size: 14))
            }

            Text(previewText)
                .lineLimit(1)
                .font(.system(size: 12))

            Spacer()

            if clip.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 10))
            }

            Text(formatTimestamp(clip.timestamp))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, compactMode ? 1 : 4)
        .contextMenu {
            Button {
                Task {
                    await appState.copyToClipboard(clip: clip)
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button {
                appState.togglePin(clipId: clip.id)
            } label: {
                Label(clip.isPinned ? "Unpin" : "Pin", systemImage: clip.isPinned ? "pin.slash" : "pin")
            }

            Divider()

            Button(role: .destructive) {
                appState.deleteClip(clipId: clip.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday " + Self.timeFormatter.string(from: date)
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            return Self.weekdayFormatter.string(from: date)
        } else {
            return Self.monthFormatter.string(from: date)
        }
    }

    private var iconName: String {
        if clip.contentType == "image" { return "photo" }
        let content = clip.content.lowercased()
        if content.starts(with: "http") { return "link" }
        if content.contains("@") && content.contains(".") && !content.contains(" ") { return "envelope" }
        if content.split(separator: "\n").count > 3 { return "doc.text" }
        if Double(content.trimmingCharacters(in: .whitespacesAndNewlines)) != nil { return "number" }
        return "text.quote"
    }

    private var iconColor: Color {
        if clip.contentType == "image" { return .blue }
        let content = clip.content.lowercased()
        if content.starts(with: "http") { return .purple }
        if content.contains("@") && content.contains(".") { return .green }
        if content.split(separator: "\n").count > 3 { return .orange }
        if Double(content.trimmingCharacters(in: .whitespacesAndNewlines)) != nil { return .teal }
        return .gray
    }

    private var previewText: String {
        // The result list is narrower than the menu, so trim a little tighter
        clip.preview(maxLength: max(10, Int(previewLength) - 5))
    }
}

struct ClipPreviewView: View {
    let clip: ClipboardEntry
    @EnvironmentObject var appState: AppState
    @State private var imageData: Data?
    @State private var showingDeleteConfirmation = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Content preview (scrollable)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if clip.contentType == "image" {
                        if let imageData = imageData, let nsImage = NSImage(data: imageData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    } else {
                        Text(clip.content)
                            .textSelection(.enabled)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Details section - more compact
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Details")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 4) {
                    DetailRow(label: "Date:", value: formatDate(clip.timestamp))
                    DetailRow(label: "Category:", value: detectCategory(for: clip))
                    DetailRow(label: "Size:", value: formatSize())

                    if let source = clip.sourceApp {
                        DetailRow(label: "Source:", value: source)
                    }

                    if clip.contentType == "image" {
                        DetailRow(label: "Dimensions:", value: clip.content)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Actions section - better button layout
            HStack(spacing: 8) {
                Button {
                    Task {
                        await appState.copyToClipboard(clip: clip)
                    }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    appState.togglePin(clipId: clip.id)
                } label: {
                    Label(clip.isPinned ? "Unpin" : "Pin", systemImage: clip.isPinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .task(id: clip.id) {
            if clip.contentType == "image" {
                imageData = await appState.database.getImageData(for: clip.id)
            } else {
                imageData = nil
            }
        }
        .alert("Delete Clip?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                appState.deleteClip(clipId: clip.id)
            }
        } message: {
            Text("Are you sure you want to delete this clip? This action cannot be undone.")
        }
    }

    private func formatDate(_ date: Date) -> String {
        return Self.dateFormatter.string(from: date)
    }

    private func detectCategory(for clip: ClipboardEntry) -> String {
        if clip.contentType == "image" {
            return "📷 Image"
        }
        let content = clip.content.lowercased()
        if content.starts(with: "http") {
            return "🔗 URL"
        } else if content.contains("@") && content.contains(".") && !content.contains(" ") {
            return "✉️ Email"
        } else if content.split(separator: "\n").count > 3 {
            return "📄 Document"
        } else if Double(content.trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
            return "🔢 Number"
        } else if content.count < 50 {
            return "💬 Short Text"
        } else {
            return "📝 Text"
        }
    }

    private func formatSize() -> String {
        if clip.contentType == "image" {
            if let imageData = imageData {
                let bytes = imageData.count
                if bytes < 1024 {
                    return "\(bytes) bytes"
                } else if bytes < 1024 * 1024 {
                    return String(format: "%.1f KB", Double(bytes) / 1024.0)
                } else {
                    return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
                }
            }
            return "Unknown"
        } else {
            let bytes = clip.content.utf8.count
            if bytes < 1024 {
                return "\(bytes) bytes"
            } else {
                return String(format: "%.1f KB", Double(bytes) / 1024.0)
            }
        }
    }
}

// MARK: - Helper Views

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.primary)
        }
    }
}

/// Bridges to the hosting `NSWindow` so the view can scope key handling and close itself
/// without guessing at `NSApp.keyWindow`.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
