import Foundation
import SwiftData

/// A top-level collection for organizing related sessions (e.g., imported albums, work projects).
/// Contains user-editable summary and auto-generated LLM summary.
@Model
public final class DiverCollection: Identifiable, DiverObject {
    public var collectionID: String = UUID().uuidString
    
    @Transient
    public var id: String { collectionID }
    
    public var displayTitle: String { name }
    public var name: String = "Untitled Collection"
    
    /// User-defined contextual summary (editable)
    public var userSummary: String? = nil
    
    /// Auto-generated LLM summary of all contents and metadata
    public var llmSummary: String? = nil
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var isFavorite: Bool = false
    public var coverImagePath: String? = nil
    
    /// Array of session IDs assigned to this collection
    public var sessionIDs: [String] = []
    
    /// Source album name from Photos library (if imported)
    public var sourceAlbumName: String? = nil
    
    @Relationship(deleteRule: .nullify, inverse: \SessionMetadata.parentCollection)
    public var sessions: [SessionMetadata]? = []
    
    public init(collectionID: String = UUID().uuidString, name: String, userSummary: String? = nil, llmSummary: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), isFavorite: Bool = false, coverImagePath: String? = nil, sessionIDs: [String] = [], sourceAlbumName: String? = nil) {

        self.collectionID = collectionID
        self.name = name
        self.userSummary = userSummary
        self.llmSummary = llmSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.coverImagePath = coverImagePath
        self.sessionIDs = sessionIDs
        self.sourceAlbumName = sourceAlbumName
    }
    
    public func asDTO() -> DiverObjectDTO {
        DiverObjectDTO(
            id: collectionID,
            title: name,
            summary: llmSummary,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isFavorite: isFavorite,
            type: .collection
        )
    }
}
