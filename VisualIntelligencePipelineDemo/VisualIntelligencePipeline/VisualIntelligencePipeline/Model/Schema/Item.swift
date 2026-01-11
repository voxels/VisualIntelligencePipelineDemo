//
//  Item.swift
//  Diver
//
//  Created by Michael A Edgcumbe on 12/22/25.
//

import Foundation
import SwiftData
import DiverShared

@Model
final class Item {
    @Attribute(.unique) var id: String
    var url: String
    var title: String
    var descriptionText: String?
    var styleTags: [String]
    var categories: [String]
    var location: String?
    var price: Double?
    var createdAt: Date

    init(
        id: String,
        url: URL,
        title: String,
        descriptionText: String? = nil,
        styleTags: [String] = [],
        categories: [String] = [],
        location: String? = nil,
        price: Double? = nil,
        createdAt: Date = Date()
    ) {
        let resolvedTitle = title.isEmpty ? (url.host ?? url.absoluteString) : title

        self.id = id
        self.url = url.absoluteString
        self.title = resolvedTitle
        self.descriptionText = descriptionText
        self.styleTags = styleTags
        self.categories = categories
        self.location = location
        self.price = price
        self.createdAt = createdAt
    }

    convenience init(
        url: URL,
        title: String,
        descriptionText: String? = nil,
        styleTags: [String] = [],
        categories: [String] = [],
        location: String? = nil,
        price: Double? = nil,
        createdAt: Date = Date(),
        salt: String? = nil
    ) {
        self.init(
            id: Item.urlHash(for: url, salt: salt),
            url: url,
            title: title,
            descriptionText: descriptionText,
            styleTags: styleTags,
            categories: categories,
            location: location,
            price: price,
            createdAt: createdAt
        )
    }

    var urlValue: URL? {
        URL(string: url)
    }

    static func urlHash(for url: URL, salt: String? = nil, length: Int = 24) -> String {
        DiverLinkWrapper.id(for: url, salt: salt, length: length)
    }
}

extension Item {
    var descriptor: DiverItemDescriptor? {
        guard let urlValue = urlValue else { return nil }
        return DiverItemDescriptor(
            id: id,
            url: urlValue.absoluteString,
            title: title,
            descriptionText: descriptionText,
            styleTags: styleTags,
            categories: categories,
            location: location,
            price: price,
            createdAt: createdAt
        )
    }
}
