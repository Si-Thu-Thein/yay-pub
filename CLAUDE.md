# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Yay is a native macOS Markdown editor (SwiftUI shell, AppKit/TextKit editor) with tree-sitter syntax highlighting and a WKWebView live preview. App target requires macOS 15.4 (per `Yay.xcodeproj`); the SPM packages declare `.macOS(.v12)` so they remain reusable, but the host app will not run below 15.4. Build with Xcode 16+.

An **iPad port is planned** — see [`IPAD_PORT_PLAN.md`](IPAD_PORT_PLAN.md). The strategy is one repo, shared SPM packages with `#if`-gated platform code, and a separate `YayiPad` Xcode app target. iPhone is a later phase.

## Common commands

```bash
# Open in Xcode (then Cmd+R to build & run)
open Yay.xcodeproj

# Release build + DMG (output: Yay.dmg or Yay-<version>.dmg)
./build.sh            # Yay.dmg
./build.sh 1.2.3      # Yay-1.2.3.dmg

# Plain xcodebuild (Debug)
xcodebuild -project Yay.xcodeproj -scheme Yay -configuration Debug build

# Build a single SPM package in isolation (useful for fast iteration on YayCore/YayTextEditor/YayPreview/YayExport)
cd YayTextEditor && swift build
```

Each SPM package declares its own test target (`YayCoreTests`, `YayPreviewTests`, `YayTextEditorTests`). Run them per-package with `cd <Package> && swift test`. The Xcode app targets (`Yay`, `YayiPad`) have no test targets, so `xcodebuild test` against the project will fail — use the SPM test invocation instead.

`build.sh` always builds **arch=arm64**, ad-hoc signs (`CODE_SIGN_IDENTITY="-"`), disables hardened runtime, and stages into a temp dir before `hdiutil create`. The resulting DMG is unsigned, which is why README tells users to right-click → Open on first launch.

## Architecture

The app is split into the Xcode app target (`Yay/`) plus four local Swift packages wired in by relative path. Dependency direction is strictly:

```
YayExport ──► YayPreview ──► YayCore
              YayTextEditor ──► YayCore + tree-sitter
Yay (app)  ──► all of the above
```

Treat `YayCore` as the only place that may be imported by every other module. Do not introduce reverse edges (e.g. YayCore depending on YayPreview) — it will break the SPM graph.

### YayCore — shared types only
Pure Swift, no UI. Holds `MarkdownTheme`, `VSCodeTheme`, and `ScrollSyncBridge` (the `ObservableObject` that lets the editor and preview share scroll position). When adding a type that both the editor and preview need to talk about, it belongs here.

### YayTextEditor — the editor (TextKit 1 + tree-sitter)
- `MarkdownNSTextView` + `MarkdownLayoutManager`: custom `NSTextView` subclass; intentionally TextKit 1 (not TextKit 2) because tree-sitter byte-offset highlighting and incremental edits are wired against `NSLayoutManager`.
- `TreeSitterHighlighter`: parses with tree-sitter-markdown via `SwiftTreeSitter`; `CodeSyntaxHighlighter` + `LanguageDefinition` handle fenced-code-block highlighting for ~30 languages.
- `YayTextEditor.swift`: the public `NSViewRepresentable` consumed by the SwiftUI app.
- `Search/`: self-contained Find panel (`FindPanelController`/`FindPanelView` drive `TextFinder` over a `TextFind` model). It is not Apple's `NSTextFinder` — keep find logic inside this folder.

### YayPreview — WKWebView renderer
`MarkdownRenderer` produces HTML; `MarkdownPreviewView` hosts it in WKWebView. JS/CSS assets (highlight.js core + per-language `lang_*.js` shards, KaTeX, Mermaid, GitHub CSS) live in `Sources/YayPreview/Resources/` and are loaded as `.process("Resources")` bundle resources. **Do not** rename or move those files without also updating the resource loader — they are referenced by exact filename.

### YayExport — PDF/HTML export
`MarkdownExportContext` + `MarkdownPDFExporter`. Reuses `YayPreview`'s renderer to keep export output visually identical to the live preview. If you change preview rendering, exports will follow automatically — that is intentional.

### Yay (app target)
SwiftUI `DocumentGroup` for `.md` files (`MarkdownFileDocument`). Folder-mode UI (`FolderSidebar`, `FolderWorkspaceView`, `FolderEntry`, `FileWatcher`) lets the user open a directory and browse it as a workspace alongside the document-based flow. `themes/light.json` is the editor color theme loaded by `MarkdownTheme`.

