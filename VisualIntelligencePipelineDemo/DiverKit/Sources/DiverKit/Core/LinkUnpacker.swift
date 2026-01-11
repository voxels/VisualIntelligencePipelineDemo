import Foundation

public struct LinkMetadata: Codable, Sendable {
    public var title: String?
    public var description: String?
    public var iconURL: URL?
    public var imageURL: URL?
}

public final class LinkUnpacker {
    public init() {}

    public func unpack(url: URL) async throws -> LinkMetadata {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("text/html,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Diver/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...399).contains(http.statusCode) {
            throw NSError(domain: "LinkUnpacker", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"
            ])
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return LinkMetadata(title: nil, description: nil, iconURL: nil, imageURL: nil)
        }

        let ogTitle = firstMetaContent(in: html, property: "og:title")
        let ogDesc  = firstMetaContent(in: html, property: "og:description")
        let ogImage = firstMetaContent(in: html, property: "og:image")
        let titleTag = firstTitle(in: html)

        return LinkMetadata(
            title: ogTitle ?? titleTag,
            description: ogDesc,
            iconURL: nil,
            imageURL: ogImage.flatMap(URL.init(string:))
        )
    }

    private func firstTitle(in html: String) -> String? {
        let pattern = #"<title[^>]*>\s*(.*?)\s*</title>"#
        return firstMatch(html, pattern: pattern)?
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstMetaContent(in html: String, property: String) -> String? {
        // matches: <meta property="og:title" content="...">
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let pattern = #"<meta[^>]+(?:property|name)=["']\#(escaped)["'][^>]+content=["']([^"']+)["'][^>]*>"#
        return firstMatch(html, pattern: pattern)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstMatch(_ html: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = re.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: html)
        else { return nil }
        return String(html[r])
    }
}
