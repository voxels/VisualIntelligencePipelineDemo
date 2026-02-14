//
//  SidebarViewModel.swift
//  DiverKit
//
//  Created by Claude on 12/24/25.
//

import SwiftUI
import SwiftData
import DiverShared

#if canImport(UIKit)
import UIKit
#endif
import PhotosUI

@MainActor
public final class SidebarViewModel: ObservableObject {
    @Published public var isMaintaining = false
    @Published public var maintenanceProgress: Double = 0
    @Published public var searchText = ""
    @Published public var sortOrder: SortOrder = .dateDescending
    @Published public var showingSettings = false
    @Published public var showingVisualIntelligence = false
    @Published public var showingShortcutGallery = false
    @Published public var isImporting = false
    @Published public var importTargetSession: DiverSession? // Target session for import
    
    // Selection Mode
    @Published public var isSelectionMode = false
    @Published public var selectedSessions: Set<String> = []
    @Published public var groupSummaryResult: SummaryResult? = nil
    @Published public var itemToEditLocation: ProcessedItem?
    @Published public var itemToReprocess: ProcessedItem?
    @Published public var itemToDuplicate: ProcessedItem?
    @Published public var showingDeleteConfirmation = false
    @Published public var showingCombineCollectionSheet = false
    @Published public var combineCollectionName = ""
    @Published public var importError: String? // For user-facing import notifications
    @Published public var isPerformingAction = false // Immediate feedback for blocking operations
    
