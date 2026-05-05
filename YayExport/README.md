# YayExport

PDF and HTML export. Reuses `YayPreview`'s renderer to keep export output visually identical to the live preview.

## Public surface
- `MarkdownExportContext` — configuration: page size, margins, theme, headers/footers.
- `MarkdownPDFExporter` — produces a PDF from Markdown by rendering through `WKWebView` and capturing via `createPDF`.

## Dependencies
- `YayCore`
- `YayPreview` (the only module YayExport depends on for rendering — do not duplicate renderer logic here)

## Platforms
`.macOS(.v12)`. `.iOS(.v15)` added in Phase 0 of the iPad port. `WKWebView.createPDF` and `PDFKit` work on both platforms; minor changes to the print path may be needed for iPad.

## Tests
`Tests/YayExportTests/` — unit tests for export context defaults and (where feasible) rendered-PDF byte sanity checks.

## Building
```bash
cd YayExport && swift build
cd YayExport && swift test
```
