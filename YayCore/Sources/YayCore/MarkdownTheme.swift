//
//  MarkdownTheme.swift
//  Yay
//
//  Created by Saturngod on 8/29/25.
//

import CoreGraphics
import Foundation

public struct MarkdownTheme {
    public let baseFontSize: CGFloat
    public let baseFont: PlatformFont
    public let baseColor: PlatformColor
    public let boldFont: PlatformFont

    public let headerColor: PlatformColor
    public let headerFont: PlatformFont

    public let codeFont: PlatformFont
    public let codeForegroundColor: PlatformColor
    public let codeBackgroundColor: PlatformColor

    public let linkColor: PlatformColor
    public let imageColor: PlatformColor
    public let imageFont: PlatformFont

    public let listColor: PlatformColor
    public let listFont: PlatformFont
    public let italicFont: PlatformFont
    public let blockquoteColor: PlatformColor
    public let blockquoteFont: PlatformFont
    public let ruleColor: PlatformColor

    public let strikeColor: PlatformColor
    public let escapeColor: PlatformColor
    public let htmlColor: PlatformColor
    public let htmlFont: PlatformFont

    public let mathColor: PlatformColor
    public let mathFont: PlatformFont

    public static let standard: MarkdownTheme = {
        if let lightTheme = VSCodeTheme.light {
            return lightTheme.toMarkdownTheme()
        }
        return MarkdownTheme(
            baseFontSize: 14,
            baseFont: .monospacedSystemFont(ofSize: 14, weight: .regular),
            baseColor: .yayLabel,
            boldFont: .monospacedSystemFont(ofSize: 14, weight: .bold),
            headerColor: .systemBlue,
            headerFont: .boldSystemFont(ofSize: 14),
            codeFont: .monospacedSystemFont(ofSize: 14, weight: .regular),
            codeForegroundColor: .yayLabel,
            codeBackgroundColor: .yayControlBackground,
            linkColor: .systemBlue,
            imageColor: .systemPurple,
            imageFont: .yayItalicMonospaced(family: "Monaco", size: 14),
            listColor: .systemOrange,
            listFont: .boldSystemFont(ofSize: 14),
            italicFont: .yayItalicMonospaced(family: "Monaco", size: 14),
            blockquoteColor: .systemGray,
            blockquoteFont: .yayItalicMonospaced(family: "Monaco", size: 14),
            ruleColor: .systemGray,
            strikeColor: .systemGray,
            escapeColor: .systemYellow,
            htmlColor: .systemPink,
            htmlFont: .monospacedSystemFont(ofSize: 14, weight: .regular),
            mathColor: .systemTeal,
            mathFont: .monospacedSystemFont(ofSize: 14, weight: .regular)
        )
    }()

    public static func fromVSCodeTheme(path: String) -> MarkdownTheme? {
        guard let vsCodeTheme = VSCodeTheme.load(from: path) else {
            return nil
        }
        return vsCodeTheme.toMarkdownTheme()
    }

    public static func fromVSCodeTheme(named themeName: String) -> MarkdownTheme? {
        if let cachedTheme = cachedTheme(named: themeName) {
            return cachedTheme
        }

        guard let vsCodeTheme = VSCodeTheme.loadFromBundle(named: themeName) else {
            return nil
        }

        let theme = vsCodeTheme.toMarkdownTheme()
        setCachedTheme(theme, named: themeName)
        return theme
    }

    // MARK: - Theme Cache
    private static var themeCache: [String: MarkdownTheme] = [:]
    private static let cacheQueue = DispatchQueue(
        label: "com.yay.markdown-theme-cache", attributes: .concurrent)

    public static let githubLight: MarkdownTheme = {
        return fromVSCodeTheme(named: "light") ?? standard
    }()

    // MARK: - Convenience Methods

    /// Creates a copy of a theme with a unified font family/size, falling back to
    /// the system monospaced font if the named family is unavailable.
    public static func withFont(
        family: String, size: CGFloat, basedOn baseTheme: MarkdownTheme = .githubLight
    ) -> MarkdownTheme {
        let baseFont = PlatformFont(name: family, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        let boldFont = PlatformFont.yayBoldMonospaced(family: family, size: size)
        let italicFont = PlatformFont.yayItalicMonospaced(family: family, size: size)
        return MarkdownTheme(
            baseFontSize: size,
            baseFont: baseFont,
            baseColor: baseTheme.baseColor,
            boldFont: boldFont,
            headerColor: baseTheme.headerColor,
            headerFont: boldFont,
            codeFont: baseFont,
            codeForegroundColor: baseTheme.codeForegroundColor,
            codeBackgroundColor: baseTheme.codeBackgroundColor,
            linkColor: baseTheme.linkColor,
            imageColor: baseTheme.imageColor,
            imageFont: italicFont,
            listColor: baseTheme.listColor,
            listFont: boldFont,
            italicFont: italicFont,
            blockquoteColor: baseTheme.blockquoteColor,
            blockquoteFont: italicFont,
            ruleColor: baseTheme.ruleColor,
            strikeColor: baseTheme.strikeColor,
            escapeColor: baseTheme.escapeColor,
            htmlColor: baseTheme.htmlColor,
            htmlFont: baseFont,
            mathColor: baseTheme.mathColor,
            mathFont: baseFont
        )
    }

    public static func withUnifiedFontSize(
        _ fontSize: CGFloat, basedOn baseTheme: MarkdownTheme = .standard
    ) -> MarkdownTheme {
        return MarkdownTheme(
            baseFontSize: fontSize,
            baseFont: .monospacedSystemFont(ofSize: fontSize, weight: .regular),
            baseColor: baseTheme.baseColor,
            boldFont: .monospacedSystemFont(ofSize: fontSize, weight: .bold),
            headerColor: baseTheme.headerColor,
            headerFont: .boldSystemFont(ofSize: fontSize),
            codeFont: .monospacedSystemFont(ofSize: fontSize, weight: .regular),
            codeForegroundColor: baseTheme.codeForegroundColor,
            codeBackgroundColor: baseTheme.codeBackgroundColor,
            linkColor: baseTheme.linkColor,
            imageColor: baseTheme.imageColor,
            imageFont: .yayItalicMonospaced(family: "Monaco", size: 14),
            listColor: baseTheme.listColor,
            listFont: .boldSystemFont(ofSize: fontSize),
            italicFont: .yayItalicMonospaced(family: "Monaco", size: fontSize),
            blockquoteColor: baseTheme.blockquoteColor,
            blockquoteFont: .yayItalicMonospaced(family: "Monaco", size: fontSize),
            ruleColor: baseTheme.ruleColor,
            strikeColor: baseTheme.strikeColor,
            escapeColor: baseTheme.escapeColor,
            htmlColor: baseTheme.htmlColor,
            htmlFont: .monospacedSystemFont(ofSize: fontSize, weight: .regular),
            mathColor: baseTheme.mathColor,
            mathFont: .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        )
    }

    public static func cachedTheme(named themeName: String) -> MarkdownTheme? {
        return cacheQueue.sync { themeCache[themeName] }
    }

    public static func setCachedTheme(_ theme: MarkdownTheme, named themeName: String) {
        cacheQueue.async(flags: .barrier) {
            themeCache[themeName] = theme
        }
    }
}
