#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation
import SwiftTreeSitter
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import YayCore
import os

//
//  TreeSitterHighlighter.swift
//  Yay
//
//  Tree-sitter based Markdown highlighter. Uses incremental parsing for
//  O(edit-size) re-parsing instead of O(document-size) regex scanning.
//  Block structure comes from tree-sitter-markdown; inline elements from
//  tree-sitter-markdown-inline via language injection. Fenced code blocks
//  still delegate to CodeSyntaxHighlighter for language-specific colors.
//

private let log = Logger(subsystem: "com.yay.editor", category: "TreeSitterHighlighter")


final class TreeSitterHighlighter {
    private var configuration: YayEditorConfiguration
    private var vsCodeTheme: VSCodeTheme?

    // MARK: - Tree-sitter Parsers & State

    private let blockParser: Parser
    private let inlineParser: Parser
    private var blockTree: MutableTree?

    /// The current tree has had one or more edits applied and should be reused
    /// by the next parse pass.
    private var blockTreeNeedsParse = false

    /// Cache of inline-parser trees keyed by the inline node's byte range.
    /// On incremental block-tree edits the cache is shifted/invalidated so that
    /// inline nodes outside the edit are reused without re-parsing.
    private struct InlineCacheKey: Hashable {
        let startByte: UInt32
        let endByte: UInt32
    }
    private var inlineTreeCache: [InlineCacheKey: MutableTree] = [:]

    // MARK: - Pre-computed Fonts (P4)

    private var baseFont: PlatformFont
    private var headerFont: PlatformFont
    private var boldFont: PlatformFont
    private var italicFont: PlatformFont
    private var boldItalicFont: PlatformFont
    private var codeFont: PlatformFont
    private var blockquoteFont: PlatformFont
    private var listFont: PlatformFont
    private var imageFont: PlatformFont
    private var htmlFont: PlatformFont
    private var mathFont: PlatformFont

    /// Whether tree-sitter parsers initialised successfully.
    private let parsersReady: Bool

    // MARK: - Init

    init(configuration: YayEditorConfiguration, vsCodeTheme: VSCodeTheme? = nil) {
        self.configuration = configuration
        self.vsCodeTheme = vsCodeTheme ?? VSCodeTheme.light

        // Block parser (document structure: headings, code blocks, lists, etc.)
        self.blockParser = Parser()
        self.inlineParser = Parser()

        var ready = true
        do {
            try blockParser.setLanguage(Language(tree_sitter_markdown()))
            try inlineParser.setLanguage(Language(tree_sitter_markdown_inline()))
        } catch {
            // Without parsers ready, applyHighlighting becomes a no-op; surface
            // the failure so the lack of highlighting is at least diagnosable.
            log.error(
                "tree-sitter parser init failed: \(error.localizedDescription, privacy: .public)")
            ready = false
        }
        self.parsersReady = ready

        // Pre-compute fonts
        let theme = configuration.theme
        self.baseFont = theme.baseFont
        self.headerFont = theme.headerFont
        self.boldFont = theme.boldFont
        self.italicFont = theme.italicFont
        self.codeFont = theme.codeFont
        self.blockquoteFont = theme.blockquoteFont
        self.listFont = theme.listFont
        self.imageFont = theme.imageFont
        self.htmlFont = theme.htmlFont
        self.mathFont = theme.mathFont
        self.boldItalicFont = PlatformFont.yayBoldItalicMonospaced(
            family: theme.baseFont.familyName ?? "Monaco",
            size: theme.baseFontSize
        )
    }

    // MARK: - Configuration Update

