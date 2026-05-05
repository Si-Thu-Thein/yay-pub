// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "YayExport",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "YayExport",
            targets: ["YayExport"]),
    ],
    dependencies: [
        .package(path: "../YayCore"),
        .package(path: "../YayPreview"),
    ],
    targets: [
        .target(
            name: "YayExport",
            dependencies: [
                "YayCore",
                "YayPreview",
            ]
        ),
    ]
)