## Conventions

- Editor lives in TextKit 1 by design — do not "modernize" to TextKit 2 without a corresponding plan for tree-sitter range mapping and the custom layout manager. (This choice also enables the iPad port: `NSLayoutManager` is shared between AppKit and UIKit.)
- `Yay.entitlements` is a sandboxed, user-selected-files config; new file/network capabilities must be added there explicitly.
- `.gitignore` excludes `.claude/`, `AGENTS.md`, `GEMINI.md`, `PACKAGES.md`, `skills/`, `opencode/`, `.opendev/`, and a few `*_TEST.md`/`*_EXAMPLE.md` scratch files — these are intentionally untracked working notes, not source. `CLAUDE.md` itself is **tracked** (this file).

## Workflow rules (mandatory)

These rules apply to all work on this repo, especially the iPad port:

- **Never commit to `main` directly.** Every change lands on a feature branch and is merged into `main` only after review. This is also enforced by a GitHub repository ruleset on `main` (PR required, `CI Passed` status check required, force-push and deletion blocked, no bypass actors).
- **Branch naming**: `phase-<N>/<short-slug>` for port phases (e.g. `phase-0/ios-platform-foundation`), or `feature/<short-slug>` / `fix/<short-slug>` otherwise.
- **Commits**: small, focused, imperative-tense subject ≤72 chars; body explains the *why*. Group related changes; don't bundle unrelated edits.
- **Definition of done** for a branch before it can be merged:
  1. `swift build` succeeds for every affected SPM package on every supported platform (`macOS`, and once Phase 0 lands, `iOS`).
  2. `xcodebuild build` succeeds for any affected app target.
  3. `swift test` passes for every package that has tests.
  4. New logic has unit tests where it is reasonable to write them (parsers, highlighters, range math, model classes — yes; trivial SwiftUI bindings — no).
- **Review before merge**: invoke the `feature-dev:code-reviewer` subagent on the branch diff. Only merge if it raises **no high-confidence (≥75) issues** that aren't addressed. Capture the reviewer's verdict in the merge commit body or PR comment.
- **Remote**: `origin` → `Si-Thu-Thein/yay-pub` (public mirror, SSH). Push feature branches and open PRs via `gh pr create --base main`. Use squash-merge or merge commits — not rebase-merge — so the review trail stays attached to the PR.
- **CI**: `.github/workflows/ci.yml` runs path-filtered per-package `swift build`/`swift test` jobs on `macos-latest` for both macOS and iOS Simulator destinations, plus `xcodebuild` builds of the `Yay` and `YayiPad` app targets. A `CI Passed` aggregator job depends on all of them with `if: always()` and is the single required status check on `main`. Keep it green. Add jobs as platforms or packages are added (and update the aggregator's `needs:` list when you do).
- **Tests live next to their package**: `YayCore/Tests/YayCoreTests/`, etc. Each `Package.swift` declares its test target.
- **Per-directory `README.md`**: every meaningful source directory has a `README.md` describing its contents and any directory-specific conventions. Keep them short (≤30 lines). Update them when the directory's purpose changes. Skip generated/scaffolding dirs only (`*.xcodeproj`, `*.xcassets`, `*.icon`, `build/`, `.swiftpm/`, `.git/`). Note: `Yay/` is a **synchronized Xcode folder**, so any new README.md inside it must also be added to `membershipExceptions` in `Yay.xcodeproj/project.pbxproj` to keep it out of the app bundle.

## Cross-platform conventions

Phases 0–3 of the iPad port have landed: the four SPM packages compile for both macOS and iOS, `YayiPad` is a working app target, and CI builds both apps on every PR. These rules apply to every change in `YayCore`/`YayTextEditor`/`YayPreview`/`YayExport`:

- **Do not import `AppKit` directly** in shared code. Use `PlatformColor`/`PlatformFont`/`PlatformView` typealiases from `YayCore`, or gate AppKit usage with `#if os(macOS)`.
- **`MarkdownLayoutManager` and the highlighters must remain platform-neutral** — they are the load-bearing shared code for both targets.
- **New view code goes in paired files**: `Foo+macOS.swift` (`NSViewRepresentable`) and `Foo+iOS.swift` (`UIViewRepresentable`), with a thin platform-neutral `Foo.swift` choosing between them.
- The macOS `Yay/` app target stays mac-only — do not add iOS code there. The iPad target is a separate `YayiPad/` directory.
