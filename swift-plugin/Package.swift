// swift-tools-version: 5.9
// EjectAllDisksPlugin - A native Swift Stream Deck plugin for disk ejection
//
// This package creates a Stream Deck plugin that directly uses the DiskArbitration
// framework for fast, native disk ejection without any subprocess overhead.

import PackageDescription

let package = Package(
    name: "EjectAllDisksPlugin",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "org.deverman.ejectalldisks",
            targets: ["EjectAllDisksPlugin"]
        )
    ],
    dependencies: [
        // StreamDeck SDK for native Swift plugin development
        .package(url: "https://github.com/deverman/StreamDeckPlugin.git", branch: "main"),
        // Local SwiftDiskArbitration package for disk operations
        .package(path: "../swift/Packages/SwiftDiskArbitration")
    ],
    targets: [
        .executableTarget(
            name: "EjectAllDisksPlugin",
            dependencies: [
                .product(name: "StreamDeck", package: "StreamDeckPlugin"),
                "SwiftDiskArbitration"
            ],
            path: "Sources/EjectAllDisksPlugin"
        ),
        .testTarget(
            name: "EjectAllDisksPluginTests",
            dependencies: [
                "EjectAllDisksPlugin",
                "SwiftDiskArbitration"
            ],
            path: "Tests/EjectAllDisksPluginTests"
        )
    ]
)
