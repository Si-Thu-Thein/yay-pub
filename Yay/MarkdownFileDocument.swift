import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class MarkdownDocument: NSDocument, ObservableObject {
    var text = "" {
        willSet { objectWillChange.send() }
        didSet {
            if text != oldValue {
                updateChangeCount(.changeDone)
            }
        }
    }

    override nonisolated static var autosavesInPlace: Bool { true }

    override static var readableTypes: [String] { [mdTypeName] }
    override static var writableTypes: [String] { [mdTypeName] }

    private static var mdTypeName: String {
        if let id = UTType(filenameExtension: "md")?.identifier { return id }
        if let id = UTType("net.daringfireball.markdown")?.identifier { return id }
        return UTType.plainText.identifier
    }

    // MARK: - Read / Write

    override func read(from data: Data, ofType typeName: String) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
        updateChangeCount(.changeCleared)
    }

    override func data(ofType typeName: String) throws -> Data {
        text.data(using: .utf8) ?? Data()
    }

    // MARK: - Window Controllers

    override func makeWindowControllers() {
        // Remove the old shared autosave frame that previous builds may have stored.
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame YayDocumentWindow")

        let contentView = ContentViewDocument(document: self)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let autosaveName = fileURL.map { "YayDoc-\(abs($0.path.hashValue))" } ?? ""
        if autosaveName.isEmpty || !window.setFrameUsingName(autosaveName) {
            window.center()
        }
        if !autosaveName.isEmpty {
            window.setFrameAutosaveName(autosaveName)
        }
        window.contentView = NSHostingView(rootView: contentView)
        let wc = NSWindowController(window: window)
        addWindowController(wc)
    }

    // MARK: - State Restoration

    override func encodeRestorableState(with coder: NSCoder, backgroundQueue queue: OperationQueue) {
        super.encodeRestorableState(with: coder, backgroundQueue: queue)
        if fileURL == nil {
            coder.encode(text, forKey: "text")
        }
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        if coder.containsValue(forKey: "text"),
           let restored = coder.decodeObject(of: NSString.self, forKey: "text") as? String {
            text = restored
        }
        // super.restoreState applies the saved window frame (from the previous session),
        // which may be at an off-center position. For untitled windows we always want
        // a fresh centered position, so override it here after restoration.
        if fileURL == nil {
            windowControllers.forEach { $0.window?.center() }
        }
    }

    // MARK: - Close Behavior

    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        if fileURL == nil && text.isEmpty {
            if let sel = shouldCloseSelector, let obj = delegate as? NSObject {
                let imp = obj.method(for: sel)
                typealias Fn = @convention(c) (NSObject, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
                unsafeBitCast(imp, to: Fn.self)(obj, sel, self, true, contextInfo)
            }
            return
        }
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }
}
