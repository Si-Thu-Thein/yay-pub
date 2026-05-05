#if os(macOS)
import AppKit
import PDFKit
import WebKit
import YayPreview

@MainActor
public final class MarkdownPDFExporter: NSObject {

    private var webView: WKWebView?
    private var offscreenWindow: NSWindow?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var outputURL: URL?
    private var timeoutTimer: Timer?
    private var headerText: String
    private var headerAlign: Int
    private var footerText: String
    private var footerAlign: Int
    private var fileName: String
    private var pdfFontFamily: String
    private var pdfFontSize: CGFloat
    private var pdfLineHeight: CGFloat
    private var baseURL: URL?
    private var pageSize = CGSize(width: 595, height: 842)

    private static let sentinelRegex = try! NSRegularExpression(
        pattern: "<!--SLINE:\\d+-->\\n?"
    )

    public init(
        headerText: String = "",
        headerAlign: Int = 1,
        footerText: String = "",
        footerAlign: Int = 1,
        fileName: String = "",
        pdfFontFamily: String = "Georgia",
        pdfFontSize: CGFloat = 11,
        pdfLineHeight: CGFloat = 1.65
    ) {
        self.headerText = headerText
        self.headerAlign = headerAlign
        self.footerText = footerText
        self.footerAlign = footerAlign
        self.fileName = fileName
        self.pdfFontFamily = pdfFontFamily
        self.pdfFontSize = pdfFontSize
        self.pdfLineHeight = pdfLineHeight
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
        self.pageSize = pageSize

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
            size: CGSize(
                width: pageSize.width * scale,
                height: pageSize.height * scale
            )
        )
        let wv = WKWebView(frame: frame, configuration: config)
        self.webView = wv

