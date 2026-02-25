import Foundation

public struct DiverQueueItem: Codable, Hashable, Sendable {
    public let id: UUID
    public let action: String
    public let descriptor: DiverItemDescriptor
    public let source: String?
    public let createdAt: Date
    public let payload: Data?
    public let payloadURL: URL?
    public let attachments: [Data]?
    
    /// PHAsset identifier for photo library imports - allows deferred data loading
    public let photosAssetIdentifier: String?
    /// Depth map data from LiDAR/dual camera capture
    public let depthPayload: Data?
    
    // Convenience for backward compatibility or easy access
    public var purposes: Set<String> { descriptor.purposes }

    public init(
        id: UUID = UUID(),
        action: String,
        descriptor: DiverItemDescriptor,
        source: String? = nil,
        createdAt: Date = Date(),
        payload: Data? = nil,
        payloadURL: URL? = nil,
        attachments: [Data]? = nil,
        photosAssetIdentifier: String? = nil,
        depthPayload: Data? = nil
    ) {
        self.id = id
        self.action = action
        self.descriptor = descriptor
        self.source = source
        self.createdAt = createdAt
        self.payload = payload
        self.payloadURL = payloadURL
        self.attachments = attachments
        self.photosAssetIdentifier = photosAssetIdentifier
        self.depthPayload = depthPayload
    }
    

}

public struct DiverQueueRecord: Hashable, Sendable {
    public let item: DiverQueueItem
    public let fileURL: URL
    
    public init(item: DiverQueueItem, fileURL: URL) {
        self.item = item
        self.fileURL = fileURL
    }
}

final public class DiverQueueStore: Sendable {
    public let directoryURL: URL
    private let fileManager: FileManager

    public init(
        directoryURL: URL,
        fileManager: FileManager = .default
    ) throws {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        try ensureDirectory()
    }

    @discardableResult
    public func enqueue(_ item: DiverQueueItem) throws -> DiverQueueRecord {
        let filename = Self.filename(for: item)
        let fileURL = directoryURL.appendingPathComponent(filename)
        let encoder = Self.createEncoder()
        let data = try encoder.encode(item)
        try data.write(to: fileURL, options: [.atomic])
        return DiverQueueRecord(item: item, fileURL: fileURL)
    }

    public func pendingEntries() throws -> [DiverQueueRecord] {
        // Ensure directory exists before listing
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try ensureDirectory()
            return [] // Directory was just created, no entries yet
        }
        
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let decoder = Self.createDecoder()
        var records: [DiverQueueRecord] = []
        for fileURL in contents where fileURL.pathExtension.lowercased() == "json" {
            let data = try Data(contentsOf: fileURL)
            let item = try decoder.decode(DiverQueueItem.self, from: data)
            records.append(DiverQueueRecord(item: item, fileURL: fileURL))
        }
        return records.sorted { $0.item.createdAt < $1.item.createdAt }
    }

    public func remove(_ record: DiverQueueRecord) throws {
        do {
            try fileManager.removeItem(at: record.fileURL)
        } catch {
            // If file is already gone, consider it removed to prevent infinite loops
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError {
                return
            }
            throw error
        }
    }

    public func removeAll() throws {
        let records = try pendingEntries()
        for record in records {
            try remove(record)
        }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private static func filename(for item: DiverQueueItem) -> String {
        let timestamp = Int(item.createdAt.timeIntervalSince1970 * 1000)
        return "\(timestamp)-\(item.id.uuidString).json"
    }

    private static func createEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func createDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
