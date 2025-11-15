import SwiftUI

struct SnippetsView: View {
    @ObservedObject var appState: AppState
    @State private var showingAddSheet = false
    @State private var searchText = ""
    @State private var editingSnippet: Snippet?
    @State private var showingImportExport = false

    var filteredSnippets: [Snippet] {
        if searchText.isEmpty {
            return appState.snippets
        }
        return appState.snippets.filter { snippet in
            snippet.trigger.localizedCaseInsensitiveContains(searchText) ||
            snippet.description.localizedCaseInsensitiveContains(searchText) ||
            snippet.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Snippets")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                // Import/Export button
                Button(action: { showingImportExport = true }) {
                    Image(systemName: "square.and.arrow.up.on.square")
                }
                .help("Import/Export Snippets")

                // Add button
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .help("Add Snippet")
            }
            .padding()

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search snippets...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom)

            Divider()

            // Snippets list
            if filteredSnippets.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text(searchText.isEmpty ? "No Snippets" : "No Matching Snippets")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    if searchText.isEmpty {
                        Text("Create snippets to quickly insert frequently used text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Create Default Snippets") {
                            appState.createDefaultSnippets()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredSnippets) { snippet in
                            SnippetRow(snippet: snippet, appState: appState, editingSnippet: $editingSnippet)
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Footer with stats
            HStack {
                Text("\(appState.snippets.count) snippet\(appState.snippets.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Tip: Type a trigger (e.g., ';email') to expand")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 700, height: 500)
        .sheet(isPresented: $showingAddSheet) {
            AddSnippetView(appState: appState, isPresented: $showingAddSheet)
        }
        .sheet(item: $editingSnippet) { snippet in
            EditSnippetView(snippet: snippet, appState: appState, isPresented: .constant(true))
        }
        .sheet(isPresented: $showingImportExport) {
            ImportExportView(appState: appState, isPresented: $showingImportExport)
        }
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    let appState: AppState
    @Binding var editingSnippet: Snippet?
    @State private var showingDeleteAlert = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Trigger badge
            Text(snippet.trigger)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.2))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                // Description
                Text(snippet.description)
                    .font(.headline)

                // Preview of content
                Text(snippet.previewContent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                // Usage count
                if snippet.usageCount > 0 {
                    Text("Used \(snippet.usageCount) time\(snippet.usageCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                // Expand button
                Button(action: {
                    Task {
                        await appState.expandSnippet(snippet)
                    }
                }) {
                    Image(systemName: "arrow.right.square")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Expand to clipboard")

                // Edit button
                Button(action: { editingSnippet = snippet }) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Edit")

                // Delete button
                Button(action: { showingDeleteAlert = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .alert("Delete Snippet?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                appState.deleteSnippet(id: snippet.id)
            }
        } message: {
            Text("Are you sure you want to delete '\(snippet.trigger)'?")
        }
    }
}

struct AddSnippetView: View {
    let appState: AppState
    @Binding var isPresented: Bool

    @State private var trigger = ""
    @State private var description = ""
    @State private var content = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Snippet")
                .font(.title2)
                .fontWeight(.bold)

            Form {
                TextField("Trigger (e.g., ;email)", text: $trigger)
                    .font(.system(.body, design: .monospaced))

                TextField("Description", text: $description)

                VStack(alignment: .leading) {
                    Text("Content")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 150)
                        .border(Color.secondary.opacity(0.3))
                }
            }
            .padding()

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    saveSnippet()
                }
                .keyboardShortcut(.return)
                .disabled(trigger.isEmpty || description.isEmpty || content.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    @MainActor
    private func saveSnippet() {
        // Validate trigger
        guard !trigger.isEmpty, !description.isEmpty, !content.isEmpty else {
            errorMessage = "All fields are required"
            showingError = true
            return
        }

        appState.saveSnippet(trigger: trigger, content: content, description: description)
        isPresented = false
    }
}

struct EditSnippetView: View {
    let snippet: Snippet
    let appState: AppState
    @Binding var isPresented: Bool

    @State private var trigger: String
    @State private var description: String
    @State private var content: String

    init(snippet: Snippet, appState: AppState, isPresented: Binding<Bool>) {
        self.snippet = snippet
        self.appState = appState
        self._isPresented = isPresented
        self._trigger = State(initialValue: snippet.trigger)
        self._description = State(initialValue: snippet.description)
        self._content = State(initialValue: snippet.content)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Snippet")
                .font(.title2)
                .fontWeight(.bold)

            Form {
                TextField("Trigger", text: $trigger)
                    .font(.system(.body, design: .monospaced))
                    .disabled(true)  // Don't allow changing trigger

                TextField("Description", text: $description)

                VStack(alignment: .leading) {
                    Text("Content")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 150)
                        .border(Color.secondary.opacity(0.3))
                }
            }
            .padding()

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    appState.saveSnippet(trigger: trigger, content: content, description: description)
                    isPresented = false
                }
                .keyboardShortcut(.return)
                .disabled(description.isEmpty || content.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }
}

struct ImportExportView: View {
    let appState: AppState
    @Binding var isPresented: Bool
    @State private var showingExportSuccess = false
    @State private var showingImportPicker = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Import/Export Snippets")
                .font(.title2)
                .fontWeight(.bold)

            VStack(spacing: 12) {
                Button(action: exportSnippets) {
                    Label("Export Snippets", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: { showingImportPicker = true }) {
                    Label("Import Snippets", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Text("Export your snippets to share or backup.\nImport snippets from a JSON file.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Done") {
                isPresented = false
            }
            .keyboardShortcut(.escape)
        }
        .padding()
        .frame(width: 400, height: 250)
        .alert("Export Successful", isPresented: $showingExportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Snippets exported to Downloads folder")
        }
        .fileImporter(isPresented: $showingImportPicker, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
    }

    private func exportSnippets() {
        Task {
            let snippets = await appState.exportSnippets()

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            if let data = try? encoder.encode(snippets) {
                let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let fileURL = downloadsURL.appendingPathComponent("ClipboardManager-Snippets-\(Date().timeIntervalSince1970).json")

                try? data.write(to: fileURL)
                showingExportSuccess = true
            }
        }
    }

    @MainActor
    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            if let data = try? Data(contentsOf: url),
               let snippets = try? JSONDecoder().decode([ExportableSnippet].self, from: data) {
                appState.importSnippets(snippets, replaceExisting: false)
            }
        case .failure:
            break
        }
    }
}
