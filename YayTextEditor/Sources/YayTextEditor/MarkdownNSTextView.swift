#if os(macOS)
import AppKit
import YayCore

//
//  MarkdownNSTextView.swift
//  Yay
//
//  Created by Saturngod on 8/29/25.
//

final class MarkdownNSTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configurePlainMarkdownInput()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configurePlainMarkdownInput()
    }

    private func configurePlainMarkdownInput() {
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
    }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    // Store the user's font in the LayoutManager so that fallback fonts used
    // for Myanmar / CJK glyphs cannot corrupt line-height calculations.
    // The getter returns the stored font because `super.font` returns the
    // fallback font when the first character uses a composite font.
    override var font: NSFont? {
        get {
            (layoutManager as? MarkdownLayoutManager)?.textFont ?? super.font
        }
        set {
            guard let font = newValue else { return }
            (layoutManager as? MarkdownLayoutManager)?.textFont = font
            super.font = font
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), let chars = event.charactersIgnoringModifiers?.lowercased()
        else {
            return super.performKeyEquivalent(with: event)
        }

        switch chars {
        case "b":
            toggleMarkup("**")
            return true
        case "i":
            toggleMarkup("*")
            return true
        case "a":
            selectAll(nil)
            return true
        case "c":
            copy(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "x":
            cut(nil)
            return true
        case "z":
            if flags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        case "y":
            // Common alternate redo shortcut
            undoManager?.redo()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func toggleMarkup(_ mark: String) {
        guard let storage = textStorage else { return }
        let nsText = string as NSString
        let sel = selectedRange()
        let markLen = (mark as NSString).length

        // Empty selection: insert paired marks and place caret between them.
        if sel.length == 0 {
            let insertion = mark + mark
            if shouldChangeText(in: sel, replacementString: insertion) {
                storage.replaceCharacters(in: sel, with: insertion)
                didChangeText()
                setSelectedRange(NSRange(location: sel.location + markLen, length: 0))
            }
            return
        }

        // If the selection is already wrapped with `mark`, unwrap it in a
        // single replacement covering [mark][selection][mark] → selection.
        if sel.location >= markLen,
            sel.location + sel.length + markLen <= nsText.length
        {
            let beforeRange = NSRange(location: sel.location - markLen, length: markLen)
            let afterRange = NSRange(location: sel.location + sel.length, length: markLen)
            if nsText.substring(with: beforeRange) == mark,
                nsText.substring(with: afterRange) == mark
            {
                let outerRange = NSRange(
                    location: sel.location - markLen,
                    length: markLen + sel.length + markLen
                )
                let inner = nsText.substring(with: sel)
                if shouldChangeText(in: outerRange, replacementString: inner) {
                    storage.replaceCharacters(in: outerRange, with: inner)
                    didChangeText()
                    setSelectedRange(NSRange(location: sel.location - markLen, length: sel.length))
                }
                return
            }
        }

        // Otherwise wrap: replace selection with mark + selection + mark in one
        // replacement, so a single InputEdit captures the change for tree-sitter.
        let inner = nsText.substring(with: sel)
        let wrapped = mark + inner + mark
        if shouldChangeText(in: sel, replacementString: wrapped) {
            storage.replaceCharacters(in: sel, with: wrapped)
            didChangeText()
            setSelectedRange(NSRange(location: sel.location + markLen, length: sel.length))
        }
    }
}

#endif
