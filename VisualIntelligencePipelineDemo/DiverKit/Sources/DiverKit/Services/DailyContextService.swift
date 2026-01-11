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
    
    public init() {}
    
    /// Adds a new context entry (e.g. from a captured session) and updates the daily summary.
    public func addContext(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Append with timestamp to keep chronological order meaningful
        let timestamp = Date().formatted(date: .omitted, time: .shortened)
        let entry = "[\(timestamp)] \(text)"
        todaysContexts.append(entry)
        
        Task {
            await updateSummary()
        }
    }
    
    /// Forces a re-generation of the daily summary based on accumulated context.
    public func updateSummary() async {
        guard !todaysContexts.isEmpty else { return }
        
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
        } catch {
            print("❌ Daily Summary Generation Failed: \(error)")
        }
    }
    
    /// Clears the daily context (e.g. at start of new day)
    public func clear() {
        todaysContexts.removeAll()
        dailySummary = "Start of a fresh day."
    }
}
