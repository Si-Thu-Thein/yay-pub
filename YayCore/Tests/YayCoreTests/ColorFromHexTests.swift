import XCTest
@testable import YayCore

final class ColorFromHexTests: XCTestCase {

    func testValidSixDigitHex() {
        let color = colorFromHex("#FF8800")
        XCTAssertNotNil(color, "Expected #FF8800 to parse to a non-nil PlatformColor")
    }

    func testValidSixDigitHexWithoutHash() {
        XCTAssertNotNil(colorFromHex("FF8800"))
    }

    func testValidEightDigitHexWithAlpha() {
        XCTAssertNotNil(colorFromHex("#80FF8800"))
    }

    func testInvalidLengthReturnsNil() {
        XCTAssertNil(colorFromHex("#ABC"), "3-digit hex is not supported")
        XCTAssertNil(colorFromHex("#FFFFFFFFF"), "9-digit hex is not supported")
        XCTAssertNil(colorFromHex(""))
    }

    func testInvalidCharactersReturnsNil() {
        XCTAssertNil(colorFromHex("#GGGGGG"), "non-hex characters should fail")
    }

    func testWhitespaceTrimmed() {
        XCTAssertNotNil(colorFromHex("  #FF8800  "), "surrounding whitespace should be tolerated")
    }
}
