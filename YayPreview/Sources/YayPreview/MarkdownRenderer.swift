import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import YayCore

/// Converts Markdown to HTML with syntax highlighting, Mermaid diagrams, and KaTeX math
public final class MarkdownRenderer {
    private let theme: MarkdownTheme

    // MARK: - Static Caches (survive across instances)

    private static var resourceCache: [String: String] = [:]
    private static var base64Cache: [String: String] = [:]

    // MARK: - Precompiled Regex Patterns

    private static let fencedCodeRegex = try! NSRegularExpression(
        pattern: "```([a-zA-Z0-9_+#\\.-]*)?\\s*\\n([\\s\\S]*?)```"
    )
    private static let inlineCodeRegex = try! NSRegularExpression(
        pattern: "(?<!`)`(?!`)([^`\\n]+?)`(?!`)"
    )
    private static let displayMathRegex = try! NSRegularExpression(
        pattern: "\\$\\$([\\s\\S]+?)\\$\\$"
    )
    private static let inlineMathRegex = try! NSRegularExpression(
        pattern: "(?<!\\$)\\$(?!\\$)([^\\$\\n]+?)\\$(?!\\$)"
    )
    private static let headerRegexes: [NSRegularExpression] = (1...6).map { level in
        let hashes = String(repeating: "#", count: level)
        return try! NSRegularExpression(pattern: "^\(hashes)\\s+(.+)$", options: .anchorsMatchLines)
    }
    private static let hrRegex = try! NSRegularExpression(
        pattern: "(?m)^\\s*(-{3,}|\\*{3,}|_{3,})\\s*$"
    )
    private static let tableSeparatorRegex = try! NSRegularExpression(
        pattern: "^\\|?[\\s:]*-{2,}[\\s:]*\\|"
    )

    // Bold/italic patterns — pre-compiled so each render doesn't recompile six
    // regexes via `replacingOccurrences(of:options:.regularExpression)`.
    private static let boldItalicAsteriskRegex = try! NSRegularExpression(pattern: "\\*\\*\\*(.+?)\\*\\*\\*")
    private static let boldItalicUnderscoreRegex = try! NSRegularExpression(pattern: "(?<!\\w)___(.+?)___(?!\\w)")
    private static let boldAsteriskRegex = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
    private static let boldUnderscoreRegex = try! NSRegularExpression(pattern: "(?<!\\w)__(.+?)__(?!\\w)")
    private static let italicAsteriskRegex = try! NSRegularExpression(pattern: "\\*(.+?)\\*")
    private static let italicUnderscoreRegex = try! NSRegularExpression(pattern: "(?<!\\w)_(.+?)_(?!\\w)")

