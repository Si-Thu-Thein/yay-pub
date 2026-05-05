# YayTextEditor

The live Markdown editor: a TextKit-1 `NSTextView` (and, post-Phase-1, a sibling `UITextView` for iPad) wired to incremental tree-sitter highlighting plus a self-contained Find panel.

## Public surface
- `YayTextEditor` — public SwiftUI representable consumed by the app target.
- `YayEditorConfiguration` — knobs (font size, line spacing, theme, etc.).

## Internal pieces
- `MarkdownNSTextView` + `MarkdownLayoutManager` — TextKit 1 view + custom layout manager. **TextKit 1 is intentional**: tree-sitter byte-offset highlighting and incremental edits are wired against `NSLayoutManager`. Do not migrate to TextKit 2.
- `TreeSitterHighlighter` — parses with `tree-sitter-markdown` via `SwiftTreeSitter`, applies attribute spans on edit.
- `CodeSyntaxHighlighter` + `LanguageDefinition` — fenced-code-block highlighting for ~30 languages.
- `Search/` — Find panel (own controller, view, and `TextFinder` model). Not Apple's `NSTextFinder` — keep find logic in the subdirectory.

## Dependencies
- `YayCore` (sibling package)
- `swift-tree-sitter`
- `tree-sitter-markdown`

## Platforms
`.macOS(.v12)`. `.iOS(.v15)` is added in Phase 0 of the iPad port; a `MarkdownUITextView` joins `MarkdownNSTextView` in Phase 1, sharing `MarkdownLayoutManager` and the highlighters unchanged.

## Tests
`Tests/YayTextEditorTests/` — unit tests for highlighter range math, code-block language detection, and the find/replace model.

## Building
```bash
cd YayTextEditor && swift build
cd YayTextEditor && swift test
```