        let win = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: frame.width, height: frame.height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.contentView?.addSubview(wv)
        win.alphaValue = 0
        win.orderBack(nil)
        self.offscreenWindow = win

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
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [self] in
                self.finish(result: result)
            }
            return
        }
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "renderComplete")
        offscreenWindow?.orderOut(nil)
        offscreenWindow = nil
        webView = nil

        if case .success(let url) = result {
            addHeaderFooter(to: url)
            completion?(.success(url))
        } else {
            completion?(result)
        }
        completion = nil
    }

    // MARK: - Header / Footer (PDFKit post-processing)

    private var hasHeader: Bool {
        !headerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasFooter: Bool {
        !footerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let marginSide: CGFloat = 50

    private func addHeaderFooter(to url: URL) {
        guard hasHeader || hasFooter else { return }

        guard let sourceDoc = PDFDocument(url: url),
              let firstPage = sourceDoc.page(at: 0) else { return }

        let pageWidth = firstPage.bounds(for: .mediaBox).width
        let pageHeight = firstPage.bounds(for: .mediaBox).height

        let outputData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: outputData as CFMutableData),
              let cgContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }

        let font = NSFont.systemFont(ofSize: 9)
        let color = NSColor.tertiaryLabelColor
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]

        for i in 0..<sourceDoc.pageCount {
            guard let page = sourceDoc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let pageNo = i + 1

            let resolve: (String) -> String = { text in
                text.replacingOccurrences(of: "{page_no}", with: "\(pageNo)")
                    .replacingOccurrences(of: "{file_name}", with: self.fileName)
            }

            cgContext.beginPDFPage([:] as CFDictionary)

            let nsCtx = NSGraphicsContext(cgContext: cgContext, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx

            page.draw(with: .mediaBox, to: cgContext)

            if hasHeader {
                let y = bounds.height - 20
                drawAligned(resolve(headerText), align: headerAlign, y: y, bounds: bounds, attrs: attrs)
            }

            if hasFooter {
                let y: CGFloat = 10
                drawAligned(resolve(footerText), align: footerAlign, y: y, bounds: bounds, attrs: attrs)
            }

            NSGraphicsContext.restoreGraphicsState()
            cgContext.endPDFPage()
        }

        cgContext.closePDF()

        guard let finalDoc = PDFDocument(data: outputData as Data) else { return }
        finalDoc.write(to: url)
    }

    private func drawAligned(
        _ text: String,
        align: Int,
        y: CGFloat,
        bounds: CGRect,
        attrs: [NSAttributedString.Key: Any]
    ) {
        guard !text.isEmpty else { return }
        let ns = text as NSString
        let w = ns.size(withAttributes: attrs).width
        let x: CGFloat
        switch align {
        case 0: x = Self.marginSide
        case 2: x = bounds.width - Self.marginSide - w
        default: x = (bounds.width - w) / 2
        }
        ns.draw(at: NSMakePoint(x, y), withAttributes: attrs)
    }

    // MARK: - Print CSS

    private func printCSS() -> String {
        let fontFamily = Self.cssFontFamily(pdfFontFamily)
        let fontSize = Self.clamped(pdfFontSize, min: 8, max: 72)
        let lineHeight = Self.clamped(pdfLineHeight, min: 1, max: 3)

        return """
    <style>
    body {
        font-family: \(fontFamily) !important;
        font-size: \(Self.cssNumber(fontSize))pt !important;
        line-height: \(Self.cssNumber(lineHeight)) !important;
        color: #1a1a1a !important;
        max-width: none !important;
        margin: 0 !important;
        padding: 0 !important;
        -webkit-hyphens: auto !important;
        hyphens: auto !important;
        hanging-punctuation: first last !important;
        text-rendering: optimizeLegibility !important;
        -webkit-font-smoothing: antialiased !important;
    }
    h1, h2, h3, h4, h5, h6 {
        font-family: -apple-system, 'Helvetica Neue', 'Segoe UI', sans-serif !important;
        font-weight: 700 !important;
        line-height: 1.25 !important;
        letter-spacing: -0.02em !important;
        color: #1a1a1a !important;
    }
    h1 { font-size: 22pt !important; margin-top: 36pt !important; margin-bottom: 12pt !important; }
    h2 { font-size: 16pt !important; margin-top: 28pt !important; margin-bottom: 8pt !important; }
    h3 { font-size: 13pt !important; margin-top: 22pt !important; margin-bottom: 6pt !important; }
    h4 { font-size: 11pt !important; margin-top: 18pt !important; margin-bottom: 6pt !important; }
    h5, h6 { font-size: 10pt !important; margin-top: 14pt !important; margin-bottom: 4pt !important; }
    p {
        margin: 0 0 9pt 0 !important;
        orphans: 3;
        widows: 3;
    }
    blockquote {
        margin: 12pt 0 !important;
        padding: 4pt 0 4pt 16pt !important;
        border-left: 2.5pt solid #d0d0d0 !important;
        color: #444 !important;
        font-style: italic !important;
    }
    ul, ol {
        margin: 6pt 0 !important;
        padding-left: 20pt !important;
    }
    li {
        margin-bottom: 3pt !important;
        orphans: 3;
        widows: 3;
    }
    hr {
        border: none !important;
        border-top: 0.5pt solid #c0c0c0 !important;
        margin: 24pt 0 !important;
    }
    code {
        font-family: 'SF Mono', 'Menlo', 'Consolas', monospace !important;
        font-size: 9pt !important;
        background: #f5f5f5 !important;
        padding: 1pt 4pt !important;
        border-radius: 2pt !important;
    }
    pre {
        margin: 12pt 0 !important;
        padding: 12pt 16pt !important;
        background: #fafafa !important;
        border: 0.5pt solid #e0e0e0 !important;
        border-radius: 4pt !important;
        font-size: 8.5pt !important;
        line-height: 1.55 !important;
        white-space: pre-wrap !important;
        word-break: break-word !important;
    }
    pre code {
        background: none !important;
        padding: 0 !important;
        font-size: inherit !important;
    }
    table {
        width: 100% !important;
        border-collapse: collapse !important;
        margin: 12pt 0 !important;
        font-size: 9.5pt !important;
    }
    th, td {
        border: 0.5pt solid #d0d0d0 !important;
        padding: 6pt 10pt !important;
    }
    th {
        background: #f5f5f5 !important;
        font-weight: 600 !important;
    }
    a {
        color: inherit !important;
        text-decoration: none !important;
    }
    img {
        max-width: 100% !important;
        max-height: 600pt !important;
    }
    pre.mermaid {
        text-align: center !important;
        margin: 16pt 0 !important;
    }
    .mermaid svg {
        max-width: 100% !important;
        height: auto !important;
    }
    .math-display {
        text-align: center !important;
        margin: 16pt 0 !important;
        overflow-x: auto !important;
    }
    .math-inline {
        display: inline-block !important;
        margin-right: 0.3em !important;
        vertical-align: baseline !important;
    }
    p, li, blockquote, pre, figure,
    h1, h2, h3, h4, h5, h6,
    table, .mermaid, .math-display {
        break-inside: avoid;
        page-break-inside: avoid;
    }
    h1, h2, h3, h4, h5, h6 {
        break-after: avoid;
        page-break-after: avoid;
    }
    table { break-inside: auto; }
    tr { break-inside: avoid; }
    </style>
    """
    }

    private static func cssFontFamily(_ family: String) -> String {
        let trimmed = family.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = trimmed.isEmpty ? "Georgia" : trimmed
        let escaped = primary
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)', 'Noto Serif', 'Times New Roman', serif"
    }

    private static func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
    }

    private static func cssNumber(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    // MARK: - Render-complete detection

    private static let renderCompleteJS = """
    (async function() {
        if (document.readyState !== 'complete' && document.readyState !== 'interactive') {
            await new Promise(function(r) { document.addEventListener('DOMContentLoaded', r); });
        }
        await new Promise(function(r) { setTimeout(r, 100); });
        var waited = 0;
        while (waited < 10000) {
            var pending = document.querySelectorAll('pre.mermaid');
            var hasPending = false;
            for (var i = 0; i < pending.length; i++) {
                if (pending[i].textContent.trim().length > 0) {
                    hasPending = true;
                    break;
                }
            }
            if (!hasPending) break;
            await new Promise(function(r) { setTimeout(r, 100); });
            waited += 100;
        }
        await new Promise(function(r) { requestAnimationFrame(r); });
        await new Promise(function(r) { requestAnimationFrame(r); });
        try {
            window.webkit.messageHandlers.renderComplete.postMessage('done');
        } catch(e) {}
    })();
    """
}

