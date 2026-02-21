import Foundation
import SwiftData

/// SessionCollection is the public name for DiverCollection.
/// The @Model class retains its original name to preserve SwiftData schema compatibility.
public typealias SessionCollection = DiverCollection


@Model
public final class SessionMetadata: Identifiable, DiverObject {
    public var sessionID: String = UUID().uuidString
    
    @Transient
    public var id: String { sessionID }
    public var title: String? = nil
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var latitude: Double? = nil
    public var longitude: Double? = nil
    public var placeID: String? = nil
    public var locationName: String? = nil
    public var summary: String? = nil
    public var isFavorite: Bool = false
    public var thumbnailAssetIdentifier: String? = nil
    
    /// Reference to parent collection (if part of an imported album)

    public var collectionID: String? = nil
    
    @Relationship(deleteRule: .cascade, inverse: \ProcessedItem.session)
    public var items: [ProcessedItem]? = []
    
    public var parentCollection: DiverCollection?
    
    /// Array of file paths to aesthetic-scored thumbnail images
    public var thumbnailPaths: [String] = []
    
    // MARK: - Phase 5 (Temporal & Social)
    
    /// Optional file path to the temporal video component of a Live Photo or burst sequence.
    public var livePhotoVideoPath: String? = nil
    
    /// Array of Apple Contacts Framework (CNContact) identifiers associated with this session's subject.
    public var contactIdentifiers: [String]? = []
    
    public init(sessionID: String = UUID().uuidString, title: String? = nil, summary: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), latitude: Double? = nil, longitude: Double? = nil, placeID: String? = nil, locationName: String? = nil, collectionID: String? = nil, isFavorite: Bool = false, thumbnailAssetIdentifier: String? = nil, thumbnailPaths: [String] = [], livePhotoVideoPath: String? = nil, contactIdentifiers: [String]? = []) {

        self.sessionID = sessionID
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.latitude = latitude
        self.longitude = longitude
        self.placeID = placeID
        self.locationName = locationName
        self.collectionID = collectionID
        self.isFavorite = isFavorite
        self.thumbnailAssetIdentifier = thumbnailAssetIdentifier
        self.thumbnailPaths = thumbnailPaths
        self.livePhotoVideoPath = livePhotoVideoPath
        self.contactIdentifiers = contactIdentifiers
    }
    
    // MARK: - DiverObject Conformance
    
    public var displayTitle: String {
        if let title = title, !title.isEmpty { return title }
        if let location = locationName, !location.isEmpty { return location }
        return createdAt.formatted(date: .abbreviated, time: .shortened)
    }
    
    public func asDTO() -> DiverObjectDTO {
        DiverObjectDTO(
            id: sessionID,
            title: displayTitle,
            summary: summary,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isFavorite: isFavorite,
            type: .session
        )
    }
}