    private static let linkRegex = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)")
    private static let imageRegex = try! NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^)]+)\\)")

    // MARK: - HTML Sanitization
    //
    // The body div in `wrapInHTMLDocument` interpolates the rendered output
    // verbatim, so any raw HTML in user markdown lands in the WebView. The
    // sanitizers below strip the highest-impact injection vectors before the
    // body is handed to WKWebView. They are intentionally conservative — the
    // wrapper's own <script>/<style> blocks aren't routed through here.
    private static let scriptBlockRegex = try! NSRegularExpression(
        pattern: "<script\\b[^>]*>[\\s\\S]*?</script\\s*>",
        options: [.caseInsensitive]
    )
    private static let scriptOrphanRegex = try! NSRegularExpression(
        pattern: "</?script\\b[^>]*/?>",
        options: [.caseInsensitive]
    )
    private static let dangerousElementRegex = try! NSRegularExpression(
        pattern: "<(iframe|object|embed|frame|frameset|meta|base|link)\\b[^>]*>[\\s\\S]*?</\\1\\s*>",
        options: [.caseInsensitive]
    )
    private static let dangerousVoidElementRegex = try! NSRegularExpression(
        pattern: "<(iframe|object|embed|frame|frameset|meta|base|link)\\b[^>]*/?>",
        options: [.caseInsensitive]
    )
    private static let eventHandlerRegex = try! NSRegularExpression(
        pattern: "\\son[a-zA-Z]+\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)",
        options: [.caseInsensitive]
    )
    private static let javascriptURLRegex = try! NSRegularExpression(
        pattern: "(href|src|formaction|action|xlink:href)\\s*=\\s*(\"\\s*javascript:[^\"]*\"|'\\s*javascript:[^']*'|javascript:[^\\s\">]+)",
        options: [.caseInsensitive]
    )

    // MARK: - Init

    public init(theme: MarkdownTheme = .standard) {
        self.theme = theme
    }

    // MARK: - Public API

    /// Full HTML document with all JS/CSS libraries (for initial WebView load)
    public func render(_ markdown: String) -> String {
        let body = renderBody(markdown)
        return wrapInHTMLDocument(body)
    }

    /// Just the HTML body content (for JavaScript body-swap updates)
    public func renderBody(_ markdown: String) -> String {
        return convertMarkdownToHTML(markdown)
    }

    // MARK: - Conversion Pipeline

    private func convertMarkdownToHTML(_ markdown: String) -> String {
        var html = injectLineSentinels(in: markdown)
        html = convertFencedCodeBlocks(html)
        html = convertInlineCode(html)
        html = convertMathExpressions(html)
        html = convertHeaders(html)
        html = convertBoldItalic(html)
        html = convertImages(html)
        html = convertLinks(html)
        html = convertLists(html)
        html = convertBlockquotes(html)
        html = convertTables(html)
        html = convertHorizontalRules(html)
        html = convertParagraphs(html)
        return sanitizeUserHTML(html)
    }

    /// Removes the most impactful injection vectors from rendered body HTML
    /// before it is interpolated into the WebView document. Code spans/blocks
    /// are already HTML-escaped earlier in the pipeline so legitimate `<script>`
    /// shown as code is unaffected.
    private func sanitizeUserHTML(_ html: String) -> String {
        func strip(_ regex: NSRegularExpression, in input: String, with template: String = "") -> String {
            return regex.stringByReplacingMatches(
                in: input,
                range: NSRange(location: 0, length: (input as NSString).length),
                withTemplate: template
            )
        }

        var result = html
        // Drop entire <script>...</script> blocks first, then any orphan tags
        // left over by malformed input.
        result = strip(Self.scriptBlockRegex, in: result)
        result = strip(Self.scriptOrphanRegex, in: result)
        // Iframes, objects, and document-affecting elements.
        result = strip(Self.dangerousElementRegex, in: result)
        result = strip(Self.dangerousVoidElementRegex, in: result)
        // Inline event handlers (onclick, onerror, onload, …) on any element.
        result = strip(Self.eventHandlerRegex, in: result)
        // Neutralise javascript: URLs in link/image/form attributes by
        // pointing them at an inert anchor.
        result = strip(Self.javascriptURLRegex, in: result, with: "$1=\"#\"")
        return result
    }

    // MARK: - Source Line Sentinels
    //
    // Inserts an HTML comment `<!--SLINE:N-->` on its own line in front of every
    // top-level block (paragraph, heading, list, code fence, blockquote, table,
    // math display, hr). After conversion, JS in the WebView lifts each comment's
    // line number onto the next sibling's `data-source-line` attribute, giving
    // every visible block a stable anchor for VS Code-style scroll sync.
    //
    // Lines inside fenced code blocks and `$$…$$` math blocks are skipped so
    // sentinels never end up inside literal source/code spans.
    private func injectLineSentinels(in markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var output: [String] = []
        output.reserveCapacity(lines.count * 2)

        var inFence = false
        var inDisplayMath = false
        var prevLineWasBlank = true  // start-of-doc counts as a block boundary

        for (index, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let lineNumber = index + 1  // 1-indexed for editor parity

            // Fence/math toggles — emit no sentinel for the closing delimiter line
            if inFence {
                if trimmed.hasPrefix("```") {
                    inFence = false
                    prevLineWasBlank = false
                }
                output.append(rawLine)
                continue
            }
            if inDisplayMath {
                if trimmed.contains("$$") {
                    inDisplayMath = false
                    prevLineWasBlank = false
                }
                output.append(rawLine)
                continue
            }

            if trimmed.isEmpty {
                prevLineWasBlank = true
                output.append(rawLine)
                continue
            }

            let isFenceOpen = trimmed.hasPrefix("```")
            let isMathOpen = trimmed.hasPrefix("$$") && !trimmed.hasSuffix("$$")
                || (trimmed == "$$")
            let isHeading = trimmed.hasPrefix("#")

            // Emit a sentinel when this line begins a new block. A block starts
            // after a blank line, at every heading, or at a fence/math opener
            // (so the opener itself anchors to its source line).
            if prevLineWasBlank || isHeading || isFenceOpen || isMathOpen {
                output.append("<!--SLINE:\(lineNumber)-->")
            }

            output.append(rawLine)
            prevLineWasBlank = false

            if isFenceOpen { inFence = true }
            if isMathOpen { inDisplayMath = true }
        }

        return output.joined(separator: "\n")
    }

    // MARK: - Code Blocks

    private func convertFencedCodeBlocks(_ text: String) -> String {
        let matches = Self.fencedCodeRegex.matches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length)
        )
        guard !matches.isEmpty else { return text }
        // NSMutableString.replaceCharacters mutates in place; the previous
        // immutable replacingCharacters allocated a fresh NSString per match,
        // making the loop O(matches × document_length).
        let result = NSMutableString(string: text)

        for match in matches.reversed() {
            let languageRange = match.range(at: 1)
            let codeRange = match.range(at: 2)

            var language = ""
            if languageRange.location != NSNotFound {
                language = result.substring(with: languageRange)
            }

            let code = codeRange.location != NSNotFound ? result.substring(with: codeRange) : ""
            let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
            let escapedCode = escapeHTML(trimmedCode)

            let replacement: String
            if language.lowercased() == "mermaid" {
                replacement = "<pre class=\"mermaid\">\(escapedCode)</pre>"
            } else {
                let langClass = language.isEmpty ? "" : " class=\"language-\(language)\""
                replacement = "<pre><code\(langClass)>\(escapedCode)</code></pre>"
            }

            result.replaceCharacters(in: match.range, with: replacement)
        }

        return result as String
    }

    private func convertInlineCode(_ text: String) -> String {
        let matches = Self.inlineCodeRegex.matches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length)
        )
        guard !matches.isEmpty else { return text }
        let result = NSMutableString(string: text)

        for match in matches.reversed() {
            let codeRange = match.range(at: 1)
            let code = result.substring(with: codeRange)
            let replacement = "<code>\(escapeHTML(code))</code>"
            result.replaceCharacters(in: match.range, with: replacement)
        }

        return result as String
    }

    // MARK: - Math Expressions

    private func convertMathExpressions(_ text: String) -> String {
        let result = NSMutableString(string: text)

        // Display math ($$...$$) — reverse iteration to avoid offset tracking
        let displayMatches = Self.displayMathRegex.matches(
            in: text, range: NSRange(location: 0, length: result.length)
        )
        for match in displayMatches.reversed() {
            let mathRange = match.range(at: 1)
            let mathContent = mathRange.location != NSNotFound ? result.substring(with: mathRange) : ""
            let replacement = "<div class=\"math math-display\">\(escapeHTML(mathContent))</div>"
            result.replaceCharacters(in: match.range, with: replacement)
        }

        // Inline math ($...$) — re-match on updated string, reverse iteration
        let updatedText = result as String
        let inlineMatches = Self.inlineMathRegex.matches(
            in: updatedText, range: NSRange(location: 0, length: result.length)
        )
        for match in inlineMatches.reversed() {
            let mathRange = match.range(at: 1)
            let mathContent = mathRange.location != NSNotFound ? result.substring(with: mathRange) : ""
            let replacement = "<span class=\"math math-inline\">\(escapeHTML(mathContent))</span>"
            result.replaceCharacters(in: match.range, with: replacement)
        }

        return result as String
    }

    // MARK: - Headers

    private func convertHeaders(_ text: String) -> String {
        var result = text

        // Process h6 down to h1 so ### doesn't match before ######
        for level in (1...6).reversed() {
            let regex = Self.headerRegexes[level - 1]
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(location: 0, length: (result as NSString).length),
                withTemplate: "<h\(level)>$1</h\(level)>"
            )
        }

        return result
    }

    // MARK: - Bold & Italic

    private func convertBoldItalic(_ text: String) -> String {
        // Order matters: triple delimiters must run before doubles, doubles
        // before singles, otherwise `**bold**` would partially match the italic
        // pattern. Underscore variants use word boundaries to avoid mangling
        // identifiers like `my_variable_name`.
        var result = text
        result = Self.replace(result, with: Self.boldItalicAsteriskRegex, template: "<strong><em>$1</em></strong>")
        result = Self.replace(result, with: Self.boldItalicUnderscoreRegex, template: "<strong><em>$1</em></strong>")
        result = Self.replace(result, with: Self.boldAsteriskRegex, template: "<strong>$1</strong>")
        result = Self.replace(result, with: Self.boldUnderscoreRegex, template: "<strong>$1</strong>")
        result = Self.replace(result, with: Self.italicAsteriskRegex, template: "<em>$1</em>")
        result = Self.replace(result, with: Self.italicUnderscoreRegex, template: "<em>$1</em>")
        return result
    }

    // MARK: - Links & Images

    private func convertLinks(_ text: String) -> String {
        return Self.replace(text, with: Self.linkRegex, template: "<a href=\"$2\">$1</a>")
    }

    private func convertImages(_ text: String) -> String {
        return Self.replace(text, with: Self.imageRegex, template: "<img src=\"$2\" alt=\"$1\">")
    }

    /// Convenience wrapper around `stringByReplacingMatches` that uses the
    /// caller-supplied compiled regex against the whole string.
    private static func replace(_ input: String, with regex: NSRegularExpression, template: String) -> String {
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(location: 0, length: (input as NSString).length),
            withTemplate: template
        )
    }

    // MARK: - Lists

    private func convertLists(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            // Ordered list: "1. text", "2. text", etc.
            if trimmed.range(of: #"^\d+\.\s+(.+)$"#, options: .regularExpression) != nil {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let m = t.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                        items.append("<li>\(String(t[m.upperBound...]))</li>")
                        i += 1
                    } else {
                        break
                    }
                }
                result.append("<ol>")
                result.append(contentsOf: items)
                result.append("</ol>")
                continue
            }

            // Unordered list: "- text", "* text", "+ text"
            if trimmed.range(of: #"^[-*+]\s+(.+)$"#, options: .regularExpression) != nil {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let m = t.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                        items.append("<li>\(String(t[m.upperBound...]))</li>")
                        i += 1
                    } else {
                        break
                    }
                }
                result.append("<ul>")
                result.append(contentsOf: items)
                result.append("</ul>")
                continue
            }

            result.append(lines[i])
            i += 1
        }

        return result.joined(separator: "\n")
    }

    // MARK: - Blockquotes

    private func convertBlockquotes(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix(">") {
                // Collect consecutive blockquote lines into one <blockquote>
                var content: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(">") {
                        var line = String(t.dropFirst())
                        if line.hasPrefix(" ") { line = String(line.dropFirst()) }
                        content.append(line)
                        i += 1
                    } else {
                        break
                    }
                }
                result.append("<blockquote>" + content.joined(separator: "<br>\n") + "</blockquote>")
            } else {
                result.append(lines[i])
                i += 1
            }
        }

        return result.joined(separator: "\n")
    }

    // MARK: - Tables

    private func convertTables(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var i = 0

        while i < lines.count {
            if i + 1 < lines.count,
               isTableRow(lines[i]),
               isTableSeparator(lines[i + 1]) {

                let alignments = parseAlignments(lines[i + 1])
                var tableHTML = "<table>\n<thead>\n<tr>\n"

                let headers = parseTableCells(lines[i])
                for (col, header) in headers.enumerated() {
                    let align = col < alignments.count ? alignments[col] : ""
                    let style = align.isEmpty ? "" : " style=\"text-align: \(align)\""
                    tableHTML += "<th\(style)>\(header.trimmingCharacters(in: .whitespacesAndNewlines))</th>\n"
                }
                tableHTML += "</tr>\n</thead>\n<tbody>\n"

                i += 2

                while i < lines.count, isTableRow(lines[i]) {
                    let cells = parseTableCells(lines[i])
                    tableHTML += "<tr>\n"
                    for (col, cell) in cells.enumerated() {
                        let align = col < alignments.count ? alignments[col] : ""
                        let style = align.isEmpty ? "" : " style=\"text-align: \(align)\""
                        tableHTML += "<td\(style)>\(cell.trimmingCharacters(in: .whitespacesAndNewlines))</td>\n"
                    }
                    tableHTML += "</tr>\n"
                    i += 1
                }

                tableHTML += "</tbody>\n</table>"
                result.append(tableHTML)
            } else {
                result.append(lines[i])
                i += 1
            }
        }

        return result.joined(separator: "\n")
    }

    private func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // Require 2+ pipe characters to avoid false positives with shell commands, etc.
        return trimmed.filter({ $0 == "|" }).count >= 2
    }

    private func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.tableSeparatorRegex.firstMatch(
            in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)
        ) != nil
    }

    private func parseAlignments(_ separator: String) -> [String] {
        return parseTableCells(separator).map { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            let left = trimmed.hasPrefix(":")
            let right = trimmed.hasSuffix(":")
            if left && right { return "center" }
            if right { return "right" }
            if left { return "left" }
            return ""
        }
    }

    private func parseTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("|") { trimmed = String(trimmed.dropFirst()) }
        if trimmed.hasSuffix("|") { trimmed = String(trimmed.dropLast()) }
        return trimmed.components(separatedBy: "|")
    }

    // MARK: - Horizontal Rules

    private func convertHorizontalRules(_ text: String) -> String {
        return Self.hrRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: "<hr>"
        )
    }

    // MARK: - Paragraphs

    private func isBlockLevelHTML(_ line: String) -> Bool {
        if line.hasPrefix("<!--") { return true }  // sentinels and user comments
        let blockTags = ["<h1", "<h2", "<h3", "<h4", "<h5", "<h6",
                         "<p>", "<p ", "</p>",
                         "<div", "</div>",
                         "<pre", "</pre>",
                         "<table", "</table>",
                         "<ul", "</ul>",
                         "<ol", "</ol>",
                         "<li", "</li>",
                         "<blockquote", "</blockquote>",
                         "<hr", "<br"]
        let lower = line.lowercased()
        return blockTags.contains { lower.hasPrefix($0) }
    }

    private func convertParagraphs(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result = ""
        var inParagraph = false
        var specialBlockDepth = 0

        let blockOpenTags = ["<div", "<pre", "<table", "<ul", "<ol", "<blockquote"]
        let blockCloseTags = ["</div>", "</pre>", "</table>", "</ul>", "</ol>", "</blockquote>"]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            let opensBlock = blockOpenTags.contains { trimmed.hasPrefix($0) }
            let closesBlock = blockCloseTags.contains { trimmed.contains($0) }

            if opensBlock {
                if inParagraph {
                    result += "</p>\n"
                    inParagraph = false
                }
                if !closesBlock {
                    specialBlockDepth += 1
                }
                result += line + "\n"
                continue
            }

            if specialBlockDepth > 0 && closesBlock {
                specialBlockDepth -= 1
                result += line + "\n"
                continue
            }

            if specialBlockDepth > 0 {
                result += line + "\n"
                continue
            }

            // Block-level HTML (headers, hr, etc.) — not inline tags like <strong>
            if trimmed.hasPrefix("<") && isBlockLevelHTML(trimmed) {
                if inParagraph {
                    result += "</p>\n"
                    inParagraph = false
                }
                result += line + "\n"
            } else if trimmed.isEmpty {
                if inParagraph {
                    result += "</p>\n"
                    inParagraph = false
                }
                result += "\n"
            } else {
                if !inParagraph {
                    result += "<p>"
                    inParagraph = true
                } else {
                    result += "<br>\n"
                }
                result += trimmed
            }
        }

        if inParagraph {
            result += "</p>\n"
        }

        return result
    }

    // MARK: - Utilities

    private func escapeHTML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    // MARK: - Resource Loading (cached)

    private func getBundledJS(named name: String) -> String {
        if let cached = Self.resourceCache[name] {
            return cached
        }

        let bundle = Bundle(for: MarkdownRenderer.self)

        let filename: String
        let ext: String
        if let dotIndex = name.lastIndex(of: ".") {
            filename = String(name[..<dotIndex])
            ext = String(name[name.index(after: dotIndex)...])
        } else {
            filename = name
            ext = ""
        }

        // SPM resource bundle
        if let resourceBundleURL = bundle.url(forResource: "YayPreview_YayPreview", withExtension: "bundle"),
           let resourceBundle = Bundle(url: resourceBundleURL) {
            if let url = resourceBundle.url(forResource: filename, withExtension: ext.isEmpty ? nil : ext),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                Self.resourceCache[name] = content
                return content
            }
        }

        // Direct access fallback
        if let url = bundle.url(forResource: filename, withExtension: ext.isEmpty ? nil : ext),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            Self.resourceCache[name] = content
            return content
        }

        return ""
    }

    private func getBase64JS(named name: String) -> String {
        if let cached = Self.base64Cache[name] {
            return cached
        }
        let js = getBundledJS(named: name)
        let base64 = Data(js.utf8).base64EncodedString()
        Self.base64Cache[name] = base64
        return base64
    }

    // MARK: - HTML Document

    private func wrapInHTMLDocument(_ body: String) -> String {
        let baseColor = colorToHex(theme.baseColor)
        let linkColor = colorToHex(theme.linkColor)
        let codeBackground = colorToHex(theme.codeBackgroundColor)

        // Load resources (cached after first call)
        let highlightJS = getBundledJS(named: "highlight.core.min.js")
        let highlightCSS = getBundledJS(named: "github.min.css")
        let katexCSS = getBundledJS(named: "katex.min.css")
        let mermaidBase64 = getBase64JS(named: "mermaid.min.js")
        let katexBase64 = getBase64JS(named: "katex.min.js")

        // Build language registration scripts
        let languages = [
            ("javascript", "lang_javascript.js"),
            ("typescript", "lang_typescript.js"),
            ("csharp", "lang_csharp.js"),
            ("php", "lang_php.js"),
            ("java", "lang_java.js"),
            ("ruby", "lang_ruby.js"),
            ("go", "lang_go.js"),
            ("rust", "lang_rust.js"),
            ("python", "lang_python.js"),
            ("swift", "lang_swift.js"),
            ("kotlin", "lang_kotlin.js"),
            ("bash", "lang_bash.js"),
            ("sql", "lang_sql.js"),
            ("json", "lang_json.js"),
            ("yaml", "lang_yaml.js"),
            ("markdown", "lang_markdown.js"),
            ("xml", "lang_xml.js"),
            ("css", "lang_css.js"),
            ("cpp", "lang_cpp.js"),
            ("objectivec", "lang_objectivec.js")
        ]

        var languageScripts = ""
        for (name, file) in languages {
            let langCode = getBundledJS(named: file)
            if !langCode.isEmpty {
                languageScripts += """

                    (function() {
                        var module = { exports: {} };
                        var exports = module.exports;
                        \(langCode)
                        if (module.exports && typeof module.exports === 'function') {
                            hljs.registerLanguage('\(name)', module.exports);
                        }
                    })();
                """
            }
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">

            <style>\(highlightCSS)</style>

            <script>
                var hljs = (function() {
                    var module = { exports: {} };
                    var exports = module.exports;
                    \(highlightJS)
                    return module.exports;
                })();
                window.hljs = hljs;
                \(languageScripts)
            </script>

            <script src="data:text/javascript;base64,\(mermaidBase64)"></script>

            <style>\(katexCSS)</style>
            <script src="data:text/javascript;base64,\(katexBase64)"></script>

            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                    line-height: 1.6;
                    color: \(baseColor);
                    max-width: 900px;
                    margin: 0 auto;
                    padding: 20px;
                }
                code {
                    background-color: \(codeBackground);
                    padding: 2px 6px;
                    border-radius: 3px;
                    font-family: "SF Mono", Monaco, "Cascadia Code", "Roboto Mono", Consolas, "Courier New", monospace;
                }
                pre {
                    background-color: \(codeBackground);
                    padding: 16px;
                    border-radius: 6px;
                    overflow-x: auto;
                }
                pre code {
                    background: none;
                    padding: 0;
                }
                a {
                    color: \(linkColor);
                    text-decoration: none;
                }
                a:hover {
                    text-decoration: underline;
                }
                img {
                    max-width: 100%;
                    height: auto;
                }
                blockquote {
                    border-left: 4px solid #ddd;
                    padding-left: 16px;
                    color: #666;
                    margin: 16px 0;
                }
                hr {
                    border: none;
                    border-top: 2px solid #eee;
                    margin: 24px 0;
                }
                table {
                    border-collapse: collapse;
                    width: 100%;
                    margin: 16px 0;
                }
                th, td {
                    border: 1px solid #ddd;
                    padding: 8px 12px;
                }
                th {
                    background-color: \(codeBackground);
                    font-weight: 600;
                }
                tbody tr:nth-child(even) {
                    background-color: \(codeBackground);
                }
                pre.mermaid {
                    text-align: center;
                    margin: 20px 0;
                    background: transparent;
                    border: none;
                    padding: 0;
                    font-family: inherit;
                }
                .math-display {
                    text-align: center;
                    margin: 20px 0;
                    overflow-x: auto;
                }
                .math-inline {
                    display: inline;
                }
            </style>
        </head>
        <body>
            <div id="content">\(body)</div>
            <script>
                // Initialize mermaid once
                if (typeof mermaid !== 'undefined') {
                    mermaid.initialize({ startOnLoad: false, theme: 'default', securityLevel: 'strict' });
                }

                function runHighlighting() {
                    // Syntax highlighting — only fenced code blocks, not inline <code>
                    if (typeof hljs !== 'undefined') {
                        document.querySelectorAll('#content pre code').forEach(function(block) {
                            // Reset previous highlighting before re-applying
                            block.removeAttribute('data-highlighted');
                            hljs.highlightElement(block);
                        });
                    }

                    // KaTeX math rendering
                    if (typeof katex !== 'undefined') {
                        document.querySelectorAll('#content .math').forEach(function(el) {
                            try {
                                var tex = el.textContent;
                                var displayMode = el.classList.contains('math-display');
                                katex.render(tex, el, { displayMode: displayMode, throwOnError: false });
                            } catch (e) {}
                        });
                    }

                    // Mermaid diagrams
                    if (typeof mermaid !== 'undefined') {
                        document.querySelectorAll('#content pre.mermaid').forEach(function(element) {
                            try {
                                var rawText = element.textContent;
                                mermaid.render('m' + Math.random().toString(36).substr(2, 9), rawText)
                                    .then(function(result) {
                                        var wrapper = document.createElement('div');
                                        wrapper.className = 'mermaid';
                                        wrapper.innerHTML = result.svg;
                                        element.parentNode.replaceChild(wrapper, element);
                                    })
                                    .catch(function(err) {});
                            } catch (e) {}
                        });
                    }
                }

                // ---- Source-line anchors (for editor↔preview scroll sync) ----
                //
                // injectLineSentinels in Swift inserts <!--SLINE:N--> comments
                // before each block. Lift those comments onto the next element
                // as a data-source-line attribute so we can map editor lines to
                // DOM positions during scroll sync.
                function applyLineMarkers() {
                    var content = document.getElementById('content');
                    if (!content) return;
                    var walker = document.createTreeWalker(content, NodeFilter.SHOW_COMMENT, null);
                    var pending = [];
                    var node;
                    while ((node = walker.nextNode())) {
                        var m = /^SLINE:(\\d+)$/.exec(node.nodeValue.trim());
                        if (m) pending.push({ node: node, line: parseInt(m[1], 10) });
                    }
                    pending.forEach(function(item) {
                        var target = item.node.nextElementSibling;
                        // If sentinel got swallowed into a <p>, look for the
                        // closest block-level ancestor of the comment instead.
                        if (!target) {
                            var p = item.node.parentNode;
                            while (p && p !== content && p.nodeType === 1) {
                                if (!p.hasAttribute('data-source-line')) {
                                    p.setAttribute('data-source-line', item.line);
                                }
                                break;
                            }
                        } else if (!target.hasAttribute('data-source-line')) {
                            target.setAttribute('data-source-line', item.line);
                        }
                        item.node.parentNode.removeChild(item.node);
                    });
                }

                var __anchorsCache = null;
                function invalidateAnchors() { __anchorsCache = null; }
                function getAnchors() {
                    if (__anchorsCache) return __anchorsCache;
                    var els = document.querySelectorAll('#content [data-source-line]');
                    var arr = [];
                    for (var i = 0; i < els.length; i++) {
                        var line = parseInt(els[i].getAttribute('data-source-line'), 10);
                        if (!isFinite(line)) continue;
                        var top = els[i].getBoundingClientRect().top + window.scrollY;
                        arr.push({ line: line, top: top });
                    }
                    arr.sort(function(a, b) { return a.line - b.line; });
                    __anchorsCache = arr;
                    return arr;
                }

                // Scroll the preview so the given source line lines up with the
                // top. Between two anchors, interpolate linearly so a giant
                // mermaid block doesn't snap.
                function scrollToSourceLine(line) {
                    var anchors = getAnchors();
                    if (anchors.length === 0) return;
                    if (line <= anchors[0].line) {
                        window.scrollTo(0, 0);
                        return;
                    }
                    if (line >= anchors[anchors.length - 1].line) {
                        window.scrollTo(0, anchors[anchors.length - 1].top);
                        return;
                    }
                    var lo = 0, hi = anchors.length - 1;
                    while (lo < hi - 1) {
                        var mid = (lo + hi) >> 1;
                        if (anchors[mid].line <= line) lo = mid; else hi = mid;
                    }
                    var a = anchors[lo], b = anchors[hi];
                    var fraction = (line - a.line) / (b.line - a.line);
                    var target = a.top + (b.top - a.top) * fraction;
                    window.scrollTo(0, target);
                }

                // Called when WKWebView is asked which source line is at top
                function topVisibleSourceLine() {
                    var anchors = getAnchors();
                    if (anchors.length === 0) return 1;
                    var y = window.scrollY;
                    if (y <= anchors[0].top) return anchors[0].line;
                    if (y >= anchors[anchors.length - 1].top) return anchors[anchors.length - 1].line;
                    var lo = 0, hi = anchors.length - 1;
                    while (lo < hi - 1) {
                        var mid = (lo + hi) >> 1;
                        if (anchors[mid].top <= y) lo = mid; else hi = mid;
                    }
                    var a = anchors[lo], b = anchors[hi];
                    var span = (b.top - a.top) || 1;
                    var fraction = (y - a.top) / span;
                    return Math.round(a.line + (b.line - a.line) * fraction);
                }

                // Notify Swift of scroll position (debounced via rAF). Suppress
                // when Swift initiated the scroll to avoid feedback loops.
                var __suppressScrollPost = 0;
                function suppressScrollPosts(ms) {
                    __suppressScrollPost = Date.now() + (ms || 200);
                }
                var __postPending = false;
                function postScrollLine() {
                    if (__postPending) return;
                    __postPending = true;
                    requestAnimationFrame(function() {
                        __postPending = false;
                        if (Date.now() < __suppressScrollPost) return;
                        if (!window.webkit || !window.webkit.messageHandlers ||
                            !window.webkit.messageHandlers.scrollSync) return;
                        try {
                            window.webkit.messageHandlers.scrollSync.postMessage(topVisibleSourceLine());
                        } catch (e) {}
                    });
                }
                window.addEventListener('scroll', postScrollLine, { passive: true });

                // Called from Swift for live updates (no full page reload)
                function updateContent(html) {
                    var scrollY = window.scrollY;
                    document.getElementById('content').innerHTML = html;
                    runHighlighting();
                    applyLineMarkers();
                    invalidateAnchors();
                    window.scrollTo(0, scrollY);
                }

                // Anchor offsets shift when mermaid SVGs / KaTeX render. Bust
                // the cache after layout settles.
                window.addEventListener('load', function() {
                    setTimeout(invalidateAnchors, 100);
                    setTimeout(invalidateAnchors, 600);
                });

                // Initial highlighting on first load
                window.addEventListener('DOMContentLoaded', function() {
                    runHighlighting();
                    applyLineMarkers();
                    invalidateAnchors();
                });
            </script>
        </body>
        </html>
        """
    }

    private func colorToHex(_ color: PlatformColor) -> String {
        #if canImport(AppKit)
        guard let rgbColor = color.usingColorSpace(NSColorSpace.sRGB) else {
            return "#000000"
        }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "#000000"
        }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #endif
    }
}
