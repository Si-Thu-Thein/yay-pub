import XCTest
@testable import YayPreview

final class MarkdownRendererTests: XCTestCase {

    func testRendererProducesHTMLDocument() {
        let renderer = MarkdownRenderer()
        let html = renderer.render("hello world")
        XCTAssertTrue(html.contains("<html"), "render() should return a full HTML document")
        XCTAssertTrue(html.contains("</html>"), "render() should close the document")
        XCTAssertTrue(html.contains("hello world"), "rendered HTML should contain the source text")
    }

    func testRenderBodyDoesNotIncludeFullDocument() {
        let renderer = MarkdownRenderer()
        let body = renderer.renderBody("hello")
        XCTAssertFalse(body.contains("<html"), "renderBody() returns body fragment only")
        XCTAssertFalse(body.contains("<head"), "renderBody() returns body fragment only")
    }

    func testHeadersConvertToHeadingTags() {
        let renderer = MarkdownRenderer()
        let body = renderer.renderBody("# Title")
        XCTAssertTrue(body.contains("<h1"), "ATX H1 should produce <h1>")
        XCTAssertTrue(body.contains("Title"), "heading content should be preserved")
    }

    func testFencedCodeBlocksProduceCodeTags() {
        let renderer = MarkdownRenderer()
        let body = renderer.renderBody("""
            ```swift
            let x = 1
            ```
            """)
        XCTAssertTrue(body.contains("<pre"), "fenced code blocks should use <pre>")
        XCTAssertTrue(body.contains("<code"), "fenced code blocks should use <code>")
    }

    func testJavaScriptURLsAreSanitized() {
        let renderer = MarkdownRenderer()
        let body = renderer.renderBody("[click](javascript:alert(1))")
        XCTAssertFalse(
            body.lowercased().contains("javascript:"),
            "javascript: URLs must be stripped from rendered output"
        )
    }
}
