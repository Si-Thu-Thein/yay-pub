# YayiPad (iPad app target)

The SwiftUI app shell for the iPadOS build. Mirrors the macOS `Yay/` target with iPad-appropriate UI patterns: `DocumentGroup` over `FileDocument` (instead of macOS's `NSDocument`), `NavigationSplitView` for the editor + preview split, toolbar buttons in place of the macOS menu bar.

## Contents
- `YayiPadApp.swift` — `@main` entry point. SwiftUI `App` with a single `DocumentGroup`.
- `MarkdownFileDocument.swift` — `FileDocument` over `.md`. Distinct from `Yay/MarkdownFileDocument.swift` (which is an `NSDocument`); the two share only the file format, not the framework integration.
- `ContentView.swift` — editor (`YayTextEditor`) + preview (`MarkdownPreviewView`) wired through a shared `ScrollSyncBridge`. Layout uses `NavigationSplitView` on iPad.
- `Info.plist` — `UISupportsDocumentBrowser` enabled so the app participates in the iOS Files app and "Open In…" flow.
- `YayiPad.entitlements` — currently empty. Capabilities are added here as features land (iCloud Drive, etc.).
- `Assets.xcassets/` — minimal: `AppIcon` placeholder. Real artwork ships with Phase 5 polish.

## Conventions
- iPad-only chrome (toolbar buttons, navigation columns) lives here, not in the SPM packages.
- The macOS `Yay/` target stays mac-only; do not add iOS code there. Likewise, do not move iOS code into the macOS target's source dir.
- Both targets consume the same `YayCore` / `YayTextEditor` / `YayPreview` / `YayExport` packages.
