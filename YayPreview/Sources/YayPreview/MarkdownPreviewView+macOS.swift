#if os(macOS)
import SwiftUI
import WebKit
import YayCore

/// SwiftUI view that displays a live preview of Markdown content
public struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    let theme: MarkdownTheme
    let baseURL: URL?
    let scrollSync: ScrollSyncBridge?

    public init(markdown: String, theme: MarkdownTheme = .standard, baseURL: URL? = nil, scrollSync: ScrollSyncBridge? = nil) {
        self.markdown = markdown
        self.theme = theme
        self.baseURL = baseURL
        self.scrollSync = scrollSync
    }

    public func makeNSView(context: Context) -> NSView {
        let configuration = WKWebViewConfiguration()

        #if DEBUG
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        if let baseURL, baseURL.isFileURL {
            let handler = LocalFileSchemeHandler(baseDirectory: baseURL)
            configuration.setURLSchemeHandler(handler, forURLScheme: localScheme)
            context.coordinator.schemeHandler = handler
        }

        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "scrollSync")
        configuration.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.autoresizingMask = [.width, .height]

        let container = NSView()
        container.autoresizesSubviews = true
        webView.frame = container.bounds
        container.addSubview(webView)

        context.coordinator.webView = webView
        context.coordinator.attach(scrollSync: scrollSync)

        // Reuse one renderer across edits — `updateNSView` runs on every
        // keystroke, so allocating a fresh MarkdownRenderer each time would
        // re-do its setup (regex compilation, base64 of bundled JS/CSS).
        let renderer = context.coordinator.renderer(for: theme)

        // Initial full document load (includes all JS/CSS libraries)
        let html = renderer.render(markdown)
        context.coordinator.loadHTML(html, into: webView, baseURL: baseURL)
        context.coordinator.lastRenderedMarkdown = markdown

        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(scrollSync: scrollSync)
        guard context.coordinator.lastRenderedMarkdown != markdown else { return }
        context.coordinator.lastRenderedMarkdown = markdown

        let renderer = context.coordinator.renderer(for: theme)

        if context.coordinator.isPageLoaded {
            // Fast path: swap only body content via JavaScript (no full page reload)
            let bodyHTML = renderer.renderBody(markdown)
            if let data = try? JSONEncoder().encode(bodyHTML),
               let jsonString = String(data: data, encoding: .utf8) {
                context.coordinator.webView?.evaluateJavaScript(
                    "updateContent(\(jsonString))",
                    completionHandler: nil
                )
            }
        } else {
            // Page not ready yet — full reload
            let html = renderer.render(markdown)
            if let webView = context.coordinator.webView {
                context.coordinator.loadHTML(html, into: webView, baseURL: baseURL)
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastRenderedMarkdown: String?
        weak var webView: WKWebView?
        var isPageLoaded = false

        private var cachedRenderer: MarkdownRenderer?
        private var cachedRendererFont: PlatformFont?
        private var cachedRendererFontSize: CGFloat?
        private weak var scrollSync: ScrollSyncBridge?
        var schemeHandler: LocalFileSchemeHandler?

        deinit {}

        func loadHTML(_ html: String, into webView: WKWebView, baseURL: URL?) {
            let effectiveBaseURL: URL?
            if let baseURL, baseURL.isFileURL {
                var components = URLComponents()
                components.scheme = localScheme
                var path = baseURL.path
                if !path.hasSuffix("/") { path += "/" }
                components.path = path
                effectiveBaseURL = components.url
            } else {
                effectiveBaseURL = baseURL
            }
            webView.loadHTMLString(html, baseURL: effectiveBaseURL)
        }

        func attach(scrollSync: ScrollSyncBridge?) {
            guard let scrollSync, scrollSync !== self.scrollSync else { return }
            self.scrollSync = scrollSync
            scrollSync.scrollPreviewToLine = { [weak self] line in
                guard let self, let webView = self.webView, self.isPageLoaded else { return }
                webView.evaluateJavaScript(
                    "suppressScrollPosts(250); scrollToSourceLine(\(line))",
                    completionHandler: nil
                )
            }
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "scrollSync",
                  let line = (message.body as? NSNumber)?.intValue,
                  let scrollSync else { return }
            // Drop messages that arrive while we're driving the editor; they
            // are echoes of our own scrollToSourceLine call.
            guard !scrollSync.isSyncing else { return }
            scrollSync.previewScrolled.send(line)
        }

        /// Returns a `MarkdownRenderer` for `theme`, reusing the cached one
        /// when the font and font size are unchanged. Rebuilt only when the
        /// theme switches in a way that affects rendering (e.g. light/dark
        /// toggle in the future). MarkdownTheme isn't Equatable, so we key
        /// on the cheapest proxy that catches real theme changes.
        func renderer(for theme: MarkdownTheme) -> MarkdownRenderer {
            if let cached = cachedRenderer,
               cachedRendererFont == theme.baseFont,
               cachedRendererFontSize == theme.baseFontSize {
                return cached
            }
            let renderer = MarkdownRenderer(theme: theme)
            cachedRenderer = renderer
            cachedRendererFont = theme.baseFont
            cachedRendererFontSize = theme.baseFontSize
            return renderer
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true
        }

        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
}

// MARK: - Preview Helper
#if DEBUG
struct MarkdownPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        MarkdownPreviewView(
            markdown: """
            # Welcome to Yay

            This is a **markdown** preview with *syntax highlighting*.

            ```swift
            func hello() {
                print("Hello, World!")
            }
            ```

            - Syntax highlighting
            - Mermaid diagrams

            [Learn more](https://github.com)
            """,
            theme: MarkdownTheme.standard
        )
        .frame(width: 600, height: 800)
    }
}
#endif

#endif
