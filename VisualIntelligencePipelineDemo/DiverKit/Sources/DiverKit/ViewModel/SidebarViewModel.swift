//
//  SidebarViewModel.swift
//  DiverKit
//
//  Created by Claude on 12/24/25.
//

import SwiftUI
import SwiftData
import DiverShared
import Observation

#if canImport(UIKit)
import UIKit

public final class ThumbnailCache: @unchecked Sendable {
    public static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, AnyObject>()
    
    private init() {
        // Keep memory footprint small
        cache.countLimit = 200
    }
    
    public func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString) as? UIImage
    }
    
    public func insert(_ image: UIImage, forKey key: String) {
        cache.setObject(image as AnyObject, forKey: key as NSString)
    }
}
#endif
import PhotosUI

@MainActor
@Observable
public final class SidebarViewModel {
    public var isMaintaining = false
    public var maintenanceProgress: Double = 0
    public var maintenanceStatus: String = ""
    public var searchText = ""
    public var sortOrder: SortOrder = .dateDescending
    public var showingSettings = false
    public var showingVisualIntelligence = false
    public var showingShortcutGallery = false
    public var isImporting = false
    public var importTargetSession: SessionMetadata? // Target session for import
    
    // Selection Mode
    public var isSelectionMode = false
    public var selectedSessions: Set<String> = []
    public var groupSummaryResult: SummaryResult? = nil
    public var itemToEditLocation: ProcessedItem?
    public var itemToReprocess: ProcessedItem?
    public var itemToDuplicate: ProcessedItem?
    public var showingDeleteConfirmation = false
    public var showingCombineCollectionSheet = false
    public var combineCollectionName = ""
    public var importError: String? // For user-facing import notifications
    
    // Background Tasks
    @ObservationIgnored private var backgroundRefreshTask: Task<Void, Error>?
    @ObservationIgnored private var semanticSearchTask: Task<Void, Error>?
    @ObservationIgnored private var processItemTask: Task<Void, Error>?
    @ObservationIgnored private var analyzeSessionTask: Task<Void, Error>?
    @ObservationIgnored private var fullAnalysisTask: Task<Void, Error>?
    @ObservationIgnored private var thumbnailLoadingTasks: [String: Task<UIImage?, Never>] = [:]
    public var isPerformingAction = false // Immediate feedback for blocking operations
    
    // Full Analysis (CLaRa) Modal State
    public var showingFullAnalysis = false
    public var fullAnalysisText = ""
    public var isGeneratingAnalysis = false
    public var fullAnalysisSessionTitle = ""
    
    // Semantic search results (IDs of items matching via knowledge graph)
    public var semanticMatchIDs: Set<String> = []
    
    public struct SummaryResult: Identifiable {
        public let id = UUID()
        public let text: String
        public init(_ text: String) { self.text = text }
    }
    
    private var pipelineService: MetadataPipelineService?
    
    public enum SortOrder: String, CaseIterable {
        case dateDescending = "Newest First"
        case dateAscending = "Oldest First"
        case titleAscending = "Title A-Z"
        case titleDescending = "Title Z-A"
    }
    
    public init() {}
    
    public func setPipelineService(_ service: MetadataPipelineService) {
        self.pipelineService = service
    }
    
    // MARK: - Logic
    
    public func sortAndFilter(items: [ProcessedItem]) -> [ProcessedItem] {
        var result = items
        
        // Filter by search text
        if !searchText.isEmpty {
            let text = searchText
            result = result.filter { item in
                let titleMatch = item.displayTitle.localizedCaseInsensitiveContains(text)
                let urlMatch = item.url?.localizedCaseInsensitiveContains(text) ?? false
                // Check summary for semantic search
                let summaryMatch = item.summary?.localizedCaseInsensitiveContains(text) ?? false
                // Check tags/categories/purposes (Concepts)
                let tagMatch = item.tags.contains { $0.localizedCaseInsensitiveContains(text) }
                let categoryMatch = item.categories.contains { $0.localizedCaseInsensitiveContains(text) }
                let purposeMatch = item.purposes.contains { $0.localizedCaseInsensitiveContains(text) }
                // Semantic match from knowledge graph
                let semanticMatch = semanticMatchIDs.contains(item.id)
                
                return titleMatch || urlMatch || summaryMatch || tagMatch || categoryMatch || purposeMatch || semanticMatch
            }
        }
        
        // Sort
        result.sort { (item1, item2) in
            // Primary Sort: Status (Processing First)
            if item1.status == .processing && item2.status != .processing { return true }
            if item1.status != .processing && item2.status == .processing { return false }
            
            // Secondary Sort: User Selection
            switch sortOrder {
            case .dateDescending:
                return item1.updatedAt > item2.updatedAt
            case .dateAscending:
                return item1.updatedAt < item2.updatedAt
            case .titleAscending:
                return item1.displayTitle < item2.displayTitle
            case .titleDescending:
                return item1.displayTitle > item2.displayTitle
            }
        }
        
        // Uniquify by ID to prevent SwiftUI warnings if the query returns duplicates
        var seen = Set<String>()
        return result.filter { item in
            if seen.contains(item.id) { return false }
            seen.insert(item.id)
            return true
        }
    }
    
    /// Filter collections by search text - searches name and LLM summary
    public func filterCollections(_ collections: [SessionCollection]) -> [SessionCollection] {
        guard !searchText.isEmpty else { return collections }
        
        let text = searchText.lowercased()
        return collections.filter { collection in
            let nameMatch = collection.name.lowercased().contains(text)
            let llmMatch = collection.llmSummary?.lowercased().contains(text) ?? false
            let userMatch = collection.userSummary?.lowercased().contains(text) ?? false
            return nameMatch || llmMatch || userMatch
        }
    }
    
    /// Filter sessions by search text - searches title, location, and summary
    public func filterSessions(_ sessions: [SessionMetadata]) -> [SessionMetadata] {
        guard !searchText.isEmpty else { return sessions }
        
        let text = searchText.lowercased()
        return sessions.filter { session in
            let titleMatch = session.title?.lowercased().contains(text) ?? false
            let locationMatch = session.locationName?.lowercased().contains(text) ?? false
            let summaryMatch = session.summary?.lowercased().contains(text) ?? false
            return titleMatch || locationMatch || summaryMatch
        }
    }
    
    /// Check if there are any search results in collections
    public var hasSearchResults: Bool {
        !searchText.isEmpty
    }
    
