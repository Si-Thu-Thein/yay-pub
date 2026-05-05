import XCTest
@testable import YayTextEditor

final class TextFindTests: XCTestCase {

    private func find(_ text: String, _ query: String, options: FindOptions? = nil) throws -> [NSRange] {
        let opts = options ?? FindOptions(findString: query)
        let tf = try TextFind(string: text, findString: query, options: opts)
        return tf.matches()
    }

    func testTextualMatchesAreCaseInsensitiveByDefault() throws {
        let ranges = try find("Hello hello HELLO", "hello")
        XCTAssertEqual(ranges.count, 3)
    }

    func testCaseSensitiveSearch() throws {
        let opts = FindOptions(findString: "Hello", isCaseSensitive: true)
        let ranges = try find("Hello hello HELLO", "Hello", options: opts)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges.first, NSRange(location: 0, length: 5))
    }

    func testWholeWordOnlyMatchesBoundaries() throws {
        let opts = FindOptions(findString: "cat", isWholeWord: true)
        let ranges = try find("cat catalog catastrophe cat", "cat", options: opts)
        // The whole-word filter should reject "catalog" and "catastrophe"
        // because the boundary after "cat" is followed by a word character.
        XCTAssertEqual(ranges.count, 2, "expected exactly the standalone 'cat' tokens")
    }

    func testRegularExpressionSearch() throws {
        let opts = FindOptions(findString: #"\d+"#, isRegularExpression: true)
        let ranges = try find("abc 123 def 4567", #"\d+"#, options: opts)
        XCTAssertEqual(ranges.count, 2)
    }

    func testEmptyFindStringThrows() {
        XCTAssertThrowsError(
            try TextFind(string: "anything", findString: "", options: FindOptions())
        )
    }

    func testInvalidRegexThrows() {
        let opts = FindOptions(findString: "[unclosed", isRegularExpression: true)
        XCTAssertThrowsError(
            try TextFind(string: "anything", findString: "[unclosed", options: opts)
        )
    }

    func testFindNextForwardWraps() throws {
        let tf = try TextFind(string: "hello hello hello", findString: "hello", options: FindOptions(findString: "hello"))
        // Cursor past the last match — with wrap on, should return the first.
        let next = tf.findNext(after: 100, forward: true, wraps: true)
        XCTAssertEqual(next?.location, 0)
    }

    func testFindNextBackwardNoWrapReturnsNilFromStart() throws {
        let tf = try TextFind(string: "hello hello hello", findString: "hello", options: FindOptions(findString: "hello"))
        let prev = tf.findNext(after: 0, forward: false, wraps: false)
        XCTAssertNil(prev)
    }
}

final class FindOptionsTests: XCTestCase {

    func testDefaultsAreCaseInsensitiveTextualWithWrap() {
        let opts = FindOptions(findString: "x")
        XCTAssertFalse(opts.isCaseSensitive)
        XCTAssertFalse(opts.isRegularExpression)
        XCTAssertFalse(opts.isWholeWord)
        XCTAssertTrue(opts.isWrap)
    }

    func testEquatable() {
        let a = FindOptions(findString: "x", isCaseSensitive: true)
        let b = FindOptions(findString: "x", isCaseSensitive: true)
        let c = FindOptions(findString: "x", isCaseSensitive: false)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
