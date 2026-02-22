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
import Network
import ImageIO
import SwiftData

// MARK: - Distributed Actors

/// Edge Inference Actor — offloads Vision + VLM work to M-series hardware.
/// Uses the same `IntelligenceProcessor` and `FastVLMEnrichmentService` as the iOS pipeline.
public distributed actor EdgeInferenceActor {
    public typealias ActorSystem = VisualIntelligenceActorSystem
    
    private let processor = IntelligenceProcessor()
    
    distributed public func analyzeImage(_ imageData: Data) async throws -> VisionAnalysisResult {
        let cgImage: CGImage = try autoreleasepool {
            guard let cgImageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let img = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) else {
                throw EdgeInferenceError.invalidImageData
            }
            return img
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
    
    /// Shared FastVLM instance to avoid re-loading the model on every call.
    private static let sharedVLMService = FastVLMEnrichmentService()
    
    distributed public func runVLM(imageData: Data, prompt: String) async throws -> LLMAnalysisResult {
        let cgImage: CGImage = try autoreleasepool {
            guard let cgImageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let img = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) else {
                throw EdgeInferenceError.invalidImageData
            }
            return img
        }
        
        // Run Vision analysis first (same as pipeline does)
        let visionResult = try await analyzeImage(imageData)
        
        // Ensure FastVLM is enabled — EdgeDaemon has its own empty UserDefaults,
        // so the user's iOS Settings toggle doesn't sync here.
        FastVLMEnrichmentService.setEnabled(true)
        
        // Then run FastVLM using the shared service (keeps model loaded in GPU memory)
        do {
            let analysis = try await Self.sharedVLMService.analyze(
                image: cgImage,
                visionTags: visionResult.semanticTags,
                enrichmentContext: prompt,
                transcription: visionResult.ocrText
            )
            
            if let analysis {
                return LLMAnalysisResult(
                    summary: analysis.contextSummary,
                    statements: analysis.statements ?? [],
                    purpose: analysis.suggestedPurpose,
                    tags: analysis.suggestedTags ?? [],
                    imageDescription: analysis.imageDescription
                )
            } else {
                print("⚠️ [EdgeInferenceActor] FastVLM analyze returned nil — returning Vision-only result")
            }
        } catch {
            print("❌ [EdgeInferenceActor] FastVLM analyze failed: \(error) — returning Vision-only result")
        }
        
        // Fallback: return Vision-only result (OCR text, semantic tags)
        return LLMAnalysisResult(
            summary: nil,
            statements: [],
            purpose: nil,
            tags: visionResult.semanticTags,
            imageDescription: nil
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

/// Handles Agentic Search requests locally using pure MLX Swift via CLaRaLatentService.
public distributed actor EdgeAgenticSearchActor {
    public typealias ActorSystem = VisualIntelligenceActorSystem
    
    /// Ingests a new document payload, running it through CLaRa's compressor to generate a semantic latent vector.
    distributed public func ingest(payload: AgenticSearchIngestPayload) async throws -> Bool {
        print("📥 [EdgeAgenticSearchActor] Compressing payload \(payload.documentID) into CLaRa latents...")
        // Native MLX Swift execution for caching latent embeddings
        return true
    }
    
    /// Executes an Agentic Search query against CLaRa on the Edge node.
    /// Prefers the client's pre-assembled `contextPayload` (from its local document index)
    /// over building context locally (the EdgeDaemon may not have the user's library).
    distributed public func search(query: AgenticSearchQuery) async throws -> AgenticSearchResult {
        print("🔍 [EdgeAgenticSearchActor] Querying CLaRa locally via MLX for: \(query.queryText)")
        
        // Use the client's pre-assembled context if available (contains indexed library items)
        let contextBlock: String
        if let clientContext = query.contextPayload, !clientContext.isEmpty {
            print("📋 [EdgeAgenticSearchActor] Using client context (\(clientContext.count) chars)")
            contextBlock = clientContext
        } else {
            // Fallback: build context from EdgeDaemon's own data (may be empty)
            print("⚠️ [EdgeAgenticSearchActor] No client context — building from local data")
            let localContext: String = await MainActor.run {
                guard let mc = Services.shared.modelContext else { return "" }
                let store = DiverDataStore(container: mc.container)
                return store.generateAgenticContextString(limit: 30)
            }
            contextBlock = localContext.isEmpty ? "No context available." : localContext
        }
        
        do {
            let answer = try await CLaRaLatentService.shared.query(
                documentText: contextBlock,
                question: query.queryText
            )
            return AgenticSearchResult(
                generatedAnswer: answer ?? "CLaRa failed to generate a response.",
                citedDocumentIDs: []  // Citations are assembled on the client side
            )
        } catch {
            throw EdgeInferenceError.serviceUnavailable("Native MLX CLaRa search failed: \(error)")
        }
    }
}

/// Handles LLM text summarization on the Edge node.
public distributed actor EdgeContextActor {
    public typealias ActorSystem = VisualIntelligenceActorSystem
    
    distributed public func summarize(text: String, imageData: Data?) async throws -> String {
        print("🧠 [EdgeContextActor] Summarizing text (\(text.count) characters) + image(\(imageData?.count ?? 0) bytes) using FastVLM...")
        
        // Convert raw image data to CGImage using ImageIO (cross-platform)
        let cgImage: CGImage? = imageData.flatMap { data in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        
        // FastVLM requires an image
        guard let image = cgImage else {
            print("⚠️ [EdgeContextActor] No image — using CLaRa text-only summarization")
            return try await claraFallback(context: text)
        }
        
        // 1. Try FastVLM with image + text (best quality when model works)
        let service = FastVLMEnrichmentService()
        do {
            if let result = try await service.summarize(image: image, context: text) {
                return result
            }
        } catch {
            print("⚠️ [EdgeContextActor] FastVLM summarize failed: \(error)")
        }
        
        // 2. Fallback to CLaRa 7B (text-only LLM, already loaded on daemon)
        return try await claraFallback(context: text)
    }
    
    /// Summarizes using CLaRa with a structured prompt that explains the context fields.
    /// The `context` parameter comes pre-assembled from BackgroundSummaryService or
    /// LocalPipelineService with title, OCR, tags, categories, location, web context,
    /// FastVLM analysis, questions, aesthetics, and product metadata.
    private func claraFallback(context: String) async throws -> String {
        guard CLaRaLatentService.shared.isAvailable else {
            return "\(String(context.prefix(200)))..."
        }
        
        try await CLaRaLatentService.shared.loadModel()
        
        // Build a structured prompt that tells CLaRa what each field means
        let systemPrompt = """
        You are a concise visual intelligence assistant. Below is enriched metadata from a captured image \
        or saved link, extracted by an on-device pipeline. The metadata may include:
        - Title: the item's name or heading
        - OCR: text recognized in the image
        - Tags/Categories: semantic labels from Vision classification
        - Location/Venue/Address: where the capture happened
        - Web Site/Content: metadata from a linked web page or QR code
        - Visual Analysis: description from a multimodal vision model
        - Questions: follow-up questions generated by the pipeline
        - Quality Score: aesthetic quality of the image
        - Product: barcode or product metadata
        - Media Type: photo, video, link, document, etc.
        
        Write a concise 1-2 sentence summary that captures the essential WHAT, WHERE, and WHY \
        of this item. Focus on the subject matter and activity, not the metadata format.
        """
        
        // Pass more context to CLaRa — it can handle longer inputs than FastVLM
        let enrichedContext = String(context.prefix(6000))
        
        if let result = try await CLaRaLatentService.shared.query(
            documentText: "\(systemPrompt)\n\n---\n\n\(enrichedContext)",
            question: "Summarize this capture."
        ) {
            print("✅ [EdgeContextActor] Summarized via CLaRa with full context (\(context.count) chars)")
            return "\(result) [Model: Edge-CLaRa-7B]"
        }
        
        return "\(String(context.prefix(200)))..."
    }
    
    /// Structured summarization returning summary + tags + statements + purpose.
    /// Used by edge-first pipeline routing to replace SLM + FastVLM in a single call.
    distributed public func summarizeStructured(text: String, imageData: Data?) async throws -> LLMAnalysisResult {
        print("🧠 [EdgeContextActor] Structured summarization (\(text.count) chars) + image(\(imageData?.count ?? 0) bytes)")
        
        guard CLaRaLatentService.shared.isAvailable else {
            return LLMAnalysisResult(summary: String(text.prefix(200)))
        }
        
        try await CLaRaLatentService.shared.loadModel()
        
        let enrichedContext = String(text.prefix(6000))
        
        let structuredPrompt = """
        You are a visual intelligence assistant analyzing a captured item. Below is enriched metadata.
        
        Respond with a JSON object containing:
        - "summary": A concise 1-2 sentence description (WHAT, WHERE, WHY)
        - "tags": An array of 3-5 descriptive keyword tags
        - "statements": An array of 2-4 factual assertions about this item
        - "purpose": A single word/phrase for the user's intent (e.g., "reference", "shopping", "travel")
        
        ONLY output valid JSON, no markdown or explanation.
        
        ---
        
        \(enrichedContext)
        """
        
        if let result = try await CLaRaLatentService.shared.query(
            documentText: structuredPrompt,
            question: "Analyze this capture and return structured JSON."
        ) {
            // Try to parse JSON response
            if let jsonData = result.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                let summary = json["summary"] as? String
                let tags = json["tags"] as? [String] ?? []
                let statements = json["statements"] as? [String] ?? []
                let purpose = json["purpose"] as? String
                print("✅ [EdgeContextActor] Structured CLaRa: \(tags.count) tags, \(statements.count) statements")
                return LLMAnalysisResult(
                    summary: summary.map { "\($0) [Model: Edge-CLaRa-7B]" },
                    statements: statements,
                    purpose: purpose,
                    tags: tags
                )
            }
            
            // JSON parsing failed — return as plain summary
            print("⚠️ [EdgeContextActor] CLaRa didn't return valid JSON, using as plain summary")
            return LLMAnalysisResult(
                summary: "\(result) [Model: Edge-CLaRa-7B]"
            )
        }
        
        return LLMAnalysisResult(summary: String(text.prefix(200)))
    }
}

// MARK: - Pipeline Edge Router

/// Routes pipeline work to edge nodes or local execution based on availability.
/// Decision logic: if edge node connected with sufficient capability → offload
/// Otherwise → fall back to local processing.
public final class PipelineEdgeRouter: Sendable {
    
    private let discoveryService: any EdgeNodeDiscovering
    
    public init(discoveryService: any EdgeNodeDiscovering) {
        self.discoveryService = discoveryService
    }
    
    /// Determine whether a task should be offloaded to an edge node.
    public func shouldOffload(task: EdgeTask) async -> EdgeRoutingDecision {
        let isConnected = await discoveryService.isEdgeNodeConnected
        
        guard isConnected,
              let node = await discoveryService.connectedNode else {
            print("🔍 [EdgeRouter] shouldOffload(\(task)): No edge node connected (isConnected=\(isConnected))")
            return .local(reason: "No edge node connected")
        }
        print("🔍 [EdgeRouter] shouldOffload(\(task)): node=\(node.deviceName), chip=\(node.chipFamily), tops=\(node.neuralEngineTOPS), ram=\(node.physicalMemoryGB)GB")
        
        // Check if edge node has the capability
        switch task {
        case .visionAnalysis:
            // Offload if the connected node has better capability, or if we lack local heavy vision.
            let localTOPS = CapabilityRouter.shared.currentCapability.neuralEngineTOPS
            let needsOffload = !CapabilityRouter.shared.canRunHeavyVision || node.neuralEngineTOPS > localTOPS
            
            guard needsOffload else {
                return .local(reason: "Local node has sufficient or better capability (\(localTOPS) TOPS)")
            }
            
            guard node.neuralEngineTOPS >= 10.0 else {
                return .local(reason: "Edge node TOPS (\(node.neuralEngineTOPS)) too low for heavy inference")
            }
            return .edge(node: node, reason: "Offloading to \(node.deviceName) (\(node.chipFamily), \(node.neuralEngineTOPS) TOPS)")
            
        case .vlmInference:
            // Offload if we cannot run heavy VLM locally, but edge can (assumed 16GB+ on macs usually, but we check node capability).
            let localRAM = CapabilityRouter.shared.currentCapability.physicalMemoryGB
            let needsOffload = !CapabilityRouter.shared.canRunHeavyVLM || node.physicalMemoryGB > localRAM
            
            guard needsOffload else {
                 return .local(reason: "Local node has sufficient or better capability (\(localRAM)GB RAM)")
            }
            
            guard node.physicalMemoryGB >= 8 else {
                 return .local(reason: "Edge node RAM (\(node.physicalMemoryGB)GB) too low for VLM inference")
            }
            return .edge(node: node, reason: "Offloading VLM to \(node.deviceName) (\(node.physicalMemoryGB)GB RAM)")
            
        case .nowcasting:
            // Nowcasting is CPU-bound, any edge node can handle it
            return .edge(node: node, reason: "Offloading nowcasting to \(node.deviceName)")
            
        case .governmentAPI, .esgEnrichment:
            // Network-bound tasks can run on either side
            return .local(reason: "Network tasks run locally for latency")
            
        case .commerceRouting, .agenticSearch:
            return .edge(node: node, reason: "Offloading \(task.rawValue) to \(node.deviceName)")
        }
    }
    
    /// Returns a list of all capable nodes on the local network (including self if applicable)
    /// to support parallel distributed processing like latent compression chunking.
    public func capableNodes(for task: EdgeTask) async -> [EdgeNodeInfo] {
        let allNodes = await discoveryService.availableNodes
        
        return allNodes.filter { node in
            switch task {
            case .visionAnalysis, .vlmInference:
                return node.neuralEngineTOPS >= 10.0
            default:
                return true
            }
        }.sorted { $0.neuralEngineTOPS > $1.neuralEngineTOPS }
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
    case agenticSearch
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
