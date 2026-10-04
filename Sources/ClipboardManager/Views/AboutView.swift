import SwiftUI

/// Standard macOS About panel: identity and credits only.
///
/// The keyboard shortcut reference that used to live here now sits in Preferences > General,
/// so it exists in exactly one place. The previous version also declared a 540pt-tall frame
/// inside a 440pt window, which centred the overflow and clipped both the title and the
/// author's email link.
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
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                appIcon
                    .frame(width: 72, height: 72)

                VStack(spacing: 3) {
                    Text("Clipboard Manager")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(versionString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("A secure, native macOS clipboard history manager.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 28)
            .padding(.horizontal, 32)

            Spacer(minLength: 24)

            VStack(spacing: 8) {
                Divider()

                VStack(spacing: 4) {
                    Text("Created by Steven Harbron")
                        .font(.callout)

                    Link("steve.harbron@icloud.com", destination: URL.authorEmail)
                        .font(.caption)
                }
                .padding(.top, 4)

                Text("Clipboard history is encrypted at rest with AES-256-GCM.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 360, height: 340)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSImage(named: "AppIcon") {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "clipboard")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.tint)
        }
    }
}

private extension URL {
    /// Safe because the literal is a valid mailto URL; the fallback keeps the view non-failable.
    static let authorEmail = URL(string: "mailto:steve.harbron@icloud.com") ?? URL(fileURLWithPath: "/")
}
