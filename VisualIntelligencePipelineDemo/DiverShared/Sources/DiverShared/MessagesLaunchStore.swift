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
    private static func fileURL(config: AppGroupConfig) -> URL? {
        guard let baseURL = try? AppGroupContainer.containerURL(config: config) else { return nil }
        return baseURL.appendingPathComponent("messages_launch_request.json")
    }

    public static func save(
        body: String?,
        config: AppGroupConfig = .default
    ) {
        let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedBody = trimmedBody.map { String($0.prefix(2000)) }
        let request = MessagesLaunchRequest(body: boundedBody)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(request) else {
            return
        }

        if let url = fileURL(config: config) {
            try? data.write(to: url)
        }
    }

    public static func consume(
        config: AppGroupConfig = .default
    ) -> MessagesLaunchRequest? {
        guard let url = fileURL(config: config),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let request = try? decoder.decode(MessagesLaunchRequest.self, from: data) else {
            // Remove corrupted data
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        // Remove after consuming
        try? FileManager.default.removeItem(at: url)
        return request
    }
}