    // Semantic search results (IDs of items matching via knowledge graph)
    @Published public var semanticMatchIDs: Set<String> = []
    
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
    public func filterCollections(_ collections: [DiverCollection]) -> [DiverCollection] {
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
    public func filterSessions(_ sessions: [DiverSession]) -> [DiverSession] {
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
        let descriptor = FetchDescriptor<DiverSession>()
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
    
    public func refresh() async {
        guard let service = pipelineService else { return }
        do {
            try await service.processPendingQueue()
            try await service.refreshProcessedItems()
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
        try? context.save()
        isPerformingAction = false
    }
    
    public func toggleFavorite(for session: SessionMetadata, context: ModelContext) {
        session.isFavorite.toggle()
        try? context.save()
        print("⭐️ Toggled favorite for session: \(session.isFavorite)")
    }
    
    public func renameSession(_ session: SessionMetadata, title: String, context: ModelContext) {
        session.title = title
        session.updatedAt = Date()
        try? context.save()
        print("✅ Renamed session to '\(title)'")
    }
    
    public func renameCollection(_ collection: DiverCollection, name: String, context: ModelContext) {
        collection.name = name
        collection.updatedAt = Date()
        try? context.save()
        print("✅ Renamed collection to '\(name)'")
    }
    
    public func addSessionToCollection(_ session: SessionMetadata, collection: DiverCollection, context: ModelContext) {
        if !collection.sessionIDs.contains(session.sessionID) {
            collection.sessionIDs.append(session.sessionID)
            collection.updatedAt = Date()
            try? context.save()
            print("✅ Added session '\(session.displayTitle)' to collection '\(collection.name)'")
        }
    }
    
    public func createCollection(name: String, session: SessionMetadata, context: ModelContext) {
        let collection = DiverCollection(
            name: name,
            sessionIDs: [session.sessionID]
        )
        context.insert(collection)
        try? context.save()
        print("✅ Created collection '\(name)' with session '\(session.displayTitle)'")
    }
    
    public func createSessionWithItem(_ item: ProcessedItem, in collection: DiverCollection, context: ModelContext) -> DiverSession {
        let newSession = DiverSession(
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
        
        try? context.save()
        print("✅ Created session with item in collection '\(collection.name)'")
        return newSession
    }
    
    public func createStandaloneSessionWithItem(itemID: String, context: ModelContext) -> DiverSession? {
        let itemFetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == itemID })
        
        do {
            if let item = try context.fetch(itemFetch).first {
                let newSession = DiverSession(
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
    
    public func createSessionInCollectionWithItem(itemID: String, collectionID: String, context: ModelContext) -> DiverSession? {
        let itemFetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.id == itemID })
        let collectionFetch = FetchDescriptor<DiverCollection>(predicate: #Predicate { $0.collectionID == collectionID })
        
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
    
    public func duplicateItem(_ item: ProcessedItem, to session: DiverSession, context: ModelContext) {
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
            themes: item.themes,
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
        try? context.save()
        print("✅ Duplicated item '\(item.displayTitle)' to session '\(session.displayTitle)'")
    }
    
    public func toggleFavorite(for item: ProcessedItem, context: ModelContext) {
        item.isFavorite.toggle()
        try? context.save()
        print("⭐️ Toggled favorite for item: \(item.isFavorite)")
    }
    
    public func sessionTitle(for session: SessionMetadata) -> String {
        return session.displayTitle
    }
    
    public func relatedConcepts(for session: SessionMetadata, allItems: [ProcessedItem], allConcepts: [UserConcept]) -> [UserConcept] {
        let sessionItems = allItems.filter { $0.session == session }
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
        try? context.save()
        return note
    }
    
    public func deleteItem(_ item: ProcessedItem, context: ModelContext) {
        let itemId = item.id
        context.delete(item)
        print("🗑️ Deleted item \(itemId)")
        // Defer save to avoid blocking the main thread
        Task { @MainActor in
            try? context.save()
        }
    }
    
    public func deleteCollection(_ collection: DiverCollection, context: ModelContext) {
        let name = collection.name
        context.delete(collection)
        print("🗑️ Deleted collection '\(name)'")
        Task { @MainActor in
            try? context.save()
        }
    }
    
    public func processItemNow(_ item: ProcessedItem) {
        Task {
            do {
                try await pipelineService?.processItemImmediately(item)
                print("✅ Triggered immediate processing for: \(item.displayTitle)")
            } catch {
                print("❌ Failed to process item immediately: \(error)")
            }
        }
    }
    
    public func cancelProcessing(_ item: ProcessedItem, context: ModelContext) {
        item.status = .failed
        item.processingLog.append("\(Date().formatted()): Cancelled by user")
        print("🚫 Cancelled processing for: \(item.displayTitle)")
        Task { @MainActor in
            try? context.save()
        }
    }
    
    public func analyzeSession(_ session: SessionMetadata, context: ModelContext) {
        Task {
            let localPipeline = LocalPipelineService(modelContext: context)
            await localPipeline.generateAndSaveSessionSummary(sessionID: session.sessionID)
            print("✅ Triggered analysis for session: \(session.displayTitle)")
        }
    }
    
    public func reprocessItem(_ item: ProcessedItem) {
        // Direct background reprocessing
        Task {
            // Reset status to provide immediate feedback
            await MainActor.run {
                 item.status = .processing
                 item.processingLog.append("\(Date().formatted()): User requested quick reprocessing.")
            }
            try? await pipelineService?.processItemImmediately(item)
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
        Task {
            try? await pipelineService?.processItemImmediately(item)
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
            
            for item in items {
                // Mark status as processing immediately
                item.status = .processing
                reprocessItem(item)
            }
            try context.save()
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
            
            print("🔄 Reprocessing \(items.count) items for session \(sessionID) via pipeline")
            
            for item in items {
                item.status = .queued
                item.processingLog.append("\(Date().formatted()): Queued for reprocessing by user")
            }
            try context.save()
            
            Task {
                try? await pipeline.processPendingQueue()
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
            let sessionFetch = FetchDescriptor<DiverSession>(
                predicate: #Predicate { $0.sessionID == sessionID }
            )
            
            do {
                let items = try context.fetch(itemFetch)
                for item in items {
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
    
    /// Combine selected sessions into a new DiverCollection
    public func combineSelectedSessions(context: ModelContext) {
        guard !selectedSessions.isEmpty, !combineCollectionName.isEmpty else { return }
        
        let name = combineCollectionName.trimmingCharacters(in: .whitespaces)
        let sessionIDs = Array(selectedSessions)
        
        // Create new collection
        let collection = DiverCollection(
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
    public func setSessionAsCurrent(_ session: DiverSession, context: ModelContext) {
        session.updatedAt = Date()
        try? context.save()
        print("⏰ Set session '\(session.title ?? session.sessionID)' as Current")
    }
    
    public func duplicateSession(sessionID: String, context: ModelContext) {
        let newSessionID = UUID().uuidString
        
        // 1. Fetch and Clone Metadata
        let metaFetch = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
        do {
            if let sourceMeta = try context.fetch(metaFetch).first {
                let newMeta = DiverSession(
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
                guard let urlString = source.url, let url = URL(string: urlString) else { continue }
                
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
                newItem.themes = source.themes
                
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
            let metaFetch = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sourceID })
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
        let sessionFetch = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == toSessionID })
        
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
                item.updatedAt = Date()
            }
        }
        try? context.save()
    }

    public func moveSessionToCollection(sessionID: String, collectionID: String, context: ModelContext) {
        let collectionFetch = FetchDescriptor<DiverCollection>(predicate: #Predicate { $0.collectionID == collectionID })
        let sessionFetch = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
        
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
        let sessionFetch = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
        
        do {
            if let session = try context.fetch(sessionFetch).first {
                // If it has a parent collection, update it
                if let collectionID = session.collectionID {
                    let collectionFetch = FetchDescriptor<DiverCollection>(predicate: #Predicate { $0.collectionID == collectionID })
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
        
        Task {
            do {
                try await pipeline.maintainLibrary { progress in
                    Task { @MainActor in
                        self.maintenanceProgress = progress
                    }
                }
                
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
        let fetchItems = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.sessionID == sessionID })
        let fetchMeta = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
        
        Task {
            do {
                let items = try context.fetch(fetchItems)
                if items.isEmpty { return }
                
                // Aggregate comprehensive context from all items
                var combinedText = ""
                
                // Extract dominant environmental context from first item
                if let firstItem = items.first {
                    if let weather = firstItem.weatherContext {
                        combinedText += "Environment: \(weather.condition), \(Int(weather.temperatureCelsius))°C\n"
                    }
                    if let activity = firstItem.activityContext {
                        combinedText += "Activity Type: \(activity.type)\n"
                    }
                    if let place = firstItem.placeContext?.name {
                        combinedText += "Primary Location: \(place)\n"
                    }
                }
                combinedText += "---\n"
                
                // Aggregate content from each item
                for item in items {
                    combinedText += "Item: \(item.title ?? "Unknown")\n"
                    if let summary = item.summary { combinedText += "Summary: \(summary)\n" }
                    if !item.purposes.isEmpty { combinedText += "Intents: \(item.purposes.joined(separator: ", "))\n" }
                    if !item.tags.isEmpty { combinedText += "Tags: \(item.tags.joined(separator: ", "))\n" }
                    // Include transcription/OCR if available
                    if let transcription = item.transcription, !transcription.isEmpty {
                        combinedText += "OCR/Transcription: \(String(transcription.prefix(200)))\n"
                    }
                    // Include place tips if available
                    if let tips = item.placeContext?.tips, !tips.isEmpty {
                        combinedText += "Place Tips: \(tips.prefix(2).joined(separator: "; "))\n"
                    }
                    combinedText += "---\n"
                }
                
                let service = ContextQuestionService()
                let summary = try await service.summarizeText(combinedText)
                
                // Save to Metadata
                await MainActor.run {
                     if let meta = try? context.fetch(fetchMeta).first {
                         meta.summary = summary
                         try? context.save()
                         print("✅ Generated summary for session \(sessionID): \(summary)")
                     }
                }
            } catch {
                print("❌ Failed to generate session summary: \(error)")
            }
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
                        let fetchMeta = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
                        if let meta = try? context.fetch(fetchMeta).first {
                            meta.summary = summary
                            try? context.save()
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
                await refresh()
            } catch {
                print("❌ Failed to import examples: \(error)")
            }
            await MainActor.run {
                isImporting = false
            }
        }
    }
    
    // MARK: - Photo Library Import
    
    public func importSelectedPhotos(_ items: [PhotosPickerItem], context: ModelContext, targetSession: DiverSession? = nil) async {
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
    public func previewImage(for session: SessionMetadata, allItems: [ProcessedItem]) -> UIImage? {
        let items = allItems.filter { $0.sessionID == session.sessionID }
        for item in items {
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

    public func importExternalItem(data: Data, filename: String? = nil, isVideo: Bool = false) {
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
                        Task { await self.refresh() }
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
