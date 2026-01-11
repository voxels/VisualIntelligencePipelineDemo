// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YahooSearch",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "YahooSearch",
            targets: ["YahooSearchWrapper"] // We wrap it to bundle resources if needed
        ),
    ],
    targets: [
        .target(
            name: "YahooSearchWrapper",
            path: "Sources",
            exclude: ["YahooSearchKit.framework"],

        )
    ]
)
