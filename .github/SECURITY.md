# Security Policy

## Reporting a Vulnerability

If you believe you have found a security issue in Yay, **please do not open a public GitHub issue**. Instead, use GitHub's private vulnerability reporting:

1. Go to the [Security tab](../../security) of this repository.
2. Click **Report a vulnerability**.
3. Fill in the form. The maintainer will respond as soon as possible.

If for any reason GitHub's private reporting isn't available to you, you can email the maintainer directly via the email listed on the [@Si-Thu-Thein GitHub profile](https://github.com/Si-Thu-Thein).

## What counts as a security issue

- Sandbox escapes from the WKWebView preview (e.g. a crafted `.md` file that causes the `yay-local://` scheme handler to serve a file outside the document's base directory; the handler today blocks this with a `standardized.path.hasPrefix` check, so any way to bypass that check is a security issue).
- Code-execution vulnerabilities triggered by opening or editing a Markdown document.
- Data leakage from the editor or preview to unintended destinations.
- Memory-corruption issues exploitable by malformed input.

## What is *not* a security issue

- Visual rendering glitches in the preview.
- Editor performance issues with very large documents.
- Missing features described in [`IPAD_PORT_PLAN.md`](../IPAD_PORT_PLAN.md).
- Issues in upstream dependencies — please report those to the upstream project (tree-sitter-markdown, highlight.js, KaTeX, Mermaid).

## Supported versions

Yay is a single-developer project. Only the `main` branch is actively maintained; older releases will not receive security backports.
