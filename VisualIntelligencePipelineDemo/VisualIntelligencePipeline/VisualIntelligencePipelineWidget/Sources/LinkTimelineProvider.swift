import WidgetKit
import SwiftUI
import AppIntents
import OSLog
import SwiftData
import DiverKit
import DiverShared

private let logger = Logger(subsystem: "com.secretatomics.Diver", category: "Widget")

struct LinkEntry: TimelineEntry {
    let date: Date
    let links: [LinkEntity]
    let configuration: SearchLinksIntent
}

struct LinkTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = LinkEntry
    typealias Intent = SearchLinksIntent

    func placeholder(in context: Context) -> LinkEntry {
        LinkEntry(
            date: Date(),
            links: [placeholderLink()],
            configuration: SearchLinksIntent()
        )
    }

    func snapshot(for configuration: SearchLinksIntent, in context: Context) async -> LinkEntry {
        // For previews, return placeholder data
        if context.isPreview {
            return LinkEntry(
                date: Date(),
                links: [placeholderLink()],
                configuration: configuration
            )
        }

        // Fetch actual data
        return await fetchEntry(for: configuration)
    }

    func timeline(for configuration: SearchLinksIntent, in context: Context) async -> Timeline<LinkEntry> {
        let entry = await fetchEntry(for: configuration)

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()

        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    // MARK: - Private Helpers

    private func fetchEntry(for configuration: SearchLinksIntent) async -> LinkEntry {
        do {
            // Use SearchLinksIntent with empty query to get recent links
            let limit = min(configuration.limit, 10) // Cap at 10 for widgets

            // Fetch recent links from SwiftData
            logger.debug("📥 Widget: Fetching entities from LinkEntityQuery")
            let entities = try await LinkEntityQuery().fetchAllEntities()
                .filter { $0.status == .ready }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(limit)

            logger.debug("✅ Widget: Fetched \(entities.count) ready entities")

            return LinkEntry(
                date: Date(),
                links: Array(entities),
                configuration: configuration
            )
        } catch {
            print("❌ [LinkTimelineProvider] Fetch failed: \(error)")
            
            // Return a fallback error item so the user sees SOMETHING
            let errorLink = LinkEntity(
                id: "error-fallback",
                url: URL(string: "https://error.log"),
                title: "Widget Error: \(error.localizedDescription)",
                summary: "Fetch failed. Check entitlements/DB.",
                status: .ready,
                tags: ["error"],
                createdAt: Date(),
                wrappedLink: nil
            )
            
            return LinkEntry(
                date: Date(),
                links: [errorLink],
                configuration: configuration
            )
        }
    }

    private func placeholderLink() -> LinkEntity {
        LinkEntity(
            id: "placeholder",
            url: URL(string: "https://example.com"),
            title: "Example Link",
            summary: "This is a placeholder link",
            status: .ready,
            tags: ["example"],
            createdAt: Date(),
            wrappedLink: nil,
            isShared: false
        )
    }
}
