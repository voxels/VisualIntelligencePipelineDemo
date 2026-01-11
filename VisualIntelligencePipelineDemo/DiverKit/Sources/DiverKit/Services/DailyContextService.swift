//
//  DailyContextService.swift
//  DiverKit
//
//  Created by Antigravity on 01/11/26.
//

import Foundation
import Combine
import SwiftUI

/// A service that tracks the user's daily context and generates a running summary using LLM.
@MainActor
public class DailyContextService: ObservableObject {
    @Published public var dailySummary: String = "No activity yet today."
    @Published public var isGenerating: Bool = false
    
    private var todaysContexts: [String] = []
    private let contextService = ContextQuestionService()
    
    private let persistenceURL: URL = {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("daily_context_state.json")
    }()
    
    struct PersistedState: Codable {
        let contexts: [String]
        let summary: String
        let date: Date
    }
    
    public init() {
        loadState()
    }
    
    /// Adds a new context entry (e.g. from a captured session) and updates the daily summary.
    public func addContext(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Append with timestamp to keep chronological order meaningful
        let timestamp = Date().formatted(date: .omitted, time: .shortened)
        let entry = "[\(timestamp)] \(text)"
        todaysContexts.append(entry)
        
        saveState()
        
        Task {
            await updateSummary()
        }
    }
    
    /// Forces a re-generation of the daily summary based on accumulated context.
    public func updateSummary() async {
        guard !todaysContexts.isEmpty else { 
            print("⚠️ logic skipped: todaysContexts is empty")
            return 
        }
        
        self.isGenerating = true
        defer { self.isGenerating = false }
        
        let fullContext = todaysContexts.joined(separator: "\n\n")
        
        do {
            // We prepend a specific instruction for "Daily Summary" nature
            let prompt = """
            Here are chronological logs of the user's activity today:
            
            \(fullContext)
            
            Generate a concise, evolving summary of the user's day so far. 
            Focus on the narrative arc of their activities. 
            Keep it under 3 sentences. 
            Write it as if you are a personal assistant briefing them on their day's progress.
            """
            
            let summary = try await contextService.summarizeText(prompt)
            self.dailySummary = summary
            self.saveState()
        } catch {
            print("❌ Daily Summary Generation Failed: \(error)")
        }
    }
    
    /// Clears the daily context (e.g. at start of new day)
    public func clear() {
        todaysContexts.removeAll()
        dailySummary = "Start of a fresh day."
        saveState()
    }
    
    private func saveState() {
        let state = PersistedState(contexts: todaysContexts, summary: dailySummary, date: Date())
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: persistenceURL)
        } catch {
            print("Failed to save daily context: \(error)")
        }
    }
    
    private func loadState() {
        do {
            let data = try Data(contentsOf: persistenceURL)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            
            // Check if it's still "today"
            let calendar = Calendar.current
            if calendar.isDateInToday(state.date) {
                self.todaysContexts = state.contexts
                self.dailySummary = state.summary
            } else {
                clear() // New day, clear file
            }
        } catch {
            // No file or invalid, ignore
        }
    }
}
