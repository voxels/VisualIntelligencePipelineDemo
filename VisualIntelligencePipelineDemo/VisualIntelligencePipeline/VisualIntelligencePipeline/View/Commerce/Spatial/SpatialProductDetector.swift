//
//  SpatialProductDetector.swift
//  VisualIntelligencePipeline
//
//  Uses ARKit scene understanding to detect products in the environment
//  and feeds them through the pipeline's scoring engines.
//  ARKitSession + SceneReconstructionProvider require visionOS.
//  On iOS/iPadOS, detection uses camera-based Vision framework instead.
//

import Foundation
import SwiftUI
import RealityKit
import DiverKit
import DiverShared

#if os(visionOS)
import ARKit
#endif

/// Detects products in the spatial environment.
/// On visionOS: uses ARKitSession + SceneReconstructionProvider for spatial detection.
/// On iOS/iPadOS: detection is handled by the existing Vision pipeline (camera-based).
@Observable
final class SpatialProductDetector {
    
    var detectedProducts: [SpatialDetectedProduct] = []
    var isTracking = false
    
    #if os(visionOS)
    private let session = ARKitSession()
    
    /// Start ARKit scene understanding for spatial product detection.
    func startTracking() async throws {
        guard SceneReconstructionProvider.isSupported else {
            print("⚠️ SpatialDetector: Scene reconstruction not supported on this device")
            return
        }
        
        let sceneReconstruction = SceneReconstructionProvider()
        try await session.run([sceneReconstruction])
        isTracking = true
        
        print("📷 SpatialDetector: Started ARKit scene tracking")
        
        for await update in sceneReconstruction.anchorUpdates {
            switch update.event {
            case .added:
                let anchor = update.anchor
                let product = SpatialDetectedProduct(
                    anchorID: anchor.id,
                    position: anchor.originFromAnchorTransform.columns.3.xyz,
                    classification: "object"
                )
                detectedProducts.append(product)
                
            case .updated:
                if let index = detectedProducts.firstIndex(where: { $0.anchorID == update.anchor.id }) {
                    detectedProducts[index].position = update.anchor.originFromAnchorTransform.columns.3.xyz
                }
                
            case .removed:
                detectedProducts.removeAll { $0.anchorID == update.anchor.id }
            }
        }
    }
    
    func stopTracking() {
        session.stop()
        isTracking = false
        detectedProducts.removeAll()
        print("📷 SpatialDetector: Stopped tracking")
    }
    #else
    /// On iOS/iPadOS, spatial detection is handled by the camera pipeline.
    /// This is a no-op — the existing VisualIntelligenceViewModel handles
    /// product detection via Vision framework barcode/classification.
    func startTracking() async throws {
        print("ℹ️ SpatialDetector: Using camera-based detection on iOS")
        isTracking = true
    }
    
    func stopTracking() {
        isTracking = false
        detectedProducts.removeAll()
    }
    #endif
    
    // MARK: - Commerce Scoring (Edge-First)
    
    /// Score a detected product using edge commerce actors when available,
    /// falling back to local services. Updates the product's scores in place.
    func scoreProduct(at index: Int) async {
        guard index < detectedProducts.count else { return }
        let product = detectedProducts[index]
        
        let classification = ProductClassification(
            productID: UUID().uuidString,
            name: product.productName,
            category: product.classification,
            brand: nil,
            barcode: nil,
            confidence: 0.5
        )
        
        let router = await MainActor.run { Services.shared.edgeRouter }
        let system = await MainActor.run { Services.shared.actorSystem }
        
        // Parallel enrichment — edge-first where available
        async let govData = fetchGovernmentData(product: classification, router: router, system: system)
        async let companyESG = fetchCompanyESG(brand: classification.name, router: router, system: system)
        async let platforms = fetchAffiliatePlatforms(product: classification, router: router, system: system)
        async let nowcast = fetchNowcast(category: classification.category, router: router, system: system)
        
        let gov = await govData
        let esg = await companyESG
        let ranked = await platforms
        let price = await nowcast
        
        // Composite score from available data
        var scores: [(name: String, score: Float)] = []
        var totalScore: Float = 0
        var scoreCount: Float = 0
        
        if let esg {
            let esgScore = min((esg.overallScore ?? 0.5) / 100.0, 1.0)
            scores.append(("ESG", esgScore))
            totalScore += esgScore
            scoreCount += 1
        }
        
        if let gov {
            // Lower score = more concerns
            let safetyScore: Float = gov.hasConcerns ? 0.3 : 0.9
            scores.append(("Safety", safetyScore))
            totalScore += safetyScore
            scoreCount += 1
        }
        
        if let price {
            // Map price trend to score
            let trendScore: Float = switch price.projectedDirection {
            case .falling: 0.8     // Good time to buy
            case .stable: 0.6
            case .rising: 0.3      // Prices going up
            }
            scores.append(("Price", trendScore))
            totalScore += trendScore
            scoreCount += 1
        }
        
        if let ranked, !ranked.isEmpty {
            scores.append(("Platforms", Float(ranked.count) / 5.0))
        }
        
        let composite = scoreCount > 0 ? totalScore / scoreCount : 0.5
        
        // Build recommendation
        let recommendation: String
        if let gov, gov.hasConcerns {
            recommendation = "⚠️ Safety concerns — \(gov.recalls.count) recalls"
        } else if composite >= 0.7 {
            recommendation = "✅ Good buy — strong ethical score"
        } else if composite >= 0.4 {
            recommendation = "⏳ Consider waiting — moderate score"
        } else {
            recommendation = "❌ Low score — review concerns"
        }
        
        // Update product
        guard index < detectedProducts.count else { return }
        detectedProducts[index].compositeScore = composite
        detectedProducts[index].strategyScores = scores
        detectedProducts[index].recommendation = recommendation
        
        print("🛒 SpatialDetector: Scored \(classification.name) → composite=\(String(format: "%.2f", composite)), \(scores.count) strategies")
    }
    
