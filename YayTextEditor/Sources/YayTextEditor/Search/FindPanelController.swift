#if os(macOS)
import AppKit
import SwiftUI

@MainActor
public final class FindPanelController: NSWindowController, NSWindowDelegate {

    public static let shared = FindPanelController()

    let textFinder = TextFinder()

    private convenience init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 148),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.title = "Find & Replace"
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.minSize = NSSize(width: 400, height: 148)
        panel.maxSize = NSSize(width: 10000, height: 148)

        self.init(window: panel)
        panel.delegate = self

        let hosting = NSHostingView(rootView: FindPanelView(textFinder: textFinder))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(hosting)

        guard let contentView = panel.contentView else { return }
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: contentView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        windowFrameAutosaveName = "YayFindPanel"
    }

    public func showPanel() {
        guard let window else { return }
        textFinder.activateFocusedTextView()
        showWindow(nil)
        window.center()

        // Defer so SwiftUI finishes laying out the NSHostingView before we
        // traverse its subviews looking for the NSTextField.
        DispatchQueue.main.async {
            window.makeKey()
            if let field = self.findFirstTextField(in: window.contentView) {
                window.makeFirstResponder(field)
                field.selectText(nil)
            }
        }
    }

    public func hidePanel() {
        textFinder.clearHighlights()
        window?.performClose(nil)
    }

    public func attach(textView: NSTextView) {
        textFinder.attach(textView: textView)
    }

    public func performFindNext() {
        if !(window?.isVisible ?? false) { showPanel() }
        textFinder.performFind(forward: true)
    }

    public func performFindPrevious() {
        if !(window?.isVisible ?? false) { showPanel() }
        textFinder.performFind(forward: false)
    }

    public func windowWillClose(_ notification: Notification) {
        textFinder.clearHighlights()
    }

    private func findFirstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField { return field }
        for subview in view.subviews {
            if let found = findFirstTextField(in: subview) { return found }
        }
        return nil
    }
}

#endif
