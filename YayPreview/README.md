# YayPreview

Live HTML preview of the Markdown document, hosted in a `WKWebView`. Reused by `YayExport` for PDF/HTML output, so any change to rendering propagates to exports automatically — that is intentional.

## Public surface
- `MarkdownPreviewView` — SwiftUI representable hosting the `WKWebView`.
- `MarkdownRenderer` — produces HTML from a Markdown string + theme.

## Resources
`Sources/YayPreview/Resources/` — bundled JS/CSS:
- `highlight.core.min.js` + `lang_*.js` — highlight.js core and per-language shards (~30 languages).
- `katex.min.js` + `katex.min.css` — math rendering.
- `mermaid.min.js` — diagram rendering.
- `github.min.css` — base GitHub-style stylesheet.

These files are loaded as bundle resources via `.process("Resources")` and **referenced by exact filename** in the renderer. Do not rename or move without updating `MarkdownRenderer`.

## Dependencies
- `YayCore`

## Platforms
`.macOS(.v12)`. `.iOS(.v15)` added in Phase 0 of the iPad port. `WKWebView` is the same API on both platforms; the SwiftUI host view becomes a `UIViewRepresentable` on iOS in Phase 2.

## Tests
`Tests/YayPreviewTests/` — unit tests for the renderer (HTML output, code-fence handling, math/mermaid escaping).

## Building
```bash
cd YayPreview && swift build
cd YayPreview && swift test
```
