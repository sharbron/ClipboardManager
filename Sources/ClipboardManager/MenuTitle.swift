import AppKit

/// Fits menu item titles to a fixed pixel width.
///
/// A `.menu`-style `MenuBarExtra` turns each row into a native `NSMenuItem`, which ignores
/// SwiftUI frames and truncation modes and sizes the whole menu to its widest title. The only
/// reliable way to bound the menu's width is to shorten the title string itself.
enum MenuTitle {
    /// Widest a clip title may render in the menu bar dropdown.
    static let maximumWidth: CGFloat = 320

    private static let ellipsis = "…"

    static func fitted(
        _ text: String,
        maxWidth: CGFloat = maximumWidth,
        font: NSFont = .menuFont(ofSize: 0)
    ) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        func width(_ string: String) -> CGFloat {
            (string as NSString).size(withAttributes: attributes).width
        }

        if width(text) <= maxWidth { return text }

        // Binary search for the longest prefix that still fits alongside the ellipsis.
        let characters = Array(text)
        var low = 0
        var high = characters.count
        while low < high {
            let mid = (low + high + 1) / 2
            if width(String(characters[..<mid]) + ellipsis) <= maxWidth {
                low = mid
            } else {
                high = mid - 1
            }
        }

        var prefix = String(characters[..<low])
        // The preview may already end in its own "..." marker; don't stack a second one on it.
        while prefix.hasSuffix(".") || prefix.hasSuffix(" ") {
            prefix.removeLast()
        }
        return prefix + ellipsis
    }
}
