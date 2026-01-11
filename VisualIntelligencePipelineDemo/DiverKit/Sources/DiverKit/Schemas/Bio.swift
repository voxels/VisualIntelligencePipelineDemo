import Foundation

/// Biography (structured or plain text)
public enum Bio: Codable, Hashable, Sendable {
    case authorBio(AuthorBio)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(AuthorBio.self) {
            self = .authorBio(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
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
        case .authorBio(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}