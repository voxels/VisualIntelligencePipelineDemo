
import Foundation
import AppIntents

struct DiverShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .blue }
    
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: SaveLinkIntent(),
                phrases: [
                    "Save to ${applicationName}",
                    "Save link in ${applicationName}",
                    "Add to ${applicationName}"
                ],
                shortTitle: "Save Link",
                systemImageName: "link.badge.plus"
            ),
            AppShortcut(
                intent: ShareLinkIntent(),
                phrases: [
                    "Share with ${applicationName}",
                    "Share link to ${applicationName}",
                    "Create ${applicationName} link"
                ],
                shortTitle: "Share Link",
                systemImageName: "square.and.arrow.up"
            ),
            AppShortcut(
                intent: SearchLinksIntent(),
                phrases: [
                    "Search ${applicationName}",
                    "Search ${applicationName} for [query]",
                    "Find [query] in ${applicationName}",
                    "Show my recent ${applicationName} links",
                    "Browse all my ${applicationName} links"
                ],
                shortTitle: "Search & Deep Link",
                systemImageName: "magnifyingglass.circle.fill"
            ),
            AppShortcut(
                intent: OpenLinkIntent(),
                phrases: [
                    "Open [link] from ${applicationName}",
                    "Show ${applicationName} link"
                ],
                shortTitle: "Open Link",
                systemImageName: "arrow.up.right.square"
            ),
            AppShortcut(
                intent: VisualIntelligenceIntent(),
                phrases: [
                    "Scan screen with ${applicationName}",
                    "Capture link from screen or photos with ${applicationName}",
                    "Analyze image with ${applicationName} intelligence",
                    "Pick photo to save to ${applicationName}"
                ],
                shortTitle: "Intelligence Scan",
                systemImageName: "sparkles.tv.fill"
            )
        ]
    }
}
