import Foundation
import DiverShared

/// Structured context collected during pipeline enrichment.
/// Replaces the legacy `accumulatedContext` string blob with typed fields.
/// Each enrichment stage populates its own field; downstream consumers
/// (FastVLM, SystemLanguageModel) read structured data instead of parsing text.
public struct PipelineContext: Sendable, Codable {
    
    /// A weighted context entry from the Know Maps knowledge graph (vector space)
    public struct WeightedEntry: Sendable, Codable, Equatable {
        public let text: String
        public let weight: Double
        
        public init(text: String, weight: Double) {
            self.text = text
            self.weight = weight
        }
    }
    
    // MARK: - Vision Framework Output
    
    /// OCR-detected text from the image
    public var ocrText: String?
    /// Classification labels from Vision framework
    public var visualTags: [String] = []
    /// Identified media (Shazam, etc.)
    public var identifiedMedia: String?
    /// Document content from document detection
    public var documentContent: String?
    /// QR code payloads detected
    public var qrPayloads: [String] = []
    /// Visual analysis log (classification labels, object detection, etc.)
    public var visualAnalysisLog: String?
    
    // MARK: - Enrichment Services Output
    
    /// Link/web enrichment data
    public var linkEnrichment: EnrichmentData?
    /// Foursquare/MapKit place enrichment
    public var placeEnrichment: EnrichmentData?
    /// DuckDuckGo search enrichment
    public var duckDuckGoEnrichment: EnrichmentData?
    /// Weather context
    public var weatherContext: WeatherContext?
    /// Activity context
    public var activityContext: ActivityContext?
    /// Live event context
    public var liveEventContext: String?
    /// Cover image path
    public var coverImagePath: String?
    /// Product concepts detected
    public var productConcepts: [String] = []
    
    // MARK: - FastVLM Analysis
    
    /// Structured analysis from FastVLM
    public var fastVLMAnalysis: FastVLMAnalysis?
    
    // MARK: - Knowledge Graph (Weighted Concepts from Know Maps)
    
    /// Weighted context entries from Know Maps vector space
    public var knowledgeGraphContext: [WeightedEntry] = []
    
    
    // MARK: - Context Output
    
    /// Serialize all context into a flat string for SystemLanguageModel fallback
    /// or for passing to FastVLM's text analysis as enrichment context.
    public var asContextString: String {
        var parts: [String] = []
        
        // Vision
        if let ocrText, !ocrText.isEmpty {
            parts.append("Detected Text: \(ocrText)")
        }
        if !visualTags.isEmpty {
            parts.append("Visual Tags: \(visualTags.joined(separator: ", "))")
        }
        if let identifiedMedia, !identifiedMedia.isEmpty {
            parts.append("Identified Media: \(identifiedMedia)")
        }
        if let documentContent, !documentContent.isEmpty {
            parts.append("Document Content: \(documentContent)")
        }
        for qr in qrPayloads {
            parts.append("QR Code: \(qr)")
        }
        if let visualAnalysisLog, !visualAnalysisLog.isEmpty {
            parts.append("Visual Analysis: \(visualAnalysisLog)")
        }
        
        // Enrichment
        if let link = linkEnrichment {
            if let title = link.title { parts.append("Link Title: \(title)") }
            if let desc = link.descriptionText { parts.append("Link Summary: \(desc)") }
        }
        if let place = placeEnrichment {
            let name = place.title ?? "Unknown"
            let cats = place.categories.joined(separator: ", ")
            parts.append("Place: \(name) - \(cats)")
        }
        if let ddg = duckDuckGoEnrichment {
            let title = ddg.title ?? "Unknown"
            let desc = ddg.descriptionText ?? ""
            parts.append("DuckDuckGo: \(title) - \(desc)")
        }
        if let weather = weatherContext {
            parts.append("Weather: \(weather.condition), \(Int(weather.temperatureCelsius))°C")
        }
        if let activity = activityContext {
            parts.append("Activity: \(activity.type) (\(activity.confidence))")
        }
        if let events = liveEventContext, !events.isEmpty {
            parts.append("Live Events: \(events)")
        }
        
        // FastVLM
        if let vlm = fastVLMAnalysis {
            if let desc = vlm.imageDescription {
                parts.append("FastVLM Vision: \(desc)")
            }
            if let summary = vlm.contextSummary {
                parts.append("FastVLM Analysis: \(summary)")
            }
        }
        
        // Knowledge Graph (RAG — weighted concepts from Know Maps vector space)
        if !knowledgeGraphContext.isEmpty {
            let sorted = knowledgeGraphContext.sorted { $0.weight > $1.weight }
            let entries = sorted.map { entry in
                entry.weight > 1.2 ? "[High Priority] \(entry.text)" : entry.text
            }
            parts.append("User Context/History:\n\(entries.joined(separator: "\n"))")
        }
        
        return parts.joined(separator: "\n")
    }
    
    /// Enrichment-only context string (no vision data — for FastVLM to receive enrichment context)
    /// Fields are ordered by signal value: highest-priority first so truncation loses the least important data.
    public var enrichmentContextString: String {
        var parts: [String] = []
        
        // 1. OCR text — primary direct evidence from the image
        if let ocrText, !ocrText.isEmpty {
            parts.append("Detected Text: \(String(ocrText.prefix(1500)))")
        }
        
        // 2. Link metadata — high signal when available
        if let link = linkEnrichment {
            if let title = link.title { parts.append("Link Title: \(title)") }
            if let desc = link.descriptionText { parts.append("Link Summary: \(String(desc.prefix(500)))") }
        }
        
        // 3. Place / location — strong contextual anchor
        if let place = placeEnrichment {
            let name = place.title ?? "Unknown"
            let cats = place.categories.joined(separator: ", ")
            let address = place.location ?? ""
            parts.append("Place: \(name) - \(cats)")
            if !address.isEmpty { parts.append("Address: \(address)") }
        }
        
        // 4. Visual tags — compact, high density
        if !visualTags.isEmpty {
            parts.append("Visual Tags: \(visualTags.joined(separator: ", "))")
        }
        
        // 5. Web search enrichment
        if let ddg = duckDuckGoEnrichment {
            parts.append("DuckDuckGo: \(ddg.title ?? "Unknown") - \(String((ddg.descriptionText ?? "").prefix(400)))")
        }
        
        // 6. Environmental context (compact)
        if let weather = weatherContext {
            parts.append("Weather: \(weather.condition), \(Int(weather.temperatureCelsius))°C")
        }
        if let activity = activityContext {
            parts.append("Activity: \(activity.type) (\(activity.confidence))")
        }
        if let events = liveEventContext, !events.isEmpty {
            parts.append("Live Events: \(String(events.prefix(300)))")
        }
        
        // 7. Visual analysis log — verbose, cap it
        if let visualAnalysisLog, !visualAnalysisLog.isEmpty {
            parts.append("Visual Analysis: \(String(visualAnalysisLog.prefix(800)))")
        }
        
        // 8. Knowledge Graph (RAG) — can be large, cap total
        if !knowledgeGraphContext.isEmpty {
            let sorted = knowledgeGraphContext.sorted { $0.weight > $1.weight }
            let entries = sorted.map { entry in
                entry.weight > 1.2 ? "[High Priority] \(entry.text)" : entry.text
            }
            let joined = entries.joined(separator: "\n")
            parts.append("User Context/History:\n\(String(joined.prefix(600)))")
        }
        
        return parts.joined(separator: "\n")
    }
    
    public init() {}
}
