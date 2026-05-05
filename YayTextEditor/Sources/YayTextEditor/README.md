# YayTextEditor module

Text view + tree-sitter highlighter + find panel.

## Files
- `YayTextEditor.swift` — public SwiftUI representable (post-Phase-1: split into `+macOS.swift` / `+iOS.swift`).
- `YayEditorConfiguration.swift` — knobs.
- `MarkdownNSTextView.swift` — `NSTextView` subclass (macOS).
- `MarkdownLayoutManager.swift` — custom `NSLayoutManager`. **Platform-neutral** — used by both macOS and iOS text views.
- `TreeSitterHighlighter.swift` — incremental tree-sitter highlighting. Platform-neutral.
- `CodeSyntaxHighlighter.swift` — fenced-code-block highlighting. Platform-neutral.
- `LanguageDefinition.swift` — language → highlighter metadata. Platform-neutral.
- `Search/` — Find panel UI + model. See [Search/README.md](Search/README.md).

## Rule
- **TextKit 1 stays.** The highlighter relies on `NSLayoutManager` byte-offset mapping; switching to TextKit 2 means rewriting all highlighting.
- Code that runs on iOS (highlighter, layout manager, language defs) must not import `AppKit`. Either go through `YayCore`'s `Platform` typealiases or `#if os(macOS)`-gate the AppKit-only parts.