    /// Remove sessions that have no items (empty/abandoned)
    public func removeEmptySessions(context: ModelContext) {
        // Fetch all sessions
        let descriptor = FetchDescriptor<SessionMetadata>()
        do {
            let sessions = try context.fetch(descriptor)
            var deletedCount = 0
            
            for session in sessions {
                // Check if session has any items
                if let items = session.items, items.isEmpty {
                     // Check if it's new (created in last 5 seconds) to avoid deleting active capture sessions
                     // that haven't saved items yet
                     if abs(session.createdAt.timeIntervalSinceNow) > 5.0 {
                         context.delete(session)
                         deletedCount += 1
                     }
                } else if session.items == nil {
                     // Also delete if items array is nil (shouldn't happen with default [] but safety check)
                     if abs(session.createdAt.timeIntervalSinceNow) > 5.0 {
                         context.delete(session)
                         deletedCount += 1
                     }
                }
            }
            
            if deletedCount > 0 {
                try context.save()
                print("🧹 Removed \(deletedCount) empty sessions")
            }
        } catch {
            print("❌ Failed to clean up empty sessions: \(error)")
        }
    }
    
    public func refresh(context: ModelContext) async {
        guard let service = pipelineService else { return }
        do {
            try await service.processPendingQueue()
            try await service.refreshProcessedItems()
            
            let container = context.container
            backgroundRefreshTask?.cancel()
            backgroundRefreshTask = Task(priority: .utility) {
                let router = PipelineEdgeRouter(discoveryService: BonjourDiscoveryService())
                let system = VisualIntelligenceActorSystem(transport: NWTransportLayer(localNodeName: UUID().uuidString))
                let backgroundService = BackgroundSummaryService(modelContainer: container)
                await backgroundService.startUpgradesIfNeeded(router: router, system: system)
            }
        } catch {
            print("❌ Refresh failed: \(error)")
        }
    }
    
    /// Perform semantic search using KnowledgeGraph when keyword search yields limited results
    /// - Parameters:
    ///   - query: The search query
    ///   - keywordResultCount: Number of results from keyword search
    /// - Note: Call this after keyword filtering to populate semanticMatchIDs
    public func performSemanticSearch(query: String, keywordResultCount: Int) async {
        // Only trigger semantic search if keyword search returned few results
        guard keywordResultCount < 5, !query.isEmpty else {
            semanticMatchIDs = []
            return
        }
        
        guard let kgService = Services.shared.knowledgeGraphService else {
            return
        }
        
        do {
            let results = try await kgService.retrieveRelevantContext(for: query, sessionID: nil)
            
            // Extract item IDs from context entries that have high relevance
            // The results are (text, weight) tuples - we look for embedded item IDs
            var matchedIDs = Set<String>()
            for (text, weight) in results where weight > 0.5 {
                // Check for UUID pattern (item IDs are UUIDs)
                let pattern = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let range = Range(match.range, in: text) {
                    matchedIDs.insert(String(text[range]))
                }
            }
            
            self.semanticMatchIDs = matchedIDs
            DiverLogger.search.debug("Semantic search for '\(query)' found \(matchedIDs.count) additional matches")
        } catch {
            DiverLogger.search.error("Semantic search failed: \(error)")
        }
    }
    
    // MARK: - Session Management
    
    public func deleteSession(_ session: SessionMetadata, context: ModelContext) {
        isPerformingAction = true
        context.delete(session)
        do { try context.save() } catch { print("❌ Save failed (delete session): \(error)") }
        isPerformingAction = false
    }
    
    public func toggleFavorite(for session: SessionMetadata, context: ModelContext) {
        session.isFavorite.toggle()
        do { try context.save() } catch { print("❌ Save failed (toggle favorite session): \(error)") }
        print("⭐️ Toggled favorite for session: \(session.isFavorite)")
    }
    
    public func renameSession(_ session: SessionMetadata, title: String, context: ModelContext) {
        session.title = title
        session.updatedAt = Date()
        do { try context.save() } catch { print("❌ Save failed (rename session): \(error)") }
        print("✅ Renamed session to '\(title)'")
    }
    
    public func renameCollection(_ collection: SessionCollection, name: String, context: ModelContext) {
        collection.name = name
        collection.updatedAt = Date()
        do { try context.save() } catch { print("❌ Save failed (rename collection): \(error)") }
        print("✅ Renamed collection to '\(name)'")
    }
    
    public func addSessionToCollection(_ session: SessionMetadata, collection: SessionCollection, context: ModelContext) {
        if !collection.sessionIDs.contains(session.sessionID) {
            collection.sessionIDs.append(session.sessionID)
            collection.updatedAt = Date()
            do { try context.save() } catch { print("❌ Save failed (add session to collection): \(error)") }
            print("✅ Added session '\(session.displayTitle)' to collection '\(collection.name)'")
        }
    }
    
    public func createCollection(name: String, session: SessionMetadata, context: ModelContext) {
        let collection = SessionCollection(
            name: name,
            sessionIDs: [session.sessionID]
        )
        context.insert(collection)
        do { try context.save() } catch { print("❌ Save failed (create collection): \(error)") }
        print("✅ Created collection '\(name)' with session '\(session.displayTitle)'")
    }
    
    public func createSessionWithItem(_ item: ProcessedItem, in collection: SessionCollection, context: ModelContext) -> SessionMetadata {
        let newSession = SessionMetadata(
            sessionID: UUID().uuidString,
            title: item.title ?? "New Session",
            createdAt: Date()
        )
        newSession.parentCollection = collection
        newSession.collectionID = collection.collectionID
        
        context.insert(newSession)
        
        // Update item relation
        item.session = newSession
        item.sessionID = newSession.sessionID
        item.updatedAt = Date()
        
        // Update collection
        collection.sessionIDs.append(newSession.sessionID)
        collection.updatedAt = Date()
        
        do { try context.save() } catch { print("❌ Save failed (create session with item): \(error)") }
        print("✅ Created session with item in collection '\(collection.name)'")
        return newSession
    }
    
