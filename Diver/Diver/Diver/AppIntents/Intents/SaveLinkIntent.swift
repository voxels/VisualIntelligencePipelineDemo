
import Foundation
import AppIntents
import DiverKit
import DiverShared
import SwiftUI
import WidgetKit

struct SaveLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Save Link to Diver"
    static var description = IntentDescription("Save a URL to your Diver library.")

    @Parameter(title: "URL")
    var url: URL

    @Parameter(title: "Title", default: nil)
    var title: String?

    @Parameter(title: "Tags", default: [])
    var tags: [String]

    internal static var _testQueueStore: DiverQueueStore?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Validation (ensure the URL is valid)
        guard Validation.isValidURL(url.absoluteString) else {
            return .result(dialog: "The provided URL is not valid.")
        }

        // Prepare descriptor with tags (stored as categories in descriptor)
        let descriptor = DiverItemDescriptor(
            id: DiverLinkWrapper.id(for: url),
            url: url.absoluteString,
            title: title ?? url.absoluteString,
            styleTags: tags,
            categories: []
        )

        // Enqueue item
        do {
            let queueStore: DiverQueueStore
            if let testStore = Self._testQueueStore {
                queueStore = testStore
            } else {
                queueStore = try DiverQueueStore(directoryURL: AppGroupContainer.queueDirectoryURL()!)
            }
            let queueItem = DiverQueueItem(
                action: "save",
                descriptor: descriptor,
                source: url.host() ?? "AppIntent"
            )
            try queueStore.enqueue(queueItem)

            // Refresh widgets to show the new item
            WidgetCenter.shared.reloadAllTimelines()

            let tagInfo = tags.isEmpty ? "" : " with tags: \(tags.joined(separator: ", "))"
            return .result(
                dialog: "Saved \(title ?? url.host ?? "link") to Diver\(tagInfo).",
                view: SaveLinkSnippet(
                    url: url.absoluteString,
                    title: title,
                    tags: tags
                )
            )
        } catch {
            return .result(dialog: "Failed to save link: \(error.localizedDescription)")
        }
    }
}

extension SaveLinkIntent {
    var snippetView: some View {
        SaveLinkSnippet(
            url: url.absoluteString,
            title: title,
            tags: tags
        )
    }
}
