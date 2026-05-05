//
//  MarkdownLayoutManager.swift
//  Yay
//
//  Suppresses display invalidation during batch temporary attribute updates,
//  reducing hundreds of invalidation cycles to a single one.
//  Also enforces uniform line height across Latin and CJK/Myanmar scripts
//  via NSLayoutManagerDelegate
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import CoreGraphics
import YayCore

final class MarkdownLayoutManager: NSLayoutManager {

    // MARK: - Display Validation Suppression

    private var ignoresDisplayValidation = false

    override func invalidateDisplay(forCharacterRange charRange: NSRange) {
        guard !ignoresDisplayValidation else { return }
        super.invalidateDisplay(forCharacterRange: charRange)
    }

    func groupTemporaryAttributesUpdate(in range: NSRange, work: () -> Void) {
        ignoresDisplayValidation = true
        defer { ignoresDisplayValidation = false }
        work()
        super.invalidateDisplay(forCharacterRange: range)
    }

    // MARK: - Uniform Line Height

    /// The user's chosen font, stored separately so that fallback fonts used
    /// for non-Latin scripts (Myanmar, CJK, etc.) cannot corrupt the line
    /// height calculation.  Set via the NSTextView subclass's `font` override.
    var textFont: PlatformFont = .systemFont(ofSize: 0) {
        didSet {
            #if canImport(AppKit)
            cachedDefaultLineHeight = defaultLineHeight(for: textFont)
            #else
            // UIKit's NSLayoutManager has no defaultLineHeight(for:). Match
            // AppKit's formula explicitly — UIFont.lineHeight excludes leading,
            // which would make iOS line spacing visibly tighter than macOS at
            // the same lineHeightMultiple.
            cachedDefaultLineHeight =
                textFont.ascender + abs(textFont.descender) + textFont.leading
            #endif
            cachedBaselineOffset = textFont.ascender + textFont.leading / 2
            delegate = self
        }
    }

    /// Multiplier applied to the default line height.  1.0 = natural height,
    /// 1.5 = 50 % taller, etc.  Set from `YayEditorConfiguration`.
    var lineHeightMultiple: CGFloat = 1.5 {
        didSet {
            lineHeightMultiple = max(lineHeightMultiple, 0)
            guard oldValue != lineHeightMultiple else { return }
            if let length = textStorage?.length, length > 0 {
                invalidateLayout(
                    forCharacterRange: NSRange(location: 0, length: length),
                    actualCharacterRange: nil)
                #if canImport(AppKit)
                textContainers.first?.textView?.needsDisplay = true
                #else
                // UIKit: NSTextContainer has no `textView` back-reference.
                // The owning UITextView (added in Phase 1) handles its own
                // display invalidation through layoutManager(_:didFinishLayoutFor:).
                #endif
            }
        }
    }

    private var cachedDefaultLineHeight: CGFloat = 0
    private var cachedBaselineOffset: CGFloat = 0

    /// The fixed line height applied to every line fragment.
    var lineHeight: CGFloat {
        (lineHeightMultiple > 0 ? lineHeightMultiple : 1) * cachedDefaultLineHeight
    }

    /// Baseline offset that visually centres glyphs within the fixed-height
    /// line fragment (baseline calculation).
    private func centeredBaselineOffset(for layoutOrientation: NSLayoutManager.TextLayoutOrientation) -> CGFloat {
        switch layoutOrientation {
        case .horizontal:
            let diff = textFont.ascender - textFont.capHeight
            return (lineHeight + cachedBaselineOffset - diff) / 2
        case .vertical:
            return lineHeight / 2
        @unknown default:
            return lineHeight / 2
        }
    }

    /// Force the extra line fragment (the empty line at the end of the
    /// document) to the same fixed height.
    override func setExtraLineFragmentRect(
        _ fragmentRect: CGRect, usedRect: CGRect, textContainer container: NSTextContainer
    ) {
        var fragmentRect = fragmentRect
        fragmentRect.size.height = lineHeight
        var usedRect = usedRect
        usedRect.size.height = lineHeight
        super.setExtraLineFragmentRect(fragmentRect, usedRect: usedRect, textContainer: container)
    }
}

// MARK: - NSLayoutManagerDelegate

extension MarkdownLayoutManager: NSLayoutManagerDelegate {

    /// Forces every line fragment to the same fixed height computed from
    /// `textFont`, preventing the line-height jumps that occur when macOS
    /// substitutes a taller fallback font for Myanmar / CJK glyphs.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<CGRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange: NSRange
    ) -> Bool {
        lineFragmentRect.pointee.size.height = lineHeight
        lineFragmentUsedRect.pointee.size.height = lineHeight
        baselineOffset.pointee = centeredBaselineOffset(for: textContainer.layoutOrientation)
        return true
    }
}
