//
//  ItemIconConfig.swift
//  VisualIntelligencePipeline
//
//  Extracted from SidebarView.swift — icon configuration for item types.
//

import SwiftUI
import DiverKit

struct ItemIconConfig {
    let iconName: String
    let color: Color
    
    static func forItem(_ item: ProcessedItem) -> ItemIconConfig {
        // Match against DiverItemType rawValues (camelCase) + common legacy variants
        if let type = item.entityType?.lowercased() {
            switch type {
            case "web":
                return ItemIconConfig(iconName: "globe", color: .blue)
            case "qrcode":
                return ItemIconConfig(iconName: "qrcode", color: .indigo)
            case "document", "pdf":
                return ItemIconConfig(iconName: "doc.text.fill", color: .cyan)
            case "product", "barcode":
                return ItemIconConfig(iconName: "barcode.viewfinder", color: .green)
            case "image":
                return ItemIconConfig(iconName: "photo.fill", color: .purple)
            case "video":
                return ItemIconConfig(iconName: "video.fill", color: .red)
            case "media":
                return ItemIconConfig(iconName: "play.rectangle.fill", color: .pink)
            case "place":
                return ItemIconConfig(iconName: "mappin.circle.fill", color: .red)
            case "text", "note":
                return ItemIconConfig(iconName: "text.alignleft", color: .mint)
            case "activity":
                return ItemIconConfig(iconName: "figure.run", color: .orange)
            case "weather":
                return ItemIconConfig(iconName: "cloud.sun.fill", color: .yellow)
            case "receipt":
                return ItemIconConfig(iconName: "receipt", color: .orange)
            case "business card", "contact":
                return ItemIconConfig(iconName: "person.crop.rectangle.fill", color: .teal)
            case "food", "menu":
                return ItemIconConfig(iconName: "fork.knife", color: .orange)
            case "music", "album":
                return ItemIconConfig(iconName: "music.note", color: .pink)
            default:
                break
            }
        }
        
        // Fallback checks — prioritize content type over location
        if item.qrContext != nil {
            return ItemIconConfig(iconName: "qrcode", color: .indigo)
        }
        if item.webContext != nil {
            return ItemIconConfig(iconName: "globe", color: .blue)
        }
        if item.rawPayload != nil {
            return ItemIconConfig(iconName: "photo.fill", color: .purple)
        }
        if item.placeContext != nil {
            return ItemIconConfig(iconName: "mappin.circle.fill", color: .red)
        }
        
        return ItemIconConfig(iconName: "square.fill", color: .gray)
    }
}
