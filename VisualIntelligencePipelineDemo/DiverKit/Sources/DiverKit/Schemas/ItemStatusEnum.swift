import Foundation

/// Processing status for items
public enum ItemStatusEnum: String, Codable, Hashable, CaseIterable, Sendable {
    case queued
    case cached
    case analyzed
    case classified
    case researching
    case ready
}