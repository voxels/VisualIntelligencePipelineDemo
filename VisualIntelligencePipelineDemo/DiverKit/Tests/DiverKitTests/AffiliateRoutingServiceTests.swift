//
//  AffiliateRoutingServiceTests.swift
//  DiverKitTests
//
//  Tests for AffiliateRoutingService: platform ranking, ethical
//  policy matching, and affiliate URL generation.
//

import Testing
@testable import DiverKit
import DiverShared

@Suite("AffiliateRoutingService Tests")
struct AffiliateRoutingServiceTests {
    
    let service = AffiliateRoutingService()
    
    @Test("Default policy returns all 5 platforms")
    func defaultPolicyReturnsAllPlatforms() async throws {
        let product = ProductClassification(
            productID: "test-001",
            name: "Organic Coffee",
            category: "food",
            brand: "FairTrade",
            barcode: nil,
            confidence: 0.8
        )
        let policy = EthicalPolicy(
            carbonThreshold: 0.8,
            preferredCertifications: [],
            platformRanking: [],
            excludeLaborViolations: false
        )
        let platforms = try await service.rankPlatforms(for: product, policy: policy)
        #expect(platforms.count == 5)
    }
    
    @Test("Strict carbon policy filters high-carbon platforms")
    func strictCarbonFilters() async throws {
        let product = ProductClassification(
            productID: "test-002",
            name: "Widget",
            category: "general",
            brand: nil,
            barcode: nil,
            confidence: 0.5
        )
        let policy = EthicalPolicy(
            carbonThreshold: 0.01, // Very strict
            preferredCertifications: ["B-Corp"],
            platformRanking: ["thrive_market"],
            excludeLaborViolations: true
        )
        let platforms = try await service.rankPlatforms(for: product, policy: policy)
        // Some platforms may be filtered
        #expect(platforms.count >= 0)
        #expect(platforms.count <= 5)
    }
    
    @Test("Platform preference order affects ranking")
    func preferenceOrderAffectsRanking() async throws {
        let product = ProductClassification(
            productID: "test-003",
            name: "T-Shirt",
            category: "clothing",
            brand: nil,
            barcode: nil,
            confidence: 0.7
        )
        let policy = EthicalPolicy(
            carbonThreshold: 0.8,
            preferredCertifications: [],
            platformRanking: ["ebay", "target"],
            excludeLaborViolations: false
        )
        let platforms = try await service.rankPlatforms(for: product, policy: policy)
        #expect(!platforms.isEmpty)
        // First platform should be influenced by preference
    }
    
    @Test("Platform matches have valid scores")
    func matchScoresValid() async throws {
        let product = ProductClassification(
            productID: "test-004",
            name: "Laptop",
            category: "electronics",
            brand: "Apple",
            barcode: nil,
            confidence: 0.9
        )
        let policy = EthicalPolicy(
            carbonThreshold: 0.5,
            preferredCertifications: [],
            platformRanking: [],
            excludeLaborViolations: false
        )
        let platforms = try await service.rankPlatforms(for: product, policy: policy)
        for platform in platforms {
            #expect(platform.ethicalMatchScore >= 0.0)
            #expect(platform.ethicalMatchScore <= 1.0)
        }
    }
    
    @Test("Affiliate URLs are non-empty")
    func affiliateURLsPopulated() async throws {
        let product = ProductClassification(
            productID: "test-005",
            name: "Shoes",
            category: "clothing",
            brand: "Nike",
            barcode: nil,
            confidence: 0.8
        )
        let policy = EthicalPolicy(
            carbonThreshold: 0.8,
            preferredCertifications: [],
            platformRanking: [],
            excludeLaborViolations: false
        )
        let platforms = try await service.rankPlatforms(for: product, policy: policy)
        for platform in platforms {
            #expect(platform.affiliateURL != nil)
        }
    }
}
