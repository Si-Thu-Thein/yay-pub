# iPad Port Plan

Step-by-step plan to port Yay to iPadOS while keeping the existing macOS app shipping. iPhone support is **Phase 2** (not in scope below).

## Strategy

- Keep one repo, one set of SPM packages. Make `YayCore` / `YayTextEditor` / `YayPreview` / `YayExport` truly cross-platform via conditional compilation, so both apps consume the same modules.
- Add a new **`YayiPad`** Xcode app target alongside the existing `Yay` (macOS) target. Both targets share the SPM packages; each has its own SwiftUI app entry point.
- Target **iPadOS 15.0+** initially (matches the existing `.macOS(.v12)` floor on packages and the iOS minimum where `WKWebView.createPDF` and `NavigationSplitView`-equivalent paths are reasonable). Bump only if needed.
- TextKit 1 + `NSLayoutManager` is shared between AppKit and UIKit — the editor's tree-sitter wiring transfers. Do not replace `NSLayoutManager` during the port.

## Phase 0 — Cross-platform foundation (3–5 days)

Make every SPM package compile for iOS without yet introducing iOS UI.

1. **Add iOS as a supported platform** in each `Package.swift`:
   ```swift
   platforms: [.macOS(.v12), .iOS(.v15)]
   ```
   for `YayCore`, `YayTextEditor`, `YayPreview`, `YayExport`.

2. **Introduce platform typealiases in `YayCore`**:
   - New file `Platform.swift` exposing `PlatformColor`, `PlatformFont`, `PlatformView`, `PlatformViewController`, `PlatformImage`, mapped to `NS*` on macOS and `UI*` on iOS via `#if canImport(AppKit)` / `#if canImport(UIKit)`.
   - Migrate `MarkdownTheme.swift` and `VSCodeTheme.swift` from `NSColor`/`NSFont` to the typealiases.

3. **Wrap AppKit-only call sites** in `#if os(macOS)` blocks across `YayTextEditor`. Anything that imports `AppKit` and is not the editor view itself (highlighter, layout manager, language defs, find model) should become platform-neutral or `#if`-gated.

4. **Verify**: `swift build` succeeds for each package on macOS, and a one-off iOS build (e.g. via `xcodebuild -scheme YayCore -destination 'generic/platform=iOS'`) succeeds.

Exit criteria: all four packages compile clean for both platforms; existing macOS app still runs unchanged.

## Phase 1 — Editor on iOS (1–2 weeks)

The hardest phase. Port the text view while reusing the highlighter and layout manager untouched.

1. **`MarkdownLayoutManager`**: confirm it builds for iOS as-is (it should — `NSLayoutManager` is identical on both platforms). Move to a platform-neutral file if currently `#if`-gated.

2. **Create `MarkdownUITextView`** (sibling of `MarkdownNSTextView`):
   - `UITextView` subclass that installs `MarkdownLayoutManager` on its `NSLayoutManager`.
   - Bridge `UITextView`'s text storage to the same `NSTextStorage` flow the macOS view uses.
   - Forward edit notifications to `TreeSitterHighlighter` exactly as the macOS view does.

3. **`TreeSitterHighlighter` and `CodeSyntaxHighlighter`**: should compile unchanged once Phase 0 is done; verify on iOS.

4. **Split `YayTextEditor.swift`** into:
   - `YayTextEditor+macOS.swift` — existing `NSViewRepresentable`.
   - `YayTextEditor+iOS.swift` — new `UIViewRepresentable` wrapping `MarkdownUITextView`.
   - `YayTextEditor.swift` — public `View` that picks the right representable via `#if`.

5. **Smoke test harness**: a minimal SwiftUI iPad preview that loads a sample `.md` string and shows the editor with highlighting.

Exit criteria: typing in the editor on an iPad simulator produces correct tree-sitter highlighting, including fenced code blocks.

## Phase 2 — Preview & export on iOS (2–3 days)

Mostly free — these modules are already close to platform-neutral.

