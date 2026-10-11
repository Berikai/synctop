// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SyncTop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SyncTopCore",
            targets: ["SyncTopCore"]
        ),
        .executable(
            name: "SyncTop",
            targets: ["SyncTop"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SyncTopCore",
            dependencies: [],
            path: "Sources/SyncTopCore"
        ),
        .executableTarget(
            name: "SyncTop",
            dependencies: ["SyncTopCore"],
            path: "Sources/SyncTop"
        ),
        .executableTarget(
            name: "SyncTopTests",
            dependencies: ["SyncTopCore"],
            path: "Tests/SyncTopTests"
        ),
    ]
)
