import Foundation
import SwiftData

@Model
public final class SessionMetadata {
    public var sessionID: String = UUID().uuidString
    public var title: String? = nil
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var latitude: Double? = nil
    public var longitude: Double? = nil
    public var placeID: String? = nil
    public var locationName: String? = nil
    public var summary: String? = nil
    
    public init(sessionID: String, title: String? = nil, summary: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), latitude: Double? = nil, longitude: Double? = nil, placeID: String? = nil, locationName: String? = nil) {
        self.sessionID = sessionID
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.latitude = latitude
        self.longitude = longitude
        self.placeID = placeID
        self.locationName = locationName
    }
}
