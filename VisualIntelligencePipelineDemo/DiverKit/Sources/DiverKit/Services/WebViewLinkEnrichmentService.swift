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
        let config = WKWebViewConfiguration()
        let requestWebView = WKWebView(frame: .zero, configuration: config)
        
        // Create loader first so we can capture it in onCancel
        let loader = WebSocketMetadataLoader(
            webView: requestWebView,
            url: url,
            timeout: timeout
        )
        
        self.activeLoaders.insert(loader)
        
        // Cleanup closure
        let cleanup = { [weak self, weak loader] in
            guard let self = self, let loader = loader else { return }
            self.activeLoaders.remove(loader)
        }
        
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                loader.assignContinuation(continuation)
                loader.onCompletion = cleanup
                
                if Task.isCancelled {
                    loader.cancel()
                } else {
                    loader.start()
                }
            }
        } onCancel: {
            Task { @MainActor in
                loader.cancel()
            }
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
    private var isFinished = false
    private var pendingResult: Result<EnrichmentData?, Error>?
    
    var onCompletion: (() -> Void)?
    
    init(webView: WKWebView, url: URL, timeout: TimeInterval) {
        self.webView = webView
        self.url = url
        self.timeout = timeout
        super.init()
        self.webView?.navigationDelegate = self
    }
    
    deinit {
        if let continuation = continuation {
            print("⚠️ WebSocketMetadataLoader deinit: Resuming leaked continuation with CancellationError")
            continuation.resume(throwing: CancellationError())
        }
    }
    
    func assignContinuation(_ continuation: CheckedContinuation<EnrichmentData?, Error>) {
        self.continuation = continuation
        // If we already finished (e.g. cancelled before continuation was assigned), resume immediately
        if let result = pendingResult {
            switch result {
            case .success(let data):
                continuation.resume(returning: data)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
            self.continuation = nil
            pendingResult = nil
        }
    }
    
    func cancel() {
        finish(with: nil, error: CancellationError())
    }
    
    func start() {
        // Start timeout using Task.sleep for robust background execution
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                await MainActor.run { [weak self] in
                    // Only error out if we haven't finished yet
                    if let self = self, !self.isFinished {
                        print("⚠️ WebViewLinkEnrichment: Timeout after \(self.timeout)s")
                        self.finish(with: nil, error: URLError(.timedOut))
                    }
                }
            } catch {
                // Task cancelled or sleep failed, safe to ignore
            }
        }
        
        let request = URLRequest(url: url)
        webView?.load(request)
    }
    
    fileprivate func finish(with data: EnrichmentData?, error: Error?) {
        guard !isFinished else { return }
        isFinished = true
        
        let result: Result<EnrichmentData?, Error>
        if let error = error {
            result = .failure(error)
        } else {
            result = .success(data)
        }
        
        if let continuation = continuation {
            switch result {
            case .success(let d):
                continuation.resume(returning: d)
            case .failure(let e):
                continuation.resume(throwing: e)
            }
            self.continuation = nil
        } else {
            // Continuation not yet assigned - store result for when it is
            pendingResult = result
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

