// swift-tools-version: 6.0
// SwiftDiskArbitration - A modern Swift wrapper for macOS DiskArbitration framework
//
// This package provides async/await APIs for disk operations using Apple's
// DiskArbitration framework, with proper Swift 6 concurrency support.

import PackageDescription

let package = Package(
    name: "SwiftDiskArbitration",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SwiftDiskArbitration",
            targets: ["SwiftDiskArbitration"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftDiskArbitration",
            dependencies: [],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "SwiftDiskArbitrationTests",
            dependencies: ["SwiftDiskArbitration"]
        ),
    ]
)
