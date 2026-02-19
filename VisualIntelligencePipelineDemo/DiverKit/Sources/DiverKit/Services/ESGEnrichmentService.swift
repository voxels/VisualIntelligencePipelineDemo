//
//  ESGEnrichmentService.swift
//  DiverKit
//
//  Created by Antigravity on 02/19/26.
//

import Foundation
import DiverShared

/// Protocol for ESG data retrieval services.
public protocol ESGEnriching: Sendable {
    /// Look up ESG data by product barcode (e.g., Open Food Facts).
    func enrich(barcode: String) async throws -> ESGEnrichment?
    /// Look up ESG data by product category (e.g., Climate TRACE sector averages).
    func enrich(category: String) async throws -> ESGEnrichment?
}

/// Service that retrieves ESG (Environmental, Social, Governance) data from open product databases.
///
/// **Barcode lookup cascade** (all free, no API key required):
/// 1. [Open Food Facts](https://world.openfoodfacts.org) — 3M+ food products
/// 2. [Open Beauty Facts](https://world.openbeautyfacts.org) — cosmetics, skincare
/// 3. [Open Pet Food Facts](https://world.openpetfoodfacts.org) — pet food
/// 4. [Open Products Facts](https://world.openproductsfacts.org) — non-food products
///
/// **Category fallback:**
/// - Climate TRACE sector-level emissions averages
///
/// All data cached with 24-hour TTL.
public final class ESGEnrichmentService: ESGEnriching, @unchecked Sendable {
    
    private let session: URLSession
    private var cache: [String: CachedEntry] = [:]
    private let cacheTTL: TimeInterval = 86400 // 24 hours
    
    private struct CachedEntry {
        let enrichment: ESGEnrichment
        let expiresAt: Date
    }
    
    /// Open *Facts database family — same API pattern, different domains.
    /// Ordered by largest database first for fastest hit rate.
    private static let openFactsDomains = [
        "world.openfoodfacts.org",       // 3M+ food products
        "world.openbeautyfacts.org",     // Cosmetics, skincare, personal care
        "world.openpetfoodfacts.org",    // Pet food
        "world.openproductsfacts.org",   // Everything else
    ]
    
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    // MARK: - Barcode Lookup (Open *Facts cascade)
    
    public func enrich(barcode: String) async throws -> ESGEnrichment? {
        // Check cache first
        if let cached = cache[barcode], cached.expiresAt > Date() {
            return cached.enrichment
        }
        
        // Cascade through all Open *Facts databases until we get a hit
        for domain in Self.openFactsDomains {
            if let enrichment = try await queryOpenFacts(barcode: barcode, domain: domain) {
                cache[barcode] = CachedEntry(enrichment: enrichment, expiresAt: Date().addingTimeInterval(cacheTTL))
                return enrichment
            }
        }
        
        return nil
    }
    
    // MARK: - Category Lookup (Climate TRACE sector averages)
    
    public func enrich(category: String) async throws -> ESGEnrichment? {
        let cacheKey = "cat:\(category)"
        if let cached = cache[cacheKey], cached.expiresAt > Date() {
            return cached.enrichment
        }
        
        let enrichment = sectorAverage(for: category)
        
        if let enrichment {
            cache[cacheKey] = CachedEntry(enrichment: enrichment, expiresAt: Date().addingTimeInterval(cacheTTL))
        }
        
        return enrichment
    }
    
    // MARK: - Open *Facts Query
    
