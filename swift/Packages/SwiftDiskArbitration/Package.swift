// swift-tools-version: 5.9
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
            dependencies: []
            // Note: StrictConcurrency is enabled by default in Swift 6
        ),
        .testTarget(
            name: "SwiftDiskArbitrationTests",
            dependencies: ["SwiftDiskArbitration"]
        ),
    ]
)
