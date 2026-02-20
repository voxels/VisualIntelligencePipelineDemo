//
//  EdgeNodeService.swift
//  DiverKit
//
//  Orchestrates edge computing: manages node discovery, actor resolution,
//  and intelligent routing of ML/analysis work to edge nodes or local fallback.
//
//  Contains 5 distributed actors for remote inference, nowcasting, commerce,
//  ESG enrichment, and financial advisory. The pipeline router dynamically
//  decides whether to process locally or offload to an edge node.
//

import Foundation
import Distributed
import ImageIO
import DiverShared

// MARK: - Distributed Actors

/// Edge Inference Actor — offloads Vision + VLM work to M-series hardware.
/// Uses the same `IntelligenceProcessor` and `FastVLMEnrichmentService` as the iOS pipeline.
public distributed actor EdgeInferenceActor {
    public typealias ActorSystem = VisualIntelligenceActorSystem
    
    private let processor = IntelligenceProcessor()
    
    distributed public func analyzeImage(_ imageData: Data) async throws -> VisionAnalysisResult {
        guard let cgImageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) else {
            throw EdgeInferenceError.invalidImageData
        }
        
        // Run the same full analysis pipeline used on-device
        let results = try await processor.process(image: cgImage, mode: .fullAnalysis)
        
        // Convert [IntelligenceResult] → VisionAnalysisResult for transport
        var ocrText: String? = nil
        var qrURLs: [String] = []
        var semanticTags: [String] = []
        var hasDocument = false
        var hasForegroundSubject = false
        var aestheticsScore: Float? = nil
        var saliencyMap: SaliencyResult? = nil
        
        for result in results {
            switch result {
            case .text(let text, _):
                ocrText = (ocrText ?? "") + text + "\n"
            case .qr(let url):
                qrURLs.append(url.absoluteString)
            case .semantic(let tag, _):
                semanticTags.append(tag)
            case .document:
                hasDocument = true
            case .siftedSubject:
                hasForegroundSubject = true
            case .aesthetics(let score):
                aestheticsScore = score
            case .saliency(let saliency):
                saliencyMap = saliency
            default:
                break
            }
        }
        
        return VisionAnalysisResult(
            ocrText: ocrText?.trimmingCharacters(in: .whitespacesAndNewlines),
            qrURLs: qrURLs,
            semanticTags: semanticTags,
            hasDocument: hasDocument,
            hasForegroundSubject: hasForegroundSubject,
            aestheticsScore: aestheticsScore,
            saliencyMap: saliencyMap
        )
    }
    
    distributed public func runVLM(imageData: Data, prompt: String) async throws -> LLMAnalysisResult {
        guard let cgImageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) else {
            throw EdgeInferenceError.invalidImageData
        }
        
        // Run Vision analysis first (same as pipeline does)
        let visionResult = try await analyzeImage(imageData)
        
        // Then run FastVLM using the same service the pipeline uses
        let vlmService = FastVLMEnrichmentService()
        let analysis = try await vlmService.analyze(
            image: cgImage,
            visionTags: visionResult.semanticTags,
            enrichmentContext: prompt,
            transcription: visionResult.ocrText
        )
        
        return LLMAnalysisResult(
            summary: analysis?.contextSummary,
            statements: analysis?.statements ?? [],
            purpose: analysis?.suggestedPurpose,
            tags: analysis?.suggestedTags ?? [],
            imageDescription: analysis?.imageDescription
        )
    }
}

/// Errors for edge inference operations.
public enum EdgeInferenceError: Error, Sendable {
    case invalidImageData
    case serviceUnavailable(String)
    case modelNotLoaded(String)
}

/// Edge Nowcasting Actor — runs DFM projections using PricingDataService + NowcastingEngine.
public distributed actor EdgeNowcastingActor {
    public typealias ActorSystem = VisualIntelligenceActorSystem
    
    distributed public func project(commodityID: String, horizonDays: Int) async throws -> PriceTrajectory {
        let pricingService = PricingDataService()
        let engine = NowcastingEngine()
        
        // Fetch real pricing data from the same sources as the pipeline
        let worldBankPrices = await pricingService.fetchWorldBankPrices(commodityID: commodityID)
        let blsPrices = await pricingService.fetchBLSPPI(seriesID: commodityID)
        
        // Feed both series into the DFM
        let series: [[PriceDataPoint]] = [worldBankPrices, blsPrices].filter { !$0.isEmpty }
        let result = engine.nowcast(series: series, horizonDays: horizonDays)
        
        // Combine all data points for the trajectory
        let allDataPoints = (worldBankPrices + blsPrices).sorted { $0.date < $1.date }
        
        return PriceTrajectory(
            commodityID: commodityID,
            dataPoints: allDataPoints,
            projectedDirection: result.direction,
            confidenceInterval: result.confidence,
            horizonDays: horizonDays
        )
    }
}

