import Foundation

public struct AppGroupConfig: Sendable, Equatable {
    public let groupIdentifier: String
    public let keychainAccessGroup: String
    public let cloudKitContainers: [String]

    public init(
        groupIdentifier: String,
        keychainAccessGroup: String,
        cloudKitContainers: [String]
    ) {
        self.groupIdentifier = groupIdentifier
        self.keychainAccessGroup = keychainAccessGroup
        self.cloudKitContainers = cloudKitContainers
    }

    public static let `default` = AppGroupConfig(
        groupIdentifier: "group.com.secretatomics.VisualIntelligence",
        keychainAccessGroup: "23264QUM9A.com.secretatomics.Diver.shared",
        cloudKitContainers: [
            "iCloud.com.secretatomics.knowmaps.Cache",
            "iCloud.com.secretatomics.knowmaps.Keys"
        ]
    )
}

public enum AppGroupError: Error, LocalizedError {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let groupIdentifier):
            return "App group container unavailable for \(groupIdentifier)."
        }
    }
}

public enum AppGroupContainer {
    public typealias URLProvider = (String) -> URL?

    public static let defaultStoreName = "Diver.sqlite"

    public static func containerURL(
        config: AppGroupConfig = .default,
        urlProvider: URLProvider = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    ) throws -> URL {
        guard let url = urlProvider(config.groupIdentifier) else {
            throw AppGroupError.unavailable(config.groupIdentifier)
        }
        return url
    }

    public static func dataStoreURL(
        config: AppGroupConfig = .default,
        storeName: String = defaultStoreName,
        urlProvider: URLProvider = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    ) throws -> URL {
        let baseURL = try containerURL(config: config, urlProvider: urlProvider)
        return baseURL.appendingPathComponent(storeName)
    }

    public static func queueDirectoryURL(
        config: AppGroupConfig = .default,
        fileManager: FileManager = .default,
        createDirectories: Bool = true,
        urlProvider: URLProvider = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    ) -> URL? {
        do {
            let baseURL = try containerURL(config: config, urlProvider: urlProvider)
            let queueURL = baseURL.appendingPathComponent("Queue", isDirectory: true)
            if createDirectories {
                try fileManager.createDirectory(at: queueURL, withIntermediateDirectories: true)
            }
            return queueURL
        }
        catch {
            print(error)
        }
        return nil
    }
}
