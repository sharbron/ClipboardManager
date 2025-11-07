import SwiftUI

struct AboutView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            // App Icon and Title
            HStack(spacing: 16) {
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 80, height: 80)
                        .cornerRadius(12)
                } else {
                    Image(systemName: "clipboard")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Clipboard Manager")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Version 2.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Built with SwiftUI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Description
            Text("A secure, native macOS clipboard history manager")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            // Features Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                FeatureCard(icon: "lock.shield.fill", text: "AES-256 Encryption", color: .green)
                FeatureCard(icon: "menubar.rectangle", text: "Menu Bar App", color: .blue)
                FeatureCard(icon: "magnifyingglass", text: "Fast Search", color: .purple)
                FeatureCard(icon: "photo", text: "Image Support", color: .orange)
            }
            .padding(.horizontal)

            Divider()
                .padding(.horizontal)

            // Author
            VStack(spacing: 6) {
                Text("Created by Steven Harbron")
                    .font(.subheadline)

                Button("steve.harbron@icloud.com") {
                    if let url = URL(string: "mailto:steve.harbron@icloud.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            Spacer()
        }
        .padding()
        .frame(width: 420, height: 440)
    }
}

struct FeatureCard: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)

            Text(text)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}