1. **`MarkdownPreviewView`**: replace `NSViewRepresentable`/`WKWebView` host with `UIViewRepresentable` variant. JS message handlers and resource loading paths are identical.

2. **`MarkdownRenderer`**: should be unchanged.

3. **`MarkdownPDFExporter`**: confirm `WKWebView.createPDF(...)` works on iOS (it does, iOS 14+). Replace any `NSPrintOperation`-based fallback with `UIPrintInteractionController` if needed. `PDFKit` is identical on iOS.

4. **Verify**: live preview renders Mermaid diagrams and KaTeX math; PDF export from iPad produces a byte-identical (or near-identical) document to macOS.

Exit criteria: preview + PDF export both work on iPad.

## Phase 3 — App shell (1 week)

Build the new `YayiPad` target's SwiftUI app.

1. **New Xcode target `YayiPad`** with its own `Info.plist`, `Assets.xcassets`, entitlements file, and bundle id (`app.myanmars.Yay.iPad` or similar). Re-link to all four SPM packages.

2. **App entry point** (`YayiPadApp.swift`):
   - `@main struct YayiPadApp: App` with a `DocumentGroup` over the existing `MarkdownFileDocument`.
   - No mac `CommandGroup` / menu bar — replace with `.toolbar` items.

3. **Document UI**: a SwiftUI view containing the editor (`YayTextEditor`) and preview (`MarkdownPreviewView`) side-by-side using `NavigationSplitView` on iPad. Reuse `ScrollSyncBridge` from `YayCore` unchanged.

4. **Settings**: replace the macOS `Settings` scene with an in-app screen pushed from the toolbar. Reuse the body of `SettingsView.swift` where possible (most of it is plain SwiftUI).

5. **Recent documents**: drop `RecentDocumentsMenu` on iPad — `DocumentGroup` provides recents UI for free via the document browser.

Exit criteria: launch on iPad, open a `.md` file from Files app, see editor + preview, edit, save.

## Phase 4 — Find & Folder UX (1 week)

Both features need new UI but reuse existing models.

1. **Find UI**:
   - Reuse `TextFind`, `FindOptions`, `TextFinder` (the model + search engine) unchanged.
   - Build a new SwiftUI find bar (overlay above the keyboard) that drives `TextFinder`.
   - Wire `Cmd+F` (hardware keyboard) via `UIKeyCommand`.

2. **Folder workspace**:
   - Reuse `FolderEntry`, `FileWatcher` (DispatchSource works on iOS).
   - Replace `FolderSidebar` / `FolderWorkspaceView` with `NavigationSplitView` columns: sidebar (folder tree) → list (files) → detail (editor+preview).
   - Folder selection: `UIDocumentPickerViewController` in folder mode, returning a security-scoped URL. Persist via bookmark data.

Exit criteria: user can pick a folder, browse it in the sidebar, open files, and use find within an open document.

## Phase 5 — Polish & ship (3–5 days)

1. **Hardware keyboard shortcuts** via `UIKeyCommand` and SwiftUI `.keyboardShortcut`: save, find, toggle preview, new document.
2. **Multi-window support** (`UIScene`-based) so users can open two documents side-by-side.
3. **iCloud Drive / Files app integration** verified end-to-end.
4. **Stage Manager / Slide Over** layout sanity check.
5. **Code signing + provisioning profile** for the iPad target.
6. **TestFlight** internal build → external testers → App Store submission.

Exit criteria: shippable iPad build on TestFlight.

## Out of scope (Phase 2 — iPhone, separate effort)

- Responsive layouts: sidebar becomes a drawer/sheet, editor and preview tab between each other instead of split-view.
- iPhone-specific find UI (smaller screen, no hardware keyboard assumed).
- Touch refinements for one-handed use.
- Estimate when picked up: **+1–2 weeks** on top of a working iPad build.

## Total estimate

**3–5 weeks** for a single experienced developer through Phase 5 (shippable iPad build). Phase 0 + 1 dominate the schedule (~50% of the work); Phases 2–5 are mostly orchestration over modules that already work cross-platform.
