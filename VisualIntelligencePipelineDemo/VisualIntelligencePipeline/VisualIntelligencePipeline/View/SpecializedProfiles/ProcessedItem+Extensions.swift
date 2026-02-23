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
        
        // 2. Try extracting from secretatomics:// deep link query parameter
        if let mainUrlStr = url, mainUrlStr.hasPrefix("secretatomics://") {
            if let deepURL = URL(string: mainUrlStr),
               let components = URLComponents(url: deepURL, resolvingAgainstBaseURL: false),
               let linkParam = components.queryItems?.first(where: { $0.name == "link" || $0.name == "url" })?.value,
               let extractedURL = URL(string: linkParam),
               ["http", "https"].contains(extractedURL.scheme?.lowercased()) {
                return extractedURL
            }
        }
        
        // 3. Try main URL if it's http/https
        if let mainUrlStr = url, let url = URL(string: mainUrlStr), ["http", "https"].contains(url.scheme?.lowercased()) {
            return url
        }
        
        // 4. Try QR code payload if it's a URL
        if let qrPayload = qrContext?.payload,
           let qrURL = URL(string: qrPayload),
           ["http", "https"].contains(qrURL.scheme?.lowercased()) {
            return qrURL
        }
        
        return nil
    }
    
    public var displayURLString: String {
        return resolvedWebURL?.absoluteString ?? url ?? "No URL"
    }
}
