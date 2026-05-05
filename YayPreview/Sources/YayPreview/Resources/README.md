# Resources

Bundled JS/CSS loaded by `MarkdownRenderer` into the preview WKWebView. Files are referenced by **exact filename** — do not rename or move without updating the renderer.

## Contents
- `highlight.core.min.js` — highlight.js core.
- `lang_*.js` — per-language highlighter shards (~30 languages: bash, cpp, csharp, css, go, java, javascript, json, kotlin, markdown, objectivec, php, python, ruby, rust, sql, swift, typescript, xml, yaml). Each shard is registered with highlight.js by filename.
- `katex.min.js`, `katex.min.css` — math rendering.
- `mermaid.min.js` — diagram rendering.
- `github.min.css` — base GitHub-style stylesheet for code blocks.

## Adding a language
1. Drop `lang_<name>.js` here from the highlight.js distribution.
2. Add the filename to the loader list in `MarkdownRenderer.swift`.
3. Add a `LanguageDefinition` entry in `YayTextEditor` if the editor should also highlight that language inside fenced code blocks.

## Updating versions
Track upstream versions in commit messages. Don't hand-edit minified output — replace the file wholesale.
