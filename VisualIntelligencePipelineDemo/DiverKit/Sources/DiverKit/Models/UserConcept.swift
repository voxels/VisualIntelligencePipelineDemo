import Foundation
import SwiftData

@Model
public final class UserConcept: Identifiable {
    public var name: String = ""
    public var definition: String = ""
    public var anchorEmbedding: [Double]?
    public var createdAt: Date = Date()
    public var weight: Double = 1.0 // Default weight
    
    public init(name: String, definition: String, anchorEmbedding: [Double]? = nil, weight: Double = 1.0) {
        self.name = name
        self.definition = definition
        self.anchorEmbedding = anchorEmbedding
        self.weight = weight
        self.createdAt = Date()
    }
}
