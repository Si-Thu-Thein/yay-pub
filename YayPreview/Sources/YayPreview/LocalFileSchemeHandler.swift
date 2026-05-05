import Foundation
import WebKit

//
//  LocalFileSchemeHandler.swift
//  Yay
//
//  Cross-platform WKURLSchemeHandler that serves files under a fixed base
//  directory. Used by MarkdownPreviewView on both macOS and iOS so that
//  relative image / asset references in the user's Markdown resolve to
//  the document's parent directory while keeping the WKWebView sandboxed
//  to that directory (no escapes via "../").
//

public let localScheme = "yay-local"

public final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    public let baseDirectory: URL

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "LocalFileSchemeHandler", code: -1))
            return
        }

        let fileURL = URL(fileURLWithPath: url.path)

        guard fileURL.standardized.path.hasPrefix(baseDirectory.standardized.path) else {
            urlSchemeTask.didFailWithError(NSError(domain: "LocalFileSchemeHandler", code: 403))
            return
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(NSError(domain: "LocalFileSchemeHandler", code: 404))
            return
        }

        let mime = Self.mimeType(for: fileURL.pathExtension)
        let response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        case "ico": return "image/x-icon"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}
