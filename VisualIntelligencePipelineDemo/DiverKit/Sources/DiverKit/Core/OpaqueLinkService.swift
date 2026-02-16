import Foundation
import SwiftData

public final class OpaqueLinkService {
    public init() {}
    
    /// Generates an internal deep link for in-app navigation.
    /// Format: secretatomics://open?id=<UUID>
    public func generateLink(for item: LocalInput) -> URL? {
        var components = URLComponents()
        components.scheme = "secretatomics"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "id", value: item.id.uuidString)]
        return components.url
    }
    
    /// Generates a shareable universal link for external sharing (Messages, Shared with You, etc.).
    /// Format: https://secretatomics.com/item?id=<UUID>
    /// These links are routed by the Apple App Site Association file to the app.
    public func generateShareableLink(for item: LocalInput) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "secretatomics.com"
        components.path = "/item"
        components.queryItems = [URLQueryItem(name: "id", value: item.id.uuidString)]
        return components.url
    }
    
    /// Generates a shareable universal link from a ProcessedItem ID.
    /// Format: https://secretatomics.com/item?id=<ID>
    public static func shareableURL(for itemID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "secretatomics.com"
        components.path = "/item"
        components.queryItems = [URLQueryItem(name: "id", value: itemID)]
        return components.url
    }
    
    /// Resolves an opaque link back to a LocalInput item in the shared store.
    public func resolve(url: URL, in context: ModelContext) throws -> LocalInput? {
        let isCustomScheme = url.scheme == "secretatomics" && (url.host == "open" || url.host == "item")
        let isUniversalLink = url.scheme == "https"
            && (url.host == "secretatomics.com" || url.host == "www.secretatomics.com")
            && (url.path == "/item" || url.path.hasPrefix("/item/"))
        
        guard isCustomScheme || isUniversalLink else {
            return nil
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value else {
            return nil
        }
        
        // Search for items by full UUID match
        let descriptor = FetchDescriptor<LocalInput>()
        let items = try context.fetch(descriptor)
        
        return items.first { item in
            item.id.uuidString == id
        }
    }
}

