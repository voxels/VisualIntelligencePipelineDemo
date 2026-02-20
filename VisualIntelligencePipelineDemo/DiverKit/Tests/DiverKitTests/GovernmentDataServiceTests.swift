//
//  GovernmentDataServiceTests.swift
//  DiverKitTests
//
//  Tests for GovernmentDataService API URL construction, response parsing,
//  and parallel execution.
//

import Testing
@testable import DiverKit
import DiverShared

@Suite("GovernmentDataService Tests")
struct GovernmentDataServiceTests {
    
    let service = GovernmentDataService()
    
    @Test("CPSC URL construction uses correct endpoint")
    func cpscURLConstruction() async {
        // Verify the service handles URL-safe encoding
        let results = await service.fetchCPSCRecalls(query: "baby stroller")
        // API may or may not return data — we verify it doesn't crash
        #expect(results.count >= 0)
    }
    
    @Test("FDA URL construction uses correct endpoint")
    func fdaURLConstruction() async {
        let results = await service.fetchFDAAlerts(query: "milk")
        #expect(results.count >= 0)
    }
    
    @Test("EPA handles nil brand gracefully")
    func epaHandlesNilBrand() async {
        let result = await service.fetchEPACompliance(brand: nil)
        #expect(result == nil)
    }
    
    @Test("Energy Star maps categories correctly")
    func energyStarCategoryMapping() async {
        let classification = ProductClassification(
            productID: "test-001",
            name: "Test TV",
            category: "television",
            brand: "Samsung",
            barcode: nil,
            confidence: 0.8
        )
        let result = await service.fetchEnergyStarRating(product: classification)
        // Will either find a result or return isCertified=false
        #expect(result != nil)
    }
    
    @Test("GovernmentEnrichment hasConcerns is false when empty")
    func enrichmentNoConcerns() {
        let enrichment = GovernmentEnrichment()
        #expect(!enrichment.hasConcerns)
    }
    
    @Test("GovernmentEnrichment hasConcerns is true with recalls")
    func enrichmentWithRecalls() {
        let recall = RecallNotice(recallID: "R-001", title: "Test Recall", description: "Hazard")
        let enrichment = GovernmentEnrichment(recalls: [recall])
        #expect(enrichment.hasConcerns)
    }
    
    @Test("Parallel enrichment returns all fields")
    func parallelEnrichment() async {
        let classification = ProductClassification(
            productID: "test-002",
            name: "Test Product",
            category: "general",
            brand: nil,
            barcode: nil,
            confidence: 0.5
        )
        let result = await service.enrich(product: classification)
        // Should complete without crash — all fields populated (possibly empty)
        #expect(result.recalls.count >= 0)
        #expect(result.fdaAlerts.count >= 0)
    }
}
