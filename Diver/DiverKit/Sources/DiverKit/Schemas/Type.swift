import Foundation

/// Search source type (music, book, etc.)
public enum Type: String, Codable, Hashable, CaseIterable, Sendable {
    case music
    case book
}