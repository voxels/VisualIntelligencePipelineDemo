//
//  DailyContextService.swift
//  DiverKit
//
//  Created by Antigravity on 01/11/26.
//

import Foundation
import SwiftUI
import DiverShared
import SwiftData

/// Generates a daily focus summary from the user's captured items using on-device LLM.
///
/// Architecture:
/// - `@Observable` (not ObservableObject) — modern SwiftUI observation.
/// - SwiftData fetches run on a **background** `ModelContext` to avoid main-thread blocking.
/// - Richer context extraction: title, location, summary, tags, FastVLM analysis,
///   web context, commerce products, transcription, media type, questions.
@MainActor
@Observable
public final class DailyContextService {
    public var dailySummary: String = "No activity yet in the last 24 hours."
    public var isGenerating: Bool = false
    
    private let contextService = ContextQuestionService()
    private let modelContainer: ModelContainer
    
    private let persistenceURL: URL = {
        do {
            return try AppGroupContainer.containerURL().appendingPathComponent("daily_context_state_v3.json")
        } catch {
            let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            return urls[0].appendingPathComponent("daily_context_state_v3.json")
        }
    }()
    
    private struct PersistedState: Codable {
        let summary: String
        let date: Date
    }
    
    private var lastSaveDate: Date?
    
    public init(container: ModelContainer) {
        self.modelContainer = container
        loadState()
    }
    
    /// True if we have a meaningful summary or recent items exist.
    public var hasContent: Bool {
        !dailySummary.contains("No activity") || checkRecentActivityExists()
    }
    
    /// Triggers a background re-generation of the daily summary.
    /// Called after pipeline saves or on app foreground.
    public func requestUpdate() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            // Brief delay for SwiftData persistence to flush
            try? await Task.sleep(for: .seconds(1))
            await self.updateSummary()
        }
    }
    
    // MARK: - Core Summary Pipeline
    
    /// Fetches recent items on a background context, extracts rich metadata,
    /// and generates a thematic summary via SLM.
    public func updateSummary() async {
        self.isGenerating = true
        defer { self.isGenerating = false }
        
        // Background ModelContext for SwiftData (per GEMINI.md rule #7)
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        
        // 1. Fetch last 24 hours of items
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let descriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.createdAt > cutoff },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        
        guard let items = try? context.fetch(descriptor), !items.isEmpty else {
            self.dailySummary = "No activity in the last 24 hours."
            saveState()
            return
        }
        
        // 2. Extract rich context per item
        let formattedContext = formatItemsContext(items)
        
        // 3. Generate summary
        if ContextQuestionService.isAvailable {
            do {
                let prompt = buildPrompt(formattedContext: formattedContext, itemCount: items.count)
                let summary = try await contextService.summarizeText(prompt)
                self.dailySummary = summary
                saveState()
            } catch {
                print("❌ Daily Summary Generation Failed: \(error)")
            }
        } else {
            // Heuristic fallback when SLM unavailable
            let count = items.count
            let locations = Set(items.compactMap { $0.location }).prefix(2).joined(separator: " and ")
            let types = Set(items.compactMap { $0.mediaType }).joined(separator: ", ")
            var fallback = "Captured \(count) items"
            if !locations.isEmpty { fallback += " at \(locations)" }
            if !types.isEmpty { fallback += " (\(types))" }
            fallback += " today."
            self.dailySummary = fallback
            saveState()
        }
    }
    
    /// Clears the daily context summary (does not delete items).
    public func clear() {
        dailySummary = "Start of a fresh day."
        saveState()
    }
    
    // MARK: - Rich Context Formatting
    
    private func formatItemsContext(_ items: [ProcessedItem]) -> String {
        let calendar = Calendar.current
        var lines: [String] = []
        
        for item in items {
            let date = item.createdAt
            let timeLabel = calendar.isDateInToday(date)
                ? "[Today \(date.formatted(date: .omitted, time: .shortened))]"
                : "[Yesterday \(date.formatted(date: .omitted, time: .shortened))]"
            
            var parts: [String] = []
            
            // Core identity
            parts.append("• \(item.title ?? "Untitled")")
            
            // Location
            if let loc = item.location {
                parts.append("  📍 \(loc)")
            }
            
            // Summary (LLM-generated)
            if let sum = item.summary, !sum.isEmpty {
                parts.append("  💡 \(sum)")
            }
            
            // FastVLM visual analysis
            if let vlm = item.fastVLMAnalysis, let desc = vlm.imageDescription, !desc.isEmpty {
                let truncated = String(desc.prefix(200))
                parts.append("  👁️ VLM: \(truncated)")
            }
            
            // Web context
            if let web = item.webContext {
                if let site = web.siteName, !site.isEmpty {
                    parts.append("  🔗 Web: \(site)")
                }
            }
            
            // Commerce / product
            if let commerce = item.commerceContext, let first = commerce.first {
                parts.append("  🛒 Product: \(first.option.productName)")
            }
            
            // Transcription (OCR text, first 150 chars)
            if let transcript = item.transcription, !transcript.isEmpty {
                let truncated = String(transcript.prefix(150))
                parts.append("  📝 Text: \(truncated)")
            }
            
            // Tags
            if !item.tags.isEmpty {
                parts.append("  🏷️ [\(item.tags.prefix(8).joined(separator: ", "))]")
            }
            
            // Media type
            if let media = item.mediaType {
                parts.append("  📷 Type: \(media)")
            }
            
            // Questions the pipeline generated
            if !item.questions.isEmpty {
                parts.append("  ❓ \(item.questions.prefix(2).joined(separator: "; "))")
            }
            
            lines.append("\(timeLabel)\n\(parts.joined(separator: "\n"))")
        }
        
        return lines.joined(separator: "\n\n")
    }
    
    private func buildPrompt(formattedContext: String, itemCount: Int) -> String {
        """
        You are a personal assistant summarizing a user's day based on their captured items.
        Create a 2-3 sentence thematic summary of their focus and activities.
        
        Guidelines:
        - Identify themes (e.g. "shopping", "research", "exploring", "documenting")
        - Mention specific locations or products if they recur
        - Note time-of-day patterns if visible (morning vs afternoon)
        - Be warm and insightful, not robotic
        - Prioritize the most recent items
        
        Current time: \(Date().formatted())
        Total items: \(itemCount)
        
        Activities (Last 24 Hours):
        \(formattedContext)
        
        Summary (2-3 SENTENCES):
        """
    }
    
    // MARK: - Helpers
    
    private func checkRecentActivityExists() -> Bool {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let descriptor = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.createdAt > cutoff })
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
    }
    
    private func saveState() {
        let state = PersistedState(summary: dailySummary, date: Date())
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: persistenceURL)
            NotificationCenter.default.post(name: Notification.Name("com.secretatomics.dailyContextUpdated"), object: nil)
        } catch {
            print("Failed to save daily context: \(error)")
        }
    }
    
    private func loadState() {
        do {
            let data = try Data(contentsOf: persistenceURL)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            self.dailySummary = state.summary
            self.lastSaveDate = state.date
        } catch {
            // No file or invalid state — start fresh
        }
    }
}
