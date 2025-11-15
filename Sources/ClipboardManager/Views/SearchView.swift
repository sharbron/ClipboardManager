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
                    NSApplication.shared.keyWindow?.close()
                }
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
            }
            .padding(8)
        }
        .frame(width: 900, height: 600)
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
            // Clean up event monitor to prevent memory leak
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }

    private func performSearch() {
        Task {
            var results: [ClipboardEntry]

            if !searchText.isEmpty {
                results = await appState.database.searchClipsWithFTS(query: searchText)
            } else {
                // Use a reasonable limit (1000) instead of 10,000 for better performance
                results = await appState.database.getRecentClips(limit: 1000)
            }

            // Apply filters
            results = results.filter { clip in
                // Type filter - text includes both "text" and "rtf"
                if filterType == .text && clip.contentType == "image" { return false }
                if filterType == .images && clip.contentType != "image" { return false }

                // Pin filter
                if filterPinned == .pinned && !clip.isPinned { return false }
                if filterPinned == .unpinned && clip.isPinned { return false }

                return true
            }

            // Sort
            if sortOrder == .oldest {
                results.sort { $0.timestamp < $1.timestamp }
            } else {
                results.sort { $0.timestamp > $1.timestamp }
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
            // Up arrow key
            if event.keyCode == 126 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                navigateUp()
                return nil
            }
            // Down arrow key
            if event.keyCode == 125 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                navigateDown()
                return nil
            }
            // Return key - copy selected and close
            if event.keyCode == 36 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                if let selected = selectedClip {
                    Task {
                        await appState.copyToClipboard(clip: selected)
                        await MainActor.run {
                            NSApplication.shared.keyWindow?.close()
                        }
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
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .frame(width: 18, height: 18)
                .font(.system(size: 14))

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
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                Task {
                    await appState.copyToClipboard(clip: clip)
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button {
                Task {
                    await appState.togglePin(clipId: clip.id)
                }
            } label: {
                Label(clip.isPinned ? "Unpin" : "Pin", systemImage: clip.isPinned ? "pin.slash" : "pin")
            }

            Divider()

            Button(role: .destructive) {
                Task {
                    await appState.deleteClip(clipId: clip.id)
                }
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
        // Use slightly shorter preview in search (45 chars vs 50 in menu)
        let preview = clip.previewText
        if preview.count > 45 {
            return String(preview.prefix(45)) + "..."
        }
        return preview
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
                    Task {
                        await appState.togglePin(clipId: clip.id)
                    }
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
                Task {
                    await appState.deleteClip(clipId: clip.id)
                }
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
