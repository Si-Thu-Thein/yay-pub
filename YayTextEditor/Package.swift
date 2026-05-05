// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "YayTextEditor",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "YayTextEditor",
            targets: ["YayTextEditor"]),
    ],
    dependencies: [
        .package(path: "../YayCore"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter.git", from: "0.8.0"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-markdown.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "YayTextEditor",
            dependencies: [
                "YayCore",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitterMarkdown", package: "tree-sitter-markdown"),
            ],
            exclude: []
        ),
        .testTarget(
            name: "YayTextEditorTests",
            dependencies: ["YayTextEditor"]
        ),
    ]
)
