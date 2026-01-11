import Foundation

/// Reference search sources
public enum SearchSource: String, Codable, Hashable, CaseIterable, Sendable {
    case openlibrary
    case spotify
}