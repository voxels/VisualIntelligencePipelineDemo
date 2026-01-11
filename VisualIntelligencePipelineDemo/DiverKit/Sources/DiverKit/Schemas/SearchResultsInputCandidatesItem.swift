import Foundation

public enum SearchResultsInputCandidatesItem: Codable, Hashable, Sendable {
    case openLibraryBook(OpenLibraryBook)
    case spotifyAlbum(SpotifyAlbum)
    case spotifyTrack(SpotifyTrack)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(OpenLibraryBook.self) {
            self = .openLibraryBook(value)
        } else if let value = try? container.decode(SpotifyAlbum.self) {
            self = .spotifyAlbum(value)
        } else if let value = try? container.decode(SpotifyTrack.self) {
            self = .spotifyTrack(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unexpected value."
            )
        }
    }

    public func encode(to encoder: Encoder) throws -> Void {
        var container = encoder.singleValueContainer()
        switch self {
        case .openLibraryBook(let value):
            try container.encode(value)
        case .spotifyAlbum(let value):
            try container.encode(value)
        case .spotifyTrack(let value):
            try container.encode(value)
        }
    }
}