/// Edge Commerce Actor — runs affiliate routing and ethical matching.
public distributed actor EdgeCommerceActor {
    public typealias ActorSystem = VisualIntelligenceActorSystem
    
    distributed public func rankPlatforms(
        product: ProductClassification,
        policy: EthicalPolicy
    ) async throws -> [PlatformMatch] {
        let router = AffiliateRoutingService()
        return try await router.rankPlatforms(for: product, policy: policy)
    }
}

/// Edge ESG Actor — runs multi-database ESG cascade on edge node.
public distributed actor EdgeESGActor {
    public typealias ActorSystem = VisualIntelligenceActorSystem
    
    distributed public func fetchGovernmentData(
        product: ProductClassification
    ) async throws -> GovernmentEnrichment {
        let service = GovernmentDataService()
        return await service.enrich(product: product)
    }
    
    distributed public func fetchCompanyESG(brand: String) async throws -> CompanyESGProfile {
        let service = OpenESGService()
        return await service.fetchProfile(brand: brand) ?? CompanyESGProfile(companyName: brand)
    }
}

/// Edge Financial Actor — budget impact analysis.
/// Requires FinanceKit managed entitlement from Apple (not yet granted).
/// Without the entitlement, returns a result indicating financial data is unavailable.
public distributed actor EdgeFinancialActor {
    public typealias ActorSystem = VisualIntelligenceActorSystem
    
    distributed public func projectBudgetImpact(
        productPrice: Decimal,
        quantity: Int
    ) async throws -> BudgetImpactResult {
        // FinanceKit requires managed entitlement from Apple (not yet granted).
        // When granted, this will query FinanceStore for monthly spending,
        // calculate budget percentage impact, and generate a recommendation
        // based on the user's spending patterns in the product's category.
        let totalCost = productPrice * Decimal(quantity)
        return BudgetImpactResult(
            totalCost: totalCost,
            monthlyBudgetPercentage: 0,
            category: "unavailable",
            recommendation: "Financial analysis requires FinanceKit entitlement (pending Apple approval)"
        )
    }
}

/// Budget impact result from financial analysis.
public struct BudgetImpactResult: Codable, Sendable {
    public let totalCost: Decimal
    public let monthlyBudgetPercentage: Float
    public let category: String
    public let recommendation: String
    
    public init(totalCost: Decimal, monthlyBudgetPercentage: Float, category: String, recommendation: String) {
        self.totalCost = totalCost
        self.monthlyBudgetPercentage = monthlyBudgetPercentage
        self.category = category
        self.recommendation = recommendation
    }
}

// MARK: - Pipeline Edge Router

/// Routes pipeline work to edge nodes or local execution based on availability.
/// Decision logic: if edge node connected with sufficient capability → offload
/// Otherwise → fall back to local processing.
public final class PipelineEdgeRouter: Sendable {
    
    private let discoveryService: any EdgeNodeDiscovering
    
    /// Minimum neural engine TOPS required for inference offloading.
    private let minimumTOPS: Float = 10.0
    
    public init(discoveryService: any EdgeNodeDiscovering) {
        self.discoveryService = discoveryService
    }
    
    /// Determine whether a task should be offloaded to an edge node.
    public func shouldOffload(task: EdgeTask) async -> EdgeRoutingDecision {
        let isConnected = await discoveryService.isEdgeNodeConnected
        
        guard isConnected,
              let node = await discoveryService.connectedNode else {
            return .local(reason: "No edge node connected")
        }
        
        // Check if edge node has the capability
        switch task {
        case .visionAnalysis, .vlmInference:
            guard node.neuralEngineTOPS >= minimumTOPS else {
                return .local(reason: "Edge node TOPS (\(node.neuralEngineTOPS)) below threshold (\(minimumTOPS))")
            }
            return .edge(node: node, reason: "Offloading to \(node.deviceName) (\(node.chipFamily), \(node.neuralEngineTOPS) TOPS)")
            
        case .nowcasting:
            // Nowcasting is CPU-bound, any edge node can handle it
            return .edge(node: node, reason: "Offloading nowcasting to \(node.deviceName)")
            
        case .governmentAPI, .esgEnrichment:
            // Network-bound tasks can run on either side
            return .local(reason: "Network tasks run locally for latency")
            
        case .commerceRouting:
            return .edge(node: node, reason: "Offloading commerce routing to \(node.deviceName)")
        }
    }
}

/// Types of tasks that can be routed to edge nodes.
public enum EdgeTask: String, Sendable {
    case visionAnalysis
    case vlmInference
    case nowcasting
    case governmentAPI
    case esgEnrichment
    case commerceRouting
}

/// Result of edge routing decision.
public enum EdgeRoutingDecision: Sendable {
    case local(reason: String)
    case edge(node: EdgeNodeInfo, reason: String)
    
    public var isEdge: Bool {
        if case .edge = self { return true }
        return false
    }
}
