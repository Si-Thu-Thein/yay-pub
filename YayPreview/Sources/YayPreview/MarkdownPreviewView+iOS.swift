#if os(iOS)
import SwiftUI
import UIKit
import WebKit
import YayCore

//
//  MarkdownPreviewView+iOS.swift
//  Yay (iPad port — Phase 2)
//
//  iOS counterpart to MarkdownPreviewView+macOS.swift. Same WKWebView-backed
//  HTML preview, exposed as a UIViewRepresentable. Reuses MarkdownRenderer,
//  LocalFileSchemeHandler, and the JS body-swap fast-path unchanged.
//

public struct MarkdownPreviewView: UIViewRepresentable {
    let markdown: String
    let theme: MarkdownTheme
    let baseURL: URL?
    let scrollSync: ScrollSyncBridge?

    public init(
        markdown: String,
        theme: MarkdownTheme = .standard,
        baseURL: URL? = nil,
        scrollSync: ScrollSyncBridge? = nil
    ) {
        self.markdown = markdown
        self.theme = theme
        self.baseURL = baseURL
        self.scrollSync = scrollSync
    }

    public func makeUIView(context: Context) -> WKWebView {
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
        // bounces = false: rubber-band overscroll would push the JS scroll-sync
        // line numbers past the document end and feed out-of-range values to
        // ScrollSyncBridge.previewScrolled. Matches the macOS NSScrollView path
        // (which does not rubber-band by default).
        webView.scrollView.bounces = false
        webView.backgroundColor = .clear
        webView.isOpaque = false

        context.coordinator.webView = webView
        context.coordinator.attach(scrollSync: scrollSync)

        let renderer = context.coordinator.renderer(for: theme)
        let html = renderer.render(markdown)
        context.coordinator.loadHTML(html, into: webView, baseURL: baseURL)
        context.coordinator.lastRenderedMarkdown = markdown

        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.attach(scrollSync: scrollSync)
        guard context.coordinator.lastRenderedMarkdown != markdown else { return }
        context.coordinator.lastRenderedMarkdown = markdown

        let renderer = context.coordinator.renderer(for: theme)

        if context.coordinator.isPageLoaded {
            let bodyHTML = renderer.renderBody(markdown)
            if let data = try? JSONEncoder().encode(bodyHTML),
               let jsonString = String(data: data, encoding: .utf8) {
                webView.evaluateJavaScript("updateContent(\(jsonString))", completionHandler: nil)
            }
        } else {
            let html = renderer.render(markdown)
            context.coordinator.loadHTML(html, into: webView, baseURL: baseURL)
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

        public func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "scrollSync",
                  let line = (message.body as? NSNumber)?.intValue,
                  let scrollSync else { return }
            guard !scrollSync.isSyncing else { return }
            scrollSync.previewScrolled.send(line)
        }

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

        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

#endif
