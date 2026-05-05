# YayExport module

PDF/HTML export driven through `YayPreview`'s renderer.

## Files
- `MarkdownExportContext.swift` — page size, margins, theme, headers/footers, output URL.
- `MarkdownPDFExporter.swift` — renders the document via `WKWebView` and captures with `createPDF` + `PDFKit`.

## Rule
**Do not duplicate Markdown→HTML logic here.** Always render through `YayPreview.MarkdownRenderer` so live preview and exports stay in sync.
