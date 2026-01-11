// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DiverShared",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "DiverShared",
            targets: ["DiverShared"]
        )
    ],
    targets: [
        .target(
            name: "DiverShared",
            path: "Sources/DiverShared"
        ),
        .testTarget(
            name: "DiverSharedTests",
            dependencies: ["DiverShared"],
            path: "Tests/DiverSharedTests"
        )
    ]
)

