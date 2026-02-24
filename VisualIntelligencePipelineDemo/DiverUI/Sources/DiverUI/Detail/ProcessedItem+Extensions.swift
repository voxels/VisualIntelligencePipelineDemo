//
//  ProcessedItem+Extensions.swift
//  DiverUI — cross-platform view helpers on ProcessedItem
//

import Foundation
import DiverKit

public extension ProcessedItem {
    var isProduct: Bool {
        let type = entityType?.lowercased() ?? ""
        return type == "product" || categories.contains("shopping") || purposes.contains("shopping")
    }

    var productSearchURL: URL? {
        guard let title, !title.isEmpty else { return nil }
        let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://duckduckgo.com/?q=\(q)&ia=web")
    }

    var resolvedWebURL: URL? {
        if let wrapped = wrappedLink, let u = URL(string: wrapped),
           ["http","https"].contains(u.scheme?.lowercased()) { return u }
        if let s = url, s.hasPrefix("secretatomics://"),
           let deep = URL(string: s),
           let comps = URLComponents(url: deep, resolvingAgainstBaseURL: false),
           let link = comps.queryItems?.first(where: { $0.name == "link" || $0.name == "url" })?.value,
           let extracted = URL(string: link),
           ["http","https"].contains(extracted.scheme?.lowercased()) { return extracted }
        if let s = url, let u = URL(string: s),
           ["http","https"].contains(u.scheme?.lowercased()) { return u }
        if let payload = qrContext?.payload, let u = URL(string: payload),
           ["http","https"].contains(u.scheme?.lowercased()) { return u }
        return nil
    }

    var displayURLString: String { resolvedWebURL?.absoluteString ?? url ?? "No URL" }
}
