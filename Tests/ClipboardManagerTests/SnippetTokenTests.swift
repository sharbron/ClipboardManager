import XCTest
@testable import ClipboardManager

/// The stock `;date` and `;time` snippets used to bake `Date()` into their stored content
/// when the defaults were created, so "today's date" meant the install date forever. They now
/// store tokens that resolve at expansion time.
final class SnippetTokenTests: XCTestCase {
    private func makeSnippet(content: String) -> Snippet {
        Snippet(
            id: 1,
            trigger: ";date",
            content: content,
            description: "Today's date",
            createdAt: Date(),
            usageCount: 0
        )
    }

    func testDateTokenResolvesToCurrentDate() {
        let expected = Date().formatted(date: .long, time: .omitted)
        XCTAssertEqual(makeSnippet(content: Snippet.dateToken).expandedContent, expected)
    }

    func testTimeTokenResolvesToCurrentTime() {
        let expected = Date().formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(makeSnippet(content: Snippet.timeToken).expandedContent, expected)
    }

    func testDateTokenReflectsTheDayItIsExpanded() throws {
        let christmas = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(from: DateComponents(year: 2030, month: 12, day: 25))
        )
        let resolved = Snippet.resolvingTokens(in: Snippet.dateToken, now: christmas)
        XCTAssertEqual(resolved, christmas.formatted(date: .long, time: .omitted))
        XCTAssertFalse(resolved.contains("{{"), "Token should be fully replaced")
    }

    func testTokensResolveInsideSurroundingText() {
        let resolved = Snippet.resolvingTokens(in: "Sent on \(Snippet.dateToken).")
        XCTAssertTrue(resolved.hasPrefix("Sent on "))
        XCTAssertTrue(resolved.hasSuffix("."))
        XCTAssertFalse(resolved.contains(Snippet.dateToken))
    }

    func testContentWithoutTokensIsUnchanged() {
        let content = "Best regards,\nYour Name"
        XCTAssertEqual(makeSnippet(content: content).expandedContent, content)
    }
}
