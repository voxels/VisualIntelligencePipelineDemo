import Foundation

/// Media file type categories
public enum MediaTypeEnum: String, Codable, Hashable, CaseIterable, Sendable {
    case image
    case video
    case audio
    case document
}