//
//  ThumbnailView.swift
//  VisualIntelligencePipeline
//
//  Extracted from SidebarView.swift — reusable thumbnail display for items.
//

import SwiftUI
import DiverKit

#if os(iOS)
import UIKit
#endif

struct ThumbnailView: View {
    let item: ProcessedItem
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 6
    
    var body: some View {
        Group {
            if let data = item.rawPayload, let uiImage = UIImage(data: data) {
                if hasAlphaChannel(uiImage) {
                    // Sifted image — show clean on a subtle background
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(2)
                        .background {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(.quaternary)
                        }
                } else {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    var fallbackIcon: some View {
        let config = ItemIconConfig.forItem(item)
        
        return ZStack {
            config.color.opacity(0.15)
            
            Image(systemName: config.iconName)
                .foregroundStyle(config.color)
                .font(.system(size: size * 0.4))
        }
    }
    
    private func hasAlphaChannel(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let alpha = cgImage.alphaInfo
        return alpha == .first || alpha == .last || alpha == .premultipliedFirst || alpha == .premultipliedLast
    }
}
