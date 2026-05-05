#if os(iOS)
import Foundation
import UIKit
import WebKit
import YayPreview

//
//  MarkdownPDFExporter+iOS.swift
//  Yay (iPad port — Phase 2)
//
//  iOS counterpart to the macOS exporter. Renders Markdown through
//  YayPreview's MarkdownRenderer into an offscreen WKWebView and captures
//  the result via WKWebView.createPDF (iOS 14+).
//
//  Phase 2 scope:
//    - PDF generation works end-to-end.
//    - Header / footer overlays (NSGraphicsContext-based on macOS) are
//      NOT supported here yet. Those become a Phase 5 polish item once
//      the iPad app target lets us drive UIPrintInteractionController-
//      based or PDFKit-based post-processing as a separate pass.
//

@MainActor
public final class MarkdownPDFExporter: NSObject {

    private var webView: WKWebView?
    private var hostWindow: UIWindow?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var outputURL: URL?
    private var timeoutTimer: Timer?
    private let pdfFontFamily: String
    private let pdfFontSize: CGFloat
    private let pdfLineHeight: CGFloat
    private var baseURL: URL?

    private static let sentinelRegex = try! NSRegularExpression(
        pattern: "<!--SLINE:\\d+-->\\n?"
    )

    public init(
        // Header/footer parameters are accepted for API parity with the macOS
        // exporter but are ignored on iOS for Phase 2. Phase 5 polish wires
        // them up via PDFKit post-processing.
        headerText: String = "",
        headerAlign: Int = 1,
        footerText: String = "",
        footerAlign: Int = 1,
        fileName: String = "",
        pdfFontFamily: String = "Georgia",
        pdfFontSize: CGFloat = 11,
        pdfLineHeight: CGFloat = 1.65
    ) {
        self.pdfFontFamily = pdfFontFamily
        self.pdfFontSize = pdfFontSize
        self.pdfLineHeight = pdfLineHeight
        _ = (headerText, headerAlign, footerText, footerAlign, fileName)
    }

    public func export(
        markdown: String,
        to outputURL: URL,
        baseURL: URL? = nil,
        pageSize: CGSize = CGSize(width: 595, height: 842),
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.outputURL = outputURL
        self.completion = completion
        self.baseURL = baseURL

        let renderer = MarkdownRenderer()
        var html = renderer.render(markdown)

        html = Self.sentinelRegex.stringByReplacingMatches(
            in: html,
            range: NSRange(location: 0, length: (html as NSString).length),
            withTemplate: ""
        )
        html = html.replacingOccurrences(of: "</head>", with: printCSS() + "</head>")

        let config = WKWebViewConfiguration()
        if let baseURL, baseURL.isFileURL {
            let handler = LocalFileSchemeHandler(baseDirectory: baseURL)
            config.setURLSchemeHandler(handler, forURLScheme: "yay-local")
        }
        config.userContentController.add(self, name: "renderComplete")
        config.userContentController.addUserScript(WKUserScript(
            source: Self.renderCompleteJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let scale: CGFloat = 96.0 / 72.0
        let frame = CGRect(
            origin: .zero,
            size: CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        )
        let wv = WKWebView(frame: frame, configuration: config)
        self.webView = wv

        // Host the WKWebView in a UIWindow so it goes through the normal
        // layout/render pipeline. iOS does not allow PDF capture from a
        // detached web view. The window stays unhidden but is not key,
        // so it is part of the scene's rendering tree but doesn't steal
        // input focus or briefly composite above the user's UI (calling
        // makeKeyAndVisible() here would cause a one-frame flash).
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let window: UIWindow
        if let scene {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: frame)
        }
        window.frame = frame
        window.addSubview(wv)
        window.isHidden = false
        self.hostWindow = window

        if let baseURL, baseURL.isFileURL {
            var components = URLComponents()
            components.scheme = "yay-local"
            var path = baseURL.path
            if !path.hasSuffix("/") { path += "/" }
            components.path = path
            wv.loadHTMLString(html, baseURL: components.url)
        } else {
            wv.loadHTMLString(html, baseURL: nil)
        }

        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finish(result: .failure(ExportError.timeout))
            }
        }
    }

    public func exportAsync(markdown: String, to url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.export(markdown: markdown, to: url) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func finish(result: Result<URL, Error>) {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "renderComplete")
        hostWindow?.isHidden = true
        hostWindow = nil
        webView = nil
        completion?(result)
        completion = nil
    }

    // MARK: - JS bridge

    private static let renderCompleteJS = """
    (function() {
        function notifyDone() {
            window.webkit.messageHandlers.renderComplete.postMessage("done");
        }
        if (document.readyState === "complete") {
            setTimeout(notifyDone, 100);
        } else {
            window.addEventListener("load", function() { setTimeout(notifyDone, 100); });
        }
    })();
    """

    // MARK: - Print CSS

    private func printCSS() -> String {
        let cssFontFamily = pdfFontFamily.contains(" ") ? "\"\(pdfFontFamily)\"" : pdfFontFamily
        return """
        <style>
            @media print {
                body {
                    font-family: \(cssFontFamily), serif;
                    font-size: \(pdfFontSize)pt;
                    line-height: \(pdfLineHeight);
                }
            }
        </style>
        """
    }
}

extension MarkdownPDFExporter: WKScriptMessageHandler {
    public nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor [weak self] in
            self?.captureToPDF()
        }
    }

    @MainActor
    private func captureToPDF() {
        guard let webView, let outputURL else {
            finish(result: .failure(ExportError.printFailed))
            return
        }

        let configuration = WKPDFConfiguration()
        configuration.rect = nil  // entire content

        webView.createPDF(configuration: configuration) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: outputURL)
                        self.finish(result: .success(outputURL))
                    } catch {
                        self.finish(result: .failure(error))
                    }
                case .failure(let error):
                    self.finish(result: .failure(error))
                }
            }
        }
    }
}

#endif