    func updateConfiguration(_ newConfiguration: YayEditorConfiguration) {
        let oldTheme = configuration.theme
        let newTheme = newConfiguration.theme
        configuration = newConfiguration

        // Skip expensive font lookups if fonts haven't changed
        guard
            oldTheme.baseFontSize != newTheme.baseFontSize
                || oldTheme.baseFont != newTheme.baseFont
        else { return }

        baseFont = newTheme.baseFont
        headerFont = newTheme.headerFont
        boldFont = newTheme.boldFont
        italicFont = newTheme.italicFont
        codeFont = newTheme.codeFont
        blockquoteFont = newTheme.blockquoteFont
        listFont = newTheme.listFont
        imageFont = newTheme.imageFont
        htmlFont = newTheme.htmlFont
        mathFont = newTheme.mathFont
        boldItalicFont = PlatformFont.yayBoldItalicMonospaced(
            family: newTheme.baseFont.familyName ?? "Monaco",
            size: newTheme.baseFontSize
        )
    }

    // MARK: - Edit Tracking (for incremental parsing)

    /// Call from `textView(_:shouldChangeTextIn:replacementString:)` before the edit lands.
    /// Captures the byte-level edit descriptor that tree-sitter needs.
    func prepareEdit(in range: NSRange, replacementString: String?, currentText: String) {
        let replacement = replacementString ?? ""
        let replacementUTF16Length = (replacement as NSString).length

        // SwiftTreeSitter's Parser uses UTF-16; byte offsets = UTF-16 code-unit offset × 2.
        let startByte = UInt32(range.location * 2)
        let oldEndByte = UInt32((range.location + range.length) * 2)
        let newEndByte = UInt32((range.location + replacementUTF16Length) * 2)

        // Compute line/column points
        let nsString = currentText as NSString
        let startPoint = self.point(at: range.location, in: nsString)
        let oldEndPoint = self.point(at: range.location + range.length, in: nsString)

        // Compute newEndPoint from startPoint + replacement string geometry
        let newEndPoint = self.endPoint(from: startPoint, after: replacement)

        let edit = InputEdit(
            startByte: startByte,
            oldEndByte: oldEndByte,
            newEndByte: newEndByte,
            startPoint: startPoint,
            oldEndPoint: oldEndPoint,
            newEndPoint: newEndPoint
        )

        guard let tree = blockTree else { return }

        let oldTextByteLength = UInt32(nsString.length * 2)
        guard edit.startByte <= edit.oldEndByte,
            edit.oldEndByte <= oldTextByteLength
        else {
            blockTree = nil
            blockTreeNeedsParse = false
            inlineTreeCache.removeAll(keepingCapacity: true)
            return
        }

        shiftInlineCache(for: edit)
        tree.edit(edit)
        blockTreeNeedsParse = true
    }

    /// Force a full re-parse on the next highlighting pass.
    func invalidateTree() {
        blockTree = nil
        blockTreeNeedsParse = false
        inlineTreeCache.removeAll(keepingCapacity: true)
    }

    // MARK: - Public Highlighting API

    #if os(macOS)
    /// macOS convenience: highlight the entire document via an NSTextView.
    func applyHighlighting(to textView: NSTextView) {
        applyHighlighting(to: textView, in: nil)
    }

    /// macOS convenience: highlight a range via an NSTextView.
    func applyHighlighting(to textView: NSTextView, in highlightRange: NSRange?) {
        guard let textStorage = textView.textStorage else { return }
        applyHighlighting(textStorage: textStorage, in: highlightRange)
    }
    #endif