    /// Queries a single Open *Facts database by barcode.
    /// All databases share the same API pattern: `https://{domain}/api/v2/product/{barcode}.json`
    private func queryOpenFacts(barcode: String, domain: String) async throws -> ESGEnrichment? {
        let fields = [
            // Scores
            "ecoscore_grade", "ecoscore_score", "nutriscore_grade",
            "carbon_footprint_from_known_ingredients_debug",
            "nova_group", "nova_groups_tags",
            // Text context (persisted for SLM summaries)
            "ingredients_text", "allergens_tags", "traces_tags",
            "origins", "manufacturing_places",
            "labels_tags", "packaging_tags", "packaging_text",
            "categories_tags", "quantity", "generic_name",
            "countries_tags", "stores",
            "brands", "product_name",
            // Nutrition
            "nutriments"
        ].joined(separator: ",")
        
        let urlString = "https://\(domain)/api/v2/product/\(barcode).json?fields=\(fields)"
        guard let url = URL(string: urlString) else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("VisualIntelligence iOS App - github.com/voxels", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int, status == 1,
              let product = json["product"] as? [String: Any] else {
            return nil
        }
        
        // ── Parse numerical scores ──
        let ecoScoreGrade = product["ecoscore_grade"] as? String
        let nutriScoreGrade = product["nutriscore_grade"] as? String
        let carbonFootprint = product["carbon_footprint_from_known_ingredients_debug"] as? String
        let labelsTags = product["labels_tags"] as? [String] ?? []
        let packagingTags = product["packaging_tags"] as? [String] ?? []
        let novaGroup = product["nova_group"] as? Int
        
        var carbonIntensity: Float? = nil
        if let carbonStr = carbonFootprint {
            let digits = carbonStr.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let value = Float(digits) {
                carbonIntensity = value / 1000.0
            }
        }
        
        // ── Parse text context ──
        let ingredientsText = product["ingredients_text"] as? String
        let allergensTags = (product["allergens_tags"] as? [String] ?? []).map { tag in
            tag.replacingOccurrences(of: "en:", with: "").replacingOccurrences(of: "-", with: " ").capitalized
        }
        let tracesTags = (product["traces_tags"] as? [String] ?? []).map { tag in
            tag.replacingOccurrences(of: "en:", with: "").replacingOccurrences(of: "-", with: " ").capitalized
        }
        let origins = product["origins"] as? String
        let manufacturingPlaces = product["manufacturing_places"] as? String
        let packagingText = product["packaging_text"] as? String
        let quantity = product["quantity"] as? String
        let genericName = product["generic_name"] as? String
        let countriesTags = (product["countries_tags"] as? [String] ?? []).map { tag in
            tag.replacingOccurrences(of: "en:", with: "").replacingOccurrences(of: "-", with: " ").capitalized
        }
        let storesStr = product["stores"] as? String
        let storesList = storesStr?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        
        // ── Parse nutriments ──
        var nutriments: [String: Float] = [:]
        if let rawNutriments = product["nutriments"] as? [String: Any] {
            let keysToParse = ["energy-kcal_100g", "fat_100g", "saturated-fat_100g",
                               "sugars_100g", "salt_100g", "proteins_100g",
                               "fiber_100g", "sodium_100g", "carbohydrates_100g"]
            for key in keysToParse {
                if let val = rawNutriments[key] as? Double {
                    let cleanKey = key.replacingOccurrences(of: "_100g", with: "").replacingOccurrences(of: "-", with: "_")
                    nutriments[cleanKey] = Float(val)
                } else if let val = rawNutriments[key] as? Int {
                    let cleanKey = key.replacingOccurrences(of: "_100g", with: "").replacingOccurrences(of: "-", with: "_")
                    nutriments[cleanKey] = Float(val)
                }
            }
        }
        
        // ── Certifications ──
        var certifications = labelsTags.compactMap { label -> String? in
            let clean = label.replacingOccurrences(of: "en:", with: "").replacingOccurrences(of: "-", with: " ").capitalized
            return clean.isEmpty ? nil : clean
        }
        
        for tag in packagingTags {
            let clean = tag.replacingOccurrences(of: "en:", with: "").replacingOccurrences(of: "-", with: " ").capitalized
            if clean.lowercased().contains("recycle") || clean.lowercased().contains("compost") || clean.lowercased().contains("reusable") {
                certifications.append(clean)
            }
        }
        
        // ── Data quality tier ──
        let tier: Int
        if carbonIntensity != nil && ecoScoreGrade != nil {
            tier = 2
        } else if ecoScoreGrade != nil || nutriScoreGrade != nil || !certifications.isEmpty {
            tier = 3
        } else {
            tier = 4
        }
        
        // ── Source name ──
        let sourceName: String
        switch domain {
        case "world.openfoodfacts.org": sourceName = "Open Food Facts"
        case "world.openbeautyfacts.org": sourceName = "Open Beauty Facts"
        case "world.openpetfoodfacts.org": sourceName = "Open Pet Food Facts"
        case "world.openproductsfacts.org": sourceName = "Open Products Facts"
        default: sourceName = "Open Facts"
        }
        
        return ESGEnrichment(
            carbonIntensity: carbonIntensity,
            dataQualityTier: tier,
            certifications: certifications,
            ecoScore: ecoScoreGrade,
            source: sourceName,
            ingredientsText: ingredientsText,
            allergens: allergensTags,
            traces: tracesTags,
            origins: origins,
            manufacturingPlaces: manufacturingPlaces,
            novaGroup: novaGroup,
            nutriScore: nutriScoreGrade,
            nutriments: nutriments,
            packagingText: packagingText,
            quantity: quantity,
            genericName: genericName,
            countriesSold: countriesTags,
            stores: storesList
        )
    }
    
    // MARK: - Sector Averages (Fallback)
    
    private func sectorAverage(for category: String) -> ESGEnrichment? {
        let normalizedCategory = category.lowercased()
        
        // Sector averages (kg CO₂e per unit) — Climate TRACE / IEA data
        let sectorData: [String: Float] = [
            "food": 2.5,
            "beverages": 1.2,
            "electronics": 25.0,
            "clothing": 10.0,
            "automotive": 120.0,
            "household": 5.0,
            "personal care": 3.0,
            "beauty": 3.0,
            "pet food": 4.0,
            "health": 8.0,
            "furniture": 15.0,
            "toy": 6.0,
        ]
        
        let carbonIntensity = sectorData.first { normalizedCategory.contains($0.key) }?.value
        
        guard carbonIntensity != nil else { return nil }
        
        return ESGEnrichment(
            carbonIntensity: carbonIntensity,
            dataQualityTier: 5,
            certifications: [],
            ecoScore: nil,
            source: "Climate TRACE (sector average)"
        )
    }
}
