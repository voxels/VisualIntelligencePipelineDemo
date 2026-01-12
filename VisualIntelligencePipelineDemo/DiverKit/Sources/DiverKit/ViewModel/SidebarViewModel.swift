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

@MainActor
public class SidebarViewModel: ObservableObject {
    // MARK: - Inputs
    @Published public var searchText = ""
    @Published public var sortOrder: SortOrder = .dateDescending
    @Published public var showingSettings = false
    @Published public var showingVisualIntelligence = false
    @Published public var showingShortcutGallery = false
    @Published public var isImporting = false
    
    // Selection Mode
    @Published public var isSelectionMode = false
    @Published public var selectedSessions: Set<String> = []
    @Published public var groupSummaryResult: SummaryResult? = nil
    @Published public var itemToEditLocation: ProcessedItem?
    @Published public var itemToReprocess: ProcessedItem?
    
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
            result = result.filter { item in
                let text = searchText
                let titleMatch = item.title?.localizedCaseInsensitiveContains(text) ?? false
                let urlMatch = item.url?.localizedCaseInsensitiveContains(text) ?? false
                // Check tags/categories/purposes (Concepts)
                let tagMatch = item.tags.contains { $0.localizedCaseInsensitiveContains(text) }
                let categoryMatch = item.categories.contains { $0.localizedCaseInsensitiveContains(text) }
                let purposeMatch = item.purposes.contains { $0.localizedCaseInsensitiveContains(text) }
                
                return titleMatch || urlMatch || tagMatch || categoryMatch || purposeMatch
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
                return (item1.lastProcessedAt ?? item1.updatedAt) > (item2.lastProcessedAt ?? item2.updatedAt)
            case .dateAscending:
                return (item1.lastProcessedAt ?? item1.updatedAt) < (item2.lastProcessedAt ?? item2.updatedAt)
            case .titleAscending:
                return (item1.title ?? item1.url ?? "") < (item2.title ?? item2.url ?? "")
            case .titleDescending:
                return (item1.title ?? item1.url ?? "") > (item2.title ?? item2.url ?? "")
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
    
    public func refresh() async {
        guard let service = pipelineService else { return }
        do {
            try await service.processPendingQueue()
            try await service.refreshProcessedItems()
        } catch {
            print("❌ Refresh failed: \(error)")
        }
    }
    
    // MARK: - Actions
    
    public func deleteItem(_ item: ProcessedItem, context: ModelContext) {
        context.delete(item)
        try? context.save()
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
    
    public func mergeSessions(sourceID: String, targetID: String, context: ModelContext) {
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
            // Show native share sheet
            await MainActor.run {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootViewController = windowScene.windows.first?.rootViewController else {
                    return
                }
                
                let activityVC = UIActivityViewController(
                    activityItems: [wrappedLink],
                    applicationActivities: nil
                )
                
                // For iPad
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = rootViewController.view
                    popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX,
                                                y: rootViewController.view.bounds.midY,
                                                width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                
                rootViewController.present(activityVC, animated: true)
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
                
                // Aggregate Content
                var combinedText = ""
                for item in items {
                    combinedText += "Item: \(item.title ?? "Unknown")\n"
                    if let summary = item.summary { combinedText += "Summary: \(summary)\n" }
                    if !item.purposes.isEmpty { combinedText += "Intents: \(item.purposes.joined(separator: ", "))\n" }
                    if !item.tags.isEmpty { combinedText += "Tags: \(item.tags.joined(separator: ", "))\n" }
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
    
    // MARK: - Photo/Video Import
    public func importExternalItem(data: Data, isVideo: Bool = false) {
        Task {
            do {
                print("📸 Import received, size: \(data.count) bytes, isVideo: \(isVideo)")
                
                // Create DiverQueueItem
                let ext = isVideo ? "mov" : "jpg"
                let filename = "import-\(UUID().uuidString).\(ext)"
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
}
