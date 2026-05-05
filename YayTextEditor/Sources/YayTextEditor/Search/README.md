# Search

In-document Find / Find & Replace. **Self-contained** — keep all find logic in this directory. Not Apple's `NSTextFinder`.

## Files
- `TextFind.swift` — search query model (text, options).
- `FindOptions.swift` — case sensitivity, regex, whole-word, etc.
- `TextFinder.swift` — search engine: walks the document, returns matches, drives next/previous navigation.
- `FindPanelController.swift` — macOS-side controller wiring the find bar to an `NSTextView` (mac-only today).
- `FindPanelView.swift` — SwiftUI find bar UI (mac-only chrome today).

## Phase 4 (iPad port)
- `TextFind`, `FindOptions`, `TextFinder` are platform-neutral and reused on iPad as-is.
- `FindPanelController` and `FindPanelView` are the rewrite targets — iPad gets a SwiftUI inline find bar over the keyboard, driven by the same `TextFinder`.
