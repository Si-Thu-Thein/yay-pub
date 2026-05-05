# Yay ရေး

A native Markdown editor for macOS and iPadOS with syntax highlighting powered by tree-sitter.

![](./assets/icon.png)

## Features

- **Tree-sitter highlighting** — fast, incremental parsing for all markdown structure
- **Code syntax highlighting** — 30+ languages in fenced code blocks
- **Live preview** — Mermaid diagrams and LaTeX math
- **Export** — PDF and HTML (macOS only — see status below)
- **Cross-platform** — single shared core, native macOS app and iPad app

## Status

| Target | Status |
|---|---|
| **Yay (macOS)** | Original. Builds and ships. Requires macOS 15.4. |
| **YayiPad (iPad)** | MVP. Builds, runs in iOS Simulator. iPad-only, requires iPadOS 16. Find UI, folder workspace, and PDF export header/footer overlays not yet implemented (Phase 4–5 of the port plan — see [`IPAD_PORT_PLAN.md`](IPAD_PORT_PLAN.md)). |
| **iPhone** | Planned, deferred until iPad ships. |

## Download

The macOS app ships as a DMG from [Releases](../../releases).

> The app is unsigned, so macOS will block it on first open. Right-click the app → **Open** to bypass Gatekeeper.

The iPad target is currently source-only. Open `Yay.xcodeproj` and select the **YayiPad** scheme to build and run in the iOS Simulator.

## Build from Source

Requires Xcode 16+.

```bash
git clone https://github.com/saturngod/yay.git
cd yay
open Yay.xcodeproj
```

| Scheme | Platform | Cmd+R |
|---|---|---|
| **Yay** | macOS 15.4+ | Builds the existing macOS app. |
| **YayiPad** | iPadOS 16+ | Builds the iPad app into the iOS Simulator. |

For a Release-mode macOS DMG: `./build.sh` (or `./build.sh 1.2.3` to tag the output).

## Architecture

The repo is one Xcode project with two app targets sharing four local Swift Packages. Dependency direction is strictly one-way; `YayCore` is the only module every other module may import.

```
YayExport ──► YayPreview ──► YayCore
              YayTextEditor ──► YayCore + tree-sitter
Yay (macOS app)  ──► all of the above
YayiPad (iPad app) ──► all of the above
```

| Package | Description |
|---|---|
| **YayCore** | Shared types (`MarkdownTheme`, `VSCodeTheme`, `ScrollSyncBridge`) and platform typealiases (`PlatformColor`, `PlatformFont`, `PlatformView`). |
| **YayTextEditor** | Live editor: TextKit 1 + tree-sitter. `MarkdownNSTextView` for macOS, `MarkdownUITextView` for iPad. |
| **YayPreview** | WKWebView HTML preview with highlight.js + KaTeX + Mermaid. Same renderer drives the macOS and iPad views. |
| **YayExport** | PDF/HTML export. macOS path uses an offscreen window + PDFKit post-processing for header/footer overlays; iOS path uses `WKWebView.createPDF` directly (overlays deferred). |

## Libraries

- [SwiftTreeSitter](https://github.com/tree-sitter/swift-tree-sitter)
- [TreeSitter](https://github.com/tree-sitter/tree-sitter)
- [TreeSitterMarkdown](https://github.com/tree-sitter-grammars/tree-sitter-markdown)
- [highlight.js](https://highlightjs.org/), [KaTeX](https://katex.org/), [Mermaid](https://mermaid.js.org/) (bundled in `YayPreview/Sources/YayPreview/Resources/`)
