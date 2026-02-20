//
//  AgenticChatViewModel.swift
//  DiverKit
//
//  Manages the state for the CLaRa-powered Agentic Search chat interface.
//

import Foundation
import DiverShared

/// Represents a single message in the Agentic Search chat interface.
public struct AgenticChatMessage: Identifiable, Equatable {
    public let id: UUID
    public let isUser: Bool
    public let text: String
    public let citedDocumentIDs: [String]
    public let timestamp: Date
    
    public init(id: UUID = UUID(), isUser: Bool, text: String, citedDocumentIDs: [String] = [], timestamp: Date = Date()) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.citedDocumentIDs = citedDocumentIDs
        self.timestamp = timestamp
    }
}

/// View model to drive the `AgenticChatView`.
@MainActor
public final class AgenticChatViewModel: ObservableObject {
    
    @Published public var messages: [AgenticChatMessage] = []
    @Published public var inputText: String = ""
    @Published public var isThinking: Bool = false
    @Published public var errorMessage: String? = nil
    
    private let searchService: any AgenticSearching
    
    public init(searchService: any AgenticSearching) {
        self.searchService = searchService
        
        // Initial greeting
        messages.append(AgenticChatMessage(
            isUser: false,
            text: "Hi! I'm CLaRa, your personal library assistant. I can search through your context and answer questions about your saved items. What are you looking for?"
        ))
    }
    
    public func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        let userMessage = AgenticChatMessage(isUser: true, text: trimmedText)
        messages.append(userMessage)
        inputText = ""
        isThinking = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await searchService.performSearch(query: trimmedText, topK: 5)
                await MainActor.run {
                    self.messages.append(AgenticChatMessage(
                        isUser: false,
                        text: result.generatedAnswer,
                        citedDocumentIDs: result.citedDocumentIDs
                    ))
                    self.isThinking = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to connect to EdgeDaemon: \(error.localizedDescription)"
                    self.messages.append(AgenticChatMessage(
                        isUser: false,
                        text: "Sorry, I couldn't reach the edge node to process your request."
                    ))
                    self.isThinking = false
                }
            }
        }
    }
}
