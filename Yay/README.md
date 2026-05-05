# Yay (macOS app target)

The SwiftUI app shell for the macOS build. **Mac-only** — do not add iOS code here; the iPad target lives in a separate `YayiPad/` directory once Phase 3 of the iPad port begins.

## Contents
- `YayApp.swift` — `@main` entry point. SwiftUI `App` with `DocumentGroup`, `WindowGroup`, command groups, and the Settings scene.
- `MarkdownFileDocument.swift` — `FileDocument` over `.md` files.
- `ContentView.swift` / `ContentViewDocument.swift` — the editor+preview split view for an open document.
- `FolderSidebar.swift`, `FolderWorkspaceView.swift`, `FolderEntry.swift`, `FileWatcher.swift` — folder-mode UI: open a directory, browse it as a workspace.
- `RecentDocumentsMenu.swift` — macOS menu bar recent documents (mac-only feature).
- `SettingsView.swift` — Preferences window content.
- `Yay.entitlements` — sandbox + user-selected-files. Add new file/network entitlements here explicitly.
- `Info.plist` — bundle metadata.
- `themes/` — bundled editor color themes (loaded by `MarkdownTheme`).
- `Assets.xcassets` — app icons and image assets.

## Conventions
- All UI in this directory is SwiftUI + AppKit interop. The custom editor view (`MarkdownNSTextView`) and the preview (`MarkdownPreviewView`) are imported from the SPM packages and wrapped in `NSViewRepresentable`s.
- New macOS-only chrome (menu commands, NSToolbar, NSWindow tweaks) belongs here, not in the SPM packages.
