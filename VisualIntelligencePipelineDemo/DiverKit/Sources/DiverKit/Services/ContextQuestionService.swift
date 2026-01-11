//
//  ContextQuestionService.swift
//  DiverKit
//
//  Created by Antigravity on 01/08/26.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A service that uses on-device LLMs to generate summaries, questions, and purposes.
public final class ContextQuestionService: Sendable {
    
    public init() {}

    /// Generates precise definitive statements about the possible activity and an automated purpose based on enrichment data.
    /// - Parameter data: The enrichment data to process.
    /// - Returns: A tuple containing a concise summary, a list of potential activity statements, a determined purpose, and tags.
    public func processContext(from data: EnrichmentData) async throws -> (summary: String?, statements: [String], purpose: String?, tags: [String]) {
        // Retrieve weighted context from Knowledge Graph if available
        var knowledgeContext: [(text: String, weight: Double)] = []
        if let kgService = await Services.shared.knowledgeGraphService {
             // Use visual title and description as query to leverage full rich context
             let query = [data.title, data.descriptionText].compactMap { $0 }.joined(separator: "\n")
             if !query.isEmpty {
                 do {
                    knowledgeContext = try await kgService.retrieveRelevantContext(for: query)
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
        
        let contextParts = [
            data.title != nil ? "Title: \(data.title!)" : nil,
            !data.categories.isEmpty ? "Categories: \(data.categories.joined(separator: ", "))" : nil,
            data.location != nil ? "Location: \(data.location!)" : nil,
            data.descriptionText != nil ? "Description: \(data.descriptionText!)" : nil,
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
                 
                 await withTaskGroup(of: String?.self) { group in
                     for chunk in chunks {
                         group.addTask {
                             try? await self.summarizeChunk(chunk)
                         }
                     }
                     for await result in group {
                         if let s = result { summaries.append(s) }
                     }
                 }
                 
                 finalInput = "Condensed Context Summary:\n" + summaries.joined(separator: "\n---\n")
            }

            do {
                let instructions = """
                Analyze the provided context to determine the user's specific activity.
                
                PRIORITY ORDER FOR CONTEXT:
                1. **VISUALS** (Captured Text, Objects, Products) - THIS IS THE SOURCE OF TRUTH.
                2. **LOCATION** (Place Name) - Use only to ground the visual activity.
                
                CRITICAL INSTRUCTIONS:
                - If "Captured Text" or "Captured Objects" are present, your statements MUST contain them.
                - Do NOT generate generic location statements like "Visiting [Place]" if you have visual details.
                - Example: If text says "Latte" and location is "Starbucks", say "Drinking a Latte at Starbucks", NOT "Visiting Starbucks".
                - Example: If text shows code/debug logs, say "Debugging Code", even if location is "Home".
                
                Provide a structured analysis:
                1. A concise summary.
                2. 2 rich statements derived PRIMARILY from VISUAL details (What are they looking at?).
                3. 2 rich statements linking VISUALS to LOCATION (Where are they doing it?).
                4. A concise user intent.
                5. Two detailed tags.
                """
                
                let session = LanguageModelSession(instructions: instructions)
                
                let response = try await session.respond(
                    to: finalInput,
                    generating: ContextAnalysis.self,
                    options: GenerationOptions(sampling: .greedy)
                )
                
                let analysis = response.content
                // Merge distinct statements into a single prioritized list
                let combinedStatements = analysis.visualStatements + analysis.locationStatements
                return (analysis.summary, combinedStatements, analysis.purpose, analysis.tags)
                
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize(let errorContext) {
                print("⚠️ Context window exceeded even after chaining: \(errorContext)")
                return ("Context too long.", [], nil, [])
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
                let instructions = """
                Analyze the following text (which represents user activity logs or multiple session contexts) and provide a high-level, cohesive summary.
                Focus on:
                - Common themes or topics.
                - The user's progression or intent across the items.
                - Specific entities or projects mentioned.
                Keep it concise (2-3 sentences).
                """
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: text)
                return response.content
            } catch {
                print("⚠️ Summary generation failed: \(error)")
                return text.prefix(200) + "..."
            }
        }
        #endif
        return text.prefix(200) + "..."
    }
    
    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func summarizeChunk(_ text: String) async throws -> String {
        let instructions = "Summarize the following text segment, retaining key details about activities, objects, and specific content."
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: text)
        return response.content
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
    
    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    @Generable
    struct ContextAnalysis {
        @Guide(description: "A concise summary of the place context in 2 sentences.")
        var summary: String
        
        @Guide(description: "2 definitive statements based ONLY on visual evidence (e.g. 'Reading a menu').")
        var visualStatements: [String]
        
        @Guide(description: "2 definitive statements based ONLY on location evidence (e.g. 'Dining out').")
        var locationStatements: [String]
        
        @Guide(description: "The likely user intent or purpose (e.g., 'Researching Coffee Shop') for the place.")
        var purpose: String
        
        @Guide(description: "Two tags that describe the main topics of the place context.")
        var tags: [String]
    }
    #endif
    /// Generates potential purposes or intent labels based on session context.
    public func suggestPurposes(from sessionContext: String) async throws -> [String] {
        guard !sessionContext.isEmpty else { return [] }
        
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 19.0, *) {
            do {
                let instructions = """
                Analyze the provided session context (a collection of related items/activities) and suggest 3-5 specific, distinct "Purposes" or "Goals" that describe why the user collected these items.
                Examples: "Planning a Trip", "Researching Camera Gear", "Debugging SwiftUI", "Shopping for Gifts".
                Return ONLY the raw phrases, separated by newlines. Do not number them.
                """
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: sessionContext)
                
                let lines = response.content.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .filter { $0.count < 40 } // Sanity check length
                
                return Array(lines.prefix(5))
            } catch {
                print("⚠️ Purpose suggestion failed: \(error)")
                return []
            }
        }
        #endif
        return []
    }
}
