import SwiftUI

struct AboutView: View {
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        if let build = info?["CFBundleVersion"] as? String, build != short {
            return "Version \(short) (\(build))"
        }
        return "Version \(short)"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            VStack(spacing: 5) {
                Text("Clipboard Manager")
                    .font(.system(size: 20, weight: .semibold))
                Text(versionString)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Text("Your clipboard, one shortcut away.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            Divider().padding(.vertical, 4)
            ShortcutList(shortcuts: ClipboardShortcuts.essentials)
            Text("⌘1–9 is available while the clipboard menu is open.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Divider().padding(.vertical, 4)
            Text("Created by Steven Harbron")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                if let url = URL(string: "https://github.com/sharbron/ClipboardManager") {
                    Link("GitHub", destination: url)
                }
                if let url = URL(string: "mailto:steve.harbron@icloud.com") {
                    Link("Contact", destination: url)
                }
            }
            .font(.system(size: 11))
        }
        .padding(28)
        .frame(width: 380)
    }
}
