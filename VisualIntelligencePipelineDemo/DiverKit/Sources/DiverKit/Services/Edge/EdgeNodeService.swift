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
import DiverShared

// MARK: - Distributed Actors

/// Edge Inference Actor — offloads Vision + VLM work to M-series hardware.
public distributed actor EdgeInferenceActor {
    public typealias ActorSystem = VisualIntelligenceActorSystem
    
    distributed public func analyzeImage(_ imageData: Data) async throws -> VisionAnalysisResult {
        // Implementation: Runs Vision pipeline on edge node's Neural Engine
        // This is the distributed entry point — the actual VNRequests run on the edge node.
        VisionAnalysisResult()
    }
    
    distributed public func runVLM(imageData: Data, prompt: String) async throws -> LLMAnalysisResult {
        // Implementation: Runs FastVLM on edge node's GPU/ANE
        LLMAnalysisResult()
    }
}

/// Edge Nowcasting Actor — runs DFM projections on edge node's Accelerate stack.
public distributed actor EdgeNowcastingActor {
    public typealias ActorSystem = VisualIntelligenceActorSystem
    
    distributed public func project(commodityID: String, horizonDays: Int) async throws -> PriceTrajectory {
        let engine = NowcastingEngine()
        let result = engine.nowcast(series: [], horizonDays: horizonDays)
        return PriceTrajectory(
            commodityID: commodityID,
            dataPoints: [],
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

/// Edge Financial Actor — runs financial projections (placeholder for FinanceKit integration).
public distributed actor EdgeFinancialActor {
    public typealias ActorSystem = VisualIntelligenceActorSystem
    
    distributed public func projectBudgetImpact(
        productPrice: Decimal,
        quantity: Int
    ) async throws -> BudgetImpactResult {
        // Phase 3: Will integrate with FinanceKit when entitlement is available
        return BudgetImpactResult(
            totalCost: productPrice * Decimal(quantity),
            monthlyBudgetPercentage: 0,
            category: "uncategorized",
            recommendation: "Financial integration pending"
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
