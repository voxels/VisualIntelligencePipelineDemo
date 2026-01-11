import Foundation
import WebKit
import DiverShared

/// A link enrichment service that uses WKWebView to load the page and extract metadata.
/// This allows capturing content from client-side rendered pages (SPAs) that simple HTTP requests miss.
@MainActor
public final class WebViewLinkEnrichmentService: NSObject, LinkEnrichmentService {
    
    // Keep track of active loaders to prevent them from being deallocated while running
    private var activeLoaders: Set<WebSocketMetadataLoader> = []
    
    // Configurable timeout
    public var timeout: TimeInterval = 10.0
    
    public override init() {
        super.init()
    }
    
    public func enrich(url: URL) async throws -> EnrichmentData? {
        return try await withCheckedThrowingContinuation { continuation in
            let requestWebView = WKWebView(frame: .zero)
            
            let loader = WebSocketMetadataLoader(
                webView: requestWebView, 
                url: url, 
                timeout: timeout, 
                continuation: continuation
            )
            
            // Clean up when done
            loader.onCompletion = { [weak self, weak loader] in
                guard let self = self, let loader = loader else { return }
                self.activeLoaders.remove(loader)
            }
            
            self.activeLoaders.insert(loader)
            loader.start()
        }
    }
}

/// Helper class to manage a single WKWebView request life-cycle
@MainActor
private class WebSocketMetadataLoader: NSObject, WKNavigationDelegate {
    let id = UUID()
    private var webView: WKWebView?
    private let url: URL
    private let timeout: TimeInterval
    private var continuation: CheckedContinuation<EnrichmentData?, Error>?
    // private var timer: Timer? // Removed in favor of Task.sleep
    
    var onCompletion: (() -> Void)?
    
    init(webView: WKWebView, url: URL, timeout: TimeInterval, continuation: CheckedContinuation<EnrichmentData?, Error>) {
        self.webView = webView
        self.url = url
        self.timeout = timeout
        self.continuation = continuation
        super.init()
        self.webView?.navigationDelegate = self
    }
    
    func start() {
        // Start timeout using Task.sleep for robust background execution
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                await MainActor.run { [weak self] in
                    // Only error out if we haven't finished yet (continuation not nil)
                    if self?.continuation != nil {
                        print("⚠️ WebViewLinkEnrichment: Timeout after \(self?.timeout ?? 0)s")
                        self?.finish(with: nil, error: URLError(.timedOut))
                    }
                }
            } catch {
                // Task cancelled or sleep failed, safe to ignore
            }
        }
        
        let request = URLRequest(url: url)
        webView?.load(request)
    }
    
    private func finish(with data: EnrichmentData?, error: Error?) {
        // No timer to invalidate
        
        if let continuation = continuation {
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: data)
            }
            self.continuation = nil
        }
        
        // Break retain cycles
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        
        onCompletion?()
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Page loaded, now run JS to extract data
        extractMetadata()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: nil, error: error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: nil, error: error)
    }
    
    private func extractMetadata() {
        // 1. Take Snapshot
        let config = WKSnapshotConfiguration()
        
        webView?.takeSnapshot(with: config) { [weak self] image, error in
            guard let self = self else { return }
            
            var snapshotPath: String?
            if let image = image, let data = image.jpegData(compressionQuality: 0.6) {
                let filename = "snap_\(UUID().uuidString).jpg"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                do {
                    try data.write(to: url)
                    snapshotPath = url.path
                } catch {
                    print("Failed to save snapshot: \(error)")
                }
            }
            
            // 2. Run JS
            self.runJSExtraction(snapshotPath: snapshotPath)
        }
    }
    
    private func runJSExtraction(snapshotPath: String?) {
        let js = """
        (function() {
            function getMetaContent(propName) {
                const meta = document.querySelector(`meta[property='${propName}'], meta[name='${propName}']`);
                return meta ? meta.getAttribute('content') : null;
            }
            
            // Extract JSON-LD
            let jsonLd = [];
            document.querySelectorAll('script[type="application/ld+json"]').forEach(script => {
                try {
                    jsonLd.push(JSON.parse(script.textContent));
                } catch(e) {}
            });
            
            // Extract visible text (naive)
            const text = document.body ? document.body.innerText.substring(0, 3000) : "";
            
            return {
                title: document.title,
                description: getMetaContent('description') || getMetaContent('og:description'),
                image: getMetaContent('og:image'),
                siteName: getMetaContent('og:site_name'),
                type: getMetaContent('og:type'),
                structuredData: jsonLd.length > 0 ? JSON.stringify(jsonLd) : null,
                textContent: text
            };
        })();
        """
        
        webView?.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            
            let fallbackTitle = self.webView?.title
            
            if let error = error {
                print("JS Extraction failed: \(error)")
                if let title = fallbackTitle {
                    print("✅ WebView: Using fallback title: \(title)")
                    self.finish(with: EnrichmentData(title: title), error: nil)
                } else {
                    self.finish(with: nil, error: error)
                }
                return
            }
            
            if let dict = result as? [String: Any] {
                let title = (dict["title"] as? String) ?? fallbackTitle
                let description = dict["description"] as? String
                let image = dict["image"] as? String
                let siteName = dict["siteName"] as? String
                let textContent = dict["textContent"] as? String
                let structuredData = dict["structuredData"] as? String
                
                let webContext = WebContext(
                    siteName: siteName,
                    snapshotURL: snapshotPath,
                    textContent: textContent,
                    structuredData: structuredData
                )
                
                let data = EnrichmentData(
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
                self.finish(with: data, error: nil)
            } else {
                 if let title = fallbackTitle {
                    self.finish(with: EnrichmentData(title: title), error: nil)
                } else {
                    self.finish(with: nil, error: nil)
                }
            }
        }
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
