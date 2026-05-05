// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "YayPreview",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "YayPreview",
            targets: ["YayPreview"]),
    ],
    dependencies: [
        .package(path: "../YayCore")
    ],
    targets: [
        .target(
            name: "YayPreview",
            dependencies: ["YayCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "YayPreviewTests",
            dependencies: ["YayPreview"]
        ),
    ]
)
