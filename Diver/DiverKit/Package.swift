// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DiverKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "DiverKit",
            targets: ["DiverKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/launchdarkly/swift-eventsource", from: "3.0.0"),
        .package(url: "https://github.com/Peter-Schorn/SpotifyAPI", from: "4.0.0"),
        .package(path: "../DiverShared")
    ],
    targets: [
        .target(
            name: "DiverKit",
            dependencies: [
                .product(name: "LDSwiftEventSource", package: "swift-eventsource"),
                .product(name: "SpotifyAPI", package: "SpotifyAPI"),
                "DiverShared"
            ],
            path: "Sources/DiverKit",
            exclude: [
                "Config/Config.md",
                "Config/Localisation/Localisation.md"
            ],
            resources: [
                .process("Resources/pipeline_logs.json"),
                .process("Resources/shortcuts-manifest.json")
            ]
        ),
        .testTarget(
            name: "DiverKitTests",
            dependencies: ["DiverKit"],
            path: "Tests/DiverKitTests",
            resources: [
                .copy("Resources/pipeline_logs.json")
            ]
        )
    ]
)