    public func createStandaloneSessionWithItem(itemID: String, context: ModelContext) -> SessionMetadata? {
        let itemFetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == itemID })
        
        do {
            if let item = try context.fetch(itemFetch).first {
                let newSession = SessionMetadata(
                    sessionID: UUID().uuidString,
                    title: item.title ?? "New Session",
                    createdAt: Date()
                )
                
                context.insert(newSession)
                
                item.session = newSession
                item.sessionID = newSession.sessionID
                item.updatedAt = Date()
                
                try context.save()
                print("✅ Created standalone session with item: \(item.displayTitle)")
                return newSession
            }
        } catch {
            print("❌ Failed to create standalone session: \(error)")
        }
        return nil
    }
    
    public func createSessionInCollectionWithItem(itemID: String, collectionID: String, context: ModelContext) -> SessionMetadata? {
        let itemFetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == itemID })
        let collectionFetch = FetchDescriptor<SessionCollection>(predicate: #Predicate { $0.collectionID == collectionID })
        
        do {
            if let item = try context.fetch(itemFetch).first,
               let collection = try context.fetch(collectionFetch).first {
                
                return createSessionWithItem(item, in: collection, context: context)
            }
        } catch {
            print("❌ Failed to create session in collection: \(error)")
        }
        return nil
    }
    
    public func duplicateItem(_ item: ProcessedItem, to session: SessionMetadata, context: ModelContext) {
        let newItem = ProcessedItem(
            id: UUID().uuidString,
            inputId: item.inputId,
            url: item.url,
            title: item.title,
            summary: item.summary,
            entityType: item.entityType,
            modality: item.modality,
            tags: item.tags,
            createdAt: Date(), // New creation date
            rawPayload: item.rawPayload,
            status: .ready, // Assume ready if copying a processed item
            source: item.source,
            updatedAt: Date(),
            referenceCount: 0,
            lastProcessedAt: Date(), // Don't reprocess immediately
            wrappedLink: item.wrappedLink,
            payloadRef: item.payloadRef,
            attributionID: item.attributionID,
            masterCaptureID: item.masterCaptureID,
            sessionID: session.sessionID, // Target Session
            transcription: item.transcription,
            visualTags: item.visualTags,
            mediaType: item.mediaType,
            fileSize: item.fileSize,
            filename: item.filename,
            photosAssetIdentifier: item.photosAssetIdentifier,
            categories: item.categories,
            location: item.location,
            latitude: item.latitude,
            longitude: item.longitude,
            placeID: item.placeID,
            originalDate: item.originalDate,
            price: item.price,
            rating: item.rating,
            isFavorite: false, // Don't copy favorite status
            purposes: Set(item.purposes),
            productMetadata: item.productMetadata,
            processingLog: ["Copied from \(item.id)"],
            failureCount: 0
        )
        
        // Copy large data blobs
        newItem.weatherContextData = item.weatherContextData
        newItem.activityContextData = item.activityContextData
        newItem.placeContextData = item.placeContextData
        newItem.webContextData = item.webContextData
        newItem.documentContextData = item.documentContextData
        newItem.qrContextData = item.qrContextData
        newItem.questions = item.questions
        
        // Link to Session
        newItem.session = session
        
        context.insert(newItem)
        do { try context.save() } catch { print("❌ Save failed (duplicate item): \(error)") }
        print("✅ Duplicated item '\(item.displayTitle)' to session '\(session.displayTitle)'")
    }
    
    public func toggleFavorite(for item: ProcessedItem, context: ModelContext) {
        item.isFavorite.toggle()
        do { try context.save() } catch { print("❌ Save failed (toggle favorite item): \(error)") }
        print("⭐️ Toggled favorite for item: \(item.isFavorite)")
    }
    
    public func sessionTitle(for session: SessionMetadata) -> String {
        return session.displayTitle
    }
    
    public func relatedConcepts(for session: SessionMetadata, allItems: [ProcessedItem], allConcepts: [UserConcept]) -> [UserConcept] {
        // Use sessionID string comparison instead of relationship ($0.session == session)
        // to avoid forcing SwiftData to fault potentially deleted relationships during body evaluation.
        let targetID = session.sessionID
        let sessionItems = allItems.filter { $0.sessionID == targetID }
        var sessionTerms = Set<String>()
        for item in sessionItems {
            sessionTerms.formUnion(item.tags)
            sessionTerms.formUnion(item.categories)
            sessionTerms.formUnion(item.purposes)
            if let act = item.activityContext { sessionTerms.insert(act.type) }
        }
        let meaningfulTerms = sessionTerms.filter { !$0.hasPrefix("At: ") }
        let related = allConcepts.filter { concept in
            meaningfulTerms.contains { term in
                term.lowercased() == concept.name.lowercased()
            }
        }
        return Array(related.sorted(by: { $0.weight > $1.weight }).prefix(5))
    }
    
    public func createNewNoteForSession(_ session: SessionMetadata, context: ModelContext) -> ProcessedItem {
        // Business logic to auto-create a summary note
        let note = ProcessedItem(
            id: UUID().uuidString,
            title: "Note for \(session.displayTitle)",
            createdAt: Date(),
            status: .ready,
            source: "ManualNote"
        )
        note.session = session
        note.sessionID = session.sessionID
        context.insert(note)
        do { try context.save() } catch { print("❌ Save failed (create note): \(error)") }
        return note
    }
    
    public func deleteItem(_ item: ProcessedItem, context: ModelContext) {
        let itemId = item.id
        context.delete(item)
        print("🗑️ Deleted item \(itemId)")
        do { try context.save() } catch { print("❌ Save failed (delete item): \(error)") }
    }
    
    public func deleteCollection(_ collection: SessionCollection, context: ModelContext) {
        let name = collection.name
        context.delete(collection)
        print("🗑️ Deleted collection '\(name)'")
        do { try context.save() } catch { print("❌ Save failed (delete collection): \(error)") }
    }
    
    public func processItemNow(_ item: ProcessedItem) {
        let itemID = item.id
        processItemTask?.cancel()
        processItemTask = Task {
            do {
                try await pipelineService?.processItemByID(itemID)
                print("✅ Triggered immediate processing for: \(itemID)")
            } catch {
                print("❌ Failed to process item immediately: \(error)")
            }
        }
    }
    
    public func cancelProcessing(_ item: ProcessedItem, context: ModelContext) {
        item.status = .failed
        item.processingLog.append("\(Date().formatted()): Cancelled by user")
        print("🚫 Cancelled processing for: \(item.displayTitle)")
        do { try context.save() } catch { print("❌ Save failed (cancel processing): \(error)") }
    }
    
    public func analyzeSession(_ session: SessionMetadata, context: ModelContext) {
        let sessionID = session.sessionID
        let container = context.container
        analyzeSessionTask?.cancel()
        analyzeSessionTask = Task(priority: .utility) {
            let actor = PersistenceActor(modelContainer: container)
            try? Task.checkCancellation()
            await actor.analyzeSession(sessionID: sessionID)
        }
    }
    
    /// Runs a full CLaRa analysis on a **collection** of sessions,
    /// producing a detailed shareable report that aggregates all items
    /// across every session in the collection.
    public func runFullAnalysis(_ collection: SessionCollection, context: ModelContext) {
        let collectionName = collection.name
        let sessionIDs = collection.sessionIDs
        let container = context.container
        
        // Set modal state immediately for instant feedback
        fullAnalysisSessionTitle = collectionName
        fullAnalysisText = ""
        isGeneratingAnalysis = true
        showingFullAnalysis = true
        
        fullAnalysisTask?.cancel()
        fullAnalysisTask = Task(priority: .utility) {
            // Background ModelContext for SwiftData fetch
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false
            
            // Fetch all items across all sessions in this collection
            var allItems: [ProcessedItem] = []
            for sid in sessionIDs {
                let descriptor = FetchDescriptor<ProcessedItem>(
                    predicate: #Predicate { $0.sessionID == sid },
                    sortBy: [SortDescriptor(\.createdAt, order: .forward)]
                )
                if let batch = try? bgContext.fetch(descriptor) {
                    allItems.append(contentsOf: batch)
                }
            }
            allItems.sort { $0.createdAt < $1.createdAt }
            
            try? Task.checkCancellation()
            
            guard !allItems.isEmpty else {
                if !Task.isCancelled {
                    await MainActor.run { [weak self] in
                        self?.fullAnalysisText = "No items found in this collection."
                        self?.isGeneratingAnalysis = false
                    }
                }
                return
            }
            let items = allItems
            
            // Aggregate rich metadata from all items across the collection
            let aggregatedContext = SidebarViewModel.aggregateSessionMetadata(
                items: items, sessionTitle: collectionName
            )
            
            // Send to edge CLaRa for detailed analysis
            let analysisResult = await SidebarViewModel.generateDetailedAnalysis(
                context: aggregatedContext
            )
            
            if !Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.fullAnalysisText = analysisResult
                    self?.isGeneratingAnalysis = false
                }
            }
        }
    }
    
    /// Aggregates all metadata from session items into a rich text block for CLaRa.
    nonisolated private static func aggregateSessionMetadata(items: [ProcessedItem], sessionTitle: String) -> String {
        let calendar = Calendar.current
        var sections: [String] = []
        
        sections.append("SESSION: \(sessionTitle)")
        sections.append("Items: \(items.count)")
        
        if let first = items.first, let last = items.last {
            let start = first.createdAt.formatted(date: .abbreviated, time: .shortened)
            let end = last.createdAt.formatted(date: .abbreviated, time: .shortened)
            sections.append("Time Range: \(start) — \(end)")
        }
        
        // Unique locations
        let locations = Set(items.compactMap { $0.location }).sorted()
        if !locations.isEmpty {
            sections.append("Locations: \(locations.joined(separator: ", "))")
        }
        
        sections.append("---")
        sections.append("DETAILED ITEM METADATA:")
        
        for (index, item) in items.enumerated() {
            var parts: [String] = []
            let time = item.createdAt.formatted(date: .omitted, time: .shortened)
            parts.append("\n[Item \(index + 1)] \(item.title ?? "Untitled") (\(time))")
            
            if let loc = item.location { parts.append("  Location: \(loc)") }
            if let sum = item.summary, !sum.isEmpty { parts.append("  Summary: \(sum)") }
            if let media = item.mediaType { parts.append("  Media: \(media)") }
            
            // FastVLM visual analysis
            if let vlm = item.fastVLMAnalysis, let desc = vlm.imageDescription, !desc.isEmpty {
                parts.append("  Visual Analysis: \(desc)")
            }
            
            // Web context
            if let web = item.webContext {
                if let site = web.siteName { parts.append("  Web Source: \(site)") }
                if let content = web.textContent, !content.isEmpty {
                    parts.append("  Web Content: \(String(content.prefix(300)))")
                }
            }
            
            // Commerce
            if let commerce = item.commerceContext, let first = commerce.first {
                parts.append("  Product: \(first.option.productName) (\(first.option.platform))")
                parts.append("  Composite Score: \(String(format: "%.2f", first.compositeScore))")
            }
            
            // Transcription
            if let transcript = item.transcription, !transcript.isEmpty {
                parts.append("  OCR Text: \(String(transcript.prefix(400)))")
            }
            
            // Tags
            if !item.tags.isEmpty {
                parts.append("  Tags: \(item.tags.joined(separator: ", "))")
            }
            
            // Questions
            if !item.questions.isEmpty {
                parts.append("  Questions: \(item.questions.joined(separator: "; "))")
            }
            
            sections.append(parts.joined(separator: "\n"))
        }
        
        return sections.joined(separator: "\n")
    }
    
    /// Routes analysis to edge CLaRa 7B or falls back to on-device SLM.
    nonisolated private static func generateDetailedAnalysis(context: String) async -> String {
        // Try edge CLaRa first (7B — handles long context well)
        let router = await MainActor.run { Services.shared.edgeRouter }
        let system = await MainActor.run { Services.shared.actorSystem }
        
        if let router = router, let system = system {
            let decision = await router.shouldOffload(task: .vlmInference)
            if case .edge(let node, _) = decision {
                do {
                    let identity = EdgeActorID(id: "EdgeContext", nodeName: node.deviceName)
                    let edgeActor = try EdgeContextActor.resolve(id: identity, using: system)
                    
                    let prompt = """
                    You are a detailed visual intelligence analyst. Produce a comprehensive written report \
                    about this collection of captured items. The report should:
                    
                    1. OVERVIEW: Summarize what this collection is about — the themes, locations, and time patterns
                    2. KEY INSIGHTS: What stands out? Patterns, notable items, interesting connections
                    3. DETAILED BREAKDOWN: Walk through the items chronologically, describing what was captured and why it matters
                    4. METADATA HIGHLIGHTS: Note any significant visual analysis, commerce data, web sources, or OCR text
                    5. RECOMMENDATIONS: Suggest follow-up actions or areas to explore further
                    
                    Write in clear paragraphs, not bullet points. Be thorough but insightful.
                    
                    ---
                    \(context)
                    """
                    
                    let noImage: Data? = nil
                    let result = try await edgeActor.summarize(text: prompt, imageData: noImage)
                    return "[Model: Edge-CLaRa-7B]\n\n\(result)"
                } catch {
                    print("⚠️ Edge CLaRa failed for full analysis: \(error)")
                }
            }
        }
        
        // Fallback: on-device SLM (shorter output)
        if ContextQuestionService.isAvailable {
            let service = ContextQuestionService()
            let prompt = """
            Create a detailed analysis of this captured collection. Include themes, patterns, \
            key items, and insights. Write 3-5 paragraphs.
            
            \(String(context.prefix(3000)))
            """
            if let result = try? await service.summarizeText(prompt) {
                return "[Model: On-Device SLM]\n\n\(result)"
            }
        }
        
        return "Analysis unavailable. Connect to your Mac running EdgeDaemon for CLaRa 7B analysis, or ensure Apple Intelligence is enabled."
    }
    
    public func reprocessItem(_ item: ProcessedItem) {
        // Immediate visual feedback on main actor
        item.status = .processing
        item.processingLog.append("\(Date().formatted()): User requested quick reprocessing.")
        
        // Background reprocessing with private ModelContext
        let itemID = item.id
        processItemTask?.cancel()
        processItemTask = Task(priority: .utility) { [pipelineService] in
            try? await pipelineService?.processItemByID(itemID)
        }
    }
    
    public func refineItem(_ item: ProcessedItem) {
        self.itemToReprocess = item
    }
    
    public func retryItem(_ item: ProcessedItem) {
        item.status = .queued
        item.processingLog.append("\(Date().formatted()): User requested automatic retry via tap.")
        Task {
            try? await pipelineService?.processPendingQueue()
        }
    }
    
    public func processNow(_ item: ProcessedItem) {
        item.status = .processing
        let itemID = item.id
        processItemTask?.cancel()
        processItemTask = Task(priority: .utility) { [pipelineService] in
            do {
                try await pipelineService?.processItemByID(itemID)
                await MainActor.run { item.status = .ready }
            } catch {
                await MainActor.run { item.status = .failed }
            }
        }
    }
    
    public func reprocessSession(sessionID: String, context: ModelContext) {
        let fetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        
        do {
            let items = try context.fetch(fetch)
            if items.isEmpty { return }
            
            print("🔄 Reprocessing \(items.count) items for session \(sessionID)")
            
            // Collect IDs and mark status immediately for visual feedback
            var itemIDs: [String] = []
            for item in items {
                item.status = .processing
                itemIDs.append(item.id)
            }
            try context.save()
            
            // Process SEQUENTIALLY in background — each call creates its own ModelContext
            processItemTask?.cancel()
            processItemTask = Task(priority: .utility) { [pipelineService] in
                for id in itemIDs {
                    try? Task.checkCancellation()
                    try? await pipelineService?.processItemByID(id)
                }
            }
        } catch {
            print("❌ Failed to fetch session items for reprocessing: \(error)")
        }
    }
    
    public func reprocessSession(sessionID: String, context: ModelContext, pipeline: MetadataPipelineService) {
        let fetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        
        do {
            let items = try context.fetch(fetch)
            if items.isEmpty { return }
            
            let itemIDs = items.map { $0.id }
            let container = context.container
            print("🔄 Reprocessing \(itemIDs.count) items for session \(sessionID) via processItemByID")
            
            processItemTask?.cancel()
            processItemTask = Task(priority: .utility) { [pipeline] in
                // Process each item through the single canonical path
                for itemID in itemIDs {
                    try? Task.checkCancellation()
                    do {
                        try await pipeline.processItemByID(itemID)
                    } catch {
                        print("❌ Failed to reprocess item \(itemID): \(error)")
                    }
                }
                
                try? Task.checkCancellation()
                // Regenerate session summary after all items are reprocessed
                let bgCtx = ModelContext(container)
                let localPipeline = LocalPipelineService(modelContext: bgCtx)
                await localPipeline.generateAndSaveSessionSummary(sessionID: sessionID)
                print("✅ Session \(sessionID) reprocessing complete with summary regeneration")
            }
        } catch {
            print("❌ Failed to fetch session items for reprocessing: \(error)")
        }
    }
    
    /// Get all unique session IDs from a list of items
    public func getAllSessionIDs(items: [ProcessedItem]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            if let sessionID = item.sessionID, !seen.contains(sessionID) {
                seen.insert(sessionID)
                result.append(sessionID)
            }
        }
        return result
    }
    
    /// Delete all items for selected sessions
    public func deleteSelectedSessions(context: ModelContext) {
        guard !selectedSessions.isEmpty else { return }
        isPerformingAction = true
        
        for sessionID in selectedSessions {
            let itemFetch = FetchDescriptor<ProcessedItem>(
                predicate: #Predicate { $0.sessionID == sessionID }
            )
            let sessionFetch = FetchDescriptor<SessionMetadata>(
                predicate: #Predicate { $0.sessionID == sessionID }
            )
            
            do {
                let items = try context.fetch(itemFetch)
                for item in items {
                    // Remove from CLaRa RAG index before deleting
                    _ = CLaRaLatentService.shared.removeDocument(id: item.id)
                    context.delete(item)
                }
                
                let sessions = try context.fetch(sessionFetch)
                for session in sessions {
                    context.delete(session)
                }
            } catch {
                print("❌ Failed to delete session \(sessionID): \(error)")
            }
        }
        
        do {
            try context.save()
            print("🗑️ Deleted \(selectedSessions.count) sessions")
        } catch {
            print("❌ Failed to save after deletion: \(error)")
        }
        
        isPerformingAction = false
        
        // Clear selection
        selectedSessions.removeAll()
        isSelectionMode = false
    }
    
    /// Combine selected sessions into a new SessionCollection
    public func combineSelectedSessions(context: ModelContext) {
        guard !selectedSessions.isEmpty, !combineCollectionName.isEmpty else { return }
        
        let name = combineCollectionName.trimmingCharacters(in: .whitespaces)
        let sessionIDs = Array(selectedSessions)
        
        // Create new collection
        let collection = SessionCollection(
            name: name,
            sessionIDs: sessionIDs
        )
        
        context.insert(collection)
        
        do {
            try context.save()
            print("📚 Created collection '\(name)' with \(sessionIDs.count) sessions")
        } catch {
            print("❌ Failed to save collection: \(error)")
        }
        
        // Clear state
        showingCombineCollectionSheet = false
        combineCollectionName = ""
        isSelectionMode = false
    }
    
    /// Update session timestamp to make it "Current"
    public func setSessionAsCurrent(_ session: SessionMetadata, context: ModelContext) {
        session.updatedAt = Date()
        do { try context.save() } catch { print("❌ Save failed (set session current): \(error)") }
        print("⏰ Set session '\(session.title ?? session.sessionID)' as Current")
    }
    
    public func duplicateSession(sessionID: String, context: ModelContext) {
        let newSessionID = UUID().uuidString
        
        // 1. Fetch and Clone Metadata
        let metaFetch = FetchDescriptor<SessionMetadata>(predicate: #Predicate { $0.sessionID == sessionID })
        do {
            if let sourceMeta = try context.fetch(metaFetch).first {
                let newMeta = SessionMetadata(
                    sessionID: newSessionID,
                    title: "Copy of \(sourceMeta.title ?? "Untitled")",
                    createdAt: Date()
                )
                newMeta.locationName = sourceMeta.locationName
                newMeta.latitude = sourceMeta.latitude
                newMeta.longitude = sourceMeta.longitude
                newMeta.placeID = sourceMeta.placeID
                
                context.insert(newMeta)
            }
        } catch {
            print("⚠️ Failed to clone session metadata: \(error)")
        }
        
        // 2. Fetch and Clone Items
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.sessionID == sessionID })
        do {
            let sourceItems = try context.fetch(fetch)
            print("©️ Duplicating \(sourceItems.count) items to new session \(newSessionID)")
            
            for source in sourceItems {
                guard let urlString = source.url, let _ = URL(string: urlString) else { continue }
                
                let uniqueID = UUID().uuidString
                
                // Construct Cloned Item
                // Fix Init Order: id, url, title, summary, createdAt, masterCaptureID, sessionID
                let newItem = ProcessedItem(
                    id: uniqueID,
                    url: source.url,
                    title: source.title,
                    summary: source.summary,
                    createdAt: Date(),
                    status: .queued,
                    masterCaptureID: source.masterCaptureID,
                    sessionID: newSessionID
                )
                newItem.tags = source.tags
                newItem.categories = source.categories
                newItem.purposes = source.purposes
                newItem.location = source.location
                
                // Copy Context Data Blobs
                newItem.webContextData = source.webContextData
                newItem.documentContextData = source.documentContextData
                newItem.qrContextData = source.qrContextData
                

                newItem.weatherContextData = source.weatherContextData
                newItem.activityContextData = source.activityContextData
                
                // Copy Media Metadata
                newItem.mediaType = source.mediaType
                newItem.filename = source.filename
                newItem.fileSize = source.fileSize
                newItem.transcription = source.transcription
                newItem.visualTags = source.visualTags
                
                context.insert(newItem)
                
                // Create Descriptor & Enqueue
                let descriptor = DiverItemDescriptor(
                    id: uniqueID,
                    url: urlString,
                    title: source.title ?? "Untitled",
                    descriptionText: source.summary,
                    styleTags: source.tags,
                    categories: source.categories,
                    type: .web, // ProcessedItem doesn't store type explicitly? Default to .web or try to infer?
                               // Actually source.type gave error. ProcessedItem is flattened.
                               // Use .web as safe default for duplication since we are mostly dealing with links/text
                    sessionID: newSessionID,
                    placeID: source.placeContext?.placeID,
                    latitude: source.placeContext?.latitude,
                    longitude: source.placeContext?.longitude,
                    purposes: Set(source.purposes)
                )
                
                Task {
                    do {
                        let queueItem = DiverQueueItem(action: "save", descriptor: descriptor, source: "duplicate")
                        let queueDirectory = AppGroupContainer.queueDirectoryURL()!
                        let queueStore = try DiverQueueStore(directoryURL: queueDirectory)
                        _ = try queueStore.enqueue(queueItem)
                    } catch {
                        print("❌ Failed to enqueue duplicate: \(error)")
                    }
                }
            }
            
            try context.save()
            print("✅ Session duplication complete: \(newSessionID)")
        } catch {
            print("❌ Failed to duplicate session items: \(error)")
        }
    }
    
    public func moveSession(sourceID: String, targetID: String, context: ModelContext) {
        guard sourceID != targetID else { return }
        
        // 1. Fetch Items from Source
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.sessionID == sourceID })
        
        do {
            let sourceItems = try context.fetch(fetch)
            if sourceItems.isEmpty { return }
            
            print("🔀 Merging \(sourceItems.count) items from \(sourceID) into \(targetID)")
            
            // 2. Move Items to Target Session
            for item in sourceItems {
                item.sessionID = targetID
                item.updatedAt = Date() // Bump update time
            }
            
            // 3. Delete Source Session Metadata
            let metaFetch = FetchDescriptor<SessionMetadata>(predicate: #Predicate { $0.sessionID == sourceID })
            if let oldMeta = try context.fetch(metaFetch).first {
                context.delete(oldMeta)
            }
            
            try context.save()
            
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            
            print("✅ Merge complete")
            
        } catch {
            print("❌ Failed to merge sessions: \(error)")
        }
    }

    public func moveItem(itemID: String, toSessionID: String, context: ModelContext) {
        let itemFetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == itemID })
        let sessionFetch = FetchDescriptor<SessionMetadata>(predicate: #Predicate { $0.sessionID == toSessionID })
        
        do {
            if let item = try context.fetch(itemFetch).first,
               let session = try context.fetch(sessionFetch).first {
                item.session = session
                item.sessionID = toSessionID
                item.updatedAt = Date()
                session.updatedAt = Date()
                try context.save()
                print("✅ Moved item \(itemID) to session \(toSessionID)")
            }
        } catch {
            print("❌ Failed to move item: \(error)")
        }
    }
    
    public func moveItems(_ items: [ItemTransfer], to session: SessionMetadata, context: ModelContext) {
        for itemTransfer in items {
            let itemID = itemTransfer.id
            let descriptor = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == itemID })
            if let item = try? context.fetch(descriptor).first {
                item.session = session
                item.sessionID = session.sessionID
                item.updatedAt = Date()
            }
        }
        session.updatedAt = Date()
        do { try context.save() } catch { print("❌ Save failed (move items): \(error)") }
    }

    public func moveSessionToCollection(sessionID: String, collectionID: String, context: ModelContext) {
        let collectionFetch = FetchDescriptor<SessionCollection>(predicate: #Predicate { $0.collectionID == collectionID })
        let sessionFetch = FetchDescriptor<SessionMetadata>(predicate: #Predicate { $0.sessionID == sessionID })
        
        do {
            if let collection = try context.fetch(collectionFetch).first,
               let session = try context.fetch(sessionFetch).first {
                
                // Add to collection IDs if not present
                if !collection.sessionIDs.contains(sessionID) {
                    collection.sessionIDs.append(sessionID)
                }
                
                session.parentCollection = collection
                session.collectionID = collectionID
                session.updatedAt = Date()
                collection.updatedAt = Date()
                
                try context.save()
                print("✅ Moved session \(sessionID) to collection \(collectionID)")
            }
        } catch {
            print("❌ Failed to move session to collection: \(error)")
        }
    }
    
    public func removeSessionFromCollection(sessionID: String, context: ModelContext) {
        let sessionFetch = FetchDescriptor<SessionMetadata>(predicate: #Predicate { $0.sessionID == sessionID })
        
        do {
            if let session = try context.fetch(sessionFetch).first {
                // If it has a parent collection, update it
                if let collectionID = session.collectionID {
                    let collectionFetch = FetchDescriptor<SessionCollection>(predicate: #Predicate { $0.collectionID == collectionID })
                    if let collection = try context.fetch(collectionFetch).first {
                        collection.sessionIDs.removeAll { $0 == sessionID }
                        collection.updatedAt = Date()
                    }
                }
                
                // Clear session pointers
                session.parentCollection = nil
                session.collectionID = nil
                session.updatedAt = Date()
                
                try context.save()
                print("✅ Removed session \(sessionID) from collection")
            }
        } catch {
            print("❌ Failed to remove session from collection: \(error)")
        }
    }

    
    public func rebuildLibrary(context: ModelContext) {
        let pipeline = LocalPipelineService(modelContext: context)
        
        isMaintaining = true
        maintenanceProgress = 0
        maintenanceStatus = "Starting…"
        
        Task {
            do {
                try await pipeline.maintainLibrary { progress in
                    Task { @MainActor in
                        self.maintenanceProgress = progress
                    }
                } statusHandler: { status in
                    Task { @MainActor in
                        self.maintenanceStatus = status
                    }
                }
                
                // Rebuild CLaRa RAG index after library reconciliation
                Task { @MainActor in
                    self.maintenanceStatus = "Rebuilding search index…"
                }
                CLaRaLatentService.shared.clearIndex()
                await CLaRaLatentService.shared.populateIndex(container: context.container)
                
                Task { @MainActor in
                    self.isMaintaining = false
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                }
            } catch {
                print("❌ Library maintenance failed: \(error)")
                Task { @MainActor in
                    self.isMaintaining = false
                }
            }
        }
    }
    
    public func shareItem(_ item: ProcessedItem) {
        Task {
            guard let urlString = item.url, let url = URL(string: urlString) else { return }
            
            // Generate wrapped link
            let wrappedLink: String
            if let existing = item.wrappedLink {
                wrappedLink = existing
            } else {
                // Generate new wrapped link
                let keychainService = KeychainService(
                    service: KeychainService.ServiceIdentifier.diver,
                    accessGroup: AppGroupConfig.default.keychainAccessGroup
                )
                
                guard let secret = keychainService.retrieveString(key: KeychainService.Keys.diverLinkSecret) else {
                    print("❌ No keychain secret found for wrapping")
                    return
                }
                
                do {
                    guard let secretData = Data(base64Encoded: secret) else {
                        print("❌ Failed to decode keychain secret")
                        return
                    }
                    let payload = DiverLinkPayload(url: url, title: item.title)
                    let wrappedURL = try DiverLinkWrapper.wrap(url: url, secret: secretData, payload: payload)
                    wrappedLink = wrappedURL.absoluteString
                } catch {
                    print("❌ Failed to wrap URL: \(error)")
                    return
                }
            }
            
            #if os(iOS)
            // Use RichLinkSharer for consistent rich media previews
            await MainActor.run {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootViewController = windowScene.windows.first?.rootViewController else {
                    return
                }
                
                // Use the configured URL if possible
                guard let finalURL = URL(string: wrappedLink) else { return }
                
                let sharer = RichLinkSharer.shared
                sharer.presentShareSheet(
                    from: rootViewController,
                    url: finalURL,
                    title: item.title,
                    image: nil, // Could extract image from item if we wanted to pass it
                    originalURL: url
                )
            }
            #endif
        }
    }
    
    public func generateSessionSummary(sessionID: String, context: ModelContext) {
        Task {
            let pipeline = LocalPipelineService(modelContext: context)
            await pipeline.generateAndSaveSessionSummary(sessionID: sessionID)
            print("✅ Generated full-metadata summary for session \(sessionID)")
        }
    }
    
    public func generateGroupSummary(context: ModelContext) {
        let ids = Array(selectedSessions)
        if ids.isEmpty { return }
        
        Task {
            var combinedText = ""
            var itemCount = 0
            
            for id in ids {
                await MainActor.run {
                    let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.sessionID == id })
                    if let items = try? context.fetch(fetch) {
                         combinedText += "\n### Session \(id.prefix(8))\n"
                         // Increased limit to capture more context
                         for item in items.prefix(50) {
                             combinedText += "- \(item.title ?? "Item")\n"
                             if let s = item.summary { combinedText += "  \(s)\n" }
                         }
                        itemCount += items.count
                    }
                }
            }
            
            if combinedText.isEmpty { return }
            
            let service = ContextQuestionService()
            do {
                let summary = try await service.summarizeText("Analyze these combined sessions (Total items: \(itemCount)):\n" + combinedText)
                
                await MainActor.run {
                    self.groupSummaryResult = SummaryResult(summary)
                    
                    // If single session, persist this summary as the session context
                    if ids.count == 1, let sessionID = ids.first {
                        let fetchMeta = FetchDescriptor<SessionMetadata>(predicate: #Predicate { $0.sessionID == sessionID })
                        if let meta = try? context.fetch(fetchMeta).first {
                            meta.summary = summary
                            do { try context.save() } catch { print("❌ Save failed (persist group summary): \(error)") }
                            print("✅ Persisted group summary to session \(sessionID)")
                        }
                    }
                }
            } catch {
                print("❌ Group summary failed: \(error)")
            }
        }
    }

    public func importExamples(context: ModelContext) {
        isImporting = true
        Task {
            do {
                try await PipelineImportService.importExamples(modelContext: context)
                await refresh(context: context)
            } catch {
                print("❌ Failed to import examples: \(error)")
            }
            await MainActor.run {
                isImporting = false
            }
        }
    }
    
    // MARK: - Photo Library Import
    
    public func importSelectedPhotos(_ items: [PhotosPickerItem], context: ModelContext, targetSession: SessionMetadata? = nil) async {
        // Use the proper PhotoLibraryImportService for clustering, session creation, and metadata extraction
        let importService = PhotoLibraryImportService(modelContext: context)
        
        do {
            if let target = targetSession {
                 // Import into EXISTING session
                 print("📥 Importing \(items.count) items into existing session: \(target.displayTitle)")
                 let importedItems = try await importService.importItems(items, into: target)
                 // Check count
                 if importedItems.count < items.count {
                     await MainActor.run {
                         self.importError = "Imported \(importedItems.count) of \(items.count) items. Some items were skipped."
                     }
                 } else {
                     print("✅ Added \(items.count) photos to session: \(target.displayTitle)")
                 }
            } else {
                // Default: Create NEW collection
                // Generate a collection name based on current date
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                let collectionName = "Import \(dateFormatter.string(from: Date()))"
                
                let collection = try await importService.importItems(items, collectionName: collectionName)
                
                // Count actual items across all sessions in the collection, not just session count
                // (Multiple photos can cluster into a single session)
                var importedCount = 0
                for sessionID in collection.sessionIDs {
                    let sid = sessionID
                    let itemFetch = FetchDescriptor<ProcessedItem>(
                        predicate: #Predicate { $0.sessionID == sid }
                    )
                    importedCount += (try? context.fetch(itemFetch).count) ?? 0
                }
                if importedCount < items.count {
                    await MainActor.run {
                        self.importError = "Imported \(importedCount) of \(items.count) items. Some items may have been skipped or failed to load."
                    }
                } else {
                     print("✅ Imported \(items.count) photos into collection: \(collection.name)")
                }
            }
            
            // Process the imported items through the pipeline
            try? await pipelineService?.processPendingQueue()
        } catch {
            print("❌ Failed to import photos: \(error)")
            await MainActor.run {
                self.importError = "Failed to import photos: \(error.localizedDescription)"
            }
        }
    }
    
#if canImport(UIKit)
    @MainActor
    public func asyncPreviewImage(for sessionID: String, allItems: [ProcessedItem], container: ModelContainer) async -> UIImage? {
        // Check cache first
        if let cached = ThumbnailCache.shared.image(forKey: sessionID) {
            return cached
        }

        // Collect model IDs on the main thread
        let itemIDs = allItems.filter { $0.sessionID == sessionID }.map { $0.persistentModelID }
        guard !itemIDs.isEmpty else { return nil }
        
        let result = await loadPreviewImage(itemIDs: itemIDs, container: container)
        
        if let result {
            ThumbnailCache.shared.insert(result, forKey: sessionID)
        }
        return result
    }
    
    nonisolated private func loadPreviewImage(itemIDs: [PersistentIdentifier], container: ModelContainer) async -> UIImage? {
        // Background context to prevent blocking main thread with external storage reads
        let bgContext = ModelContext(container)
        bgContext.autosaveEnabled = false
        
        for id in itemIDs {
            try? await Task.sleep(nanoseconds: 1_000) // Yield slightly
            if Task.isCancelled { return nil }
            guard let item = bgContext.model(for: id) as? ProcessedItem else { continue }
            
            if let data = item.rawPayload {
                // Fast, memory-efficient downsampling without fully decoding
                if let imageSource = CGImageSourceCreateWithData(data as CFData, nil) {
                    let options = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 300,
                        kCGImageSourceCreateThumbnailWithTransform: true
                    ] as CFDictionary
                    
                    if let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) {
                        return UIImage(cgImage: cgImage)
                    }
                }
                // Fallback
                if let image = UIImage(data: data) { return image }
            }
            
            if let path = item.webContext?.snapshotURL, let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }
    
    // Kept for backward compatibility if needed synchronously
    public func previewImage(for session: SessionMetadata, allItems: [ProcessedItem]) -> UIImage? {
        let items = allItems.filter { $0.sessionID == session.sessionID }
        for item in items {
            // This blocks the main thread! Prefer asyncPreviewImage
            if let data = item.rawPayload, let image = UIImage(data: data) {
                return image
            }
            if let path = item.webContext?.snapshotURL, let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }
#endif

    public func importExternalItem(data: Data, filename: String? = nil, isVideo: Bool = false, context: ModelContext) {
        Task {
            do {
                print("📸 Import received, size: \(data.count) bytes, isVideo: \(isVideo)")
                
                // Detect appropriate extension
                let ext: String
                
                // 1. Prefer explicit filename extension
                if let filename = filename, !filename.isEmpty,
                   let fileExt = (filename as NSString).pathExtension.lowercased() as String?,
                   !fileExt.isEmpty {
                    ext = fileExt
                } 
                // 2. Sniff Data for Magic Bytes (Don't guess)
                else if let detected = self.detectExtension(from: data) {
                    ext = detected
                } 
                // 3. Last Resort Fallback (Generic)
                else {
                    ext = isVideo ? "mov" : "jpg" // Fallback for unknown streams
                }
                let _ = "import-\(UUID().uuidString).\(ext)"
                let queueDirectory = AppGroupContainer.queueDirectoryURL()!
                
                let descriptor = DiverItemDescriptor(
                    id: UUID().uuidString,
                    url: "", // Fix: url is non-optional String
                    title: isVideo ? "Imported Video" : "Imported Photo",
                    descriptionText: nil,
                    createdAt: Date(), 
                    type: isVideo ? .video : .image,
                )
                
                let queueItem = DiverQueueItem(
                    id: UUID(),
                    action: "analyze",
                    descriptor: descriptor,
                    source: "library_import",
                    payload: data
                )
                
                let queueStore = try DiverQueueStore(directoryURL: queueDirectory)
                let path = try queueStore.enqueue(queueItem)
                print("✅ Enqueued imported item at \(path)")
                
                await MainActor.run {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        Task { await self.refresh(context: context) }
                    }
                }
            } catch {
                print("❌ Failed to process external image: \(error)")
            }
        }
    }
    
    private func detectExtension(from data: Data) -> String? {
        var values = [UInt8](repeating: 0, count: 12)
        data.copyBytes(to: &values, count: min(data.count, 12))
        
        // JPEG: FF D8 FF
        if values[0] == 0xFF && values[1] == 0xD8 && values[2] == 0xFF { return "jpg" }
        
        // PNG: 89 50 4E 47
        if values[0] == 0x89 && values[1] == 0x50 && values[2] == 0x4E && values[3] == 0x47 { return "png" }
        
        // GIF: 47 49 46
        if values[0] == 0x47 && values[1] == 0x49 && values[2] == 0x46 { return "gif" }
        
        // HEIC/MP4: ....ftyp (offset 4)
        // Check for 'ftyp' at bytes 4-7
        if values[4] == 0x66 && values[5] == 0x74 && values[6] == 0x79 && values[7] == 0x70 {
            // Check major brand
            let majorBrand = String(bytes: values[8...11], encoding: .ascii)
            if majorBrand == "heic" { return "heic" }
            if ["mp41", "mp42", "isom", "qt  "].contains(majorBrand) { return "mov" }
        }
        
        return nil
    }
}
