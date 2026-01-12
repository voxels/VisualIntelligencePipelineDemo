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
    
    public var hasContent: Bool {
        !contexts.isEmpty
    }

    public func ingest(_ items: [String]) {
        guard !items.isEmpty else { return }
        
        let now = Date()
        let newEntries = items.map { ContextEntry(text: $0, date: now) }
        contexts.append(contentsOf: newEntries)
        
        cleanOldEntries()
        saveState()
        
        Task {
            await updateSummary()
        }
    }
    
    /// Adds a new context entry (e.g. from a captured session) and updates the daily summary.
    public func addContext(_ text: String) {
        guard !text.isEmpty else { return }
        
        let now = Date()
        contexts.append(ContextEntry(text: text, date: now))
        
        cleanOldEntries()
        saveState()
        
        Task {
            await updateSummary()
        }
    }
    
    private func cleanOldEntries() {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        contexts.removeAll { $0.date < cutoff }
    }
    
    /// Forces a re-generation of the daily summary based on accumulated context.
    public func updateSummary() async {
        cleanOldEntries()
        
        guard !contexts.isEmpty else { 
            self.dailySummary = "No activity in the last 24 hours."
            return 
        }
        
        self.isGenerating = true
        defer { self.isGenerating = false }
        
        let sorted = contexts.sorted(by: { $0.date < $1.date })
        
        var formattedContext = ""
        let calendar = Calendar.current
        
        for entry in sorted {
            let prefix = calendar.isDateInToday(entry.date) ? "[Today \(entry.date.formatted(date: .omitted, time: .shortened))]" : "[Yesterday \(entry.date.formatted(date: .omitted, time: .shortened))]"
            formattedContext += "\(prefix) \(entry.text)\n\n"
        }
        
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
            self.dailySummary = summary
            self.saveState()
        } catch {
            print("❌ Daily Summary Generation Failed: \(error)")
        }
    }
    
    /// Clears the daily context
    public func clear() {
        contexts.removeAll()
        dailySummary = "Start of a fresh day."
        saveState()
    }
    
    private func saveState() {
        let now = Date()
        self.lastSaveDate = now
        let state = PersistedState(entries: contexts, summary: dailySummary, date: now)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: persistenceURL)
            // Post notification for app to reload widgets
            NotificationCenter.default.post(name: Notification.Name("com.secretatomics.dailyContextUpdated"), object: nil)
        } catch {
            print("Failed to save daily context: \(error)")
        }
    }
    
    private func loadState() {
        do {
            let data = try Data(contentsOf: persistenceURL)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            
            self.contexts = state.entries
            self.dailySummary = state.summary
            self.lastSaveDate = state.date
            
            cleanOldEntries()
        } catch {
            // No file or invalid, ignore
        }
    }
}
