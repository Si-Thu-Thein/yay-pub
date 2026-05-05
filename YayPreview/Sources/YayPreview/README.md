# YayPreview module

WKWebView-based live HTML preview.

## Files
- `MarkdownRenderer.swift` — Markdown → HTML. Pure logic, no UI. Reused by `YayExport`.
- `MarkdownPreviewView.swift` — SwiftUI host for the WKWebView (post-Phase-2: split into `+macOS.swift` / `+iOS.swift`).
- `Resources/` — bundled JS/CSS. See [Resources/README.md](Resources/README.md).

## Rule
Renderer changes propagate to PDF/HTML exports because `YayExport` reuses this renderer. That's intentional — keep them in sync deliberately.
