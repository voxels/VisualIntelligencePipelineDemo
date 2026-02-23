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

import ARKit

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
    /// On iOS/iPadOS, barcode detection is handled by the ARCameraView coordinator
    /// which runs VNDetectBarcodesRequest on ARKit frames and adds products directly.
    func startTracking() async throws {
        print("ℹ️ SpatialDetector: Using camera-based detection on iOS")
        isTracking = true
    }
    
    func stopTracking() {
        isTracking = false
        arSession?.pause()
        detectedProducts.removeAll()
        print("📷 SpatialDetector: Stopped tracking")
    }
    
    /// Pause AR processing (app backgrounded) without clearing detected products.
    func pauseSession() {
        isTracking = false
        arSession?.pause()
        print("📷 SpatialDetector: Paused (background)")
    }
    
    /// Resume AR processing (app foregrounded). Re-runs session config.
    func resumeSession() {
        isTracking = true
        if let session = arSession {
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal, .vertical]
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
            }
            session.run(config)
            print("📷 SpatialDetector: Resumed (foreground)")
        }
    }
    
    /// Weak reference to the ARSession, set by the Coordinator.
    /// Used to pause/resume from lifecycle events.
    weak var arSession: ARSession?
    #endif
    
    // MARK: - Commerce Scoring (Edge-First)
    
    /// Score a detected product by looking up its barcode in Open Facts / UPC Item DB,
    /// then enriching with government safety data. Updates the product's name, scores,
    /// and intelligence summary in place.
    func scoreProduct(at index: Int) async {
        guard index < detectedProducts.count else { return }
        let product = detectedProducts[index]
        
        // ── Step 1: Barcode → Product Identity (ESG enrichment cascade) ──
        let esgService = ESGEnrichmentService()
        var esgEnrichment: ESGEnrichment? = nil
        
        if let barcode = product.barcode {
            esgEnrichment = try? await esgService.enrich(barcode: barcode)
            
            if let enrichment = esgEnrichment {
                // Update product name from database
                let resolvedName = enrichment.productName ?? enrichment.genericName ?? product.productName
                let resolvedBrand = enrichment.brand
                
                guard index < detectedProducts.count else { return }
                detectedProducts[index].productName = resolvedName
                detectedProducts[index].brand = resolvedBrand
                
                print("🏷️ SpatialDetector: Resolved barcode \(barcode) → \(resolvedName) by \(resolvedBrand ?? "unknown")")
            }
        }
        
        // ── Step 2: Build meaningful scores from real data ──
        let resolvedProduct = index < detectedProducts.count ? detectedProducts[index] : product
        
        let classification = ProductClassification(
            productID: UUID().uuidString,
            name: resolvedProduct.productName,
            category: resolvedProduct.classification,
            brand: resolvedProduct.brand,
            barcode: resolvedProduct.barcode,
            confidence: 0.5
        )
        
        let router = await MainActor.run { Services.shared.edgeRouter }
        let system = await MainActor.run { Services.shared.actorSystem }
        
        // Government safety data + price trajectory + company ESG + affiliate platforms (parallel)
        async let govResult = fetchGovernmentData(product: classification, router: router, system: system)
        async let trajectoryResult = fetchNowcast(category: classification.category, router: router, system: system)
        async let companyESGResult: CompanyESGProfile? = {
            if let brand = resolvedProduct.brand {
                return await self.fetchCompanyESG(brand: brand, router: router, system: system)
            }
            return nil
        }()
        async let affiliateResult = fetchAffiliatePlatforms(product: classification, router: router, system: system)
        
        let gov = await govResult
        let trajectory = await trajectoryResult
        let companyESG = await companyESGResult
        let affiliatePlatforms = await affiliateResult
        
        // Build scores from ESG + Government data
        var scores: [(name: String, score: Float)] = []
        var summaryParts: [String] = []
        var totalScore: Float = 0
        var scoreCount: Float = 0
        
        // ESG Score — from eco-score grade, certifications, data quality
        if let enrichment = esgEnrichment {
            var esgScore: Float = 0.5 // Default baseline
            
            // Eco-Score (A=0.95, B=0.75, C=0.55, D=0.35, E=0.15)
            if let ecoGrade = enrichment.ecoScore?.lowercased() {
                switch ecoGrade {
                case "a": esgScore = 0.95; summaryParts.append("Eco-Score A (excellent)")
                case "b": esgScore = 0.75; summaryParts.append("Eco-Score B (good)")
                case "c": esgScore = 0.55; summaryParts.append("Eco-Score C (moderate)")
                case "d": esgScore = 0.35; summaryParts.append("Eco-Score D (below average)")
                case "e": esgScore = 0.15; summaryParts.append("Eco-Score E (poor)")
                default: break
                }
            }
            
            // Certification bonus
            if !enrichment.certifications.isEmpty {
                esgScore = min(1.0, esgScore + Float(enrichment.certifications.count) * 0.05)
                let certs = enrichment.certifications.prefix(3).joined(separator: ", ")
                summaryParts.append("Certified: \(certs)")
            }
            
            // Carbon intensity
            if let carbon = enrichment.carbonIntensity {
                let carbonScore: Float = carbon < 1.0 ? 0.9 : carbon < 3.0 ? 0.7 : carbon < 10.0 ? 0.4 : 0.2
                esgScore = (esgScore + carbonScore) / 2.0
                summaryParts.append(String(format: "%.1f kg CO₂e", carbon))
            }
            
            scores.append(("Ethics", esgScore))
            totalScore += esgScore
            scoreCount += 1
            
            // Health Score — from NOVA group + Nutri-Score
            if enrichment.novaGroup != nil || enrichment.nutriScore != nil {
                var healthScore: Float = 0.5
                
                if let nova = enrichment.novaGroup {
                    healthScore = Float(5 - nova) / 4.0 // NOVA 1=1.0, 4=0.25
                    summaryParts.append("NOVA \(nova)/4 processing")
                }
                
                if let ns = enrichment.nutriScore?.lowercased() {
                    let nsScore: Float = switch ns {
                    case "a": 0.95
                    case "b": 0.75
                    case "c": 0.55
                    case "d": 0.35
                    case "e": 0.15
                    default: 0.5
                    }
                    healthScore = (healthScore + nsScore) / 2.0
                    summaryParts.append("Nutri-Score \(ns.uppercased())")
                }
                
                scores.append(("Health", healthScore))
                totalScore += healthScore
                scoreCount += 1
            }
            
            // Origin/Sourcing
            if let origin = enrichment.origins, !origin.isEmpty {
                summaryParts.append("Origin: \(origin)")
            }
            
            // Allergens (health-critical)
            if !enrichment.allergens.isEmpty {
                summaryParts.append("⚠️ Allergens: \(enrichment.allergens.prefix(4).joined(separator: ", "))")
            }
            
            // Package size (useful for value comparison)
            if let qty = enrichment.quantity, !qty.isEmpty {
                summaryParts.append(qty)
            }
            
            // Where to buy
            if !enrichment.stores.isEmpty {
                summaryParts.append("Available at: \(enrichment.stores.prefix(3).joined(separator: ", "))")
            }
            
            // Source attribution
            summaryParts.append("via \(enrichment.source)")
        }
        
        // Safety Score — only when government data found something actionable
        if let gov {
            let hasRecalls = !gov.recalls.isEmpty
            let hasFDA = !gov.fdaAlerts.isEmpty
            let hasEPA = gov.epaCompliance?.hasViolations == true
            let isFood = esgEnrichment?.source.contains("Food") == true || esgEnrichment?.novaGroup != nil
            let hasEnergyStar = gov.energyStarRating?.isCertified == true && !isFood // Energy Star irrelevant for food
            
            // Only show Safety score if there's actual safety data
            if hasRecalls || hasFDA || hasEPA || hasEnergyStar {
                var safetyScore: Float = 0.9
                
                if hasRecalls {
                    safetyScore = max(0.1, safetyScore - Float(gov.recalls.count) * 0.25)
                    let firstRecall = gov.recalls.first
                    let hazardText = firstRecall?.hazard ?? firstRecall?.title ?? "safety recall"
                    summaryParts.insert("🚨 CPSC: \(hazardText)", at: 0)
                }
                
                if hasFDA {
                    safetyScore = max(0.1, safetyScore - Float(gov.fdaAlerts.count) * 0.2)
                    if let first = gov.fdaAlerts.first {
                        summaryParts.insert("⚠️ FDA \(first.classification): \(first.reason.prefix(60))", at: min(1, summaryParts.count))
                    }
                }
                
                if hasEPA, let epa = gov.epaCompliance {
                    safetyScore = max(0.1, safetyScore - 0.3)
                    summaryParts.append("🏭 EPA: \(epa.violationCount) violation(s) — \(epa.complianceStatus)")
                }
                
                if hasEnergyStar, let energy = gov.energyStarRating {
                    safetyScore = min(1.0, safetyScore + 0.1)
                    var energyLine = "⭐ Energy Star certified"
                    if let kwh = energy.annualEnergyUseKWh {
                        energyLine += String(format: " (%.0f kWh/yr", kwh)
                        if let cost = energy.energyCostPerYear {
                            energyLine += String(format: ", $%.0f/yr)", cost)
                        } else {
                            energyLine += ")"
                        }
                    }
                    summaryParts.append(energyLine)
                }
                
                scores.append(("Safety", safetyScore))
                totalScore += safetyScore
                scoreCount += 1
            }
        }
        
        // Durability — only meaningful for durable goods categories
        let category = resolvedProduct.classification.lowercased()
        if ["electronics", "appliance", "hardware", "tools", "furniture", "equipment"].contains(where: { category.contains($0) }) {
            scores.append(("Durability", 0.7))
            totalScore += 0.7
            scoreCount += 1
            summaryParts.append("Durable goods")
        }
        
        // Company-level ESG — only when B Corp or company data found
        if let company = companyESG {
            if company.isBCorp {
                summaryParts.append("🏅 B Corp certified")
                // Boost ethics score if we have one, otherwise add as standalone
                if let ethicsIdx = scores.firstIndex(where: { $0.name == "Ethics" }) {
                    let boosted = min(1.0, scores[ethicsIdx].score + 0.1)
                    totalScore += (boosted - scores[ethicsIdx].score)
                    scores[ethicsIdx] = ("Ethics", boosted)
                }
            }
            if !company.certifications.isEmpty {
                let certs = company.certifications.filter { cert in
                    !summaryParts.contains(where: { $0.contains(cert) })
                }
                if !certs.isEmpty {
                    summaryParts.append(certs.prefix(2).joined(separator: ", "))
                }
            }
            if !company.controversies.isEmpty {
                summaryParts.append("⚠️ \(company.controversies.count) controvers(ies)")
            }
        }
        
        let composite = scoreCount > 0 ? totalScore / scoreCount : 0.5
        
        // Build recommendation with reasoning
        let recommendation: String
        if let gov, gov.hasConcerns {
            recommendation = "⚠️ \(gov.recalls.count) safety recall(s) found — review before purchasing"
        } else {
            // Cite the strongest signal driving the recommendation
            let sorted = scores.sorted { $0.score > $1.score }
            let topSignal = sorted.first.map { "\($0.name) \(Int($0.score * 100))%" } ?? ""
            let weakSignal = sorted.last.map { $0.score < 0.5 ? " — \($0.name) low (\(Int($0.score * 100))%)" : "" } ?? ""
            
            if composite >= 0.7 {
                recommendation = "✅ Recommended — \(topSignal)\(weakSignal)"
            } else if composite >= 0.4 {
                let reason = sorted.filter { $0.score < 0.5 }.map { "\($0.name) \(Int($0.score * 100))%" }.joined(separator: ", ")
                recommendation = "⏳ Wait — \(reason.isEmpty ? "moderate scores" : reason)"
            } else {
                let reason = sorted.filter { $0.score < 0.4 }.map { "\($0.name) \(Int($0.score * 100))%" }.joined(separator: ", ")
                recommendation = "❌ Not recommended — \(reason.isEmpty ? "low scores across the board" : reason)"
            }
        }
        
        // Build summary
        let summary = summaryParts.isEmpty ? nil : summaryParts.joined(separator: " · ")
        
        // Only show results backed by real data
        let hasRealData = esgEnrichment != nil || (gov?.hasConcerns == true)
        
        // Update product
        guard index < detectedProducts.count else { return }
        detectedProducts[index].compositeScore = composite
        detectedProducts[index].strategyScores = scores
        detectedProducts[index].recommendation = hasRealData ? recommendation : "No data found"
        detectedProducts[index].summary = summary
        detectedProducts[index].hasData = hasRealData
        detectedProducts[index].isScoring = false
        detectedProducts[index].esgEnrichment = esgEnrichment
        detectedProducts[index].priceTrajectory = trajectory
        detectedProducts[index].companyESG = companyESG
        detectedProducts[index].affiliatePlatforms = affiliatePlatforms
        
        if hasRealData {
            print("🛒 SpatialDetector: Scored \(detectedProducts[index].productName) → composite=\(String(format: "%.0f%%", composite * 100)), \(scores.count) strategies")
        } else {
            print("🛒 SpatialDetector: No data found for barcode \(detectedProducts[index].barcode ?? "unknown") — hiding card")
        }
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
    var brand: String? = nil
    var barcode: String? = nil
    var summary: String? = nil
    var compositeScore: Float = 0.0
    var strategyScores: [(name: String, score: Float)] = []
    var recommendation: String = "Analyzing…"
    
    /// Whether real data was found for this product. If false, the card
    /// should be hidden — we don't show inconclusive default scores.
    var hasData: Bool = false
    
    /// True while scoring is in progress (show spinner, not card).
    var isScoring: Bool = true
    
    /// World-space transform of where the barcode was detected.
    /// Used to project the score card back to screen coordinates each frame.
    var worldAnchor: simd_float4x4 = matrix_identity_float4x4
    
    /// Screen-space position of the card (x, y in points, z > 0 means visible).
    /// Offset above the barcode to avoid occluding it.
    var screenPosition: SIMD3<Float> = SIMD3<Float>(200, 400, 1)
    
    /// Screen-space position of the actual barcode (for drawing connector lines).
    var barcodeScreenPosition: CGPoint = .zero
    
    /// Full ESG enrichment data for expanded detail view.
    var esgEnrichment: ESGEnrichment? = nil
    
    /// Price trajectory for trend chart display.
    var priceTrajectory: PriceTrajectory? = nil
    
    /// Company-level ESG profile (B Corp, certifications, controversies).
    var companyESG: CompanyESGProfile? = nil
    
    /// Ranked ethical shopping platforms with affiliate links.
    var affiliatePlatforms: [PlatformMatch]? = nil
    
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
