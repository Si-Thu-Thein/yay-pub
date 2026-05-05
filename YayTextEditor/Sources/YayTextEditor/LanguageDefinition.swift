//
//  LanguageDefinition.swift
//  Yay
//
//  Created by Saturngod on 8/29/25.
//

import Foundation

final class LanguageDefinition {
    let keywords: [String]
    let types: [String]?
    let operators: [String]?
    let stringPattern: String
    let commentPatterns: [String]
    let variablePattern: String?
    let numberPattern: String
    let functionPattern: String?
    let keywordSet: Set<String>
    let typeSet: Set<String>

    // Pre-compiled regexes — built once at init, not per-highlight
    let stringRegex: NSRegularExpression?
    let commentRegexes: [NSRegularExpression]
    let numberRegex: NSRegularExpression?
    let variableRegex: NSRegularExpression?
    let storageKeywordsRegex: NSRegularExpression?
    let regularKeywordsRegex: NSRegularExpression?
    let typesRegex: NSRegularExpression?

    /// Fixed list of storage-class keywords used to split keywords into two groups.
    private static let storageKeywordSet: Set<String> = [
        "class", "public", "private", "protected", "static", "final", "abstract",
        "interface", "struct", "enum", "var", "let", "const", "function", "func",
        "def", "import", "package", "namespace",
    ]

    init(
        keywords: [String],
        types: [String]? = nil,
        operators: [String]? = nil,
        stringPattern: String = "([\"'])(?:[^\\\\\\1]|\\\\.)*?\\1",
        commentPatterns: [String] = ["//.*$", "/\\*[\\s\\S]*?\\*/"],
        variablePattern: String? = nil,
        numberPattern: String = "\\b\\d+(?:\\.\\d+)?\\b",
        functionPattern: String? = nil
    ) {
        self.keywords = keywords
        self.types = types
        self.operators = operators
        self.stringPattern = stringPattern
        self.commentPatterns = commentPatterns
        self.variablePattern = variablePattern
        self.numberPattern = numberPattern
        self.functionPattern = functionPattern
        self.keywordSet = Set(keywords)
        self.typeSet = Set(types ?? [])

        // Pre-compile string regex
        self.stringRegex = try? NSRegularExpression(pattern: stringPattern, options: [])

        // Pre-compile comment regexes
        self.commentRegexes = commentPatterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: .anchorsMatchLines)
        }

        // Pre-compile number regex
        self.numberRegex = try? NSRegularExpression(pattern: numberPattern, options: [])

        // Pre-compile variable regex
        if let vp = variablePattern {
            self.variableRegex = try? NSRegularExpression(pattern: vp, options: [])
        } else {
            self.variableRegex = nil
        }

        // Pre-compile storage keywords regex (class, public, static, etc.)
        let storageKws = keywords.filter { Self.storageKeywordSet.contains($0) }
        if !storageKws.isEmpty {
            let joined =
                storageKws
                .map { NSRegularExpression.escapedPattern(for: $0) }
                .joined(separator: "|")
            self.storageKeywordsRegex = try? NSRegularExpression(
                pattern: "\\b(?:\(joined))\\b", options: []
            )
        } else {
            self.storageKeywordsRegex = nil
        }

        // Pre-compile regular keywords regex (everything except storage keywords)
        let regularKws = keywords.filter { !Self.storageKeywordSet.contains($0) }
        if !regularKws.isEmpty {
            let joined =
                regularKws
                .map { NSRegularExpression.escapedPattern(for: $0) }
                .joined(separator: "|")
            self.regularKeywordsRegex = try? NSRegularExpression(
                pattern: "\\b(?:\(joined))\\b", options: []
            )
        } else {
            self.regularKeywordsRegex = nil
        }

        // Pre-compile types regex
        if let types = types, !types.isEmpty {
            let joined =
                types
                .map { NSRegularExpression.escapedPattern(for: $0) }
                .joined(separator: "|")
            self.typesRegex = try? NSRegularExpression(
                pattern: "\\b(?:\(joined))\\b", options: []
            )
        } else {
            self.typesRegex = nil
        }
    }
}
