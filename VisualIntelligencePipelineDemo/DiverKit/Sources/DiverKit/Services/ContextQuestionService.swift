//
//  ContextQuestionService.swift
//  DiverKit
//
//  Created by Antigravity on 01/08/26.
//

import Foundation
import DiverShared
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A service that uses on-device LLMs to generate summaries, questions, and purposes.
public final class ContextQuestionService: Sendable {
    
    public init() {}

    public static var isAvailable: Bool {
        // Enforce device restrictions (e.g. iPhone 16+) defined in Shared module
        guard IntelligenceCapability.isAvailable else { return false }
        
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 19.0, *) {
            return true
        }
        #endif
        return false
    }

    /// Generates precise definitive statements about the possible activity and an automated purpose based on enrichment data.
    /// - Parameters:
    ///   - data: The enrichment data to process.
    ///   - sessionID: Optional session ID to scope context retrieval. When provided, only uses context from the current session.
    /// - Returns: A tuple containing a concise summary, a list of potential activity statements, a determined purpose, and tags.
    public func processContext(from data: EnrichmentData, sessionID: String? = nil) async throws -> (summary: String?, statements: [String], purpose: String?, tags: [String]) {
        // Retrieve weighted context from Knowledge Graph if available
        var knowledgeContext: [(text: String, weight: Double)] = []
        if let kgService = await Services.shared.knowledgeGraphService {
             // Use visual title and description as query to leverage full rich context
             let query = [data.title, data.descriptionText].compactMap { $0 }.joined(separator: "\n")
             if !query.isEmpty {
                 do {
                    knowledgeContext = try await kgService.retrieveRelevantContext(for: query, sessionID: sessionID)
                 } catch {
                    // Ignore errors, continue without context
                 }
             }
        }
        
        // Sort context by weight descending
        let sortedContext = knowledgeContext.sorted { $0.weight > $1.weight }
        let contextStrings = sortedContext.map { entry -> String in
            if entry.weight > 1.2 {
                return "[High Priority] \(entry.text)"
            }
            return entry.text
        }
        
        // Build comprehensive context from all available sources
        let contextParts: [String?] = [
            // Core identification
            data.title != nil ? "Title: \(data.title!)" : nil,
            data.sourceURL != nil ? "Source URL: \(data.sourceURL!)" : nil,
            data.productContext != nil ? "Product Info: \(data.productContext!)" : nil,
            data.visualContext != nil ? "Visual Analysis: \(data.visualContext!)" : nil,
            data.descriptionText != nil ? "Description: \(data.descriptionText!)" : nil,
            
            // Categories and tags
            !data.categories.isEmpty ? "Categories: \(data.categories.joined(separator: ", "))" : nil,
            !data.styleTags.isEmpty ? "Style/Themes: \(data.styleTags.joined(separator: ", "))" : nil,
            
            // Web context (extracted page content)
            data.webContext?.siteName != nil ? "Website: \(data.webContext!.siteName!)" : nil,
            data.webContext?.textContent != nil ? "Page Content: \(String(data.webContext!.textContent!.prefix(500)))" : nil,
            data.webContext?.structuredData != nil ? "Structured Data: \(data.webContext!.structuredData!)" : nil,
            
            // Place context (venue details)
            data.placeContext?.name != nil ? "Place: \(data.placeContext!.name!)" : nil,
            data.placeContext?.address != nil ? "Address: \(data.placeContext!.address!)" : nil,
            !((data.placeContext?.categories ?? []).isEmpty) ? "Venue Type: \((data.placeContext?.categories ?? []).joined(separator: ", "))" : nil,
            data.placeContext?.rating != nil ? "Rating: \(data.placeContext!.rating!)/10" : nil,
            data.placeContext?.priceLevel != nil ? "Price Level: \(data.placeContext!.priceLevel!)" : nil,
            !((data.placeContext?.tips ?? []).isEmpty) ? "Tips: \((data.placeContext?.tips ?? []).prefix(3).joined(separator: "; "))" : nil,
            
            // Environmental context (weather and activity - optional)
            data.weatherContext != nil ? "Weather: \(data.weatherContext!.condition), \(Int(data.weatherContext!.temperatureCelsius))°C" : nil,
            data.activityContext != nil ? "Activity: \(data.activityContext!.type) (\(data.activityContext!.confidence) confidence)" : nil,
            
            // Pricing and ratings (standalone)
            data.price != nil ? "Price: $\(String(format: "%.2f", data.price!))" : nil,
            data.rating != nil ? "Rating: \(data.rating!)" : nil,
            
            // Location (for grounding)
            data.location != nil ? "Location: \(data.location!)" : nil,
            
            // Document context
            data.documentContext != nil ? "Document: \(data.documentContext!.fileType)\(data.documentContext!.pageCount != nil ? ", \(data.documentContext!.pageCount!) pages" : "")" : nil,
            
            // QR context
            data.qrContext != nil ? "QR Code: \(data.qrContext!.payload)" : nil,
            
            // Session Context (sibling items)
            data.sessionContext != nil ? "Session Context (Nearby Captures): \(data.sessionContext!)" : nil,
            
            // User history/knowledge graph
            !contextStrings.isEmpty ? "User Context/History: \(contextStrings.joined(separator: "\n"))" : nil
        ]
        
        let contextString = contextParts.compactMap { $0 }.joined(separator: "\n")
        
        guard !contextString.isEmpty else {
            return (nil, [], nil, [])
        }
        
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 19.0, *) {
            var finalInput = contextString
            
            // CHAINING: If context is too large, buffer and chain summaries
            if contextString.count > 3500 {
                 let chunks = chunkText(contextString, size: 3000, overlap: 200)
                 var summaries: [String] = []
                 
                 // Process chunks serially on MainActor to avoid threading issues
                 for chunk in chunks {
                     if let summary = try? await runChunkSummary(sanitizeForLLM(chunk)) {
                         summaries.append(summary)
                     }
                 }
                 
                 finalInput = "Condensed Context Summary:\n" + summaries.joined(separator: "\n---\n")
            }

            do {
                let result = try await runContextAnalysis(input: sanitizeForLLM(finalInput))
                return result
                
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize(let errorContext) {
                print("⚠️ Context window exceeded even after chaining: \(errorContext)")
                return ("Context too long.", [], nil, [])
            } catch let error as LanguageModelSession.GenerationError {
                print("⚠️ GenAI GenerationError (falling back): \(error)")
                return (data.descriptionText, [], nil, [])
            } catch {
                print("⚠️ GenAI error (falling back to basic context): \(error)")
                // Fallback: return basic context without AI insights
                return (data.descriptionText, [], nil, [])
            }
        }
        #endif
        
        print("⚠️ SystemLanguageModel unavailable (requires iOS 26.0+). Returning empty result.")
        return (data.descriptionText, [], nil, [])
    }
    
    /// Generates a high-level summary from a block of text (e.g. session logs).
    public func summarizeText(_ text: String) async throws -> String {
        guard !text.isEmpty else { return "" }
        
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 19.0, *) {
            do {
                let result = try await runTextSummary(text: sanitizeForLLM(text))
                return result
            } catch let error as LanguageModelSession.GenerationError {
                print("⚠️ Summary GenerationError: \(error)")
                 return String(text.prefix(200)) + "..."
            } catch {
                print("⚠️ Summary generation failed: \(error)")
                return String(text.prefix(200)) + "..."
            }
        }
        #endif
        return String(text.prefix(200)) + "..."
    }
    
    // MARK: - MainActor LLM Helpers
    // These must run on MainActor to satisfy FoundationModels threading requirements
    
    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @MainActor
    private func runContextAnalysis(input: String) async throws -> (summary: String?, statements: [String], purpose: String?, tags: [String]) {
        let instructions = """
        Analyze the provided context to determine the user's specific activity and intent.
        
        PRIORITY ORDER FOR CONTEXT (use all available, prioritized):
        1. **VISUALS** (Captured Text, Objects, Products) - Primary source of truth
        2. **WEB CONTENT** (Page Content, Structured Data) - Secondary source
        3. **PLACE DETAILS** (Venue name, tips, categories) - Contextual grounding
        4. **ENVIRONMENT** (Weather, Activity type if present)
        5. **LOCATION** (Address, coordinates) - Only for grounding
        
        CRITICAL INSTRUCTIONS:
        - Derive statements from the MOST SPECIFIC data available.
        - If web content or captured text exists, statements MUST reference it.
        - Do NOT generate vague statements like "Browsing the web" or "Visiting a place".
        - Be specific: "Reading an article about camera lenses" not "Reading online".
        - Be specific: "Ordering a latte at a coffee shop" not "At a coffee shop".
        
        Provide a structured analysis:
        1. A concise 2-sentence summary of what the user is doing.
        2. 2 statements derived from the PRIMARY evidence (visuals, web content, or captured text).
        3. 2 statements that add environmental/location context.
        4. A concise user intent or goal.
        5. Two specific, descriptive tags.
        """
        
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: truncate(input, limit: 12000),
            generating: ContextAnalysis.self,
            options: GenerationOptions(sampling: .greedy)
        )
        
        let analysis = response.content
        let combinedStatements = analysis.visualStatements + analysis.locationStatements
        return (analysis.summary, combinedStatements, analysis.purpose, analysis.tags)
    }
    
    @available(iOS 26.0, macOS 26.0, *)
    @MainActor
    private func runTextSummary(text: String) async throws -> String {
        let instructions = """
        Analyze the following text (which represents user activity logs or multiple session contexts) and provide a high-level, cohesive summary.
        
        CRITICAL INSTRUCTIONS:
        - If no location is mentioned, do NOT invent one. Focus on the activity (e.g. "Researching cameras", "Browsing web").
        
        Focus on:
        - Common themes or topics.
        - The user's progression or intent across the items.
        - Specific entities or projects mentioned.
        Keep it concise (2-3 sentences).
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: await smartSummarize(text))
        
        // DATA SANITIZATION: Aggressively remove hallucinated "Home" references
        let cleanSummary = response.content
            .replacingOccurrences(of: "at home", with: "", options: [String.CompareOptions.caseInsensitive, String.CompareOptions.regularExpression])
            .replacingOccurrences(of: "from home", with: "", options: [String.CompareOptions.caseInsensitive, String.CompareOptions.regularExpression])
            .replacingOccurrences(of: "in their home", with: "", options: [String.CompareOptions.caseInsensitive, String.CompareOptions.regularExpression])
            .replacingOccurrences(of: " at . ", with: ". ", options: String.CompareOptions.regularExpression)
        
        return cleanSummary
    }
    
    @available(iOS 26.0, macOS 26.0, *)
    @MainActor
    private func runChunkSummary(_ text: String) async throws -> String {
        let instructions = "Summarize the following text segment, retaining key details about activities, objects, and specific content."
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: text)
        return response.content
    }
    
    @available(iOS 26.0, macOS 26.0, *)
    @MainActor
    private func runPurposeSuggestion(context: String) async throws -> [String] {
        let instructions = """
        Analyze the provided session context (a collection of related items/activities) and suggest 3-5 specific, distinct "Purposes" or "Goals" that describe why the user collected these items.
        Examples: "Planning a Trip", "Researching Camera Gear", "Debugging SwiftUI", "Shopping for Gifts".
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: await smartSummarize(context),
            generating: PurposeSuggestions.self,
            options: GenerationOptions(sampling: .greedy)
        )
        
        return response.content.purposes
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    #endif

    private func chunkText(_ text: String, size: Int, overlap: Int) -> [String] {
        var chunks: [String] = []
        if text.isEmpty { return [] }
        
        var startIndex = text.startIndex
        while startIndex < text.endIndex {
            let endIndex = text.index(startIndex, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = String(text[startIndex..<endIndex])
            chunks.append(chunk)
            
            if endIndex == text.endIndex { break }
            startIndex = text.index(startIndex, offsetBy: size - overlap, limitedBy: text.endIndex) ?? text.endIndex
        }
        return chunks
    }
    
    private func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit))
    }
    
    /// intelligently reduces text size by summarizing chunks if too large
    private func smartSummarize(_ text: String) async -> String {
        let limit = 12000
        if text.count <= limit { return text }
        
        // Split into chunks and summarize each
        let chunks = chunkText(text, size: 4000, overlap: 200)
        var summaries: [String] = []
        
        for chunk in chunks {
            // We use a simplified summarizer here to avoid recursion hell
            // Just truncate the chunk if it's somehow massive, but it won't be (4000 chars)
             #if canImport(FoundationModels)
             if #available(iOS 26.0, macOS 26.0, *) {
                 if let summary = try? await runChunkSummary(chunk) {
                     summaries.append(summary)
                 } else {
                     summaries.append(String(chunk.prefix(500)) + "...")
                 }
             } else {
                 summaries.append(String(chunk.prefix(500)) + "...")
             }
             #else
             summaries.append(String(chunk.prefix(500)) + "...")
             #endif
        }
        
        return summaries.joined(separator: "\n")
    }

    /// Sanitizes input text for the on-device LLM to prevent `unsupportedLanguageOrLocale` errors.
    /// Strips non-ASCII characters and normalizes to US English compatible text.
    private func sanitizeForLLM(_ text: String) -> String {
        // Transliterate accented characters to ASCII equivalents (é -> e, ñ -> n, etc.)
        let mutableString = NSMutableString(string: text)
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableString, nil, kCFStringTransformStripCombiningMarks, false)
        
        // Keep only printable ASCII characters (space through tilde), newlines, and tabs
        let sanitized = (mutableString as String).unicodeScalars.filter { scalar in
            (scalar.value >= 32 && scalar.value <= 126) || scalar == "\n" || scalar == "\t"
        }
        return String(String.UnicodeScalarView(sanitized))
    }
    
    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct ContextAnalysis {
        @Guide(description: "A concise 2-sentence summary of the captured context and user activity.")
        var summary: String
        
        @Guide(description: "2 definitive statements based on PRIMARY evidence (captured text, web content, or visuals).")
        var visualStatements: [String]
        
        @Guide(description: "2 definitive statements adding environmental or location context.")
        var locationStatements: [String]
        
        @Guide(description: "The likely user intent or goal (e.g., 'Researching camera gear', 'Planning a trip').")
        var purpose: String
        
        @Guide(description: "Two specific, descriptive tags for the captured context.")
        var tags: [String]
    }
    #endif
    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct PurposeSuggestions {
        @Guide(description: "3-5 suggested purposes for the collection of items. Short phrases like 'Planning a Trip'.")
        var purposes: [String]
    }
    #endif

    /// Generates potential purposes or intent labels based on session context.
    public func suggestPurposes(from sessionContext: String) async throws -> [String] {
        guard !sessionContext.isEmpty else { return [] }
        
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 19.0, *) {
            do {
                print("🔍 ContextQuestionService: Suggesting purposes for context (\(sessionContext.count) chars)")
                let suggestions = try await runPurposeSuggestion(context: sanitizeForLLM(sessionContext))
                print("✅ ContextQuestionService: Generated \(suggestions.count) purposes: \(suggestions.joined(separator: ", "))")
                return Array(suggestions.prefix(5))
            } catch {
                print("❌ ContextQuestionService: Purpose suggestion failed: \(error)")
                return []
            }
        }
        #endif
        return []
    }
}
