#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation
import YayCore

//
//  CodeSyntaxHighlighter.swift
//  Yay
//
//  Created by Saturngod on 8/29/25.
//

final class CodeSyntaxHighlighter {

    // MARK: - Canonical Language Definitions (one instance per language)

    private static let javascriptNumberPattern =
        "(?<![\\w$])(?:0[xX][0-9a-fA-F](?:_?[0-9a-fA-F])*n?|0[bB][01](?:_?[01])*n?|0[oO][0-7](?:_?[0-7])*n?|(?:\\d(?:_?\\d)*\\.\\d(?:_?\\d)*|\\.\\d(?:_?\\d)*|\\d(?:_?\\d)*)(?:[eE][+-]?\\d(?:_?\\d)*)?n?)(?![\\w$])"

    private static let javascript = LanguageDefinition(
        keywords: [
            "abstract", "arguments", "await", "boolean", "break", "byte", "case", "catch", "char",
            "class", "const", "continue", "debugger", "default", "delete", "do", "double", "else",
            "enum", "eval", "export", "extends", "false", "final", "finally", "float", "for",
            "function", "goto", "if", "implements", "import", "in", "instanceof", "int",
            "interface", "let", "long", "native", "new", "null", "package", "private", "protected",
            "public", "return", "short", "static", "super", "switch", "synchronized", "this",
            "throw", "throws", "transient", "true", "try", "typeof", "var", "void", "volatile",
            "while", "with", "yield", "async", "console", "log", "window", "document",
        ],
        types: [
            "Array", "Object", "String", "Number", "Boolean", "Function", "Promise", "Map", "Set",
        ],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|`(?:[^`\\\\]|\\\\.)*`",
        numberPattern: javascriptNumberPattern
    )

    private static let typescript = LanguageDefinition(
        keywords: [
            "abstract", "any", "as", "asserts", "async", "await", "boolean", "break", "case",
            "catch", "class", "const", "continue", "declare", "default", "delete", "do", "else",
            "enum", "export", "extends", "false", "finally", "for", "from", "function", "get", "if",
            "implements", "import", "in", "infer", "instanceof", "interface", "is", "keyof", "let",
            "module", "namespace", "never", "new", "null", "number", "object", "of", "package",
            "private", "protected", "public", "readonly", "require", "return", "set", "static",
            "string", "super", "switch", "symbol", "this", "throw", "true", "try", "type", "typeof",
            "undefined", "unique", "unknown", "var", "void", "while", "with", "yield",
        ],
        types: [
            "Array", "Object", "String", "Number", "Boolean", "Function", "Promise", "Map", "Set",
            "any", "unknown", "never", "void",
        ],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|`(?:[^`\\\\]|\\\\.)*`",
        numberPattern: javascriptNumberPattern
    )

    private static let jsx = LanguageDefinition(
        keywords: [
            "abstract", "arguments", "await", "boolean", "break", "byte", "case", "catch", "char",
            "class", "const", "continue", "debugger", "default", "delete", "do", "double", "else",
            "enum", "eval", "export", "extends", "false", "final", "finally", "float", "for",
            "function", "goto", "if", "implements", "import", "in", "instanceof", "int",
            "interface", "let", "long", "native", "new", "null", "package", "private", "protected",
            "public", "return", "short", "static", "super", "switch", "synchronized", "this",
            "throw", "throws", "transient", "true", "try", "typeof", "var", "void", "volatile",
            "while", "with", "yield", "async", "React", "useState", "useEffect", "useContext",
            "props", "state", "render",
        ],
        types: [
            "Array", "Object", "String", "Number", "Boolean", "Function", "Promise", "Map", "Set",
            "Component", "Element",
        ],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|`(?:[^`\\\\]|\\\\.)*`",
        numberPattern: javascriptNumberPattern
    )

    private static let tsx = LanguageDefinition(
        keywords: [
            "abstract", "any", "as", "asserts", "async", "await", "boolean", "break", "case",
            "catch", "class", "const", "continue", "declare", "default", "delete", "do", "else",
            "enum", "export", "extends", "false", "finally", "for", "from", "function", "get", "if",
            "implements", "import", "in", "infer", "instanceof", "interface", "is", "keyof", "let",
            "module", "namespace", "never", "new", "null", "number", "object", "of", "package",
            "private", "protected", "public", "readonly", "require", "return", "set", "static",
            "string", "super", "switch", "symbol", "this", "throw", "true", "try", "type", "typeof",
            "undefined", "unique", "unknown", "var", "void", "while", "with", "yield", "React",
            "useState", "useEffect", "useContext", "props", "state", "render",
        ],
        types: [
            "Array", "Object", "String", "Number", "Boolean", "Function", "Promise", "Map", "Set",
            "Component", "Element", "any", "unknown", "never", "void",
        ],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|`(?:[^`\\\\]|\\\\.)*`",
        numberPattern: javascriptNumberPattern
    )

    private static let swift = LanguageDefinition(
        keywords: [
            "associatedtype", "class", "deinit", "enum", "extension", "func", "import", "init",
            "inout", "internal", "let", "operator", "private", "protocol", "public", "static",
            "struct", "subscript", "typealias", "var", "break", "case", "continue", "default",
            "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return",
            "switch", "where", "while", "as", "catch", "false", "is", "nil", "rethrows", "super",
            "self", "Self", "throw", "throws", "true", "try", "async", "await", "print",
        ],
        types: [
            "Any", "AnyObject", "AnyClass", "String", "Int", "Double", "Float", "Bool", "Array",
            "Dictionary", "Set", "Optional", "Result", "Error",
        ],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\""
    )

    private static let php = LanguageDefinition(
        keywords: [
            "abstract", "and", "array", "as", "break", "callable", "case", "catch", "class",
            "clone", "const", "continue", "declare", "default", "die", "do", "echo", "else",
            "elseif", "empty", "enddeclare", "endfor", "endforeach", "endif", "endswitch",
            "endwhile", "eval", "exit", "extends", "final", "finally", "for", "foreach", "function",
            "global", "goto", "if", "implements", "include", "include_once", "instanceof",
            "insteadof", "interface", "isset", "list", "namespace", "new", "or", "print", "private",
            "protected", "public", "require", "require_once", "return", "static", "switch", "throw",
            "trait", "try", "unset", "use", "var", "while", "xor", "yield",
        ],
        types: [
            "string", "int", "float", "bool", "array", "object", "resource", "null", "mixed",
            "iterable", "callable", "void", "never", "self", "static",
        ],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|`(?:[^`\\\\]|\\\\.)*`",
        commentPatterns: ["//.*$", "#.*$", "/\\*[\\s\\S]*?\\*/"],
        variablePattern: "\\$[a-zA-Z_\\x7f-\\xff][a-zA-Z0-9_\\x7f-\\xff]*",
        numberPattern: "-?\\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b"
    )

    private static let java = LanguageDefinition(
        keywords: [
            "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class",
            "const", "continue", "default", "do", "double", "else", "enum", "extends", "final",
            "finally", "float", "for", "goto", "if", "implements", "import", "instanceof", "int",
            "interface", "long", "native", "new", "package", "private", "protected", "public",
            "return", "short", "static", "strictfp", "super", "switch", "synchronized", "this",
            "throw", "throws", "transient", "try", "void", "volatile", "while", "System", "out",
            "println", "print",
        ],
        types: [
            "String", "Integer", "Double", "Float", "Boolean", "Character", "Byte", "Short", "Long",
            "Object", "Array", "List", "Map", "Set",
        ],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\""
    )

    private static let csharp = LanguageDefinition(
        keywords: [
            "abstract", "as", "base", "bool", "break", "byte", "case", "catch", "char", "checked",
            "class", "const", "continue", "decimal", "default", "delegate", "do", "double", "else",
            "enum", "event", "explicit", "extern", "false", "finally", "fixed", "float", "for",
            "foreach", "goto", "if", "implicit", "in", "int", "interface", "internal", "is", "lock",
            "long", "namespace", "new", "null", "object", "operator", "out", "override", "params",
            "private", "protected", "public", "readonly", "ref", "return", "sbyte", "sealed",
            "short", "sizeof", "stackalloc", "static", "string", "struct", "switch", "this",
            "throw", "true", "try", "typeof", "uint", "ulong", "unchecked", "unsafe", "ushort",
            "using", "virtual", "void", "volatile", "while", "Console", "WriteLine", "Write",
        ],
        types: [
            "string", "int", "double", "float", "bool", "char", "byte", "short", "long", "decimal",
            "object", "Array", "List", "Dictionary",
        ],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\""
    )

    private static let c = LanguageDefinition(
        keywords: [
            "auto", "break", "case", "const", "continue", "default", "do", "else", "enum",
            "extern", "for", "goto", "if", "inline", "register", "restrict", "return", "sizeof",
            "static", "struct", "switch", "typedef", "union", "volatile", "while", "_Bool",
            "_Complex", "_Imaginary",
        ],
        types: [
            "char", "double", "float", "int", "long", "short", "signed", "unsigned", "void",
            "size_t", "ssize_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "int8_t",
            "int16_t", "int32_t", "int64_t", "bool",
        ],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'",
        commentPatterns: ["//.*$", "/\\*[\\s\\S]*?\\*/"],
        numberPattern: "\\b(?:0[xX][0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)[uUlLfF]*\\b"
    )

    private static let cpp = LanguageDefinition(
        keywords: [
            "alignas", "alignof", "and", "asm", "auto", "break", "case", "catch", "class",
            "concept", "const", "constexpr", "consteval", "constinit", "continue", "decltype",
            "default", "delete", "do", "else", "enum", "explicit", "export", "extern", "false",
            "for", "friend", "goto", "if", "inline", "mutable", "namespace", "new", "noexcept",
            "nullptr", "operator", "private", "protected", "public", "requires", "return",
            "sizeof", "static", "struct", "switch", "template", "this", "throw", "true", "try",
            "typedef", "typename", "union", "using", "virtual", "volatile", "while",
        ],
        types: [
            "bool", "char", "char8_t", "char16_t", "char32_t", "double", "float", "int", "long",
            "short", "signed", "unsigned", "void", "wchar_t", "size_t", "std", "string", "vector",
            "map", "set", "unordered_map", "optional", "variant", "unique_ptr", "shared_ptr",
        ],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|R\"[\\s\\S]*?\"",
        commentPatterns: ["//.*$", "/\\*[\\s\\S]*?\\*/"],
        numberPattern: "\\b(?:0[xX][0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)[uUlLfF]*\\b"
    )

    private static let bash = LanguageDefinition(
        keywords: [
            "if", "then", "else", "elif", "fi", "case", "esac", "for", "select", "while", "until",
            "do", "done", "function", "time", "coproc", "in", "break", "continue", "return", "exit",
            "export", "local", "readonly", "declare", "typeset", "unset", "shift", "test", "eval",
            "exec", "source", "alias", "unalias", "history", "jobs", "bg", "fg", "wait", "kill",
            "trap", "echo", "printf", "read", "cd", "pwd", "pushd", "popd", "dirs", "ls", "cat",
            "grep", "awk", "sed", "sort", "uniq", "wc", "head", "tail", "find", "xargs", "chmod",
            "chown", "cp", "mv", "rm", "mkdir", "rmdir", "touch", "ln", "mount", "umount", "ps",
            "top", "df", "du", "free", "uname", "whoami", "id", "groups", "su", "sudo",
        ],
        types: [],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'",
        commentPatterns: ["#.*$"],
        variablePattern: "\\$[a-zA-Z_][a-zA-Z0-9_]*|\\$\\{[^}]+\\}"
    )

    private static let python = LanguageDefinition(
        keywords: [
            "and", "as", "assert", "break", "class", "continue", "def", "del", "elif", "else",
            "except", "exec", "finally", "for", "from", "global", "if", "import", "in", "is",
            "lambda", "not", "or", "pass", "print", "raise", "return", "try", "while", "with",
            "yield", "True", "False", "None", "async", "await", "nonlocal",
        ],
        types: [
            "int", "float", "str", "bool", "list", "dict", "tuple", "set", "frozenset", "bytes",
            "bytearray",
        ],
        stringPattern: "\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?'''|\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'",
        commentPatterns: ["#.*$"]
    )

    private static let json = LanguageDefinition(
        keywords: ["true", "false", "null"],
        types: nil,
        operators: nil,
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"",
        commentPatterns: [],
        variablePattern: nil,
        numberPattern: "-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?"
    )

    private static let diff = LanguageDefinition(keywords: [], commentPatterns: [])

    private static let elixir = LanguageDefinition(
        keywords: [
            "def", "defp", "defmodule", "defmacro", "defstruct", "do", "end", "fn", "when", "case",
            "cond", "if", "else", "receive", "after", "try", "catch", "rescue", "raise", "alias",
            "import", "require", "use", "with", "quote", "unquote", "true", "false", "nil",
        ],
        types: ["String", "Integer", "Float", "List", "Map", "Tuple", "Atom"],
        operators: nil,
        stringPattern: "\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?'''|\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'",
        commentPatterns: ["#.*$"]
    )

    private static let vbnet = LanguageDefinition(
        keywords: [
            "Dim", "As", "Integer", "String", "Boolean", "Double", "Decimal", "Sub", "Function",
            "End", "If", "Then", "Else", "ElseIf", "While", "For", "Each", "In", "Next", "Return",
            "Public", "Private", "Protected", "Friend", "Class", "Module", "Imports", "Namespace",
            "Try", "Catch", "Finally", "Throw", "Select", "Case", "New", "Me", "MyBase", "MyClass",
            "Not", "And", "Or", "True", "False", "Nothing",
        ],
        types: [
            "Integer", "String", "Boolean", "Double", "Decimal", "Object", "List", "Dictionary",
            "DateTime", "Byte", "Short", "Long", "Char",
        ],
        operators: nil,
        stringPattern: "\"(?:[^\"]|\"\")*\"",
        commentPatterns: ["'.*$", "(?i)\\bREM\\b.*$"]
    )

    private static let applescript = LanguageDefinition(
        keywords: [
            "tell", "end", "if", "then", "else", "repeat", "with", "without", "of", "to", "set",
            "get", "property", "script", "on", "try", "error", "return", "considering", "ignoring",
            "activate", "display", "do", "shell", "script",
        ],
        types: ["integer", "real", "text", "string", "list", "record", "date", "boolean"],
        operators: nil,
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"",
        commentPatterns: ["--.*$", "\\(\\*[\\s\\S]*?\\*\\)"]
    )

    private static let ruby = LanguageDefinition(
        keywords: [
            "BEGIN", "END", "alias", "and", "begin", "break", "case", "class", "def", "defined?",
            "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next",
            "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then",
            "true", "undef", "unless", "until", "when", "while", "yield", "puts", "print",
            "require",
        ],
        types: [
            "String", "Integer", "Float", "Array", "Hash", "Symbol", "Object", "NilClass",
            "TrueClass", "FalseClass",
        ],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'",
        commentPatterns: ["#.*$"]
    )

    private static let go = LanguageDefinition(
        keywords: [
            "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
            "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range",
            "return", "select", "struct", "switch", "type", "var", "true", "false", "nil", "iota",
        ],
        types: [
            "string", "int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32",
            "uint64", "uintptr", "byte", "rune", "float32", "float64", "complex64", "complex128",
            "bool", "error", "any", "comparable",
        ],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|`[\\s\\S]*?`",
        commentPatterns: ["//.*$", "/\\*[\\s\\S]*?\\*/"],
        numberPattern:
            "\\b(?:0[xX][0-9a-fA-F](?:_?[0-9a-fA-F])*(?:\\.[0-9a-fA-F](?:_?[0-9a-fA-F])*)?(?:[pP][+-]?\\d(?:_?\\d)*)?|0[bB][01](?:_?[01])*|0[oO][0-7](?:_?[0-7])*|\\d(?:_?\\d)*(?:\\.\\d(?:_?\\d)*)?(?:[eE][+-]?\\d(?:_?\\d)*)?|\\.\\d(?:_?\\d)*(?:[eE][+-]?\\d(?:_?\\d)*)?)(?:i)?\\b"
    )

    private static let rust = LanguageDefinition(
        keywords: [
            "as", "break", "const", "continue", "crate", "else", "enum", "extern", "false", "fn",
            "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref",
            "return", "Self", "self", "static", "struct", "super", "trait", "true", "type",
            "unsafe", "use", "where", "while", "async", "await", "dyn",
        ],
        types: [
            "String", "str", "i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64",
            "u128", "usize", "f32", "f64", "bool", "char", "Option", "Result", "Vec", "Box",
        ],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|r#?\"[\\s\\S]*?\"#?",
        commentPatterns: ["//.*$", "/\\*[\\s\\S]*?\\*/"]
    )

    private static let mermaid = LanguageDefinition(
        keywords: [
            "graph", "flowchart", "sequenceDiagram", "gantt", "classDiagram", "stateDiagram", "pie",
            "gitGraph", "journey", "mindmap", "timeline", "quadrantChart", "sankey-beta",
            "requirementDiagram", "subgraph", "end", "click", "style", "classDef", "class", "note",
            "loop", "alt", "opt", "par", "crit", "break", "rect", "participant", "actor", "title",
            "direction", "TD", "TB", "BT", "RL", "LR", "dateFormat", "axisFormat", "linkStyle",
            "block", "link", "callback",
        ],
        types: [
            "State", "Action", "Transition", "Note", "Shape", "Node", "Edge", "Participant",
            "Actor",
        ],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"",
        commentPatterns: ["%%.*$"],
        variablePattern: "-->|==>|-\\.->?|---|===|<-->|<==>|x--x|o--o|<--|<==",
        numberPattern: "-?\\b\\d+(?:\\.\\d+)?\\b|#[0-9a-fA-F]{3,8}\\b|\\brgba?\\([^)]+\\)"
    )

    private static let sql = LanguageDefinition(
        keywords: [
            "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
            "CREATE", "TABLE", "ALTER", "ADD", "DROP", "PRIMARY", "KEY", "FOREIGN", "NOT", "NULL",
            "JOIN", "LEFT", "RIGHT", "FULL", "OUTER", "INNER", "ON", "GROUP", "BY", "ORDER",
            "HAVING", "DISTINCT", "LIMIT", "OFFSET", "UNION", "ALL", "AND", "OR", "AS", "IN", "IS",
            "BETWEEN", "LIKE", "CASE", "WHEN", "THEN", "ELSE", "END",
        ],
        types: [
            "INT", "INTEGER", "VARCHAR", "TEXT", "DATE", "DATETIME", "BOOLEAN", "FLOAT", "DOUBLE",
            "DECIMAL", "NUMERIC", "SERIAL", "BIGINT", "SMALLINT", "JSON", "UUID",
        ],
        stringPattern: "'(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\"",
        commentPatterns: ["--.*$", "/\\*[\\s\\S]*?\\*/"],
        numberPattern: "-?\\b\\d+(?:\\.\\d+)?\\b"
    )

    private static let yaml = LanguageDefinition(
        keywords: ["true", "false", "null", "yes", "no", "on", "off"],
        stringPattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'",
        commentPatterns: ["#.*$"],
        numberPattern: "-?\\b\\d+(?:\\.\\d+)?\\b"
    )

    private static let htmlLang = LanguageDefinition(keywords: [], commentPatterns: [])
    private static let cssLang = LanguageDefinition(keywords: [], commentPatterns: [])

    // MARK: - Language Map (aliases share the same instance)

    private static let languages: [String: LanguageDefinition] = [
        // JavaScript family
        "javascript": javascript, "js": javascript, "mjs": javascript, "cjs": javascript,
        "typescript": typescript, "ts": typescript, "mts": typescript, "cts": typescript,
        "jsx": jsx, "javascriptreact": jsx,
        "tsx": tsx, "typescriptreact": tsx,
        // Systems languages
        "swift": swift,
        "java": java,
        "csharp": csharp, "c#": csharp, "cs": csharp, "c-sharp": csharp, "dotnet": csharp,
        "c": c, "h": c,
        "cpp": cpp, "c++": cpp, "cc": cpp, "cxx": cpp, "hpp": cpp, "hxx": cpp,
        "go": go,
        "rust": rust, "rs": rust,
        // Scripting
        "python": python, "py": python,
        "ruby": ruby, "rb": ruby,
        "php": php,
        "bash": bash, "sh": bash, "shell": bash, "shellscript": bash, "zsh": bash,
        "elixir": elixir, "ex": elixir, "exs": elixir,
        // Data / config
        "json": json,
        "yaml": yaml, "yml": yaml,
        "sql": sql,
        // Special
        "diff": diff, "git": diff, "patch": diff,
        "mermaid": mermaid,
        "html": htmlLang, "css": cssLang,
        // VB
        "vbnet": vbnet, "vb": vbnet,
        "applescript": applescript, "osascript": applescript,
    ]

    // MARK: - Pre-compiled shared regexes for special-case languages

    private static let htmlCommentRegex = try? NSRegularExpression(
        pattern: "<!--[\\s\\S]*?-->", options: [])
    private static let htmlTagNameRegex = try? NSRegularExpression(
        pattern: "</?([a-zA-Z][a-zA-Z0-9:-]*)\\b", options: [])
    private static let htmlAttrRegex = try? NSRegularExpression(
        pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(\"[^\\\"]*\"|'[^']*')", options: [])

    private static let cssCommentRegex = try? NSRegularExpression(
        pattern: "/\\*[\\s\\S]*?\\*/", options: [])
    private static let cssStringRegex = try? NSRegularExpression(
        pattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'", options: [])
    private static let cssAtRuleRegex = try? NSRegularExpression(
        pattern: "^\\s*@\\w+", options: .anchorsMatchLines)
    private static let cssPropNameRegex = try? NSRegularExpression(
        pattern: "^\\s*([A-Za-z_-][A-Za-z0-9_-]*)\\s*:", options: .anchorsMatchLines)
    private static let cssHexRegex = try? NSRegularExpression(
        pattern: "#[0-9a-fA-F]{3,8}\\b", options: [])
    private static let cssSelectorRegex = try? NSRegularExpression(
        pattern: "(\\.[-\\w]+|#[-\\w]+|::?[-\\w]+)", options: [])
    private static let cssNumUnitRegex = try? NSRegularExpression(
        pattern: "\\b\\d+(?:\\.\\d+)?(?:px|em|rem|vh|vw|%|s|ms)?\\b", options: [])

    private static let yamlKeyRegex = try? NSRegularExpression(
        pattern: "^\\s*([^\\s:#][^:]*?)\\s*:", options: .anchorsMatchLines)
    private static let yamlBoolRegex = try? NSRegularExpression(
        pattern: "(?i)\\b(true|false|null|yes|no|on|off)\\b", options: [])
    private static let yamlAnchorRegex = try? NSRegularExpression(
        pattern: "[&*][A-Za-z0-9_-]+", options: [])

    private static let classNameRegex = try? NSRegularExpression(
        pattern: "\\b(?:class|interface|struct|enum)\\s+([A-Z][A-Za-z0-9_]*)", options: [])
    private static let implementsRegex = try? NSRegularExpression(
        pattern: "\\b(?:implements|extends)\\s+([A-Z][A-Za-z0-9_]*)", options: [])
    private static let constructorRegex = try? NSRegularExpression(
        pattern: "\\bnew\\s+([A-Z][A-Za-z0-9_]*)\\s*\\(", options: [])
    private static let typeAnnotationRegex = try? NSRegularExpression(
        pattern: "\\b([A-Z][A-Za-z0-9_]*)\\s+([a-z_][A-Za-z0-9_]*)\\s*[;=,)]", options: [])
    private static let funcCallRegex = try? NSRegularExpression(
        pattern: "(?<!\\.)\\b([A-Za-z_][A-Za-z0-9_]*)\\b(?=\\s*\\()", options: [])
    private static let methodCallRegex = try? NSRegularExpression(
        pattern: "(?<=\\.)\\b([A-Za-z_][A-Za-z0-9_]*)\\b(?=\\s*\\()", options: [])
    private static let jsonKeyRegex = try? NSRegularExpression(
        pattern: "^\\s*(\"[^\"]+?\")\\s*:", options: .anchorsMatchLines)

    // MARK: - Public API

    static func supportsLanguage(_ language: String) -> Bool {
        return languages[language.lowercased()] != nil
    }

    static func highlightCode(
        _ code: String, language: String, theme: MarkdownTheme, vsCodeTheme: VSCodeTheme? = nil
    ) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: code)
        // NSAttributedString ranges are in UTF-16 units. `String.count` returns
        // grapheme cluster count, which underflows for emoji/combining marks
        // and silently truncates highlighting (or risks OOB downstream).
        let range = NSRange(location: 0, length: (code as NSString).length)
        // Set the default color across the whole range up front; subsequent
        // regex passes overwrite specific ranges. Avoids enumerating every
        // attribute run at the end to fill in gaps.
        attributedString.addAttribute(
            .foregroundColor, value: theme.codeForegroundColor, range: range)

        // Helper function to get color from VS Code theme or fallback to GitHub Light colors
        func getColor(for element: SyntaxElement, fallback: PlatformColor) -> PlatformColor {
            if let color = vsCodeTheme?.getColorForSyntaxElement(element) {
                return color
            }

            func colorFromHex(_ hex: String) -> PlatformColor? {
                var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                if hexString.hasPrefix("#") { hexString.removeFirst() }
                guard hexString.count == 6 else { return nil }
                var rgb: UInt64 = 0
                guard Scanner(string: hexString).scanHexInt64(&rgb) else { return nil }
                let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
                let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
                let blue = CGFloat(rgb & 0x0000FF) / 255.0
                return PlatformColor(red: red, green: green, blue: blue, alpha: 1.0)
            }

            switch element {
            case .comment: return colorFromHex("#6a737d") ?? fallback
            case .string: return colorFromHex("#032f62") ?? fallback
            case .keyword: return colorFromHex("#d73a49") ?? fallback
            case .storage: return colorFromHex("#d73a49") ?? fallback
            case .entity: return colorFromHex("#6f42c1") ?? fallback
            case .constant: return colorFromHex("#005cc5") ?? fallback
            case .variable: return colorFromHex("#e36209") ?? fallback
            case .function: return colorFromHex("#6f42c1") ?? fallback
            case .number: return colorFromHex("#005cc5") ?? fallback
            case .support: return colorFromHex("#005cc5") ?? fallback
            default: return fallback
            }
        }

        // Base styling (no foreground color — let syntax elements set their own)
        attributedString.addAttributes([.font: theme.codeFont], range: range)

        let lowerLang = language.lowercased()
        guard let langDef = languages[lowerLang] else {
            return attributedString
        }

        let text = code
        let nsText = text as NSString
        var protectedRanges: [NSRange] = []

        func isValidRange(_ range: NSRange) -> Bool {
            range.location != NSNotFound && range.location >= 0 && NSMaxRange(range) <= nsText.length
        }

        func intersectsProtectedRange(_ range: NSRange) -> Bool {
            guard isValidRange(range) else { return true }
            return protectedRanges.contains { NSIntersectionRange($0, range).length > 0 }
        }

        func addForeground(_ color: PlatformColor, range: NSRange) {
            guard isValidRange(range) else { return }
            attributedString.addAttribute(.foregroundColor, value: color, range: range)
        }

        func applyRegex(
            _ regex: NSRegularExpression?,
            color: PlatformColor,
            captureGroup: Int = 0,
            protect: Bool = false,
            skipProtected: Bool = true,
            filter: ((NSRange) -> Bool)? = nil
        ) {
            guard let regex else { return }
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match, captureGroup < match.numberOfRanges else { return }
                let targetRange = match.range(at: captureGroup)
                guard isValidRange(targetRange) else { return }
                if skipProtected && intersectsProtectedRange(targetRange) { return }
                if let filter, !filter(targetRange) { return }

                addForeground(color, range: targetRange)
                if protect {
                    protectedRanges.append(match.range)
                }
            }
        }

        // MARK: Special case: Git/Diff/Patch

        if ["diff", "git", "patch"].contains(lowerLang) {
            nsText.enumerateSubstrings(
                in: NSRange(location: 0, length: nsText.length), options: .byLines
            ) { substring, lineRange, _, _ in
                guard let line = substring else { return }
                if line.hasPrefix("@@") {
                    attributedString.addAttribute(
                        .foregroundColor,
                        value: getColor(for: .number, fallback: PlatformColor.systemOrange),
                        range: lineRange)
                } else if line.hasPrefix("+++") || line.hasPrefix("---") {
                    attributedString.addAttribute(
                        .foregroundColor,
                        value: getColor(for: .function, fallback: PlatformColor.systemBlue),
                        range: lineRange)
                } else if line.hasPrefix("+") {
                    attributedString.addAttribute(
                        .foregroundColor,
                        value: getColor(for: .string, fallback: PlatformColor.systemGreen),
                        range: lineRange)
                } else if line.hasPrefix("-") {
                    attributedString.addAttribute(
                        .foregroundColor,
                        value: getColor(for: .keyword, fallback: PlatformColor.systemRed),
                        range: lineRange)
                } else if line.hasPrefix("diff ") || line.hasPrefix("index ") {
                    attributedString.addAttribute(
                        .foregroundColor,
                        value: getColor(for: .comment, fallback: PlatformColor.systemGray),
                        range: lineRange)
                }
            }
            return attributedString
        }

        // MARK: Special case: HTML

        if lowerLang == "html" {
            htmlCommentRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor, value: getColor(for: .comment, fallback: PlatformColor.systemGray),
                    range: match.range)
            }
            htmlTagNameRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor,
                    value: getColor(for: .keyword, fallback: PlatformColor.systemPurple),
                    range: match.range(at: 1))
            }
            htmlAttrRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor, value: getColor(for: .function, fallback: PlatformColor.systemBlue),
                    range: match.range(at: 1))
                attributedString.addAttribute(
                    .foregroundColor, value: getColor(for: .string, fallback: PlatformColor.systemGreen),
                    range: match.range(at: 2))
            }
            return attributedString
        }

        // MARK: Special case: CSS

        if lowerLang == "css" {
            cssCommentRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor, value: getColor(for: .comment, fallback: PlatformColor.systemGray),
                    range: match.range)
            }
            cssStringRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor, value: getColor(for: .string, fallback: PlatformColor.systemGreen),
                    range: match.range)
            }
            cssAtRuleRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor,
                    value: getColor(for: .keyword, fallback: PlatformColor.systemPurple),
                    range: match.range)
            }
            cssPropNameRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor, value: getColor(for: .function, fallback: PlatformColor.systemBlue),
                    range: match.range(at: 1))
            }
            cssHexRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor, value: getColor(for: .constant, fallback: PlatformColor.systemTeal),
                    range: match.range)
            }
            cssSelectorRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor, value: getColor(for: .type, fallback: PlatformColor.systemPurple),
                    range: match.range)
            }
            cssNumUnitRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor, value: getColor(for: .number, fallback: PlatformColor.systemOrange),
                    range: match.range)
            }
            return attributedString
        }

        // MARK: Special case: YAML

        if lowerLang == "yaml" || lowerLang == "yml" {
            for regex in langDef.commentRegexes {
                regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                    guard let match else { return }
                    attributedString.addAttribute(
                        .foregroundColor,
                        value: getColor(for: .comment, fallback: PlatformColor.systemGray),
                        range: match.range)
                }
            }
            langDef.stringRegex?.enumerateMatches(in: text, options: [], range: range) {
                match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor, value: getColor(for: .string, fallback: PlatformColor.systemGreen),
                    range: match.range)
            }
            langDef.numberRegex?.enumerateMatches(in: text, options: [], range: range) {
                match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor, value: getColor(for: .number, fallback: PlatformColor.systemOrange),
                    range: match.range)
            }
            yamlKeyRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor, value: PlatformColor.systemBlue, range: match.range(at: 1))
            }
            yamlBoolRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor,
                    value: getColor(for: .keyword, fallback: PlatformColor.systemPurple),
                    range: match.range)
            }
            yamlAnchorRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                attributedString.addAttribute(
                    .foregroundColor, value: getColor(for: .type, fallback: PlatformColor.systemTeal),
                    range: match.range)
            }
            return attributedString
        }

        // MARK: Generic language highlighting (uses pre-compiled regexes from LanguageDefinition)

        // 1. Protect strings and comments by source order. That keeps `//`
        // inside a string from becoming a comment, and quotes inside comments
        // from preventing the comment range from being colored.
        var protectedTokens: [(range: NSRange, color: PlatformColor)] = []
        func collectProtectedToken(_ regex: NSRegularExpression?, color: PlatformColor) {
            guard let regex else { return }
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match, isValidRange(match.range) else { return }
                protectedTokens.append((match.range, color))
            }
        }

        collectProtectedToken(
            langDef.stringRegex,
            color: getColor(for: .string, fallback: PlatformColor.systemGreen)
        )
        for regex in langDef.commentRegexes {
            collectProtectedToken(
                regex,
                color: getColor(for: .comment, fallback: PlatformColor.systemGray)
            )
        }
        protectedTokens.sort {
            if $0.range.location == $1.range.location {
                return $0.range.length > $1.range.length
            }
            return $0.range.location < $1.range.location
        }
        for token in protectedTokens where !intersectsProtectedRange(token.range) {
            addForeground(token.color, range: token.range)
            protectedRanges.append(token.range)
        }

        // 2. Numbers
        applyRegex(
            langDef.numberRegex,
            color: getColor(for: .number, fallback: PlatformColor.systemOrange)
        )

        // 3. Variables
        applyRegex(
            langDef.variableRegex,
            color: getColor(for: .variable, fallback: PlatformColor.systemBlue)
        )

        // 4. Storage keywords
        applyRegex(
            langDef.storageKeywordsRegex,
            color: getColor(for: .storage, fallback: PlatformColor.systemRed)
        )

        // 5. Regular keywords
        applyRegex(
            langDef.regularKeywordsRegex,
            color: getColor(for: .keyword, fallback: PlatformColor.systemPurple)
        )

        // 6. Types
        applyRegex(
            langDef.typesRegex,
            color: getColor(for: .support, fallback: PlatformColor.systemTeal)
        )

        // 7. Class/interface names, implements/extends, constructors, type annotations
        applyRegex(
            classNameRegex,
            color: getColor(for: .entity, fallback: PlatformColor.systemPurple),
            captureGroup: 1
        )
        applyRegex(
            implementsRegex,
            color: getColor(for: .entity, fallback: PlatformColor.systemPurple),
            captureGroup: 1
        )
        applyRegex(
            constructorRegex,
            color: getColor(for: .entity, fallback: PlatformColor.systemPurple),
            captureGroup: 1
        )
        typeAnnotationRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match else { return }
            let typeRange = match.range(at: 1)
            guard isValidRange(typeRange), !intersectsProtectedRange(typeRange) else { return }
            let typeName = nsText.substring(with: typeRange)
            if !langDef.keywordSet.contains(typeName) && !langDef.typeSet.contains(typeName) {
                addForeground(
                    getColor(for: .entity, fallback: PlatformColor.systemPurple), range: typeRange)
            }
        }

        // 8. Function and method calls
        funcCallRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match else { return }
            let nameRange = match.range(at: 1)
            guard isValidRange(nameRange), !intersectsProtectedRange(nameRange) else { return }
            let token = nsText.substring(with: nameRange)
            if langDef.keywordSet.contains(token) { return }
            addForeground(getColor(for: .function, fallback: PlatformColor.systemBlue), range: nameRange)
        }
        applyRegex(
            methodCallRegex,
            color: getColor(for: .function, fallback: PlatformColor.systemBlue),
            captureGroup: 1
        )

        // JSON keys
        if lowerLang == "json" {
            jsonKeyRegex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match = match else { return }
                addForeground(PlatformColor.systemBlue, range: match.range(at: 1))
            }
        }

        return attributedString
    }
}
