import Foundation
@preconcurrency import LinkPresentation
import DiverShared

/// A link enrichment service that uses LPMetadataProvider for metadata extraction
/// and a lightweight URLSession HTML fetch for page text content and structured data.
///
/// This replaces the previous WKWebView-based implementation which could cause
/// EXC_GUARD crashes by spawning offscreen WebKit XPC processes.
public final class WebViewLinkEnrichmentService: NSObject, LinkEnrichmentService, @unchecked Sendable {
    
    /// Configurable timeout for both metadata and HTML fetch
    private let timeout: TimeInterval
    
    public init(timeout: TimeInterval = 10.0) {
        self.timeout = timeout
        super.init()
    }
    
    public func enrich(url: URL) async throws -> EnrichmentData? {
        // Run LPMetadataProvider and HTML fetch concurrently
        async let metadataResult = fetchLinkMetadata(url: url)
        async let htmlResult = fetchHTMLContent(url: url)
        
        let metadata = try? await metadataResult
        let html = try? await htmlResult
        
        // If both failed, return nil
        guard metadata != nil || html != nil else { return nil }
        
        let title = metadata?.title ?? html?.title
        let description = metadata?.description
        let image = metadata?.imageURL
        let siteName = metadata?.siteName
        let textContent = html?.textContent
        let structuredData = html?.structuredData
        
        let webContext = WebContext(
            siteName: siteName,
            snapshotURL: nil,
            textContent: textContent,
            structuredData: structuredData
        )
        
        return EnrichmentData(
            title: title,
            descriptionText: description,
            image: image,
            categories: [],
            styleTags: [],
            location: nil,
            price: nil,
            rating: nil,
            questions: [],
            webContext: webContext
        )
    }
    
    // MARK: - LPMetadataProvider
    
    private struct LinkMetadata {
        let title: String?
        let description: String?
        let imageURL: String?
        let siteName: String?
    }
    
    private func fetchLinkMetadata(url: URL) async throws -> LinkMetadata {
        try Task.checkCancellation()
        
        let provider = LPMetadataProvider()
        provider.timeout = timeout
        
        // nonisolated(unsafe) is safe here: LPMetadataProvider.cancel() is thread-safe
        // and we only call it from the onCancel closure.
        nonisolated(unsafe) let unsafeProvider = provider
        
        // Cancel the provider if our task gets cancelled
        return try await withTaskCancellationHandler {
            let metadata = try await provider.startFetchingMetadata(for: url)
            
            return LinkMetadata(
                title: metadata.title,
                description: metadata.value(forKey: "summary") as? String,
                imageURL: metadata.imageProvider != nil ? metadata.originalURL?.absoluteString : nil,
                siteName: metadata.value(forKey: "siteName") as? String
            )
        } onCancel: {
            unsafeProvider.cancel()
        }
    }
    
    // MARK: - Lightweight HTML Fetch
    
    private struct HTMLExtraction {
        let title: String?
        let textContent: String?
        let structuredData: String?
    }
    
    private func fetchHTMLContent(url: URL) async throws -> HTMLExtraction {
        try Task.checkCancellation()
        
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Only process HTML responses
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              contentType.contains("text/html") else {
            return HTMLExtraction(title: nil, textContent: nil, structuredData: nil)
        }
        
        try Task.checkCancellation()
        
        // Cap at 100KB to avoid memory pressure
        let maxBytes = 100_000
        let htmlString: String
        if data.count > maxBytes {
            htmlString = String(data: data.prefix(maxBytes), encoding: .utf8) ?? ""
        } else {
            htmlString = String(data: data, encoding: .utf8) ?? ""
        }
        
        guard !htmlString.isEmpty else {
            return HTMLExtraction(title: nil, textContent: nil, structuredData: nil)
        }
        
        let title = extractHTMLTitle(from: htmlString)
        let textContent = extractTextContent(from: htmlString)
        let structuredData = extractJSONLD(from: htmlString)
        
        return HTMLExtraction(
            title: title,
            textContent: textContent,
            structuredData: structuredData
        )
    }
    
    // MARK: - HTML Parsing Helpers
    
    /// Extract <title> tag content
    private func extractHTMLTitle(from html: String) -> String? {
        guard let titleRange = html.range(of: "<title[^>]*>(.*?)</title>",
                                          options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let match = String(html[titleRange])
        // Strip the tags
        return match.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Extract visible text content, stripping HTML tags, scripts, and styles
    private func extractTextContent(from html: String) -> String? {
        var text = html
        
        // Remove script and style blocks entirely
        text = text.replacingOccurrences(
            of: "<(script|style|noscript)[^>]*>[\\s\\S]*?</\\1>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // Remove HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        
        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        
        // Collapse whitespace
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Cap at 3000 chars (matching original WKWebView JS limit)
        if text.count > 3000 {
            text = String(text.prefix(3000))
        }
        
        return text.isEmpty ? nil : text
    }
    
    /// Extract JSON-LD structured data blocks
    private func extractJSONLD(from html: String) -> String? {
        let pattern = "<script[^>]*type\\s*=\\s*[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: range)
        
        guard !matches.isEmpty else { return nil }
        
        var jsonBlocks: [String] = []
        for match in matches {
            if let captureRange = Range(match.range(at: 1), in: html) {
                let jsonString = String(html[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Validate it's actually JSON
                if let jsonData = jsonString.data(using: .utf8),
                   (try? JSONSerialization.jsonObject(with: jsonData)) != nil {
                    jsonBlocks.append(jsonString)
                }
            }
        }
        
        guard !jsonBlocks.isEmpty else { return nil }
        
        if jsonBlocks.count == 1 {
            return jsonBlocks[0]
        }
        return "[\(jsonBlocks.joined(separator: ","))]"
    }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

extension NSImage {
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}
#endif