    /// Cross-platform entry point. Applies tree-sitter Markdown highlighting
    /// to `textStorage`. Attribute writes are batched via beginEditing/endEditing,
    /// which the layout manager processes as a single invalidation pass.
    func applyHighlighting(
        textStorage: NSTextStorage,
        in highlightRange: NSRange?
    ) {
        guard parsersReady else { return }

        let theme = configuration.theme
        let text = textStorage.string
        let textLength = (text as NSString).length
        guard textLength > 0 else { return }

        let fullRange = NSRange(location: 0, length: textLength)
        let range = highlightRange ?? fullRange
        let clampedRange = NSIntersectionRange(range, fullRange)
        guard clampedRange.length > 0 else { return }

        // Step 1: Parse (incremental if possible, full otherwise)
        parseDocument(text)
        guard let rootNode = blockTree?.rootNode else { return }

        // Step 2: Collect inline node ranges within the visible area
        var inlineRanges: [SwiftTreeSitter.TSRange] = []
        collectInlineRanges(from: rootNode, into: &inlineRanges, visibleRange: clampedRange)

        // Parse each inline node INDEPENDENTLY to prevent cross-paragraph
        // emphasis matching (e.g. ** in one paragraph pairing with ** in another).
        // Reuse cached trees for unchanged inline nodes; the cache is shifted
        // for non-overlapping nodes during incremental block re-parse.
        var inlineTrees: [MutableTree] = []
        for inlineRange in inlineRanges {
            let key = InlineCacheKey(
                startByte: inlineRange.bytes.lowerBound,
                endByte: inlineRange.bytes.upperBound
            )
            if let cached = inlineTreeCache[key] {
                inlineTrees.append(cached)
                continue
            }
            inlineParser.includedRanges = [inlineRange]
            if let tree = inlineParser.parse(text) {
                inlineTreeCache[key] = tree
                inlineTrees.append(tree)
            }
        }
        inlineParser.includedRanges = []

        // Step 3: Apply styling
        let work = { [self] in
            // Clear previous attributes in the range
            textStorage.removeAttribute(
                .foregroundColor, range: clampedRange)
            textStorage.removeAttribute(
                .backgroundColor, range: clampedRange)
            textStorage.removeAttribute(.underlineStyle, range: clampedRange)
            textStorage.removeAttribute(
                .strikethroughStyle, range: clampedRange)

            // Reset to base font
            textStorage.addAttribute(.font, value: self.baseFont, range: clampedRange)

            // Block-level styling from tree-sitter parse tree
            self.applyBlockStyling(
                rootNode: rootNode,
                textStorage: textStorage,
                text: text,
                textLength: textLength,
                range: clampedRange,
                theme: theme
            )

            // Inline-level styling — each inline node parsed independently
            for inlineTree in inlineTrees {
                guard let inlineRoot = inlineTree.rootNode else { continue }
                self.applyInlineStyling(
                    rootNode: inlineRoot,
                    textStorage: textStorage,
                    textLength: textLength,
                    range: clampedRange,
                    theme: theme
                )
            }
        }

        // textStorage.beginEditing()/endEditing() naturally batches the
        // attribute writes — processEditing fires one invalidateDisplay for
        // the dirty range when endEditing returns. The pre-refactor path used
        // MarkdownLayoutManager.groupTemporaryAttributesUpdate because the
        // temporary-attribute API doesn't go through processEditing; on the
        // textStorage path that wrapper would just add a second redundant
        // invalidation, so we don't call it anymore.
        textStorage.beginEditing()
        work()
        textStorage.endEditing()
    }

    // MARK: - Document Parsing

    private func parseDocument(_ text: String) {
        if let tree = blockTree, blockTreeNeedsParse {
            if let parsedTree = blockParser.parse(tree: tree, string: text) {
                blockTree = parsedTree
            } else {
                blockTree = blockParser.parse(text)
                inlineTreeCache.removeAll(keepingCapacity: true)
            }
            blockTreeNeedsParse = false
        } else if blockTree == nil {
            inlineTreeCache.removeAll(keepingCapacity: true)
            blockTree = blockParser.parse(text)
        }
    }

    /// Reposition cached inline trees to match the new byte coordinates after
    /// `edit`. Trees whose range overlapped the edit are dropped; trees entirely
    /// after the edit are shifted by `(newEndByte - oldEndByte)`; trees entirely
    /// before the edit keep their key.
    private func shiftInlineCache(for edit: InputEdit) {
        guard !inlineTreeCache.isEmpty else { return }
        let oldEnd = edit.oldEndByte
        let editStart = edit.startByte
        let delta = Int64(edit.newEndByte) - Int64(oldEnd)

        var newCache: [InlineCacheKey: MutableTree] = [:]
        newCache.reserveCapacity(inlineTreeCache.count)

        for (key, tree) in inlineTreeCache {
            // Drop entries whose old range overlapped the edited bytes.
            if key.startByte < oldEnd && key.endByte > editStart {
                continue
            }
            if key.startByte >= oldEnd {
                // Entirely after the edit: tell tree-sitter to shift internal
                // node byte offsets, then move the cache key by the same delta.
                tree.edit(edit)
                let newKey = InlineCacheKey(
                    startByte: UInt32(Int64(key.startByte) + delta),
                    endByte: UInt32(Int64(key.endByte) + delta)
                )
                newCache[newKey] = tree
            } else {
                // Entirely before the edit: byte offsets are unchanged.
                newCache[key] = tree
            }
        }
        inlineTreeCache = newCache
    }

