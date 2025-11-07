import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pinned clips section
            if appState.clips.contains(where: { $0.isPinned }) {
                Section("Pinned") {
                    ForEach(pinnedClips) { clip in
                        ClipMenuItemView(clip: clip)
                    }
                }
                Divider()
            }

            // Recent clips grouped by date
            ForEach(sortedGroupedClips, id: \.label) { group in
                Section(group.label) {
                    ForEach(group.clips) { clip in
                        ClipMenuItemView(clip: clip)
                    }
                }
            }

            if appState.clips.isEmpty {
                Text("No clipboard history")
                    .foregroundColor(.secondary)
            }

            Divider()

            // Actions
            Button("Search...") {
                WindowManager.shared.openSearch(appState: appState)
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Preferences...") {
                WindowManager.shared.openPreferences(appState: appState)
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()

            Button("About") {
                WindowManager.shared.openAbout(appState: appState)
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }

    private var pinnedClips: [ClipboardEntry] {
        appState.clips.filter { $0.isPinned }
    }

    private var sortedGroupedClips: [(label: String, clips: [ClipboardEntry], sortKey: Date)] {
        let unpinnedClips = appState.clips.filter { !$0.isPinned }

        // Group clips by date category label
        let grouped = Dictionary(grouping: unpinnedClips) { clip in
            formatDateGroup(clip.timestamp)
        }

        // Convert to array of tuples with sort key based on most recent clip in group
        let groups = grouped.map { label, clips in
            let mostRecentDate = clips.map { $0.timestamp }.max() ?? Date.distantPast
            return (label: label, clips: clips, sortKey: mostRecentDate)
        }

        // Sort by date (newest first)
        return groups.sorted { $0.sortKey > $1.sortKey }
    }

    private func formatDateGroup(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            return "This Week"
        } else {
            return Self.dateFormatter.string(from: date)
        }
    }
}

struct ClipMenuItemView: View {
    let clip: ClipboardEntry
    @EnvironmentObject var appState: AppState

    var body: some View {
        Menu {
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
        } label: {
            HStack(spacing: 8) {
                // Icon
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .frame(width: 16)

                // Preview text
                Text(previewText)
                    .lineLimit(1)

                Spacer()

                // Pin indicator
                if clip.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 10))
                }
            }
        } primaryAction: {
            Task {
                await appState.copyToClipboard(clip: clip)
            }
        }
    }

    private var iconName: String {
        if clip.contentType == "image" {
            return "photo"
        }
        let content = clip.content.lowercased()
        if content.starts(with: "http://") || content.starts(with: "https://") {
            return "link"
        } else if content.contains("@") && content.contains(".") && !content.contains(" ") {
            return "envelope"
        } else if content.split(separator: "\n").count > 3 {
            return "doc.text"
        } else if Double(content.trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
            return "number"
        } else {
            return "text.quote"
        }
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
        clip.previewText
    }
}

// Make ClipboardEntry Identifiable for ForEach
extension ClipboardEntry: Identifiable {
    var idString: String { String(id) }
}
