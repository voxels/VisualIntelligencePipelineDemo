//
//  DailyContextService.swift
//  DiverKit
//
//  Created by Antigravity on 01/11/26.
//

import Foundation
import Combine
import SwiftUI
import DiverShared
import SwiftData

/// A service that tracks the user's daily context and generates a running summary using LLM.
@MainActor
public class DailyContextService: ObservableObject {
    @Published public var dailySummary: String = "No activity yet in the last 24 hours."
    @Published public var isGenerating: Bool = false
    
    struct ContextEntry: Codable {
        let text: String
        let date: Date
    }

    private var contexts: [ContextEntry] = []
    private let contextService = ContextQuestionService()
    
    private let persistenceURL: URL = {
        do {
            return try AppGroupContainer.containerURL().appendingPathComponent("daily_context_state_v2.json")
        } catch {
            // Fallback for previews/tests
            let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            return urls[0].appendingPathComponent("daily_context_state_v2.json")
        }
    }()
    
    struct PersistedState: Codable {
        let entries: [ContextEntry]
        let summary: String
        let date: Date
    }
    
    private var lastSaveDate: Date?

    public init() {
        loadState()
    }
    

    
    // Derived property, true if we have a summary or if there are items in the DB
    public var hasContent: Bool {
        return !dailySummary.contains("No activity") || checkRecentActivityExists()
    }

    // Deprecated: No longer stores text. Just triggers update.
    public func ingest(_ items: [String]) {
        Task {
            // Wait a moment for DB persistence
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            await updateSummary()
        }
    }
    
    // Deprecated: No longer stores text. Just triggers update.
    public func addContext(_ text: String) {
        Task {
            // Wait a moment for DB persistence
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            await updateSummary()
        }
    }
    
    private func checkRecentActivityExists() -> Bool {
        // Quick check without full fetch
        guard let context = Services.shared.modelContext else { return false }
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let descriptor = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.createdAt > cutoff })
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count > 0
    }
    
    /// Forces a re-generation of the daily summary based on Live SwiftData.
    public func updateSummary() async {
        guard let context = Services.shared.modelContext else {
            print("⚠️ DailyContextService: No ModelContext available.")
            return
        }
        
        self.isGenerating = true
        defer { self.isGenerating = false }
        
        // 1. Fetch Recent Items (Live Data)
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
        
        // 2. Format Context from Live Items
        var formattedContext = ""
        let calendar = Calendar.current
        
        for item in items {
            let date = item.createdAt
            let prefix = calendar.isDateInToday(date) ? "[Today \(date.formatted(date: .omitted, time: .shortened))]" : "[Yesterday \(date.formatted(date: .omitted, time: .shortened))]"
            
            // Richer Context Construction
            var details = "Item: \(item.title ?? "Untitled")"
            if let loc = item.location { details += " @ \(loc)" }
            if let sum = item.summary { details += " - \(sum)" }
            if !item.tags.isEmpty { details += " [\(item.tags.joined(separator: ", "))]" }
            
            formattedContext += "\(prefix) \(details)\n\n"
        }
        
        // 3. Generate Summary via LLM
        do {
            let prompt = """
            Create a concise, one-sentence summary of the user's focus over the last 24 hours based on these activities. 
            Prioritize the most recent items (the ones at the end of the list).
            If no activities are listed, say "No recent activity."
            
            Current time: \(Date().formatted())
            Activities (Last 24 Hours):
            \(formattedContext)
            
            Summary (ONE SENTENCE):
            """
            
            let summary = try await contextService.summarizeText(prompt)
            
            await MainActor.run {
                self.dailySummary = summary
                self.saveState()
            }
            
        } catch {
            print("❌ Daily Summary Generation Failed: \(error)")
        }
    }
    
    /// Clears the daily context summary (Does not delete actual items)
    public func clear() {
        dailySummary = "Start of a fresh day."
        saveState()
    }
    
    private func saveState() {
        let now = Date()
        self.lastSaveDate = now
        // We now only persist the SUMMARY, not the source entries (which live in DB)
        let state = PersistedState(entries: [], summary: dailySummary, date: now)
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
            // No file or invalid, ignore
        }
    }
}
