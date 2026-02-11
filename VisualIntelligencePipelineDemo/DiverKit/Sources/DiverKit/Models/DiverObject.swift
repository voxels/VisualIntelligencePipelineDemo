import Foundation

/// A protocol for the core data models to share common metadata.
public protocol DiverObject: Identifiable {
    var id: String { get }
    var displayTitle: String { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var isFavorite: Bool { get set }
}

/// A Sendable Data Transfer Object for thread-safe cross-actor communication.
/// This allows passing model state across Task boundaries without exposing
/// non-Sendable SwiftData models.
public struct DiverObjectDTO: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let summary: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let isFavorite: Bool
    public let type: DiverObjectType
    
    public init(id: String, title: String, summary: String? = nil, createdAt: Date, updatedAt: Date, isFavorite: Bool, type: DiverObjectType) {
        self.id = id
        self.title = title
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.type = type
    }
}

public enum DiverObjectType: String, Sendable, Codable {
    case item
    case session
    case collection
}

public extension DiverObject {
    /// Helper to convert a relative date to a string.
    var relativeUpdatedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }
}
