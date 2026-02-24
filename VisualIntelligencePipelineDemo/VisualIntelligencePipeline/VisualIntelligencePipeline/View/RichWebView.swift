import SwiftUI
import WebKit

// MARK: - Rich Web View Support
struct RichWebView: UIViewRepresentable {
    let url: URL
    var onTitleChange: ((String) -> Void)? = nil
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        // Load request
        let request = URLRequest(url: url)
        webView.load(request)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // If needed, handle URL changes or updates here
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: RichWebView
        
        init(_ parent: RichWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let title = webView.title {
                parent.onTitleChange?(title)
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView Error: \(error.localizedDescription)")
        }
    }
}
