import Foundation
import AppIntents
import OSLog
import DiverKit
import DiverShared
import SwiftUI

private let logger = Logger(subsystem: "com.secretatomics.VisualIntelligencePipeline", category: "AppIntents")

/// Search your library or browse recent links.
/// If query is empty, returns recent links. Otherwise searches by title/URL/summary.
/// Single selection only - returns one LinkEntity that can be shared.
struct SearchLinksIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Search Links (Fuzzy Match)"
    static var description = IntentDescription("Search your saved links using fuzzy token matching across titles, tags, and transcriptions.")

    @Parameter(title: "Query")
    var query: String?

    @Parameter(title: "Limit", default: 10)
    var limit: Int

    @Parameter(title: "Tags", default: [])
    var tags: [String]
    
    @Parameter(title: "Selected Link")
    var selectedLink: LinkEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<LinkEntity> & ProvidesDialog & ShowsSnippetView {
        // 1. If a specific link was already selected (e.g. via Disambiguation or explicit parameter), return it immediately
        if let selectedLink {
            return .result(
                value: selectedLink,
                dialog: "Selected \(selectedLink.title ?? "link")",
                view: SearchLinkSnippet(
                    id: selectedLink.id,
                    title: selectedLink.title,
                    url: selectedLink.url,
                    summary: selectedLink.summary,
                    tags: selectedLink.tags
                )
            )
        }
    
        var searchString = query ?? ""
        
        if searchString.isEmpty {
            logger.debug("🔎 SearchLinksIntent: Query empty, requesting value from user")
            searchString = try await $query.requestValue("What would you like to search for? (Type 'recent' to browse all)")
        }
        
        let entities: [LinkEntity]
        if searchString.lowercased() == "recent" {
            logger.debug("🔎 SearchLinksIntent: 'recent' keyword used, fetching all ready entities")
            entities = try LinkEntityQuery().fetchAllEntities()
        } else {
            logger.debug("🔎 SearchLinksIntent: Searching for '\(searchString)'")
            entities = try LinkEntityQuery().searchEntities(matching: searchString)
        }
        
        logger.debug("📊 SearchLinksIntent: Received \(entities.count) entities from query")

        // Filter by tags if provided
        let filtered = entities
            .filter { entity in
                tags.isEmpty || Set(tags).isSubset(of: Set(entity.tags))
            }
            .prefix(limit)

        let results = Array(filtered)
        
        
        var userSelectedResult: LinkEntity? = nil
        // 2. If multiple results found and limit allows, ask user to choose
        if results.count > 1 && limit > 1 {
            userSelectedResult = try await $selectedLink.requestDisambiguation(
                among: results,
                dialog: "Found \(results.count) matches. Which one would you like?"
            )
        }

        // Single selection - return first result or throw error if none
        guard let selected = userSelectedResult else {
            let message = "No links found for \"\(searchString)\"."
            throw NSError(
                domain: "com.secretatomics.VisualIntelligencePipeline",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        let dialog: IntentDialog
        if searchString.lowercased() == "recent" {
            dialog = "Found \(results.count) recent link(s). Returning: \(selected.title ?? selected.url?.host ?? "link")"
        } else {
            dialog = "Found \(results.count) link(s) for \"\(searchString)\". Returning: \(selected.title ?? selected.url?.host ?? "link")"
        }

        return .result(
            value: selected,
            dialog: dialog,
            view: SearchLinkSnippet(
                id: selected.id,
                title: selected.title,
                url: selected.url,
                summary: selected.summary,
                tags: selected.tags
            )
        )
    }
}

/// Snippet view for SearchLinksIntent shown in Siri/Shortcuts UI.
struct SearchLinkSnippet: View {
    let id: String
    let title: String?
    let url: URL?
    let summary: String?
    let tags: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .foregroundColor(.purple)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title ?? "Link")
                        .font(.headline)
                        .lineLimit(2)
                    
                    if let url {
                        Text(url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            
            HStack {
                if !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                Link(destination: URL(string: "secretatomics://open?id=\(id)")!) {
                    HStack(spacing: 4) {
                        Text("View in Visual Intelligence")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    SearchLinkSnippet(
        id:UUID().uuidString,
        title: "The Glass Bead Game",
        url: URL(string: "https://example.com/books/1"),
        summary: "A utopian society where philosophy, math, music, and art reign supreme and one man begins to question whether a life of pure intellect is truly meaningful.",
        tags: ["philosophy", "classic"]
    )
    .padding()
}
