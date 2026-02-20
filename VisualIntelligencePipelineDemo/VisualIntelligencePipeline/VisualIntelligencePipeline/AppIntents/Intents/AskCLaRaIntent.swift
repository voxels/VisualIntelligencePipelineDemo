import Foundation
import AppIntents
import OSLog
import DiverKit
import DiverShared
import SwiftUI
import SwiftData

private let logger = Logger(subsystem: "com.secretatomics.VisualIntelligencePipeline", category: "AppIntents")

/// Ask CLaRa a question against your Visual Intelligence memory pipeline.
struct AskCLaRaIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask CLaRa"
    static var description = IntentDescription("Ask CLaRa a question about your visual memory (documents, photos, and links).")

    @Parameter(title: "Question")
    var question: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        var queryText = question ?? ""
        
        if queryText.isEmpty {
            logger.debug("🤖 AskCLaRaIntent: Query empty, requesting value from user")
            queryText = try await $question.requestValue("What would you like to ask CLaRa?")
        }
        
        logger.debug("🤖 AskCLaRaIntent: Asking CLaRa: '\(queryText)'")
        
        // Ensure model is loaded or accessible
        guard CLaRaLatentService.shared.isAvailable else {
            let msg = "CLaRa is currently unavailable or downloading."
            return .result(
                dialog: IntentDialog(stringLiteral: msg),
                view: CLaRaAnswerSnippet(question: queryText, answer: msg, isError: true)
            )
        }
        
        // Pre-warm the unified memory cache
        try? await CLaRaLatentService.shared.loadModel()
        
        // Pull real context from ProcessedItem SwiftData
        var semanticContext = "User Visual Memory Context:\n"
        if let store = UnifiedDataManager.shared?.store {
            let context = store.mainContext
            var fetchObj = FetchDescriptor<ProcessedItem>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            fetchObj.fetchLimit = 15
            
            if let recentItems = try? context.fetch(fetchObj) {
                for item in recentItems {
                    semanticContext += "- [Date: \(item.createdAt.formatted())] "
                    semanticContext += "Title: \(item.title ?? "Unknown"). "
                    if let summary = item.summary {
                        semanticContext += "Summary: \(summary) "
                    }
                    if !item.tags.isEmpty {
                        semanticContext += "Tags: \(item.tags.joined(separator: ", ")). "
                    }
                    semanticContext += "\n"
                }
            }
        }
        
        let answer = try? await CLaRaLatentService.shared.query(documentText: semanticContext, question: queryText)
        let finalAnswer = answer ?? "I'm sorry, I couldn't generate an answer at this time."
        
        logger.debug("🤖 AskCLaRaIntent: Answer generated.")

        return .result(
            dialog: IntentDialog(stringLiteral: finalAnswer),
            view: CLaRaAnswerSnippet(
                question: queryText,
                answer: finalAnswer,
                isError: answer == nil
            )
        )
    }
}

/// Snippet view for AskCLaRaIntent shown in Siri/Shortcuts UI.
struct CLaRaAnswerSnippet: View {
    let question: String
    let answer: String
    let isError: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "brain.head.profile")
                    .foregroundColor(isError ? .orange : .indigo)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(question)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Text("CLaRa Agentic Search")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(answer)
                .font(.subheadline)
                .foregroundStyle(isError ? .secondary : .primary)
                .lineLimit(nil)
            
            HStack {
                Spacer()
                Link(destination: URL(string: "secretatomics://chat")!) {
                    HStack(spacing: 4) {
                        Text("Continue in App")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.indigo)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    CLaRaAnswerSnippet(
        question: "When does my car registration expire?",
        answer: "Based on the DMV renewal notice you scanned on Tuesday, your car registration expires on October 31st.",
        isError: false
    )
    .padding()
}
