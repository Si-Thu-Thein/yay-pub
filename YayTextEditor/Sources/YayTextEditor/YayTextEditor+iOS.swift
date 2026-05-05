#if os(iOS)
import SwiftUI
import UIKit
import YayCore

//
//  YayTextEditor+iOS.swift
//  Yay (iPad port — Phase 1)
//
//  UIViewRepresentable counterpart to the macOS YayTextEditor. Shares the
//  same public surface (`text`, `configuration`, `scrollSync`) so SwiftUI
//  call sites can stay platform-agnostic. Internally builds a TextKit-1
//  stack (NSTextStorage + MarkdownLayoutManager + NSTextContainer) and
//  hands it to MarkdownUITextView.
//
//  This is a Phase 1 MVP — sophisticated optimisations from the macOS
//  Coordinator (incremental highlighting, visible-range tracking, scroll
//  sync, find-panel attach) are deferred:
//    - Scroll sync arrives with the iOS preview in Phase 2.
//    - Find UI arrives in Phase 4.
//    - Visible-range / debounced highlighting is a Phase-1.5 polish pass.
//

public struct YayTextEditor: UIViewRepresentable {
    @Binding var text: String
    public var configuration: YayEditorConfiguration = .standard
    public var scrollSync: ScrollSyncBridge?

    public init(
        text: Binding<String>,
        configuration: YayEditorConfiguration = .standard,
        scrollSync: ScrollSyncBridge? = nil
    ) {
        self._text = text
        self.configuration = configuration
        self.scrollSync = scrollSync
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> UITextView {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        let textContainer = NSTextContainer()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownUITextView(frame: .zero, textContainer: textContainer)

        textView.text = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsEditingTextAttributes = false
        textView.font = configuration.theme.baseFont
        textView.textColor = configuration.theme.baseColor
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator

        layoutManager.lineHeightMultiple = configuration.lineHeightMultiple

        textContainer.lineFragmentPadding = configuration.lineFragmentPadding
        textView.textContainerInset = UIEdgeInsets(
            top: configuration.textContainerInset.height,
            left: configuration.textContainerInset.width,
            bottom: configuration.textContainerInset.height,
            right: configuration.textContainerInset.width
        )

        layoutManager.allowsNonContiguousLayout = true

        if configuration.enablesLiveHighlighting {
            context.coordinator.performHighlight(on: textView)
        }

        if configuration.focusOnAppear {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }

        return textView
    }

    public func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.highlighter.updateConfiguration(configuration)

        if let lm = textView.layoutManager as? MarkdownLayoutManager {
            lm.lineHeightMultiple = configuration.lineHeightMultiple
        }

        let newFont = configuration.theme.baseFont
        if textView.font != newFont {
            textView.font = newFont
            textView.textColor = configuration.theme.baseColor
            if configuration.enablesLiveHighlighting {
                context.coordinator.highlighter.invalidateTree()
                context.coordinator.performHighlight(on: textView)
            }
        }

        if textView.text != text {
            textView.text = text
            if configuration.enablesLiveHighlighting {
                context.coordinator.highlighter.invalidateTree()
                context.coordinator.performHighlight(on: textView)
            }
        }
    }

    public class Coordinator: NSObject, UITextViewDelegate {
        var parent: YayTextEditor
        let highlighter: TreeSitterHighlighter

        init(_ parent: YayTextEditor) {
            self.parent = parent
            self.highlighter = TreeSitterHighlighter(configuration: parent.configuration)
        }

        // MARK: - Edit Tracking

        public func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            let current = textView.text ?? ""
            highlighter.prepareEdit(in: range, replacementString: text, currentText: current)
            return true
        }

        public func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            if parent.configuration.enablesLiveHighlighting {
                performHighlight(on: textView)
            }
        }

        // MARK: - Highlighting

        func performHighlight(on textView: UITextView) {
            highlighter.applyHighlighting(textStorage: textView.textStorage, in: nil)
        }
    }
}

#endif
