// swift-tools-version: 6.0

import PackageDescription

// DiverUI — cross-platform SwiftUI component library.
//
// Contains all views that compile on iOS, macOS, and visionOS without UIKit.
// App targets import DiverUI instead of duplicating views per-platform.
//
// What lives here:
//   Session/     — SessionRowView, session header
//   Item/        — ItemRowView, ItemThumbnail, PlatformImage adapter
//   Detail/      — ReferenceDetailView router + 6 specialized profiles
//   Chat/        — AgenticChatView (CLaRa conversation UI)
//   Library/     — TagCloudView, ConceptListView, ContextChipBar, MaintenanceStatusView
//   Settings/    — EdgeNodeSetupView, EdgeNodeStatusPill
//   Commerce/    — Scoring overlays, ownership, score history charts
//   Platform/    — PlatformImage typealias + Image(data:) extension
//
// What does NOT live here (UIKit / camera / platform-specific):
//   VisualIntelligenceView   — AVFoundation camera (iOS only)
//   SidebarView              — navigation shell with iOS-only affordances
//   RichWebView              — WKWebView wrapper (UIKit)
//   SiftedOverlayView        — UIImage sifting
//   SharedWithYouView        — SharedWithYou framework (iOS only)
//   SidebarView              — navigation shell
//   SettingsView             — SMAppService, iOS-specific toggles

let package = Package(
    name: "DiverUI",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
        .visionOS("26.3")
    ],
    products: [
        .library(
            name: "DiverUI",
            targets: ["DiverUI"]
        )
    ],
    dependencies: [
        .package(path: "../DiverKit"),
        .package(path: "../DiverShared")
    ],
    targets: [
        .target(
            name: "DiverUI",
            dependencies: [
                "DiverKit",
                "DiverShared"
            ],
            path: "Sources/DiverUI"
        )
    ],
    swiftLanguageModes: [.v6]
)
