//
//  KnowMapsModels_Mac.swift
//  VisualIntelligenceMac
//
//  Local shim for knowmaps models to avoid broken UI dependencies on macOS.
//  Matches the original definitions in the knowmaps package for CloudKit compatibility.
//

import Foundation
import SwiftData

@Model
public class UserCachedRecord: Identifiable, Hashable, Equatable, Codable {
    public var id: UUID = UUID()
    var recordId: String = UUID().uuidString
    var group: String = ""
    var identity: String = ""
    var title: String = ""
    var icons: String = ""
    var list: String = ""
    var section: String = ""
    var rating: Double = 0

    public init(id: UUID = UUID(), recordId: String, group: String, identity: String, title: String, icons: String, list: String, section: String, rating: Double) {
        self.id = id
        self.recordId = recordId
        self.group = group
        self.identity = identity
        self.title = title
        self.icons = icons
        self.list = list
        self.section = section
        self.rating = rating
    }

    public func setRecordId(to string: String) {
        recordId = string
    }

    // MARK: - Codable Conformance

    enum CodingKeys: String, CodingKey {
        case id
        case recordId
        case group
        case identity
        case title
        case icons
        case list
        case section
        case rating
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(recordId, forKey: .recordId)
        try container.encode(group, forKey: .group)
        try container.encode(identity, forKey: .identity)
        try container.encode(title, forKey: .title)
        try container.encode(icons, forKey: .icons)
        try container.encode(list, forKey: .list)
        try container.encode(section, forKey: .section)
        try container.encode(rating, forKey: .rating)
    }

    public required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let recordId = try container.decode(String.self, forKey: .recordId)
        let group = try container.decode(String.self, forKey: .group)
        let identity = try container.decode(String.self, forKey: .identity)
        let title = try container.decode(String.self, forKey: .title)
        let icons = try container.decode(String.self, forKey: .icons)
        let list = try container.decode(String.self, forKey: .list)
        let section = try container.decode(String.self, forKey: .section)
        let rating = try container.decode(Double.self, forKey: .rating)
        self.init(id: id, recordId: recordId, group: group, identity: identity, title: title, icons: icons, list: list, section: section, rating: rating)
    }
}

@Model
public final class RecommendationData: Identifiable, Hashable, Equatable, Codable {
    public var id: UUID = UUID()
    var recordId: String = UUID().uuidString
    var identity: String = ""
    var attributes: [String] = []
    var reviews: [String] = []
    var attributeRatings: [String: Double] = [:]
    
    public init(
        id: UUID = UUID(),
        recordId: String,
        identity: String,
        attributes: [String],
        reviews: [String],
        attributeRatings: [String: Double]
    ) {
        self.id = id
        self.recordId = recordId
        self.identity = identity
        self.attributes = attributes
        self.reviews = reviews
        self.attributeRatings = attributeRatings
    }
    
    public func setRecordId(to string: String) {
        recordId = string
    }
    
    // MARK: - Codable Conformance
    
    enum CodingKeys: String, CodingKey {
        case id
        case recordId
        case identity
        case attributes
        case reviews
        case attributeRatings
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(recordId, forKey: .recordId)
        try container.encode(identity, forKey: .identity)
        try container.encode(attributes, forKey: .attributes)
        try container.encode(reviews, forKey: .reviews)
        try container.encode(attributeRatings, forKey: .attributeRatings)
    }
    
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let recordId = try container.decode(String.self, forKey: .recordId)
        let identity = try container.decode(String.self, forKey: .identity)
        let attributes = try container.decode([String].self, forKey: .attributes)
        let reviews = try container.decode([String].self, forKey: .reviews)
        let attributeRatings = try container.decode([String: Double].self, forKey: .attributeRatings)
        
        self.init(
            id: id,
            recordId: recordId,
            identity: identity,
            attributes: attributes,
            reviews: reviews,
            attributeRatings: attributeRatings
        )
    }
}
