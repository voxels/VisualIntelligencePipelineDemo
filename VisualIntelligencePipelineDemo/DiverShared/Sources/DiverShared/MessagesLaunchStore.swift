import Foundation

public struct MessagesLaunchRequest: Codable, Sendable, Equatable {
    public let body: String?
    public let createdAt: Date

    public init(body: String?, createdAt: Date = Date()) {
        self.body = body
        self.createdAt = createdAt
    }
}

public enum MessagesLaunchStore {
    private static let key = "Diver.MessagesLaunchRequest"

    public static func save(
        body: String?,
        config: AppGroupConfig = .default,
        defaults: UserDefaults? = nil
    ) {
        let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedBody = trimmedBody.map { String($0.prefix(2000)) }
        let request = MessagesLaunchRequest(body: boundedBody)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(request) else {
            return
        }

        let storage = defaults ?? UserDefaults(suiteName: config.groupIdentifier)
        storage?.set(data, forKey: key)
    }

    public static func consume(
        config: AppGroupConfig = .default,
        defaults: UserDefaults? = nil
    ) -> MessagesLaunchRequest? {
        let storage = defaults ?? UserDefaults(suiteName: config.groupIdentifier)

        guard let data = storage?.data(forKey: key) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let request = try? decoder.decode(MessagesLaunchRequest.self, from: data) else {
            // Remove corrupted data
            storage?.removeObject(forKey: key)
            return nil
        }

        storage?.removeObject(forKey: key)
        return request
    }
}
