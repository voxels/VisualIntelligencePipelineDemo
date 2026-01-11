//
//  LinkMetadata.swift
//  ActionExtension
//
//  Created by Claude on 12/24/25.
//

import Foundation

struct LinkMetadata {
    let title: String?
    let description: String?
    let imageURL: URL?
    let domain: String

    init(url: URL, title: String? = nil, description: String? = nil, imageURL: URL? = nil) {
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.domain = url.host ?? url.absoluteString
    }

    /// Placeholder metadata for immediate display while fetching
    static func placeholder(for url: URL) -> LinkMetadata {
        LinkMetadata(
            url: url,
            title: url.host ?? "Link",
            description: url.absoluteString,
            imageURL: nil
        )
    }
}