    // MARK: - Inline Range Collection

    /// Collects byte ranges of `inline` nodes that overlap the visible range.
    /// These are passed to the inline parser via `includedRanges`.
    private func collectInlineRanges(
        from node: Node,
        into ranges: inout [SwiftTreeSitter.TSRange],
        visibleRange: NSRange
    ) {
        let nodeRange = node.range
        let visibleEnd = NSMaxRange(visibleRange)
        guard NSMaxRange(nodeRange) > visibleRange.location,
            nodeRange.location < visibleEnd
        else { return }

        guard let nodeType = node.nodeType else { return }

        if nodeType == "inline" {
            ranges.append(node.tsRange)
            return
        }

        // Recurse into container nodes
        for i in 0..<node.childCount {
            guard let child = node.child(at: i) else { continue }
            let childRange = child.range
            if NSMaxRange(childRange) <= visibleRange.location { continue }
            if childRange.location >= visibleEnd { break }

            // Skip code blocks — they don't contain inline markdown
            let childType = child.nodeType
            if childType == "fenced_code_block" || childType == "indented_code_block"
                || childType == "html_block"
            {
                continue
            }
            collectInlineRanges(from: child, into: &ranges, visibleRange: visibleRange)
        }
    }

    // MARK: - Block-Level Styling

    private func applyBlockStyling(
        rootNode: Node,
        textStorage: NSTextStorage,
        text: String,
        textLength: Int,
        range: NSRange,
        theme: MarkdownTheme
    ) {
        walkVisible(rootNode, in: range) { [self] node in
            let nodeRange = node.range
            guard NSMaxRange(nodeRange) <= textLength else { return false }
            let visibleNodeRange = NSIntersectionRange(nodeRange, range)
            guard visibleNodeRange.length > 0 else { return false }

            guard let nodeType = node.nodeType else { return true }

            switch nodeType {
            case "atx_heading", "setext_heading":
                textStorage.addAttribute(.font, value: self.headerFont, range: visibleNodeRange)
                textStorage.addAttribute(
                    .foregroundColor, value: theme.headerColor, range: visibleNodeRange)

            case "atx_h1_marker", "atx_h2_marker", "atx_h3_marker",
                "atx_h4_marker", "atx_h5_marker", "atx_h6_marker",
                "setext_h1_underline", "setext_h2_underline":
                textStorage.addAttribute(
                    .foregroundColor, value: theme.headerColor, range: visibleNodeRange)

            case "fenced_code_block":
                self.styleFencedCodeBlock(
                    node: node,
                    textStorage: textStorage,
                    text: text,
                    textLength: textLength,
                    range: range,
                    theme: theme
                )
                return false  // don't recurse into code block children (we handled them)

            case "indented_code_block":
                textStorage.addAttribute(.font, value: self.codeFont, range: visibleNodeRange)
                textStorage.addAttribute(
                    .foregroundColor, value: theme.codeForegroundColor, range: visibleNodeRange
                )
                textStorage.addAttribute(
                    .backgroundColor, value: theme.codeBackgroundColor, range: visibleNodeRange
                )
                return false

            case "block_quote":
                // Content styled by recursion; only markers get special styling
                break

            case "block_quote_marker":
                textStorage.addAttribute(.font, value: self.blockquoteFont, range: visibleNodeRange)
                textStorage.addAttribute(
                    .foregroundColor, value: theme.blockquoteColor, range: visibleNodeRange)

            case "list_marker_minus", "list_marker_plus", "list_marker_star",
                "list_marker_dot", "list_marker_parenthesis":
                textStorage.addAttribute(.font, value: self.listFont, range: visibleNodeRange)
                textStorage.addAttribute(
                    .foregroundColor, value: theme.listColor, range: visibleNodeRange)

            case "thematic_break":
                textStorage.addAttribute(
                    .foregroundColor, value: theme.ruleColor, range: visibleNodeRange)

            case "html_block":
                textStorage.addAttribute(.font, value: self.htmlFont, range: visibleNodeRange)
                textStorage.addAttribute(
                    .foregroundColor, value: theme.htmlColor, range: visibleNodeRange)
                return false

            case "link_reference_definition":
                textStorage.addAttribute(
                    .foregroundColor, value: theme.linkColor, range: visibleNodeRange)

            case "backslash_escape":
                textStorage.addAttribute(
                    .foregroundColor, value: theme.escapeColor, range: visibleNodeRange)

            default:
                break
            }

            return true  // recurse into children
        }
    }

