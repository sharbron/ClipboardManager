import XCTest
import AppKit
@testable import ClipboardManager

/// Tests which representation gets captured when a pasteboard offers several
final class ClipboardCaptureTests: XCTestCase {
    var pasteboard: NSPasteboard!
    let limits = CaptureLimits(maxTextBytes: 100 * 1024, maxImageBytes: 10 * 1024 * 1024)

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard.withUniqueName()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func tiffData(width: Int = 4, height: Int = 4) throws -> Data {
        try blankTIFF(width: width, height: height)
    }

    private func rtfData(_ text: String, padding: Int = 0) throws -> Data {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]
        )
        var data = try XCTUnwrap(attributed.rtf(from: NSRange(location: 0, length: attributed.length)))
        if padding > 0 {
            // A formatting-heavy payload: RTF comment group ignored by the reader.
            let comment = "{\\*\\generator " + String(repeating: "x", count: padding) + ";}"
            let closing = try XCTUnwrap(data.lastIndex(of: UInt8(ascii: "}")))
            data.insert(contentsOf: Data(comment.utf8), at: closing)
        }
        return data
    }

    private func decide() -> CaptureDecision {
        ClipboardCapture.decide(for: pasteboard, limits: limits)
    }

    // MARK: - Priority

    func testDecide_FinderFileCopyWithIconTIFF_CapturesFilePath() throws {
        pasteboard.clearContents()
        let url = URL(fileURLWithPath: "/Users/test/Documents/report.pdf")
        pasteboard.writeObjects([url as NSURL])
        pasteboard.addTypes([.tiff], owner: nil)
        pasteboard.setData(try tiffData(width: 128, height: 128), forType: .tiff)

        XCTAssertEqual(decide(), .text("/Users/test/Documents/report.pdf"))
    }

    func testDecide_RichTextWithPictureRepresentation_CapturesRichText() throws {
        let rtf = try rtfData("Quarterly totals")
        pasteboard.declareTypes([.rtf, .string, .tiff], owner: nil)
        pasteboard.setData(rtf, forType: .rtf)
        pasteboard.setString("Quarterly totals", forType: .string)
        pasteboard.setData(try tiffData(), forType: .tiff)

        XCTAssertEqual(decide(), .richText(plainText: "Quarterly totals", rtf: rtf))
    }

    func testDecide_PNGOnly_CapturesImage() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try tiffData(width: 8, height: 6)))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        pasteboard.declareTypes([.png], owner: nil)
        pasteboard.setData(png, forType: .png)

        XCTAssertEqual(decide(), .image(description: "[Image: 8x6]", png: png))
    }

    func testDecide_TIFFOnly_CapturesImageAsPNG() throws {
        pasteboard.declareTypes([.tiff], owner: nil)
        pasteboard.setData(try tiffData(width: 5, height: 3), forType: .tiff)

        guard case let .image(description, png) = decide() else {
            return XCTFail("Expected an image capture")
        }
        XCTAssertEqual(description, "[Image: 5x3]")
        XCTAssertEqual(png.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]), "Stored bytes should be PNG")
    }

    func testDecide_PlainText_CapturesText() {
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("hello", forType: .string)

        XCTAssertEqual(decide(), .text("hello"))
    }

    func testDecide_EmptyPasteboard_Ignores() {
        pasteboard.clearContents()
        XCTAssertEqual(decide(), .ignore)
    }

    // MARK: - Privacy markers

    func testDecide_ConcealedType_Ignores() {
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        pasteboard.declareTypes([.string, concealed], owner: nil)
        pasteboard.setString("hunter2", forType: .string)
        pasteboard.setData(Data(), forType: concealed)

        XCTAssertEqual(decide(), .ignore)
    }

    func testDecide_TransientType_Ignores() {
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        pasteboard.declareTypes([.string, transient], owner: nil)
        pasteboard.setString("temporary", forType: .string)
        pasteboard.setData(Data(), forType: transient)

        XCTAssertEqual(decide(), .ignore)
    }

    // MARK: - Size limits

    func testDecide_OversizedRTFWithSmallText_FallsBackToPlainText() throws {
        let rtf = try rtfData("Short text", padding: 200 * 1024)
        XCTAssertGreaterThan(rtf.count, limits.maxTextBytes)
        pasteboard.declareTypes([.rtf, .string], owner: nil)
        pasteboard.setData(rtf, forType: .rtf)
        pasteboard.setString("Short text", forType: .string)

        XCTAssertEqual(decide(), .text("Short text"))
    }

    func testDecide_OversizedText_ReportsTooLarge() {
        let text = String(repeating: "a", count: limits.maxTextBytes + 1)
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)

        XCTAssertEqual(decide(), .tooLarge(kind: "Text", size: text.utf8.count, limit: limits.maxTextBytes))
    }

    func testDecide_OversizedImage_ReportsTooLarge() throws {
        pasteboard.declareTypes([.tiff], owner: nil)
        pasteboard.setData(try tiffData(), forType: .tiff)
        let tinyLimits = CaptureLimits(maxTextBytes: limits.maxTextBytes, maxImageBytes: 1)

        guard case .tooLarge(kind: "Image", size: _, limit: 1) =
                ClipboardCapture.decide(for: pasteboard, limits: tinyLimits) else {
            return XCTFail("Expected the image to be rejected as too large")
        }
    }
}

/// A blank bitmap of the given pixel size, as TIFF - what most apps put on the pasteboard.
func blankTIFF(width: Int, height: Int) throws -> Data {
    let rep = try XCTUnwrap(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    return try XCTUnwrap(rep.tiffRepresentation)
}
