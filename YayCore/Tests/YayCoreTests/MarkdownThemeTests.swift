import XCTest
@testable import YayCore

final class MarkdownThemeTests: XCTestCase {

    func testStandardThemeBaseFontSize() {
        // The standard theme should have a sane base font size, regardless
        // of whether VSCodeTheme.light loads (it falls back to a hard-coded
        // 14pt theme when the bundle resource is unavailable, e.g. in tests).
        let theme = MarkdownTheme.standard
        XCTAssertGreaterThan(theme.baseFontSize, 0)
        XCTAssertEqual(theme.baseFont.pointSize, theme.baseFontSize)
    }

    func testWithUnifiedFontSizeAppliesSizeAcrossElements() {
        let theme = MarkdownTheme.withUnifiedFontSize(20, basedOn: .standard)
        XCTAssertEqual(theme.baseFont.pointSize, 20)
        XCTAssertEqual(theme.boldFont.pointSize, 20)
        XCTAssertEqual(theme.codeFont.pointSize, 20)
        XCTAssertEqual(theme.headerFont.pointSize, 20)
    }

    func testWithFontFallsBackForUnknownFamily() {
        let theme = MarkdownTheme.withFont(
            family: "DefinitelyNotAFontFamilyXYZ",
            size: 18,
            basedOn: .standard
        )
        XCTAssertEqual(theme.baseFont.pointSize, 18)
        XCTAssertEqual(theme.boldFont.pointSize, 18)
    }

    func testThemeCacheRoundTrip() {
        let theme = MarkdownTheme.withUnifiedFontSize(15)
        MarkdownTheme.setCachedTheme(theme, named: "unit-test-cache-key")
        let recovered = MarkdownTheme.cachedTheme(named: "unit-test-cache-key")
        XCTAssertNotNil(recovered)
        XCTAssertEqual(recovered?.baseFontSize, 15)
    }
}
