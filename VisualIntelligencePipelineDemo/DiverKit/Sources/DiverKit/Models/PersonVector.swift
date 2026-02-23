import Foundation
import SwiftData

/// Represents a vectorized face extracted from a PHPerson or local capture for on-device identity matching.
@Model
public final class PersonVector: Identifiable {
    @Attribute(.unique) public var id: String
    
    /// The display name extracted from the Photos library (if assigned by the user).
    public var name: String?
    
    /// The underlying PHPerson local identifier from the user's photo library.
    public var localIdentifier: String
    
    /// Serialized VNFeaturePrintObservation data. Stored externally as it can be large.
    @Attribute(.externalStorage) public var featurePrintData: Data
    
    /// A lightweight thumbnail of the person's face for UI display without needing to hit PhotoKit.
    public var faceCropData: Data?
    
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(id: String = UUID().uuidString,
                name: String? = nil,
                localIdentifier: String,
                featurePrintData: Data,
                faceCropData: Data? = nil) {
        self.id = id
        self.name = name
        self.localIdentifier = localIdentifier
        self.featurePrintData = featurePrintData
        self.faceCropData = faceCropData
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
