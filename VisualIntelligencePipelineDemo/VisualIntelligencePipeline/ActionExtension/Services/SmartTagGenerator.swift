//
//  SmartTagGenerator.swift
//  ActionExtension
//
//  Created by Claude on 12/24/25.
//

import Foundation

struct SmartTagGenerator {

    /// Generate suggested tags based on URL domain and current context
    static func generateTags(for url: URL) -> [String] {
        var tags: [String] = []

        // Domain-based tags
        if let host = url.host {
            tags.append(contentsOf: domainTags(for: host))
        }

        // Time-based tags
        tags.append(contentsOf: timeTags())

        // Remove duplicates while preserving order
        return Array(NSOrderedSet(array: tags)) as! [String]
    }

    // MARK: - Domain Tag Mapping

    private static func domainTags(for host: String) -> [String] {
        let lowercaseHost = host.lowercased()

        // Video platforms
        if lowercaseHost.contains("youtube.com") || lowercaseHost.contains("youtu.be") {
            return ["video"]
        }
        if lowercaseHost.contains("vimeo.com") {
            return ["video"]
        }
        if lowercaseHost.contains("tiktok.com") {
            return ["video", "social"]
        }

        // Development
        if lowercaseHost.contains("github.com") {
            return ["code", "dev"]
        }
        if lowercaseHost.contains("stackoverflow.com") {
            return ["code", "dev"]
        }
        if lowercaseHost.contains("developer.apple.com") {
            return ["docs", "dev", "apple"]
        }

        // Social media
        if lowercaseHost.contains("reddit.com") {
            return ["social"]
        }
        if lowercaseHost.contains("twitter.com") || lowercaseHost.contains("x.com") {
            return ["social"]
        }
        if lowercaseHost.contains("instagram.com") {
            return ["social", "photos"]
        }
        if lowercaseHost.contains("linkedin.com") {
            return ["social", "professional"]
        }

        // News & articles
        if lowercaseHost.contains("medium.com") {
            return ["articles"]
        }
        if lowercaseHost.contains("substack.com") {
            return ["newsletter", "articles"]
        }
        if lowercaseHost.contains("nytimes.com") || lowercaseHost.contains("wsj.com") {
            return ["news"]
        }

        // Shopping
        if lowercaseHost.contains("amazon.com") {
            return ["shopping"]
        }
        if lowercaseHost.contains("etsy.com") {
            return ["shopping"]
        }

        // Food & recipes
        if lowercaseHost.contains("allrecipes.com") || lowercaseHost.contains("foodnetwork.com") {
            return ["recipes", "food"]
        }

        // Travel
        if lowercaseHost.contains("airbnb.com") || lowercaseHost.contains("booking.com") {
            return ["travel"]
        }

        // Default: no domain-specific tags
        return []
    }

    // MARK: - Time-Based Tags

    private static func timeTags() -> [String] {
        let calendar = Calendar.current
        let now = Date()

        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)

        var tags: [String] = []

        // Weekday vs weekend
        if weekday == 1 || weekday == 7 {
            // Sunday or Saturday
            tags.append("personal")
        } else {
            // Weekday - add work tag during business hours
            if hour >= 9 && hour < 17 {
                tags.append("work")
            } else {
                tags.append("personal")
            }
        }

        // Time of day
        if hour >= 20 || hour < 6 {
            tags.append("read-later")
        }

        return tags
    }

    // MARK: - Custom Tag Validation

    /// Validate and sanitize user-entered custom tag
    static func validateTag(_ tag: String) -> String? {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= 30 else { return nil }

        // Convert to lowercase, replace spaces with hyphens
        let sanitized = trimmed.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)

        return sanitized.isEmpty ? nil : sanitized
    }
}
