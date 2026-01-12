import Foundation

public struct ContextSnapshot: Codable, Sendable {
    public let weather: WeatherContext?
    public let activity: ActivityContext?
    public let place: PlaceContext?
    public let timestamp: Date
    
    public init(weather: WeatherContext? = nil, activity: ActivityContext? = nil, place: PlaceContext? = nil, timestamp: Date = Date()) {
        self.weather = weather
        self.activity = activity
        self.place = place
        self.timestamp = timestamp
    }
}

public struct WeatherContext: Codable, Sendable {
    public let condition: String // e.g., "Rainy", "Cloudy"
    public let temperatureCelsius: Double
    public let symbolName: String // SF Symbol name
    
    public init(condition: String, temperatureCelsius: Double, symbolName: String) {
        self.condition = condition
        self.temperatureCelsius = temperatureCelsius
        self.symbolName = symbolName
    }
}

public struct ActivityContext: Codable, Sendable {
    public let type: String // "walking", "automotive", "stationary", "unknown"
    public let confidence: String // "high", "medium", "low"
    
    public init(type: String, confidence: String) {
        self.type = type
        self.confidence = confidence
    }
}

public struct PlaceContext: Codable, Sendable {
    public let name: String?
    public let categories: [String]
    public let placeID: String?
    public let address: String?
    public let rating: Double?
    public let isOpen: Bool?
    public let latitude: Double?
    public let longitude: Double?
    public let priceLevel: String?
    public let phoneNumber: String?
    public let website: String?
    public let photos: [String]?
    public let tips: [String]?
    
    public init(name: String? = nil, categories: [String] = [], placeID: String? = nil, address: String? = nil, rating: Double? = nil, isOpen: Bool? = nil, latitude: Double? = nil, longitude: Double? = nil, priceLevel: String? = nil, phoneNumber: String? = nil, website: String? = nil, photos: [String]? = nil, tips: [String]? = nil) {
        self.name = name
        self.categories = categories
        self.placeID = placeID
        self.address = address
        self.rating = rating
        self.isOpen = isOpen
        self.latitude = latitude
        self.longitude = longitude
        self.priceLevel = priceLevel
        self.phoneNumber = phoneNumber
        self.website = website
        self.photos = photos
        self.tips = tips
    }
}

public struct WebContext: Codable, Sendable {
    public var siteName: String?
    public var faviconURL: String?
    public var readingTimeMinutes: Int?
    public var isReaderAvailable: Bool
    public var snapshotURL: String?
    public var textContent: String?
    public var structuredData: String? // JSON String
    
    public init(siteName: String? = nil, faviconURL: String? = nil, readingTimeMinutes: Int? = nil, isReaderAvailable: Bool = false, snapshotURL: String? = nil, textContent: String? = nil, structuredData: String? = nil) {
        self.siteName = siteName
        self.faviconURL = faviconURL
        self.readingTimeMinutes = readingTimeMinutes
        self.isReaderAvailable = isReaderAvailable
        self.snapshotURL = snapshotURL
        self.textContent = textContent
        self.structuredData = structuredData
    }
}

public struct DocumentContext: Codable, Sendable {
    public let fileType: String
    public let pageCount: Int?
    public let author: String?
    
    public init(fileType: String, pageCount: Int? = nil, author: String? = nil) {
        self.fileType = fileType
        self.pageCount = pageCount
        self.author = author
    }
}

public struct QRCodeContext: Codable, Sendable {
    public let payload: String
    
    public init(payload: String) {
        self.payload = payload
    }
}

