// swift-tools-version: 6.3
// EjectAllDisksPlugin - A native Swift Stream Deck plugin for disk ejection
//
// This package creates a Stream Deck plugin that directly uses the DiskArbitration
// framework for fast, native disk ejection without any subprocess overhead.

import PackageDescription

#if !compiler(>=6.3.3)
#error("SafeEject requires Swift 6.3.3 or newer")
#endif

let swift6Settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .strictMemorySafety(),
    .treatAllWarnings(as: .error),
    .unsafeFlags(["-strict-concurrency=complete"]),
    .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
]

let package = Package(
    name: "EjectAllDisksPlugin",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "org.deverman.ejectalldisks",
            targets: ["EjectAllDisksPlugin"]
        )
    ],
    dependencies: [
        // StreamDeck SDK for native Swift plugin development
        .package(
            url: "https://github.com/deverman/StreamDeckPlugin.git",
            revision: "4ab9413d360a8a8657172914c4f98ba3f86743f3"
        ),
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
            path: "Sources/EjectAllDisksPlugin",
            swiftSettings: swift6Settings
        ),
        .testTarget(
            name: "EjectAllDisksPluginTests",
            dependencies: [
                "EjectAllDisksPlugin",
                "SwiftDiskArbitration"
            ],
            path: "Tests/EjectAllDisksPluginTests",
            swiftSettings: swift6Settings
        )
    ]
)
