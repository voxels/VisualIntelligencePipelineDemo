import Foundation
import AppIntents
import DiverKit
import SwiftUI

import UniformTypeIdentifiers

/// Represents a link stored in Visual Intelligence, suitable for App Intents/Siri/Shortcuts.
struct LinkEntity: AppEntity, Identifiable, Hashable, Codable, Sendable {
    // MARK: - AppEntity conformance
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Link")
    static var defaultQuery: LinkEntityQuery = LinkEntityQuery()
    
    var id: String  // Usually the URL hash used as primary key
    var displayRepresentation: DisplayRepresentation {
        var displayTitle = LocalizedStringResource(stringLiteral: "Link")
        if let title {
            displayTitle = LocalizedStringResource(stringLiteral: title)
        } else if let url {
            displayTitle = LocalizedStringResource(stringLiteral: url.absoluteString)
        }
        
        var displaySubtitle = LocalizedStringResource(stringLiteral: "")
        if let url {
            displaySubtitle = LocalizedStringResource(stringLiteral: url.absoluteString)
        }
        
        let image = DisplayRepresentation.Image(systemName: "link.circle.fill")
        
        return DisplayRepresentation(
            title: displayTitle,
            subtitle: displaySubtitle,
            image: image
        )
    }
    
    // MARK: - Link fields
    var url: URL?
    var title: String?
    var summary: String?
    var status: ProcessingStatus  // Should match your enum in DiverKit
    var tags: [String]
    var createdAt: Date
    var wrappedLink: String?
    var isShared: Bool
    var attributionID: String?
    
    // MARK: - Initializers
    /// Initialize from ProcessedItem model
    init(processedItem: ProcessedItem) {
        self.id = processedItem.id
        self.url = URL(string: processedItem.url ?? "about.blank")
        self.title = processedItem.title
        self.summary = processedItem.summary
        self.status = processedItem.status
        self.tags = processedItem.tags
        self.createdAt = processedItem.createdAt
        self.wrappedLink = processedItem.wrappedLink
        self.attributionID = processedItem.attributionID
        // If attributionID is present, it's from Shared with You
        self.isShared = processedItem.attributionID != nil
    }
    
    /// For direct construction
    init(
        id: String,
        url: URL?,
        title: String?,
        summary: String?,
        status: ProcessingStatus,
        tags: [String],
        createdAt: Date,
        wrappedLink: String?,
        isShared: Bool = false,
        attributionID: String? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.summary = summary
        self.status = status
        self.tags = tags
        self.createdAt = createdAt
        self.wrappedLink = wrappedLink
        self.isShared = isShared
        self.attributionID = attributionID
    }
}

extension LinkEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { entity in
            entity.wrappedLink ?? ""
        })
    }
}
