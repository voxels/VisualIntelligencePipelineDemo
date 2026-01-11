import Foundation

/// Represents a pipeline log fixture loaded from JSON
public struct PipelineLogFixture: Codable {
    public let logs: [LogEntry]

    public struct LogEntry: Codable {
        public let sourceFile: String
        public let jobUuid: String
        public let inputId: String
        public let entries: [LogEntryItem]

        enum CodingKeys: String, CodingKey {
            case sourceFile = "source_file"
            case jobUuid = "job_uuid"
            case inputId = "input_id"
            case entries
        }
    }

    public struct LogEntryItem: Codable {
        public let category: String?
        public let payload: PayloadWrapper
        public let context: String
    }

    public struct PayloadWrapper: Codable {
        public let messageType: String?
        public let type: String?
        public let createdReferences: [ReferenceEntity]?
        public let candidates: [ReferenceCandidate]?

        enum CodingKeys: String, CodingKey {
            case messageType = "message_type"
            case type
            case createdReferences = "created_references"
            case candidates
        }
    }

    public struct ReferenceEntity: Codable {
        public let entityType: String
        public let name: String
        public let referenceMetadata: ReferenceMetadata
        public let id: String
        public let userId: String

        enum CodingKeys: String, CodingKey {
            case entityType = "entity_type"
            case name
            case referenceMetadata = "reference_metadata"
            case id
            case userId = "user_id"
        }
    }

    public struct ReferenceMetadata: Codable {
        public let title: String?
        public let artists: [String]?
        public let albumType: String?
        public let spotifyId: String?
        public let entityType: String?
        public let releaseDate: String?
        public let totalTracks: Int?
        public let externalUrls: [String: String]?
        public let authors: [FixtureAuthor]?
        public let isbn: String?
        public let publisher: String?
        public let description: String?
        public let coverUrl: String?

        enum CodingKeys: String, CodingKey {
            case title, artists, description, isbn, publisher, authors
            case albumType = "album_type"
            case spotifyId = "spotify_id"
            case entityType = "entity_type"
            case releaseDate = "release_date"
            case totalTracks = "total_tracks"
            case externalUrls = "external_urls"
            case coverUrl = "cover_url"
        }
    }

    public struct FixtureAuthor: Codable {
        public let name: String
    }

    public struct ReferenceCandidate: Codable {
        public let title: String?
        public let entityType: String?
        public let artists: [String]?
        public let spotifyId: String?
        public let externalUrls: [String: String]?

        enum CodingKeys: String, CodingKey {
            case title, artists
            case entityType = "entity_type"
            case spotifyId = "spotify_id"
            case externalUrls = "external_urls"
        }
    }
}

/// Utility for loading pipeline log fixtures from JSON files
public enum PipelineLogFixtureLoader {
    /// Load a pipeline log fixture from a JSON file
    public static func load(from url: URL) throws -> PipelineLogFixture {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(PipelineLogFixture.self, from: data)
    }

    /// Load pipeline_logs.json from the test bundle
    public static func loadDefault() throws -> PipelineLogFixture {
        guard let url = Bundle.module.url(forResource: "pipeline_logs", withExtension: "json") else {
            throw FixtureError.fileNotFound("pipeline_logs.json")
        }
        return try load(from: url)
    }

    /// Extract all reference entities from a fixture
    public static func extractReferences(from fixture: PipelineLogFixture) -> [PipelineLogFixture.ReferenceEntity] {
        fixture.logs.flatMap { log in
            log.entries.compactMap { entry in
                entry.payload.createdReferences
            }.flatMap { $0 }
        }
    }

    /// Extract all reference candidates from a fixture
    public static func extractCandidates(from fixture: PipelineLogFixture) -> [PipelineLogFixture.ReferenceCandidate] {
        fixture.logs.flatMap { log in
            log.entries.compactMap { entry in
                entry.payload.candidates
            }.flatMap { $0 }
        }
    }
}

public enum FixtureError: Error, LocalizedError {
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let filename):
            return "Fixture file not found: \(filename)"
        }
    }
}
