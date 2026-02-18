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
        // Check specific types first
        if let type = item.entityType?.lowercased() {
            switch type {
            case "document", "pdf":
                return ItemIconConfig(iconName: "doc.text.fill", color: .blue)
            case "product", "barcode":
                return ItemIconConfig(iconName: "barcode.viewfinder", color: .green)
            case "receipt":
                return ItemIconConfig(iconName: "receipt", color: .orange)
            case "business card", "contact":
                return ItemIconConfig(iconName: "person.crop.rectangle.fill", color: .teal)
            case "food", "menu":
                return ItemIconConfig(iconName: "fork.knife", color: .orange)
            case "music", "album":
                return ItemIconConfig(iconName: "music.note", color: .pink)
            case "text", "note":
                return ItemIconConfig(iconName: "doc.text.fill", color: .blue)
            default:
                break
            }
        }
        
        // Fallback checks
        if item.placeContext != nil {
            return ItemIconConfig(iconName: "mappin.circle.fill", color: .red)
        }
        if item.webContext != nil {
            return ItemIconConfig(iconName: "globe", color: .blue)
        }
        if item.rawPayload != nil {
            return ItemIconConfig(iconName: "photo.fill", color: .purple)
        }
        
        return ItemIconConfig(iconName: "square.fill", color: .gray)
    }
}
