import SwiftUI
import SharedWithYou

#if os(iOS)
import UIKit
typealias PlatformViewRepresentable = UIViewRepresentable
#else
import AppKit
typealias PlatformViewRepresentable = NSViewRepresentable
#endif

@available(iOS 16.0, macOS 13.0, *)
struct DiverAttributionView: PlatformViewRepresentable {
    let highlight: SWHighlight
    
    func makeUIView(context: Context) -> SWAttributionView {
        let view = SWAttributionView()
        view.highlight = highlight
        view.displayContext = .summary
        view.horizontalAlignment = .leading
        view.backgroundStyle = .color
        return view
    }
    
    func updateUIView(_ uiView: SWAttributionView, context: Context) {
        uiView.highlight = highlight
    }
    
    #if os(macOS)
    func makeNSView(context: Context) -> SWAttributionView {
        let view = SWAttributionView()
        view.highlight = highlight
        view.displayContext = .summary
        view.horizontalAlignment = .leading
        view.backgroundStyle = .color
        return view
    }
    
    func updateNSView(_ nsView: SWAttributionView, context: Context) {
        nsView.highlight = highlight
    }
    #endif
}
