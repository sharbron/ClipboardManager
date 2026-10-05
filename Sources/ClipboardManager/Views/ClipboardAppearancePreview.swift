import SwiftUI

/// Uses sample content so changing appearance never exposes clipboard history in Settings.
struct ClipboardAppearancePreview: View {
    let previewLength: Int
    let showTypeIcons: Bool
    let compactMode: Bool

    private let samples = [
        ("text.quote", "Ideas for the weekend: visit the bookshop, pick up coffee, and take a walk by the river."),
        ("link", "https://www.example.com/notes"),
        ("photo", "Image (1280 × 720)")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clipboard Preview")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                ForEach(samples.indices, id: \.self) { index in
                    HStack(spacing: compactMode ? 6 : 10) {
                        if showTypeIcons {
                            Image(systemName: samples[index].0)
                                .foregroundStyle(index == 0 ? Color.secondary : Color.accentColor)
                                .frame(width: 18)
                        }
                        Text(preview(samples[index].1))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        KeyCap(keys: "⌘ \(index + 1)")
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, compactMode ? 3 : 7)
                }
            }
            .padding(.bottom, 6)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            }
            Text("Sample clips")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func preview(_ text: String) -> String {
        text.count > previewLength ? String(text.prefix(previewLength)) + "…" : text
    }
}
