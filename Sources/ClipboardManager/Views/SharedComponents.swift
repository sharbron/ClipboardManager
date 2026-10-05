import SwiftUI

/// A single keyboard shortcut and what it does.
struct KeyboardShortcutItem: Identifiable {
    let id = UUID()
    let keys: String
    let description: String

    init(_ keys: String, _ description: String) {
        self.keys = keys
        self.description = description
    }
}

/// A keycap-styled label for a shortcut.
struct KeyCap: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .fixedSize()
    }
}

/// A list of shortcuts whose descriptions line up in a column.
///
/// A plain HStack per row left the descriptions ragged, because each keycap is a different
/// width. A Grid sizes the keycap column to the widest cap and aligns the rest against it.
struct ShortcutList: View {
    let shortcuts: [KeyboardShortcutItem]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(shortcuts) { shortcut in
                GridRow {
                    KeyCap(keys: shortcut.keys)
                        .gridColumnAlignment(.trailing)

                    Text(shortcut.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Shortcut rows styled for a settings `Form`: the action on the left, the keycap trailing —
/// the layout macOS itself uses for shortcut lists.
struct ShortcutFormRows: View {
    let shortcuts: [KeyboardShortcutItem]

    var body: some View {
        ForEach(shortcuts) { shortcut in
            LabeledContent {
                KeyCap(keys: shortcut.keys)
            } label: {
                Text(shortcut.description)
            }
        }
    }
}

/// Shared by About and Preferences so shortcut labels stay consistent.
enum ClipboardShortcuts {
    static let global = [
        KeyboardShortcutItem("⌘⇧ Space", "Open clipboard history")
    ]
    static let menu = [
        KeyboardShortcutItem("⌘ 1–9", "Copy a recent clip"),
        KeyboardShortcutItem("⌘ F", "Search clipboard history"),
        KeyboardShortcutItem("⌘ ,", "Open preferences")
    ]
    static let search = [
        KeyboardShortcutItem("↑ ↓", "Navigate search results"),
        KeyboardShortcutItem("Return", "Copy selected clip and close"),
        KeyboardShortcutItem("Esc", "Close search")
    ]
    static let essentials = global + [menu[0]] + search
}

/// Explanatory text below a settings group, matching Window Switcher.
struct SettingsFooter: View {
    let text: String

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
