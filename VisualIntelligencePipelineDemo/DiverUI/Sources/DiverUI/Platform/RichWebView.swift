// RichWebView.swift
// DiverUI — iOS/iPadOS only (WKWebView requires UIKit)
//
// Cross-platform callers always guard with #if os(iOS) before using this type.

#if canImport(UIKit) && !os(visionOS)
import SwiftUI
import WebKit

/// WKWebView wrapper for inline web content previews.
/// Available on iOS only — macOS uses a Link button fallback instead.
public struct RichWebView: UIViewRepresentable {
    public let url: URL
    public var onTitleChange: ((String) -> Void)? = nil

    public init(url: URL, onTitleChange: ((String) -> Void)? = nil) {
        self.url = url
        self.onTitleChange = onTitleChange
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public class Coordinator: NSObject, WKNavigationDelegate {
        var parent: RichWebView
        init(_ parent: RichWebView) { self.parent = parent }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let title = webView.title { parent.onTitleChange?(title) }
        }
        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("⚠️ [RichWebView] \(error.localizedDescription)")
        }
    }
}
#endif
