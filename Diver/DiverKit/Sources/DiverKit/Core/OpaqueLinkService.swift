import Foundation
import SwiftData

public final class OpaqueLinkService {
    public init() {}
    
    /// Generates a privacy-safe universal link for a saved item.
    /// Example: diver://item?id=8B12A34F
    public func generateLink(for item: LocalInput) -> URL? {
        let shortID = item.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "secretatomics.com"
        components.path = "/item"
        components.queryItems = [URLQueryItem(name: "id", value: String(shortID))]
        return components.url
    }
    
    /// Resolves an opaque link back to a LocalInput item in the shared store.
    public func resolve(url: URL, in context: ModelContext) throws -> LocalInput? {
        let host = url.host?.lowercased()
        let isDiverScheme = url.scheme == "diver" && url.host == "item"
        let isSecretAtomicsHost = host == "secretatomics.com"
            || host == "www.secretatomics.com"
            || host == "diver.secretatomics.com"
            || host == "www.diver.secretatomics.com"
        let isSecretAtomicsUniversalLink = url.scheme == "https" && isSecretAtomicsHost && (url.path == "/item" || url.path.hasPrefix("/item/"))
        
        guard isDiverScheme || isSecretAtomicsUniversalLink else {
            return nil
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let shortID = components.queryItems?.first(where: { $0.name == "id" })?.value else {
            return nil
        }
        
        // Search for items where the prefix of their UUID matches the shortID
        let descriptor = FetchDescriptor<LocalInput>()
        let items = try context.fetch(descriptor)
        
        return items.first { item in
            item.id.uuidString.replacingOccurrences(of: "-", with: "").hasPrefix(shortID)
        }
    }
}
