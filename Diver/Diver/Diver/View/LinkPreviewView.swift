
import SwiftUI
import LinkPresentation

// MARK: - Link Preview Wrapper
struct LinkPreviewView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> LPLinkView {
        let preview = LPLinkView(url: url)
        
        // Try to fetch metadata
        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { metadata, error in
            if let metadata = metadata {
                DispatchQueue.main.async {
                    preview.metadata = metadata
                }
            }
        }
        
        return preview
    }
    
    func updateUIView(_ uiView: LPLinkView, context: Context) {
        // No update needed for static URL usually, but could handle change if needed
    }
}
