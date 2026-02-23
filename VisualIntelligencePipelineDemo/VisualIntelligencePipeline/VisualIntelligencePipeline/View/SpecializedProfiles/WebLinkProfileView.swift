import SwiftUI
import DiverKit

public struct WebLinkProfileView: View {
    let item: ProcessedItem
    
    public init(item: ProcessedItem) {
        self.item = item
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Web Context Header
            if let webCtx = item.webContext {
                VStack(alignment: .leading, spacing: 8) {
                    if let siteName = webCtx.siteName {
                        Text(siteName)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let description = webCtx.textContent, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(4)
                    }
                }
                .padding(.horizontal)
            }
            
            // Rich Web Preview
            if let url = item.resolvedWebURL {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "safari")
                        Text("Open in Browser")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                // Embedded Web View for visual preview
                RichWebView(url: url)
                    .frame(height: 400)
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
}
