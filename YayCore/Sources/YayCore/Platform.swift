// Cross-platform typealiases shared by every YPM package.
//
// Shared code in YayCore/YayTextEditor/YayPreview/YayExport must not import
// AppKit or UIKit directly. Use these typealiases (and `#if os(macOS)` for
// truly platform-specific call sites) so a single source file compiles on
// both macOS and iOS.

#if canImport(AppKit)
import AppKit

public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
public typealias PlatformImage = NSImage
public typealias PlatformView = NSView
public typealias PlatformViewController = NSViewController

#elseif canImport(UIKit)
import UIKit

public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
public typealias PlatformImage = UIImage
public typealias PlatformView = UIView
public typealias PlatformViewController = UIViewController

#else
#error("Unsupported platform: YayCore requires AppKit (macOS) or UIKit (iOS).")
#endif

import CoreGraphics

extension PlatformColor {
    /// Cross-platform primary text colour. `.labelColor` on macOS, `.label` on iOS.
    public static var yayLabel: PlatformColor {
        #if canImport(AppKit)
        return .labelColor
        #else
        return .label
        #endif
    }

    /// Cross-platform control/editor background. `.controlBackgroundColor` on macOS,
    /// `.systemBackground` on iOS.
    public static var yayControlBackground: PlatformColor {
        #if canImport(AppKit)
        return .controlBackgroundColor
        #else
        return .systemBackground
        #endif
    }
}

extension PlatformFont {
    /// Italic variant of `family` at `size`, with a monospaced fallback.
    /// On macOS uses NSFontManager; on iOS derives an italic descriptor from
    /// the system monospaced font (UIKit has no NSFontManager equivalent).
    public static func yayItalicMonospaced(
        family: String,
        size: CGFloat
    ) -> PlatformFont {
        #if canImport(AppKit)
        if let f = NSFontManager.shared.font(
            withFamily: family, traits: .italicFontMask, weight: 5, size: size
        ) {
            return f
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
        #else
        let base = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        if let italic = base.fontDescriptor.withSymbolicTraits(.traitItalic) {
            return UIFont(descriptor: italic, size: size)
        }
        return base
        #endif
    }

    /// Bold variant of `family` at `size`, with a bold-system fallback.
    public static func yayBoldMonospaced(
        family: String,
        size: CGFloat
    ) -> PlatformFont {
        #if canImport(AppKit)
        return NSFontManager.shared.font(
            withFamily: family,
            traits: .boldFontMask,
            weight: 9, size: size
        ) ?? .monospacedSystemFont(ofSize: size, weight: .bold)
        #else
        let base = UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        if let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
        #endif
    }

    /// Bold-italic variant of `family` at `size`, with a bold-system fallback.
    public static func yayBoldItalicMonospaced(
        family: String,
        size: CGFloat
    ) -> PlatformFont {
        #if canImport(AppKit)
        return NSFontManager.shared.font(
            withFamily: family,
            traits: [.boldFontMask, .italicFontMask],
            weight: 9, size: size
        ) ?? .boldSystemFont(ofSize: size)
        #else
        let base = UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        if let descriptor = base.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
        #endif
    }
}
