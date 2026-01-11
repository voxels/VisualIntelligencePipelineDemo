import Foundation

public enum DiverListLabel {
    public static let `default` = "Diver"
}

public enum DiverItemType: String, Codable, Equatable, Hashable, Sendable {
    case web
    case place
    case text
    case document
    case image
    case activity
    case qrCode
    case weather
    case product
    case media
}

public struct DiverItemDescriptor: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let url: String
    public let title: String
    public let descriptionText: String?
    public let styleTags: [String]
    public let categories: [String]
    public let location: String?
    public let price: Double?
    public let createdAt: Date
    public let type: DiverItemType
    public let attributionID: String?
    public let purpose: String?
    public let wrappedLink: String?
    public let masterCaptureID: String?
    public let sessionID: String?
    public let coverImageURL: URL?
    public let placeID: String?
    public let latitude: Double?
    public let longitude: Double?
    public var purposes: [String] = []
    public var processingLog: [String] = []
    
    public var tags: [String] { styleTags }

    public init(
        id: String,
        url: String,
        title: String,
        descriptionText: String? = nil,
        styleTags: [String] = [],
        categories: [String] = [],
        location: String? = nil,
        price: Double? = nil,
        createdAt: Date = Date(),
        type: DiverItemType = .web,
        attributionID: String? = nil,
        purpose: String? = nil,
        wrappedLink: String? = nil,
        masterCaptureID: String? = nil,
        sessionID: String? = nil,
        coverImageURL: URL? = nil,
        placeID: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        purposes: [String] = [],
        processingLog: [String] = []
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.descriptionText = descriptionText
        self.styleTags = styleTags
        self.categories = categories
        self.location = location
        self.price = price
        self.createdAt = createdAt
        self.type = type
        self.attributionID = attributionID
        self.purpose = purpose
        self.wrappedLink = wrappedLink
        self.masterCaptureID = masterCaptureID
        self.sessionID = sessionID
        self.coverImageURL = coverImageURL
        self.placeID = placeID
        self.latitude = latitude
        self.longitude = longitude
        self.processingLog = processingLog
        
        // Migrate legacy purpose if needed
        var combined = purposes
        if let p = purpose, !combined.contains(p) {
            combined.append(p)
        }
        self.purposes = combined
    }

    public var urlValue: URL? {
        URL(string: url)
    }
}

public extension DiverItemDescriptor {
    func preferredListLabel(preferred: String?) -> String {
        let resolvedPreferred = preferred?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !resolvedPreferred.isEmpty {
            return resolvedPreferred
        }

        if let category = categories
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty })
        {
            return category
        }

        if let styleTag = styleTags
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty })
        {
            return styleTag
        }

        return DiverListLabel.default
    }
}
