# YayCore

Foundational, UI-light Swift package shared by every other module. The dependency graph is strictly one-way — every other YPM package depends on `YayCore`; `YayCore` depends on no in-repo package.

## Public surface
- `MarkdownTheme` — colours, fonts, and weights used by the editor for each tree-sitter syntax category. Loaded from JSON in `Yay/themes/`.
- `VSCodeTheme` — colour palette consumed by the fenced-code-block highlighter (`CodeSyntaxHighlighter` in `YayTextEditor`).
- `ScrollSyncBridge` — `ObservableObject` shared between editor and preview to mirror scroll position.
- `Platform.swift` (added in Phase 0 of iPad port) — `PlatformColor`/`PlatformFont`/`PlatformView` typealiases that resolve to `NS*` on macOS and `UI*` on iOS.

## Platforms
`.macOS(.v12)` today. `.iOS(.v15)` is added during Phase 0 of the iPad port. After that, **shared code in this package must not import `AppKit` or `UIKit` directly** — go through the platform typealiases or `#if os(...)` guards.

## Tests
`Tests/YayCoreTests/` — unit tests for theme parsing and the platform abstractions.

## Building
```bash
cd YayCore && swift build
cd YayCore && swift test
```
