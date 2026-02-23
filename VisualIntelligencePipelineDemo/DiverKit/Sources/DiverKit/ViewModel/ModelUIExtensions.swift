import Foundation

#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

// MARK: - DiverObject UI Extensions

public extension DiverObject {
    /// Helper to convert a relative date to a string.
    var relativeUpdatedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }
}

// MARK: - ProcessedItem UI Extensions

public extension ProcessedItem {
    // Internal URL schemes that should never be shown to the user as titles
    private static let internalSchemes: [String] = [
        "secretatomics://"
    ]
    
    /// A human-readable label derived from the item's type/categories, used when title is nil
    /// and the URL is an internal scheme that shouldn't be displayed.
    var displayLabel: String {
        if let title, !title.isEmpty { return title }
        
        // If URL is a real external URL, show it
        if let url, !ProcessedItem.internalSchemes.contains(where: { url.hasPrefix($0) }) {
            return url
        }
        
        // Fallback: derive a label from categories or entity type
        if categories.contains("document") { return "Scanned Document" }
        if categories.contains("product") { return "Product" }
        if categories.contains("media") { return "Media" }
        if categories.contains("web") || categories.contains("qr") { return "Web Link" }
        if categories.contains("place") { return "Place" }
        if categories.contains("visual_intelligence") { return "Capture" }
        
        return "Processing..."
    }
    
    var displayTitle: String {
        displayLabel
    }
}

// MARK: - SessionMetadata UI Extensions

public extension SessionMetadata {
    var displayTitle: String {
        if let title = title, !title.isEmpty { return title }
        if let location = locationName, !location.isEmpty { return location }
        return createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - DiverCollection UI Extensions

public extension DiverCollection {
    var displayTitle: String { name }
}

// MARK: - SSEEvent UI Extensions

extension SSEEvent {
    var levelColor: String {
        switch self.level {
        case "info": return "blue"
        case "warning": return "yellow"
        case "error": return "red"
        case "success": return "green"
        default: return "gray"
        }
    }
    
    /// Display icon based on message content
    var icon: String {
        // TikTok-specific icon
        if message.contains("tiktok.com") || message.contains("TikTok") {
            return "play.rectangle.fill" // SF Symbol placeholder
        }
        
        // Media/Web context
        if message.contains("screenshot") || message.contains("image") {
            return "photo.fill"
        }
        if message.contains("URL") || message.contains("web") {
            return "safari.fill"
        }
        
        // Process steps
        if message.localizedCaseInsensitiveContains("analyzing") || message.localizedCaseInsensitiveContains("vision") {
            return "eye.fill"
        }
        if message.localizedCaseInsensitiveContains("saving") || message.localizedCaseInsensitiveContains("persisted") {
            return "square.and.arrow.down.fill"
        }
        if message.localizedCaseInsensitiveContains("routing") {
            return "arrow.triangle.branch"
        }
        
        switch self.level {
        case "info": return "info.circle.fill"
        case "warning": return "exclamationmark.triangle.fill"
        case "error": return "xmark.octagon.fill"
        case "success": return "checkmark.circle.fill"
        default: return "circle.fill"
        }
    }
}

// MARK: - IntelligenceResult UI Extensions

public extension IntelligenceResult {
    var icon: String {
        switch self {
        case .qr: return "qrcode"
        case .richWeb: return "safari"
        case .text: return "text.magnifyingglass"
        case .semantic: return "brain"
        case .entertainment(_, let type, _):
            switch type {
            case .movie: return "film"
            case .concert: return "music.mic"
            case .book: return "book"
            case .podcast: return "podcast.arrow.up.universal"
            }
        case .siftedSubject(_, _, let label):
            if let l = label?.lowercased() {
                if l.contains("dog") || l.contains("cat") { return "pawprint.fill" }
                if l.contains("coffee") || l.contains("mug") { return "cup.and.saucer.fill" }
                if l.contains("laptop") || l.contains("screen") { return "laptopcomputer" }
                if l.contains("plant") || l.contains("flower") { return "leaf.fill" }
            }
            return "hand.raised.fingers.spread"
        case .product: return "barcode.viewfinder"
        case .document: return "doc.text.below.ecg.fill" // More distinct document icon
        case .purpose: return "sparkles.rectangle.stack"
        case .aesthetics: return "sparkle.magnifyingglass"
        case .saliency: return "eye.trianglebadge.exclamationmark"
        }
    }
}

// MARK: - JobProgress UI Extensions

extension JobProgress {
    var formattedDuration: String {
        guard let duration = duration else { return "—" }
        
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}