    // MARK: - Edge-First Service Routing
    
    private func fetchGovernmentData(
        product: ProductClassification,
        router: PipelineEdgeRouter?,
        system: VisualIntelligenceActorSystem?
    ) async -> GovernmentEnrichment? {
        // Edge-first for government API calls
        if let router, let system,
           case .edge(let node, _) = await router.shouldOffload(task: .governmentAPI) {
            do {
                let identity = EdgeActorID(id: "EdgeESG", nodeName: node.deviceName)
                let actor = try EdgeESGActor.resolve(id: identity, using: system)
                return try await actor.fetchGovernmentData(product: product)
            } catch {
                print("⚠️ SpatialDetector: Edge gov data failed, falling back local: \(error)")
            }
        }
        // Local fallback
        let service = GovernmentDataService()
        return await service.enrich(product: product)
    }
    
    private func fetchCompanyESG(
        brand: String,
        router: PipelineEdgeRouter?,
        system: VisualIntelligenceActorSystem?
    ) async -> CompanyESGProfile? {
        if let router, let system,
           case .edge(let node, _) = await router.shouldOffload(task: .esgEnrichment) {
            do {
                let identity = EdgeActorID(id: "EdgeESG", nodeName: node.deviceName)
                let actor = try EdgeESGActor.resolve(id: identity, using: system)
                return try await actor.fetchCompanyESG(brand: brand)
            } catch {
                print("⚠️ SpatialDetector: Edge ESG failed, falling back local: \(error)")
            }
        }
        let service = OpenESGService()
        return await service.fetchProfile(brand: brand)
    }
    
    private func fetchAffiliatePlatforms(
        product: ProductClassification,
        router: PipelineEdgeRouter?,
        system: VisualIntelligenceActorSystem?
    ) async -> [PlatformMatch]? {
        let policy = EthicalPolicy(
            carbonThreshold: 50,
            preferredCertifications: ["B Corp", "Fair Trade"],
            platformRanking: ["thrift", "refurbished", "direct", "marketplace", "fast-fashion"],
            excludeLaborViolations: true
        )
        
        if let router, let system,
           case .edge(let node, _) = await router.shouldOffload(task: .commerceRouting) {
            do {
                let identity = EdgeActorID(id: "EdgeCommerce", nodeName: node.deviceName)
                let actor = try EdgeCommerceActor.resolve(id: identity, using: system)
                return try await actor.rankPlatforms(product: product, policy: policy)
            } catch {
                print("⚠️ SpatialDetector: Edge commerce failed, falling back local: \(error)")
            }
        }
        let service = AffiliateRoutingService()
        return try? await service.rankPlatforms(for: product, policy: policy)
    }
    
    private func fetchNowcast(
        category: String,
        router: PipelineEdgeRouter?,
        system: VisualIntelligenceActorSystem?
    ) async -> PriceTrajectory? {
        if let router, let system,
           case .edge(let node, _) = await router.shouldOffload(task: .nowcasting) {
            do {
                let identity = EdgeActorID(id: "EdgeNowcasting", nodeName: node.deviceName)
                let actor = try EdgeNowcastingActor.resolve(id: identity, using: system)
                return try await actor.project(commodityID: category, horizonDays: 30)
            } catch {
                print("⚠️ SpatialDetector: Edge nowcast failed, falling back local: \(error)")
            }
        }
        let pricingService = PricingDataService()
        return try? await pricingService.project(commodityID: category)
    }
}

/// A product detected in the spatial environment.
struct SpatialDetectedProduct: Identifiable {
    let id = UUID()
    let anchorID: UUID
    var position: SIMD3<Float>
    let classification: String
    let timestamp: Date = .now
    
    /// Pipeline-generated scores (populated after scoring).
    var productName: String = "Detected Object"
    var compositeScore: Float = 0.0
    var strategyScores: [(name: String, score: Float)] = []
    var recommendation: String = "Analyzing…"
    
    var scoreColor: Color {
        if compositeScore >= 0.7 { return .green }
        if compositeScore >= 0.4 { return .orange }
        return .red
    }
}

// MARK: - SIMD Extension

#if os(visionOS)
extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}
#endif
