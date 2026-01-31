import Foundation
import SwiftData

/// A top-level collection for organizing related sessions (e.g., imported albums, work projects).
/// Contains user-editable summary and auto-generated LLM summary.
@Model
public final class DiverCollection: Identifiable {
    public var collectionID: String = UUID().uuidString
    public var name: String = "Untitled Collection"
    
    /// User-defined contextual summary (editable)
    public var userSummary: String? = nil
    
    /// Auto-generated LLM summary of all contents and metadata
    public var llmSummary: String? = nil
    
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    
    /// IDs of sessions belonging to this collection
    public var sessionIDs: [String] = []
    
    /// Source album name from Photos library (if imported)
    public var sourceAlbumName: String? = nil
    
    public init(
        collectionID: String = UUID().uuidString,
        name: String,
        userSummary: String? = nil,
        llmSummary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sessionIDs: [String] = [],
        sourceAlbumName: String? = nil
    ) {
        self.collectionID = collectionID
        self.name = name
        self.userSummary = userSummary
        self.llmSummary = llmSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessionIDs = sessionIDs
        self.sourceAlbumName = sourceAlbumName
    }
}
