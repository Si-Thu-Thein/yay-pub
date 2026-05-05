# Editor themes

JSON theme files loaded at runtime by `MarkdownTheme` (in `YayCore`) to colour the editor. Each file describes colours and font weights for tree-sitter syntax categories (headers, code, links, blockquotes, etc.).

## Adding a theme
1. Drop a new `<name>.json` file here following the schema of the existing `light.json`.
2. Add the file to the `Yay` target's "Copy Bundle Resources" build phase.
3. Wire it into the theme picker in `SettingsView.swift`.

## Format
See `light.json` for the canonical structure. Colour values are hex strings (e.g. `#1F2328`); fonts are referenced by Postscript name + size.

Themes are macOS-side resources today. When the iPad target is added, the same JSON files will be reused — `MarkdownTheme` already abstracts the colour/font types behind `PlatformColor`/`PlatformFont` (Phase 0 of the iPad port).
