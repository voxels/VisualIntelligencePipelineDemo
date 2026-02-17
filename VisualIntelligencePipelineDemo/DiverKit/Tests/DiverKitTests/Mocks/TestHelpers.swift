import XCTest
import SwiftData
import CoreLocation
import DiverShared
@testable import DiverKit

// MARK: - In-Memory SwiftData Helpers

/// Creates an in-memory `UnifiedDataManager` for testing. Returns the manager so both `container` and `mainContext` are accessible.
@MainActor
func makeTestDataManager() -> UnifiedDataManager {
    return UnifiedDataManager(inMemory: true)
}

// MARK: - ProcessedItem Factory

/// Creates a `ProcessedItem` with sensible defaults. Override any parameter as needed.
func makeProcessedItem(
    id: String = UUID().uuidString,
    url: String? = nil,
    title: String? = "Test Item",
    status: ProcessingStatus = .ready,
    sessionID: String? = nil,
    createdAt: Date = Date(),
    location: String? = nil,
    tags: [String] = [],
    summary: String? = nil,
    entityType: String? = "web"
) -> ProcessedItem {
    let item = ProcessedItem(
        id: id,
        url: url ?? "https://example.com/\(id)",
        title: title,
        status: status,
        sessionID: sessionID
    )
    item.createdAt = createdAt
    item.location = location
    item.tags = tags
    item.summary = summary
    item.entityType = entityType
    return item
}

// MARK: - Session Factory

/// Creates a `SessionMetadata` with sensible defaults.
func makeSession(
    sessionID: String = UUID().uuidString,
    title: String = "Test Session",
    createdAt: Date = Date(),
    latitude: Double? = nil,
    longitude: Double? = nil,
    collectionID: String? = nil
) -> SessionMetadata {
    let session = SessionMetadata(sessionID: sessionID, title: title)
    session.createdAt = createdAt
    if let lat = latitude, let lon = longitude {
        session.latitude = lat
        session.longitude = lon
    }
    session.collectionID = collectionID
    return session
}

// MARK: - Collection Factory

/// Creates a `SessionCollection` with sensible defaults.
func makeCollection(
    collectionID: String = UUID().uuidString,
    name: String = "Test Collection",
    sessionIDs: [String] = []
) -> SessionCollection {
    let collection = SessionCollection(collectionID: collectionID, name: name)
    collection.sessionIDs = sessionIDs
    return collection
}

// MARK: - ImportedAsset Factory

/// Creates an `ImportedAsset` with minimal dummy data for clustering tests.
func makeImportedAsset(
    id: String = UUID().uuidString,
    creationDate: Date? = Date(),
    latitude: Double? = nil,
    longitude: Double? = nil,
    isVideo: Bool = false,
    isScreenshot: Bool = false,
    isScreenRecording: Bool = false
) -> ImportedAsset {
    let location: CLLocationCoordinate2D?
    if let lat = latitude, let lon = longitude {
        location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    } else {
        location = nil
    }
    return ImportedAsset(
        id: id,
        data: Data([0x00, 0x01, 0x02, 0x03]), // Minimal dummy data
        isVideo: isVideo,
        isScreenshot: isScreenshot,
        isScreenRecording: isScreenRecording,
        creationDate: creationDate,
        location: location
    )
}

// MARK: - Queue Helpers

/// Creates a temporary directory for queue store testing. Caller must clean up.
func makeTemporaryDirectory() throws -> URL {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
    return tempURL
}

// MARK: - DiverItemDescriptor Factory

/// Creates a `DiverItemDescriptor` with sensible defaults.
func makeDescriptor(
    id: String = UUID().uuidString,
    url: String = "https://example.com",
    title: String = "Test",
    type: DiverItemType = .web,
    attributionID: String? = nil,
    sessionID: String? = nil
) -> DiverItemDescriptor {
    DiverItemDescriptor(
        id: id,
        url: url,
        title: title,
        type: type,
        attributionID: attributionID,
        sessionID: sessionID
    )
}
