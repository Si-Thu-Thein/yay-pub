#if os(iOS)
import UIKit
import YayCore

//
//  MarkdownUITextView.swift
//  Yay (iPad port — Phase 1)
//
//  iOS counterpart to MarkdownNSTextView. Installs MarkdownLayoutManager,
//  disables iOS auto-substitution features that would corrupt Markdown
//  syntax (smart quotes/dashes/spell-correct), and exposes the same
//  `font` override pattern so the layout manager can compute uniform line
//  heights for non-Latin scripts.
//

final class MarkdownUITextView: UITextView {

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configurePlainMarkdownInput()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configurePlainMarkdownInput()
    }

    private func configurePlainMarkdownInput() {
        autocorrectionType = .no
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        autocapitalizationType = .none
    }

    /// Mirrors the macOS view: store the user's chosen font on the layout
    /// manager so non-Latin fallback fonts can't corrupt the line height.
    override var font: UIFont? {
        get {
            (layoutManager as? MarkdownLayoutManager)?.textFont ?? super.font
        }
        set {
            guard let font = newValue else { return }
            (layoutManager as? MarkdownLayoutManager)?.textFont = font
            super.font = font
        }
    }

    // MARK: - Paste as plain text

    override func paste(_ sender: Any?) {
        guard let plain = UIPasteboard.general.string else {
            super.paste(sender)
            return
        }
        // insertText goes through the standard UITextInput path, which fires
        // textViewDidChange for the binding update. No need to consult the
        // delegate's shouldChangeTextIn — that contract is for user-initiated
        // edits, not programmatic ones.
        insertText(plain)
    }

    // MARK: - Hardware keyboard shortcuts

    override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []
        commands.append(contentsOf: [
            UIKeyCommand(
                input: "b",
                modifierFlags: .command,
                action: #selector(toggleBold)
            ),
            UIKeyCommand(
                input: "i",
                modifierFlags: .command,
                action: #selector(toggleItalic)
            ),
        ])
        return commands
    }

    @objc private func toggleBold() {
        toggleMarkup("**")
    }

    @objc private func toggleItalic() {
        toggleMarkup("*")
    }

    /// Replace the contents of `range` with `replacement`, then notify the
    /// delegate. UITextView's `textView(_:shouldChangeTextIn:replacementText:)`
    /// is deliberately NOT consulted — that delegate method's contract covers
    /// user-initiated edits, and gating our own `Cmd+B` / `Cmd+I` / paste
    /// through it would silently break those shortcuts the moment a real
    /// guard (read-only mode, character limit) gets added to the delegate.
    private func replaceRange(
        _ range: NSRange,
        with replacement: String,
        finalSelection: NSRange
    ) {
        textStorage.replaceCharacters(in: range, with: replacement)
        selectedRange = finalSelection
        delegate?.textViewDidChange?(self)
    }

    private func toggleMarkup(_ mark: String) {
        let nsText = text as NSString
        let sel = selectedRange
        let markLen = (mark as NSString).length

        if sel.length == 0 {
            replaceRange(
                sel,
                with: mark + mark,
                finalSelection: NSRange(location: sel.location + markLen, length: 0)
            )
            return
        }

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
                replaceRange(
                    outerRange,
                    with: inner,
                    finalSelection: NSRange(location: sel.location - markLen, length: sel.length)
                )
                return
            }
        }

        let inner = nsText.substring(with: sel)
        replaceRange(
            sel,
            with: mark + inner + mark,
            finalSelection: NSRange(location: sel.location + markLen, length: sel.length)
        )
    }
}

#endif