// MARK: - WKScriptMessageHandler

extension MarkdownPDFExporter: WKScriptMessageHandler {

    public func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "renderComplete",
              let wv = webView,
              let win = offscreenWindow,
              let url = outputURL else { return }

        DispatchQueue.main.async {
            self.runPrintOperation(webView: wv, window: win, saveTo: url, pageSize: self.pageSize)
        }
    }

    private func runPrintOperation(
        webView: WKWebView,
        window: NSWindow,
        saveTo url: URL,
        pageSize: CGSize
    ) {
        let printInfo = NSPrintInfo()
        printInfo.paperSize = pageSize
        printInfo.topMargin = hasHeader ? 54 : 36
        printInfo.bottomMargin = hasFooter ? 54 : 36
        printInfo.leftMargin = 50
        printInfo.rightMargin = 50
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic

        printInfo.dictionary().addEntries(from: [
            NSPrintInfo.AttributeKey.jobDisposition: NSPrintInfo.JobDisposition.save,
            NSPrintInfo.AttributeKey.jobSavingURL: url
        ])

        let op = webView.printOperation(with: printInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false

        op.view?.frame = CGRect(origin: .zero, size: printInfo.paperSize)

        op.runModal(for: window, delegate: self,
                    didRun: #selector(printDidRun(_:success:context:)),
                    contextInfo: nil)
    }

    @objc private func printDidRun(
        _ op: NSPrintOperation,
        success: Bool,
        context: UnsafeMutableRawPointer?
    ) {
        finish(result: success
            ? .success(outputURL!)
            : .failure(ExportError.printFailed))
    }
}

#endif
