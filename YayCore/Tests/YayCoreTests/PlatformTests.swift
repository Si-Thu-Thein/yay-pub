import XCTest
@testable import YayCore

final class PlatformTests: XCTestCase {

    func testYayLabelResolvesToAColor() {
        // Smoke test: the cross-platform helper resolves on whichever platform
        // we're building for, without throwing or returning a sentinel.
        let color = PlatformColor.yayLabel
        XCTAssertNotNil(color)
    }

    func testYayControlBackgroundResolvesToAColor() {
        let color = PlatformColor.yayControlBackground
        XCTAssertNotNil(color)
    }

    func testItalicMonospacedFallback() {
        // A nonsense family name should fall back to the system monospaced font
        // rather than crash or return a system default with the wrong size.
        let font = PlatformFont.yayItalicMonospaced(family: "DefinitelyNotAFontFamilyXYZ", size: 13)
        XCTAssertEqual(font.pointSize, 13, "fallback font should preserve the requested size")
    }

    func testBoldItalicMonospacedFallback() {
        let font = PlatformFont.yayBoldItalicMonospaced(family: "DefinitelyNotAFontFamilyXYZ", size: 17)
        XCTAssertEqual(font.pointSize, 17)
    }
}
