//
//  VSCodeTheme.swift
//  Yay
//
//  Created by Saturngod on 8/30/25.
//

import CoreGraphics
import Foundation

public struct VSCodeTheme: Codable {
    let name: String
    let colors: [String: String]
    let semanticHighlighting: Bool?
    let tokenColors: [TokenColor]

    struct TokenColor: Codable {
        let scope: [String]
        let settings: TokenSettings

        enum CodingKeys: String, CodingKey {
            case scope, settings
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            settings = try container.decode(TokenSettings.self, forKey: .settings)

            if let scopeArray = try? container.decode([String].self, forKey: .scope) {
                scope = scopeArray
            } else if let scopeString = try? container.decode(String.self, forKey: .scope) {
                scope = [scopeString]
            } else {
                scope = []
            }
        }
    }

    struct TokenSettings: Codable {
        let foreground: String?
        let background: String?
        let fontStyle: String?
    }

    // MARK: - Theme Cache
    private static var themeCache: [String: VSCodeTheme] = [:]
    private static let cacheQueue = DispatchQueue(
        label: "com.yay.theme-cache", attributes: .concurrent)
}

extension VSCodeTheme {
    public static func load(from path: String) -> VSCodeTheme? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
            let theme = try? JSONDecoder().decode(VSCodeTheme.self, from: data)
        else {
            return nil
        }
        return theme
    }

    public static func loadFromBundle(named themeName: String) -> VSCodeTheme? {
        // Check cache first
        if let cachedTheme = cacheQueue.sync(execute: { themeCache[themeName] }) {
            return cachedTheme
        }

        var theme: VSCodeTheme?

        // Primary: try bundle resource (themes are in root Resources directory)
        if let url = Bundle.main.url(forResource: themeName, withExtension: "json") {
            theme = loadFromURL(url)
        }

        if theme == nil {
            print("Warning: Theme '\(themeName)' not found in bundle or fallback location")
        } else {
            // Cache the theme
            cacheQueue.async(flags: .barrier) {
                themeCache[themeName] = theme
            }
        }

        return theme
    }

    private static func loadFromURL(_ url: URL) -> VSCodeTheme? {
        do {
            let data = try Data(contentsOf: url)
            let theme = try JSONDecoder().decode(VSCodeTheme.self, from: data)
            return theme
        } catch {
            print("Error loading theme from \(url): \(error)")
            return nil
        }
    }

    // MARK: - Built-in Themes
    public static var light: VSCodeTheme? {
        return loadFromBundle(named: "light")
    }

    // MARK: - Theme Discovery
    public static func availableThemes() -> [String] {
        guard let resourcesURL = Bundle.main.resourceURL else {
            return []
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: resourcesURL, includingPropertiesForKeys: nil)
            return
                contents
                .filter { $0.pathExtension == "json" }
                .compactMap { $0.deletingPathExtension().lastPathComponent }
        } catch {
            print("Error discovering themes: \(error)")
            return []
        }
    }

    public static func loadTheme(named name: String) -> VSCodeTheme? {
        return loadFromBundle(named: name)
    }

    public func toMarkdownTheme(withFontSize fontSize: CGFloat = 14) -> MarkdownTheme {
        let baseFontSize = fontSize
        let baseFont = PlatformFont.monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
        let codeFont = PlatformFont.monospacedSystemFont(ofSize: baseFontSize, weight: .regular)
        let headerFont = PlatformFont.monospacedSystemFont(ofSize: baseFontSize, weight: .bold)
        let boldFont = PlatformFont.monospacedSystemFont(ofSize: baseFontSize, weight: .bold)
        return MarkdownTheme(
            baseFontSize: baseFontSize,
            baseFont: baseFont,
            baseColor: colorFromHex(colors["editor.foreground"] ?? "#24292e") ?? .yayLabel,
            boldFont: boldFont,
            headerColor: colorFromHex(getTokenColor(for: "markup.heading") ?? "#005cc5")
                ?? .systemBlue,
            headerFont: headerFont,
            codeFont: codeFont,
            codeForegroundColor: colorFromHex(
                colors["editorBracketHighlight.foreground1"] ?? "#24292e") ?? .systemRed,
            codeBackgroundColor: colorFromHex(colors["textCodeBlock.background"] ?? "#f6f8fa")
                ?? .yayControlBackground,
            linkColor: colorFromHex(colors["textLink.foreground"] ?? "#0366d6")
                ?? .systemBlue,
            imageColor: colorFromHex(getTokenColor(for: "markup.inserted") ?? "#6f42c1")
                ?? .systemPurple,
            imageFont: .monospacedSystemFont(ofSize: baseFontSize, weight: .regular),
            listColor: colorFromHex(
                getTokenColor(for: "punctuation.definition.list.begin.markdown") ?? "#e36209")
                ?? .systemOrange,
            listFont: .monospacedSystemFont(ofSize: baseFontSize, weight: .bold),
            italicFont: .yayItalicMonospaced(family: "Monaco", size: baseFontSize),
            blockquoteColor: colorFromHex(getTokenColor(for: "markup.quote") ?? "#22863a")
                ?? .systemGray,
            blockquoteFont: .monospacedSystemFont(ofSize: baseFontSize, weight: .regular),
            ruleColor: colorFromHex(colors["textSeparator.foreground"] ?? "#d1d5da")
                ?? .systemGray,
            strikeColor: colorFromHex(getTokenColor(for: "markup.strikethrough") ?? "#6a737d")
                ?? .systemGray,
            escapeColor: colorFromHex(getTokenColor(for: "constant.character.escape") ?? "#22863a")
                ?? .systemYellow,
            htmlColor: colorFromHex(getTokenColor(for: "meta.tag.sgml.html") ?? "#6f42c1")
                ?? .systemPink,
            htmlFont: codeFont,
            mathColor: colorFromHex(getTokenColor(for: "markup.math") ?? "#36acaa")
                ?? .systemTeal,
            mathFont: codeFont
        )
    }

    /// Convenience method for backward compatibility
    public func toMarkdownTheme() -> MarkdownTheme {
        return toMarkdownTheme(withFontSize: 14)
    }

    private func getTokenColor(for targetScope: String) -> String? {
        // First try exact matches
        for tokenColor in tokenColors {
            if tokenColor.scope.contains(targetScope) {
                return tokenColor.settings.foreground
            }
        }

        // Then try prefix matches (less specific scopes)
        for tokenColor in tokenColors {
            for scope in tokenColor.scope {
                if targetScope.hasPrefix(scope) || scope.hasPrefix(targetScope) {
                    return tokenColor.settings.foreground
                }
            }
        }

        return nil
    }

    public func getColorForSyntaxElement(_ element: SyntaxElement) -> PlatformColor? {
        let scopes: [String]

        switch element {
        case .comment:
            scopes = ["comment", "punctuation.definition.comment"]
        case .string:
            scopes = ["string", "punctuation.definition.string"]
        case .keyword:
            scopes = ["keyword"]
        case .storage:
            scopes = ["storage", "storage.type", "storage.modifier"]
        case .type:
            scopes = ["support.type", "support.class", "entity.name.type"]
        case .entity:
            scopes = ["entity", "entity.name", "entity.name.class", "entity.name.type"]
        case .constant:
            scopes = ["constant", "entity.name.constant", "variable.other.constant"]
        case .variable:
            scopes = ["variable", "variable.other"]
        case .function:
            scopes = ["entity.name.function", "support.function"]
        case .number:
            scopes = ["constant.numeric"]
        case .`operator`:
            scopes = ["keyword.operator"]
        case .punctuation:
            scopes = ["punctuation"]
        case .support:
            scopes = ["support", "support.constant", "support.variable"]
        }

        // Try each scope in order of priority
        for scope in scopes {
            if let colorHex = getTokenColor(for: scope) {
                return colorFromHex(colorHex)
            }
        }

        return nil
    }
}

public enum SyntaxElement {
    case comment
    case string
    case keyword
    case storage  // for class, public, private, static, etc.
    case type
    case entity  // for class names, function names
    case constant
    case variable
    case function
    case number
    case `operator`
    case punctuation
    case support  // for built-in types and functions
}

public func colorFromHex(_ hex: String) -> PlatformColor? {
    var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)

    if hexString.hasPrefix("#") {
        hexString.removeFirst()
    }

    guard hexString.count == 6 || hexString.count == 8 else {
        return nil
    }

    var rgb: UInt64 = 0
    guard Scanner(string: hexString).scanHexInt64(&rgb) else {
        return nil
    }

    let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
    let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
    let blue = CGFloat(rgb & 0x0000FF) / 255.0
    let alpha: CGFloat = hexString.count == 8 ? CGFloat((rgb & 0xFF00_0000) >> 24) / 255.0 : 1.0

    return PlatformColor(red: red, green: green, blue: blue, alpha: alpha)
}
