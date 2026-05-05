# YayCore module

Shared types only. No UI, no rendering, no platform-specific imports in pure-shared code (use `Platform.swift` typealiases).

## Files
- `MarkdownTheme.swift` — colour/font theme used by the editor for tree-sitter syntax categories.
- `VSCodeTheme.swift` — palette consumed by the fenced-code-block highlighter.
- `ScrollSyncBridge.swift` — `ObservableObject` mirroring scroll position between editor and preview.
- `Platform.swift` *(added in Phase 0 of iPad port)* — `PlatformColor`/`PlatformFont`/`PlatformView` typealiases.

## Rule
If you need to add a type that both the editor and the preview will reference, it belongs here. Anything UI-bearing or platform-bound (NSView, UIView, NSWindow) does **not** belong here.