    // MARK: - Fenced Code Block

    private func styleFencedCodeBlock(
        node: Node,
        textStorage: NSTextStorage,
        text: String,
        textLength: Int,
        range: NSRange,
        theme: MarkdownTheme
    ) {
        let nodeRange = node.range
        guard NSMaxRange(nodeRange) <= textLength else { return }
        let visibleNodeRange = NSIntersectionRange(nodeRange, range)
        guard visibleNodeRange.length > 0 else { return }
        let nsText = text as NSString

        // Code font for the entire block
        textStorage.addAttribute(.font, value: codeFont, range: visibleNodeRange)

        var language = ""
        var codeContentRange: NSRange?

        // Walk children to find info_string, code_fence_content, and delimiters
        for i in 0..<node.childCount {
            guard let child = node.child(at: i) else { continue }
            let childRange = child.range
            guard NSMaxRange(childRange) <= textLength else { continue }

            switch child.nodeType {
            case "info_string":
                // The info_string may contain a `language` child
                if let langNode = child.firstChild, langNode.nodeType == "language" {
                    let langRange = langNode.range
                    if NSMaxRange(langRange) <= textLength {
                        language = nsText.substring(with: langRange).lowercased()
                        let visibleLangRange = NSIntersectionRange(langRange, range)
                        if visibleLangRange.length > 0 {
                            textStorage.addAttribute(
                                .foregroundColor, value: PlatformColor.systemOrange,
                                range: visibleLangRange)
                        }
                    }
                } else if childRange.length > 0 {
                    // Fallback: treat entire info_string as language
                    language = nsText.substring(with: childRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let visibleInfoRange = NSIntersectionRange(childRange, range)
                    if visibleInfoRange.length > 0 {
                        textStorage.addAttribute(
                            .foregroundColor, value: PlatformColor.systemOrange,
                            range: visibleInfoRange
                        )
                    }
                }

            case "code_fence_content":
                codeContentRange = childRange

            case "fenced_code_block_delimiter":
                let visibleDelimiterRange = NSIntersectionRange(childRange, range)
                if visibleDelimiterRange.length > 0 {
                    textStorage.addAttribute(.font, value: codeFont, range: visibleDelimiterRange)
                    textStorage.addAttribute(
                        .foregroundColor, value: PlatformColor.systemGray,
                        range: visibleDelimiterRange)
                }

            default:
                break
            }
        }

        // Apply language-specific highlighting to code content
        if let contentRange = codeContentRange, contentRange.length > 0,
            NSMaxRange(contentRange) <= textLength
        {
            let contentHighlightRange = lineBoundedIntersection(
                of: contentRange, with: range, in: nsText)
            guard contentHighlightRange.length > 0 else { return }

            if !language.isEmpty && CodeSyntaxHighlighter.supportsLanguage(language) {
                let codeContent = nsText.substring(with: contentHighlightRange)
                let highlighted = CodeSyntaxHighlighter.highlightCode(
                    codeContent, language: language,
                    theme: configuration.theme, vsCodeTheme: vsCodeTheme
                )
                highlighted.enumerateAttributes(
                    in: NSRange(location: 0, length: highlighted.length), options: []
                ) { attrs, attrRange, _ in
                    let adjusted = NSRange(
                        location: contentHighlightRange.location + attrRange.location,
                        length: attrRange.length
                    )
                    guard NSMaxRange(adjusted) <= textLength else { return }
                    for (key, value) in attrs {
                        if key == .foregroundColor || key == .backgroundColor {
                            textStorage.addAttribute(
                                key, value: value, range: adjusted)
                        } else {
                            textStorage.addAttribute(key, value: value, range: adjusted)
                        }
                    }
                }
            } else {
                textStorage.addAttribute(
                    .foregroundColor, value: theme.codeForegroundColor,
                    range: contentHighlightRange
                )
            }
        }
    }

    // MARK: - Inline-Level Styling

    private func applyInlineStyling(
        rootNode: Node,
        textStorage: NSTextStorage,
        textLength: Int,
        range: NSRange,
        theme: MarkdownTheme
    ) {
        walkVisible(rootNode, in: range) { [self] node in
            let nodeRange = node.range
            guard NSMaxRange(nodeRange) <= textLength else { return false }
            let visibleNodeRange = NSIntersectionRange(nodeRange, range)
            guard visibleNodeRange.length > 0 else { return false }

            guard let nodeType = node.nodeType else { return true }

            switch nodeType {
            case "strong_emphasis":
                // Apply bold first, then override nested emphasis with bold+italic
                textStorage.addAttribute(.font, value: self.boldFont, range: visibleNodeRange)
                for i in 0..<node.childCount {
                    if let child = node.child(at: i), child.nodeType == "emphasis" {
                        let childRange = child.range
                        let visibleChildRange = NSIntersectionRange(childRange, range)
                        if NSMaxRange(childRange) <= textLength && visibleChildRange.length > 0 {
                            textStorage.addAttribute(
                                .font, value: self.boldItalicFont, range: visibleChildRange)
                        }
                    }
                }

            case "emphasis":
                textStorage.addAttribute(.font, value: self.italicFont, range: visibleNodeRange)

            case "code_span":
                textStorage.addAttribute(.font, value: self.codeFont, range: visibleNodeRange)
                textStorage.addAttribute(
                    .foregroundColor, value: theme.codeForegroundColor,
                    range: visibleNodeRange
                )
                return false

            case "inline_link", "full_reference_link", "collapsed_reference_link", "shortcut_link":
                textStorage.addAttribute(
                    .foregroundColor, value: theme.linkColor, range: visibleNodeRange)
                textStorage.addAttribute(
                    .underlineStyle, value: NSUnderlineStyle.single.rawValue,
                    range: visibleNodeRange)

            case "uri_autolink", "email_autolink":
                textStorage.addAttribute(
                    .foregroundColor, value: theme.linkColor, range: visibleNodeRange)
                textStorage.addAttribute(
                    .underlineStyle, value: NSUnderlineStyle.single.rawValue,
                    range: visibleNodeRange)

            case "image":
                textStorage.addAttribute(.font, value: self.imageFont, range: visibleNodeRange)
                textStorage.addAttribute(
                    .foregroundColor, value: theme.imageColor, range: visibleNodeRange)

            case "strikethrough":
                textStorage.addAttribute(
                    .foregroundColor, value: theme.strikeColor, range: visibleNodeRange)
                textStorage.addAttribute(
                    .strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                    range: visibleNodeRange)

            case "backslash_escape":
                textStorage.addAttribute(
                    .foregroundColor, value: theme.escapeColor, range: visibleNodeRange)

            case "html_tag":
                textStorage.addAttribute(.font, value: self.htmlFont, range: visibleNodeRange)
                textStorage.addAttribute(
                    .foregroundColor, value: theme.htmlColor, range: visibleNodeRange)

            case "latex_block", "latex_span_delimiter":
                textStorage.addAttribute(.font, value: self.mathFont, range: visibleNodeRange)
                textStorage.addAttribute(
                    .foregroundColor, value: theme.mathColor, range: visibleNodeRange)

            default:
                break
            }

            return true  // recurse into children
        }
    }

    // MARK: - Efficient Tree Walking

    /// Walks only nodes that overlap `range`. Tree-sitter children are source
    /// ordered, so siblings after the requested range can be skipped entirely.
    private func walkVisible(_ node: Node, in range: NSRange, visitor: (Node) -> Bool) {
        let nodeRange = node.range
        let rangeEnd = NSMaxRange(range)
        guard NSMaxRange(nodeRange) > range.location,
            nodeRange.location < rangeEnd
        else { return }

        guard visitor(node) else { return }

        for i in 0..<node.childCount {
            guard let child = node.child(at: i) else { continue }
            let childRange = child.range
            if NSMaxRange(childRange) <= range.location { continue }
            if childRange.location >= rangeEnd { break }
            walkVisible(child, in: range, visitor: visitor)
        }
    }

    /// Walks the tree using a TreeCursor (more efficient than recursive child access).
    /// The visitor returns `true` to recurse into children, `false` to skip.
    private func walkWithCursor(_ cursor: TreeCursor, visitor: (Node) -> Bool) {
        guard let node = cursor.currentNode else { return }

        let shouldRecurse = visitor(node)

        if shouldRecurse && cursor.goToFirstChild() {
            walkWithCursor(cursor, visitor: visitor)

            while cursor.gotoNextSibling() {
                walkWithCursor(cursor, visitor: visitor)
            }

            _ = cursor.gotoParent()
        }
    }

    private func lineBoundedIntersection(
        of contentRange: NSRange,
        with visibleRange: NSRange,
        in text: NSString
    ) -> NSRange {
        let intersection = NSIntersectionRange(contentRange, visibleRange)
        guard intersection.length > 0 else { return NSRange(location: 0, length: 0) }

        let lineRange = text.lineRange(for: intersection)
        return NSIntersectionRange(lineRange, contentRange)
    }

    // MARK: - Point Calculation

    /// Computes tree-sitter Point (row, column) from a UTF-16 code-unit offset.
    /// Column is in bytes (UTF-16 bytes = code-unit offset × 2 from line start).
    private func point(at utf16Offset: Int, in nsString: NSString) -> Point {
        let safeOffset = min(utf16Offset, nsString.length)

        var row: UInt32 = 0
        var lastLineStart: Int = 0

        // Scan for newlines up to the offset
        var searchStart = 0
        while searchStart < safeOffset {
            let remaining = NSRange(location: searchStart, length: safeOffset - searchStart)
            let nlRange = nsString.range(of: "\n", range: remaining)
            if nlRange.location == NSNotFound { break }
            row += 1
            lastLineStart = nlRange.location + 1
            searchStart = lastLineStart
        }

        let column = UInt32((safeOffset - lastLineStart) * 2)
        return Point(row: row, column: column)
    }

    /// Computes the end Point after inserting `replacement` starting at `startPoint`.
    private func endPoint(from startPoint: Point, after replacement: String) -> Point {
        guard !replacement.isEmpty else { return startPoint }

        let lines = replacement.components(separatedBy: "\n")
        if lines.count == 1 {
            // Single line: same row, column advances by replacement UTF-16 byte length
            let colBytes = UInt32((replacement as NSString).length * 2)
            return Point(row: startPoint.row, column: startPoint.column + colBytes)
        } else {
            // Multi-line: row advances, column is the last line's length
            let lastLine = lines.last ?? ""
            let colBytes = UInt32((lastLine as NSString).length * 2)
            return Point(row: startPoint.row + UInt32(lines.count - 1), column: colBytes)
        }
    }
}
