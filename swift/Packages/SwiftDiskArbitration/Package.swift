// swift-tools-version: 6.3
// SwiftDiskArbitration - A modern Swift wrapper for macOS DiskArbitration framework
//
// This package provides async/await APIs for disk operations using Apple's
// DiskArbitration framework, with proper Swift 6 concurrency support.

import PackageDescription

#if !compiler(>=6.3.3)
#error("SwiftDiskArbitration requires Swift 6.3.3 or newer")
#endif

let swift6Settings: [SwiftSetting] = [
  .swiftLanguageMode(.v6),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .strictMemorySafety(),
  .treatAllWarnings(as: .error),
  .unsafeFlags(["-strict-concurrency=complete"]),
  .unsafeFlags(["-require-explicit-sendable"]),
  .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
]

let package = Package(
    name: "SwiftDiskArbitration",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "SwiftDiskArbitration",
            targets: ["SwiftDiskArbitration"]
        ),
        .executable(
            name: "swiftdiskarb-bench",
            targets: ["SwiftDiskArbitrationBench"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftDiskArbitration",
            dependencies: [],
            swiftSettings: swift6Settings
        ),
        .executableTarget(
            name: "SwiftDiskArbitrationBench",
            dependencies: ["SwiftDiskArbitration"],
            path: "Tools/SwiftDiskArbitrationBench",
            swiftSettings: swift6Settings
        ),
        .testTarget(
            name: "SwiftDiskArbitrationTests",
            dependencies: ["SwiftDiskArbitration"],
            swiftSettings: swift6Settings
        ),
    ]
)
