//
//  FoundationModelsIntentClassifier.swift
//  DiverKit
//
//  Created by Claude on 12/24/25.
//

import Foundation
import NaturalLanguage

@available(iOS 14.0, macOS 11.0, *)
public class FoundationModelsIntentClassifier {
    
    public enum Intent: String, Sendable {
        case search
        case save
        case interaction
        case unknown
    }
    
    // Singleton for easy access, though instance usage is preferred
    @MainActor public static let shared = FoundationModelsIntentClassifier()
    
    private let tagger: NLTagger
    
    public init() {
        self.tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
    }
    
    /// Classifies the intent of the given input text using Natural Language analysis.
    public func classify(text: String) -> Intent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }
        
        // 1. Check for URL - strong signal for .save
        if isValidURL(trimmed) {
            return .save
        }
        
        // 2. Natural Language Analysis
        tagger.string = trimmed
        
        var foundVerb: String?
        var foundNoun: String?
        var isQuestion = false
        
        tagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            if let tag = tag {
                let word = String(trimmed[range]).lowercased()
                
                if tag == .verb {
                    foundVerb = word
                } else if tag == .noun {
                    foundNoun = word
                } else if tag == .pronoun || tag == .adverb {
                    if ["who", "what", "where", "when", "how", "why"].contains(word) {
                        isQuestion = true
                    }
                }
            }
            return true
        }
        
        // 3. Heuristic Rules based on Analysis
        
        if isQuestion {
            return .search
        }
        
        if let verb = foundVerb {
            // Check verb semantics/embeddings could be here.
            // For now, strict mapping.
            let saveVerbs = ["save", "keep", "store", "bookmark", "remember"]
            let searchVerbs = ["find", "search", "lookup", "google", "show"]
            let interactVerbs = ["buy", "shop", "order", "book", "reserve"]
            
            if saveVerbs.contains(verb) { return .save }
            if searchVerbs.contains(verb) { return .search }
            if interactVerbs.contains(verb) { return .interaction }
        }
        
        // Default fallbacks
        if trimmed.count > 50 {
            // likely a description or note -> save
            return .save
        }
        
        // Short text, noun heavy -> likely a search query
        return .search
    }
    
    private func isValidURL(_ text: String) -> Bool {
        // Quick check
        if let url = URL(string: text), url.scheme != nil && url.host != nil {
            return true
        }
        return false
    }
}
