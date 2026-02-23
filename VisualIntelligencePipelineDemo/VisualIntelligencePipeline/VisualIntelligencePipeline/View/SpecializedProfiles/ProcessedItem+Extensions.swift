import Foundation
import DiverKit

extension ProcessedItem {
    public var isProduct: Bool {
        let type = entityType?.lowercased() ?? ""
        return type == "product" || categories.contains("shopping") || purposes.contains("shopping")
    }
    
    public var productSearchURL: URL? {
        guard let title = title, !title.isEmpty else { return nil }
        let query = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://duckduckgo.com/?q=\(query)&ia=web")
    }
    
    public var resolvedWebURL: URL? {
        // 1. Try wrappedLink (explicit web link)
        if let wrapped = wrappedLink, let url = URL(string: wrapped), ["http", "https"].contains(url.scheme?.lowercased()) {
            return url
        }
        
        // 2. Try main URL if it's http/https
        if let mainUrlStr = url, let url = URL(string: mainUrlStr), ["http", "https"].contains(url.scheme?.lowercased()) {
            return url
        }
        
        return nil
    }
    
    public var displayURLString: String {
        return resolvedWebURL?.absoluteString ?? url ?? "No URL"
    }
}
