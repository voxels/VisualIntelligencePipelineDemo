import Foundation
import SwiftData
import DiverShared
import CoreLocation
import ImageIO

@MainActor
public final class LocalPipelineService {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    public func process(
        input: LocalInput,
        descriptor: DiverItemDescriptor? = nil,
        enrichmentService: LinkEnrichmentService? = nil,
        locationService: LocationProvider? = nil,
        foursquareService: ContextualEnrichmentService? = nil,
        duckDuckGoService: ContextualEnrichmentService? = nil,
        weatherService: WeatherEnrichmentService? = nil,
        activityService: ActivityEnrichmentService? = nil,
        indexingService: KnowledgeGraphIndexingService? = nil,
        contextService: ContextQuestionService? = nil
    ) async throws -> ProcessedItem {
        let resolvedId = descriptor?.id ?? resolveId(for: input)

        DiverLogger.pipeline.debug("Processing LocalInput - inputId: \(input.id.uuidString), resolvedId: \(resolvedId), hasDescriptor: \(descriptor != nil), attributionID: \(descriptor?.attributionID ?? "nil")")

        let fetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.id == resolvedId }
        )
        let existing = try modelContext.fetch(fetch).first

        let resolvedTitle = descriptor?.title ?? deriveTitle(for: input)
        let resolvedSummary = descriptor?.descriptionText ?? input.text
        let resolvedEntityType = descriptor?.type.rawValue ?? input.inputType
        let resolvedModality = descriptor?.type.rawValue ?? input.inputType
        let resolvedTags = descriptor.map { Array(Set($0.styleTags + $0.categories)).sorted() } ?? []
        let rawPayload = input.rawPayload ?? (try? encodePayload(input: input, descriptor: descriptor))

        if let existing {
            DiverLogger.pipeline.debug("Updating existing ProcessedItem - id: \(resolvedId)")
            existing.status = .processing
            try? modelContext.save() // Trigger live UI update to show 'Processing'

            if existing.inputId == nil {
                existing.inputId = input.id.uuidString
            }
            if existing.url == nil {
                existing.url = input.url
            }
            if existing.title == nil || existing.title?.isEmpty == true || (descriptor?.title != nil && existing.title != descriptor?.title) {
                existing.title = resolvedTitle
            }
            if existing.summary == nil || existing.summary?.isEmpty == true {
                existing.summary = resolvedSummary
            }
            if existing.entityType == nil || existing.entityType?.isEmpty == true {
                existing.entityType = resolvedEntityType
            }
            
            // Apply standard URL enrichment if available
            var accumulatedContext = ""
            
            if let urlString = input.url, let url = URL(string: urlString), let enrichmentService {
                if url.scheme?.lowercased().hasPrefix("secretatomics") == false {
                    if let enrichment = try await enrichmentService.enrich(url: url) {
                        applyEnrichment(enrichment, to: existing)
                        if let desc = enrichment.descriptionText { accumulatedContext += "\nLink Summary: \(desc)" }
                    }
                }
            }
            
            // Apply contextual Location -> Foursquare -> DuckDuckGo enrichment
            var effectiveLocation: CLLocation? = nil
            var hasUserOverride = false
            
            if let locationService {
                // Session Context Override for Updates
                effectiveLocation = await locationService.getCurrentLocation()
                
                // Fallback: Check raw payload for location metadata if unavailable (e.g. reprocessing)
                if effectiveLocation == nil, let data = rawPayload {
                     if let source = CGImageSourceCreateWithData(data as CFData, nil),
                        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                        let gps = props["{GPS}"] as? [String: Any],
                        let lat = gps["Latitude"] as? Double,
                        let latRef = gps["LatitudeRef"] as? String,
                        let lng = gps["Longitude"] as? Double,
                        let lngRef = gps["LongitudeRef"] as? String {
                         
                         let finalLat = latRef == "S" ? -lat : lat
                         let finalLng = lngRef == "W" ? -lng : lng
                         effectiveLocation = CLLocation(latitude: finalLat, longitude: finalLng)
                         DiverLogger.pipeline.debug("Extracted Location from Image Metadata: \(finalLat), \(finalLng)")
                     }
                }
                
                if let descriptorSessionID = descriptor?.sessionID ?? existing.sessionID {
                     let fetchSession = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == descriptorSessionID })
                     if let session = try? modelContext.fetch(fetchSession).first {
                         if let lat = session.latitude, let lng = session.longitude {
                             effectiveLocation = CLLocation(latitude: lat, longitude: lng)
                             DiverLogger.pipeline.debug("Using Session Location Override for Update: \(lat), \(lng)")
                         }
                         if let summary = session.summary {
                             accumulatedContext += "\n\nSESSION CONTEXT:\n\(summary)\n"
                         }
                         if let locName = session.locationName, !locName.isEmpty {
                             hasUserOverride = true
                         }
                     }
                }

                if let location = effectiveLocation {
                    let coords = location.coordinate
                    
                    // 1. Foursquare Place Lookup
                    if let foursquareService, let fsEnrichment = try await foursquareService.enrich(location: coords) {
                        applyEnrichment(fsEnrichment, to: existing)
                        accumulatedContext += "\nFoursquare: \(fsEnrichment.title ?? "Unknown") - \(fsEnrichment.categories.joined(separator: ", "))"
                        
                        if let venueName = fsEnrichment.title, let duckDuckGoService {
                            if let ddgEnrichment = try await duckDuckGoService.enrich(query: venueName, location: coords) {
                                applyEnrichment(ddgEnrichment, to: existing, overwriteTitle: true)
                                accumulatedContext += "\nDuckDuckGo: \(ddgEnrichment.title ?? "Unknown") - \(ddgEnrichment.descriptionText ?? "")"
                            }
                        }
                    }
                }
            }

            if existing.modality == nil || existing.modality?.isEmpty == true {
                existing.modality = resolvedModality
            }
            if existing.tags.isEmpty, !resolvedTags.isEmpty {
                existing.tags = resolvedTags
            }
            if existing.createdAt == Date.distantPast {
                existing.createdAt = input.createdAt
            }
            if existing.rawPayload == nil {
                existing.rawPayload = rawPayload
            }
            if existing.attributionID == nil {
                existing.attributionID = descriptor?.attributionID
            }
            if existing.masterCaptureID == nil {
                existing.masterCaptureID = descriptor?.masterCaptureID
            }
            if existing.sessionID == nil {
                existing.sessionID = descriptor?.sessionID
            }

            // Mark as ready check removed from here, moving to the very end of the process function

            // Update Phase 1 fields
            existing.updatedAt = Date()
            if existing.source == nil, let source = input.source {
                existing.source = source
            }
            // Determine purposes
            var finalPurposes = descriptor?.purposes ?? []
             if finalPurposes.isEmpty, let legacyPurpose = descriptor?.purpose {
                finalPurposes.append(legacyPurpose)
            }
            // Append existing purposes if we are updating, don't overwrite blindly unless intentional
            // For now, let's union them
            let existingPurposes = Set(existing.purposes)
            let newPurposes = Set(finalPurposes)
            let combinedPurposes = Array(existingPurposes.union(newPurposes)).sorted()
            
            if combinedPurposes.isEmpty && existingPurposes.isEmpty {
                // Try to determine if truly empty
                // ... (LLM logic same as above if needed, or skip for updates to save perf)
            } else if !newPurposes.isEmpty {
                 existing.purposes = combinedPurposes
                 // Link new ones
                 for purpose in newPurposes {
                     if !existingPurposes.contains(purpose) {
                         try await linkToParent(item: existing, purpose: purpose)
                     }
                 }
            }
            
            // Background LLM Re-analysis for Updates (Second Verification Pass)
            let finalLocation = effectiveLocation
            let isUserLocationFixed = hasUserOverride
            let contactService = Services.shared.contactService
            let inputURLString = input.url
            let interimAccumulatedContext = accumulatedContext
            let interimResolvedId = resolvedId
            
            // Trigger reprocessing with full enrichment
            existing.processingLog.append("\(Date().formatted()): Reprocessing existing item: \(existing.title ?? "Untitled").")
            
            // Increment failure count if we are coming back from a failed state
            if existing.status == .failed {
                existing.failureCount += 1
                if existing.failureCount > 2 {
                    DiverLogger.pipeline.warning("Item \(existing.id) failed too many times. Deleting.")
                    modelContext.delete(existing)
                    modelContext.delete(input)
                    try? modelContext.save()
                    return existing // Returning detached item, but it's deleted
                }
            }

            Task {
                var localAccumulatedContext = interimAccumulatedContext
                let results = await self.performParallelEnrichment(
                    resolvedId: interimResolvedId,
                    descriptor: descriptor,
                    rawPayload: rawPayload,
                    finalLocation: finalLocation,
                    isUserLocationFixed: isUserLocationFixed,
                    inputURLString: inputURLString,
                    enrichmentService: enrichmentService,
                    locationService: locationService,
                    foursquareService: foursquareService,
                    duckDuckGoService: duckDuckGoService,
                    weatherService: weatherService,
                    activityService: activityService,
                    contactService: contactService
                )
                
                await MainActor.run {
                    for result in results {
                        self.processParallelResult(result, to: existing, accumulatedContext: &localAccumulatedContext)
                    }
                }
                
                await performLLMAnalysis(for: existing, descriptor: descriptor, accumulatedContext: localAccumulatedContext)
            }
            
            // Fix looping/inbox bug: Delete input after processing
            modelContext.delete(input)
            
            return existing
        }

        DiverLogger.pipeline.debug("Creating new ProcessedItem - id: \(resolvedId), title: \(resolvedTitle)")

        let processed = ProcessedItem(
            id: resolvedId,
            inputId: input.id.uuidString,
            url: input.url,
            title: resolvedTitle,
            summary: resolvedSummary,
            entityType: resolvedEntityType,
            modality: resolvedModality,
            tags: resolvedTags,
            createdAt: input.createdAt,
            rawPayload: rawPayload,
            status: ProcessingStatus.ready,
            source: input.source,
            attributionID: descriptor?.attributionID,
            masterCaptureID: descriptor?.masterCaptureID,
            sessionID: descriptor?.sessionID,
            categories: descriptor?.categories ?? []
        )
        
        // Insert immediately for live UI updates
        processed.status = .processing
        processed.processingLog.append("\(Date().formatted()): Starting new item pipeline.")
        print("🚀 [LocalPipeline] Starting pipeline for item: \(processed.id)")
        modelContext.insert(processed)
        try? modelContext.save()
        
        var accumulatedContext = ""
        

        
        // Apply contextual Location -> Foursquare -> DuckDuckGo enrichment
        // Apply contextual Location -> Foursquare -> DuckDuckGo -> Weather -> Activity in PARALLEL
        // Apply contextual Location -> Foursquare -> DuckDuckGo -> Weather -> Activity -> Link in PARALLEL
        // Apply contextual Location -> Foursquare -> DuckDuckGo -> Weather -> Activity in PARALLEL
        // Apply contextual Location -> Foursquare -> DuckDuckGo -> Weather -> Activity -> Link in PARALLEL
        var currentLocation = await locationService?.getCurrentLocation()
        
        // SESSION CONTEXT OVERRIDE
        var hasUserOverride = false
        if let sessionID = descriptor?.sessionID ?? processed.sessionID {
             let fetchSession = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
             if let session = try? modelContext.fetch(fetchSession).first {
                 if let lat = session.latitude, let lng = session.longitude {
                     // Use session location if explicitly set (e.g. from map selection or edit)
                     currentLocation = CLLocation(latitude: lat, longitude: lng)
                     DiverLogger.pipeline.debug("Using Session Location Override: \(lat), \(lng)")
                 }
                 if let locName = session.locationName, !locName.isEmpty {
                     hasUserOverride = true
                 }
             }
        }
        
        // Capture immutable copy for tasks
        let finalLocation = currentLocation
        let isUserLocationFixed = hasUserOverride
        
        let contactService = Services.shared.contactService
        let inputURLString = input.url
        
        let results = await performParallelEnrichment(
            resolvedId: resolvedId,
            descriptor: descriptor,
            rawPayload: rawPayload,
            finalLocation: finalLocation,
            isUserLocationFixed: isUserLocationFixed,
            inputURLString: inputURLString,
            enrichmentService: enrichmentService,
            locationService: locationService,
            foursquareService: foursquareService,
            duckDuckGoService: duckDuckGoService,
            weatherService: weatherService,
            activityService: activityService,
            contactService: contactService
        )
        
        for result in results {
            processParallelResult(result, to: processed, accumulatedContext: &accumulatedContext)
        }
        processed.processingLog.append("\(Date().formatted()): Parallel enrichment complete.")
        print("✅ [LocalPipeline] Parallel enrichment complete for \(processed.id)")
        
        // Secondary LLM Analysis
        await performLLMAnalysis(for: processed, descriptor: descriptor, accumulatedContext: accumulatedContext)
        // Trigger live UI update
        try? modelContext.save()
        
        // 4. QR Code Handling
        // If the descriptor says it's a QR code, or we detected one (future), save the context
        if resolvedEntityType == DiverItemType.qrCode.rawValue, let payload = resolvedSummary {
             processed.qrContext = QRCodeContext(payload: payload)
        }




        
        // Determine purpose if missing (LLM fallback)
        var finalPurposes = descriptor?.purposes ?? []
        // Fallback checks
        if finalPurposes.isEmpty, let legacyPurpose = descriptor?.purpose {
            finalPurposes.append(legacyPurpose)
        }
        

        // 5. LLM Analysis (Background "Second Pass")
        // User Requirement: "verification pass should always be run in the background after running the first UI pass"
        // We spawn a task to allow the function to return the 'ready' item immediately for UI display.
        Task {
            await performLLMAnalysis(for: processed, descriptor: descriptor, accumulatedContext: accumulatedContext)
        }

        if !finalPurposes.isEmpty {
            processed.purposes = finalPurposes
            for purpose in finalPurposes {
                try await linkToParent(item: processed, purpose: purpose)
            }
        }
        
        // Finalize Title Logic (Fallback: Text > Tags > UUID)
        finalizeTitle(for: processed)

        if let descriptor, let indexingService {
            try await indexingService.indexItem(descriptor)
        }

        if let descriptor {
            await updateDiverSession(from: descriptor)
        }

        // Extract high-level concepts from text content
        if processed.webContext?.textContent != nil {
            await extractConcepts(from: processed)
        }
        
        // Auto-create UserConcepts from tags/themes
        // Safety: Wrap in do/catch so auxiliary metadata failure doesn't fail the whole item processing
        do {
            try await autoCreateConcepts(from: processed)
        } catch {
            DiverLogger.pipeline.error("Failed to auto-create concepts for item \(resolvedId): \(error)")
            // Continue processing, do not rethrow
        }
        
        DiverLogger.storage.debug("Inserted new ProcessedItem - id: \(resolvedId)")
        
        // Fix looping/inbox bug: Delete input after processing
        modelContext.delete(input)

        // Trigger Session Summary Update
        if let sid = processed.sessionID {
            Task {
                await self.generateAndSaveSessionSummary(sessionID: sid)
            }
        }

        // Update Daily Narrative
        if let dailyService = Services.shared.dailyContextService {
            let summaryText = processed.summary ?? processed.title ?? "Processed Item"
            dailyService.addContext(summaryText)
            
            // Log contribution and current narrative state
            let timestamp = Date().formatted(date: .omitted, time: .standard)
            let currentNarrative = dailyService.dailySummary // Will be previous state until async update finishes, but acceptable
            processed.processingLog.append("\(timestamp): Added to Daily Narrative. Current Narrative Snapshot: \(currentNarrative)")
        }

        // Mark as ready before returning
        processed.status = .ready
        try? modelContext.save()

        return processed
    }


    public func refreshProcessedItems(
        enrichmentService: LinkEnrichmentService? = nil,
        locationService: LocationProvider? = nil,
        foursquareService: ContextualEnrichmentService? = nil,
        duckDuckGoService: ContextualEnrichmentService? = nil,
        weatherService: WeatherEnrichmentService? = nil,
        activityService: ActivityEnrichmentService? = nil,
        indexingService: KnowledgeGraphIndexingService? = nil
    ) async throws {
        let inputs = try modelContext.fetch(FetchDescriptor<LocalInput>())
        DiverLogger.pipeline.info("Refreshing \(inputs.count) processed items")

        for input in inputs {
            _ = try await process(
                input: input,
                enrichmentService: enrichmentService,
                locationService: locationService,
                foursquareService: foursquareService,
                duckDuckGoService: duckDuckGoService,
                weatherService: weatherService,
                activityService: activityService,
                indexingService: indexingService
            )
        }
        try modelContext.save()

        try modelContext.save()

        DiverLogger.pipeline.info("✅ Saved refreshed processed items to SwiftData. Total items: \(inputs.count)")
    }

    public func reprocessPipeline(
        cutoffDate: Date,
        enrichmentService: LinkEnrichmentService? = nil,
        locationService: LocationProvider? = nil,
        foursquareService: ContextualEnrichmentService? = nil,
        duckDuckGoService: ContextualEnrichmentService? = nil,
        weatherService: WeatherEnrichmentService? = nil,
        activityService: ActivityEnrichmentService? = nil,
        indexingService: KnowledgeGraphIndexingService? = nil,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        // 1. Clear existing queue items (processing or queued) to avoid duplicates or stalls
        // We delete the ProcessedItem but ensure the LocalInput is preserved for the main loop if within date range,
        // OR we just reset them to be processed immediately.
        // The user asked to "take everything ... out first", implying a reset of the queue.
        // We will fetch all pending items, delete them, and recreate them as inputs if needed.
        let queueFetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate {
                $0.statusRaw == "queued" ||
                $0.statusRaw == "processing" ||
                $0.statusRaw == "failed"
            }
        )
        if let queuedItems: [ProcessedItem] = try? modelContext.fetch(queueFetch) {
            DiverLogger.pipeline.info("Clearing \(queuedItems.count) items from queue before reprocessing.")
            for item in queuedItems {
                // Ensure LocalInput exists or recreate it
                if let inputIdStr = item.inputId, let inputID = UUID(uuidString: inputIdStr) {
                    // Check if input exists
                    let inputDesc = FetchDescriptor<LocalInput>(predicate: #Predicate { $0.id == inputID })
                    let existingInputs: [LocalInput]? = try? modelContext.fetch(inputDesc)
                    if existingInputs?.isEmpty ?? true {
                        // Recreate LocalInput if missing
                         let input = LocalInput(
                            id: inputID,
                            createdAt: item.createdAt,
                            url: item.url,
                            text: item.summary,
                            source: item.source,
                            inputType: item.entityType ?? "web",
                            rawPayload: item.rawPayload
                        )
                        modelContext.insert(input)
                    }
                }
                // Remove the stalled item
                modelContext.delete(item)
            }
            try? modelContext.save()
        }

        // Fetch items created after the cutoff
        let fetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.createdAt > cutoffDate }
        )
        let items = try modelContext.fetch(fetch)
        DiverLogger.pipeline.info("Reprocessing \(items.count) items created after \(cutoffDate)")
        
        var completedCount = 0
        let totalCount = Double(items.count)
        
        // Batched Processing for Concurrency Control
        let batchSize = 4
        let batches = items.chunked(into: batchSize)
        
        for (batchIndex, batch) in batches.enumerated() {
            DiverLogger.pipeline.debug("Processing batch \(batchIndex + 1)/\(batches.count)")
            
            var batchTasks: [Task<Void, Never>] = []
            
            for item in batch {
                let itemID = item.persistentModelID
                let previousPlaceID = item.placeContext?.placeID
                let previousPlaceName = item.placeContext?.name ?? item.location
                
                let task = Task(priority: .utility) { @MainActor in
                    // Fetch fresh instance to ensure MainActor safety
                    guard let freshItem = self.modelContext.model(for: itemID) as? ProcessedItem else { return }
                    
                    // Reconstruct LocalInput
                    let inputId = UUID(uuidString: freshItem.inputId ?? "") ?? UUID()
                    let input = LocalInput(
                        id: inputId,
                        createdAt: freshItem.createdAt,
                        url: freshItem.url,
                        text: freshItem.summary, // Use current summary as text input if original text is lost
                        source: freshItem.source,
                        inputType: freshItem.entityType ?? "web",
                        rawPayload: freshItem.rawPayload
                    )
                    
                    // Re-insert input to simulate fresh processing
                    self.modelContext.insert(input)
                    
                    // Reset status to queued
                    freshItem.status = .queued
                    freshItem.processingLog.append("\(Date().formatted()): Queued for maintenance reprocessing")
                    
                    do {
                        // Trigger process
                        let processed = try await self.process(
                            input: input,
                            descriptor: nil,
                            enrichmentService: enrichmentService,
                            locationService: nil, // Prevent using current GPS for historical items; rely on Session location
                            foursquareService: foursquareService,
                            duckDuckGoService: duckDuckGoService,
                            weatherService: weatherService,
                            activityService: activityService,
                            indexingService: indexingService
                        )
                        
                        // Conflict Detection
                        let newPlaceID = processed.placeContext?.placeID
                        let newPlaceName = processed.placeContext?.name ?? processed.location
                        
                        // If place ID changed (and wasn't nil before), flag it
                        if let oldID = previousPlaceID, let newID = newPlaceID, oldID != newID {
                            processed.status = .reviewRequired
                            processed.processingLog.append("\(Date().formatted()): ⚠️ Conflict: Place changed from '\(previousPlaceName ?? "Unknown")' to '\(newPlaceName ?? "Unknown")'. Please confirm purpose alignment.")
                        } else if previousPlaceID != nil && newPlaceID == nil {
                            // Lost place context?
                            processed.status = .reviewRequired
                            processed.processingLog.append("\(Date().formatted()): ⚠️ Conflict: Lost place context (was '\(previousPlaceName ?? "Unknown")')")
                        }
                    } catch {
                        DiverLogger.pipeline.error("Failed to reprocess item \(freshItem.id): \(error)")
                        freshItem.status = .failed
                        freshItem.processingLog.append("\(Date().formatted()): Reprocessing failed: \(error.localizedDescription)")
                    }
                }
                batchTasks.append(task)
            }
            
            // Await all tasks in the batch
            for task in batchTasks {
                _ = await task.result
            }
            
            // Save after each batch to persist progress and free memory pressure
            try? modelContext.save()
            
            // Update progress
             completedCount += batchSize
             let currentCount = min(Double(completedCount), totalCount) // Clamp
             if totalCount > 0 {
                 let progress = currentCount / totalCount
                 await MainActor.run {
                     progressHandler?(progress)
                 }
             }
        }
    }

    private func applyEnrichment(_ enrichment: EnrichmentData, to item: ProcessedItem, overwriteTitle: Bool = false) {
        if let title = enrichment.title {
            let currentTitle = item.title ?? ""
            if overwriteTitle || currentTitle.isEmpty || currentTitle.contains("://") || currentTitle.contains("www.") || currentTitle == "Untitled" || (item.url != nil && currentTitle == URL(string: item.url!)?.host) {
                item.title = title
            }
        }
        if let description = enrichment.descriptionText, item.summary == nil || item.summary?.isEmpty == true {
            item.summary = description
        }
        if !enrichment.categories.isEmpty || !enrichment.styleTags.isEmpty {
            let currentTags = Set(item.tags)
            let enrichmentTags = Set(enrichment.categories + enrichment.styleTags)
            let allTags = currentTags.union(enrichmentTags)
            item.tags = Array(allTags).sorted()
            
            if !enrichment.categories.isEmpty {
                 let currentCats = Set(item.categories)
                 let newCats = Set(enrichment.categories)
                 item.categories = Array(currentCats.union(newCats)).sorted()
            }
        }
        if let location = enrichment.location, item.location == nil || item.location?.isEmpty == true {
            item.location = location
        }
        if let price = enrichment.price, item.price == nil || item.price == 0 {
            item.price = price
        }
        if let rating = enrichment.rating, item.rating == nil || item.rating == 0 {
            item.rating = rating
        }
        
        // Persist structured contexts if available
        if let newWeb = enrichment.webContext {
            if let existingWeb = item.webContext {
                // Merge logic: existing preferred for snapshot if new is nil?
                // Or new preferred? New enrichment implies a fresh fetch.
                // However, for re-processing where fetch might fail (headless browser issue),
                // we should preserve the old snapshot if the new one is nil.
                
                var merged = newWeb
                if merged.snapshotURL == nil { merged.snapshotURL = existingWeb.snapshotURL }
                if merged.textContent == nil { merged.textContent = existingWeb.textContent }
                if merged.structuredData == nil { merged.structuredData = existingWeb.structuredData }
                if merged.siteName == nil { merged.siteName = existingWeb.siteName }
                
                item.webContext = merged
            } else {
                item.webContext = newWeb
            }
        }
        if let doc = enrichment.documentContext { item.documentContext = doc }
        if let place = enrichment.placeContext { item.placeContext = place }
        if !enrichment.questions.isEmpty { item.questions = enrichment.questions }
        // questions are handled by the ViewModel/UI during the review phase
    }

    private func resolveId(for input: LocalInput) -> String {
        if let urlString = input.url, let url = URL(string: urlString) {
            return DiverLinkWrapper.id(for: url)
        }
        return input.id.uuidString
    }

    private func deriveTitle(for input: LocalInput) -> String {
        if let urlString = input.url, let url = URL(string: urlString) {
            return url.host ?? urlString
        }
        if let text = input.text, !text.isEmpty {
            return String(text.prefix(80))
        }
        return "Untitled"
    }

    private func encodePayload(input: LocalInput, descriptor: DiverItemDescriptor?) throws -> Data {
        let payload = LocalPipelinePayload(input: .init(from: input), descriptor: descriptor)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    private func linkToParent(item: ProcessedItem, purpose: String) async throws {
        // Find or create a parent record for this purpose
        let fetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.title == purpose && $0.entityType == "activity" }
        )
        
        let parent: ProcessedItem
        if let existingParent = try modelContext.fetch(fetch).first {
            parent = existingParent
        } else {
            parent = ProcessedItem(
                id: UUID().uuidString,
                title: purpose,
                entityType: "activity",
                status: .ready
            )
            modelContext.insert(parent)
        }
        
        item.parentItem = parent
        DiverLogger.pipeline.info("Linked item \(item.id) to parent activity '\(purpose)'")
    }

    private func extractConcepts(from item: ProcessedItem) async {
        guard let text = item.webContext?.textContent, !text.isEmpty else { return }
        
        // Include purpose/activity in the analysis input so concepts reflect both content and intent
        var combinedText = text
        if !item.purposes.isEmpty {
            combinedText += "\n\nUser Context/Purpose: \(item.purposes.joined(separator: ", "))"
        }
        if let activity = item.activityContext {
            combinedText += "\n\nPhysical Activity: \(activity.type)"
        }
        
        let contextService = ContextQuestionService()
        let dummyData = EnrichmentData(title: item.title, descriptionText: combinedText)

        if let (summary, statements, _, tags) = try? await contextService.processContext(from: dummyData) {
            // Merge generated tags into item tags
            let existing = Set(item.tags)
            let newTags = Set(tags)
            let combined = existing.union(newTags)
            item.tags = Array(combined).sorted()
            
            // Save generated statements as context/questions
            if !statements.isEmpty {
                item.questions = statements
            }
            
            // Update summary if missing
            if item.summary == nil || item.summary?.isEmpty == true {
                item.summary = summary
            }
            
            DiverLogger.pipeline.debug("Extracted concepts from web content: \(tags)")
        }
    }

    private func autoCreateConcepts(from item: ProcessedItem) async throws {
        // Normalize and separate candidates
        let purposeCandidates = Set(item.purposes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        
        // Identify product candidates ONLY if entity type is product
        var productCandidates = Set<String>()
        if item.entityType?.lowercased() == "product" {
             productCandidates = Set(item.categories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        }
        
        // Other candidates (tags, themes, and generic categories if not a product)
        let otherCandidates = Set(
            (item.tags + item.categories + item.themes)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        
        let allCandidates = purposeCandidates.union(productCandidates).union(otherCandidates)
        
        guard !allCandidates.isEmpty else { return }

        for candidate in allCandidates {
            // Check if concept exists
            let descriptor = FetchDescriptor<UserConcept>(
                predicate: #Predicate<UserConcept> { $0.name == candidate }
            )
            
            // Determine weight: 3.0 for products, 2.0 for purposes, 1.0 for others
            // Priority: Product > Purpose > Other
            var weight = 1.0
            if productCandidates.contains(candidate) {
                weight = 3.0
            } else if purposeCandidates.contains(candidate) {
                weight = 2.0
            }
            
            if let count = try? modelContext.fetchCount(descriptor), count == 0 {
                let concept = UserConcept(
                    name: candidate,
                    definition: "Auto-created from item metadata",
                    weight: weight
                )
                modelContext.insert(concept)
                DiverLogger.pipeline.debug("Auto-created UserConcept: '\(candidate)' with weight \(weight)")
            } else if weight > 1.0 {
                // Optional: We could upgrade weights of existing concepts here if we wanted strictly enforced weights,
                // but respecting the "created from" instruction, we stick to new ones only for now.
            }
        }
    }
    private func updateDiverSession(from descriptor: DiverItemDescriptor) async {
        guard let sessionID = descriptor.sessionID else { return }
        
        // Fetch existing or create new
        let fetch = FetchDescriptor<DiverSession>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        
        let session: DiverSession
        if let existing = try? modelContext.fetch(fetch).first {
             session = existing
        } else {
             session = DiverSession(sessionID: sessionID)
             modelContext.insert(session)
             DiverLogger.pipeline.debug("Created new DiverSession for session: \(sessionID)")
        }
        
        // Update fields if present in descriptor
        // We prioritize the most recent location info
        if let lat = descriptor.latitude { session.latitude = lat }
        if let lng = descriptor.longitude { session.longitude = lng }
        if let pid = descriptor.placeID { session.placeID = pid }
        if let loc = descriptor.location { session.locationName = loc }
        
        // Update timestamp to now to reflect latest activity
        session.updatedAt = Date()
        
        // If title is currently nil or date-based, try to set a better one based on the master item?
        // For now, we leave title management to the user or later inference.
    }

    private func performLLMAnalysis(for item: ProcessedItem, descriptor: DiverItemDescriptor?, accumulatedContext: String) async {
        let contextService = ContextQuestionService()
        
        // Fetch Session Context to inform intelligence
        var sessionContext = ""
        if let sessionID = item.sessionID {
            let currentID = item.id
            let sessionDesc = FetchDescriptor<ProcessedItem>(
                predicate: #Predicate { $0.sessionID == sessionID && $0.id != currentID },
                sortBy: [SortDescriptor(\.createdAt)]
            )
            if let siblings = try? modelContext.fetch(sessionDesc) {
                let text = siblings.compactMap { sibling in
                    let t = sibling.title ?? "Untitled"
                    let s = sibling.summary ?? ""
                    return "- \(t): \(s)"
                }.joined(separator: "\n")
                
                if !text.isEmpty {
                    sessionContext = "\n\n=== Session Context ===\nDuring this session, the user also captured:\n" + text
                }
            }
        }
        
        // Pass full context; ContextQuestionService now handles chaining/chunking for large inputs
        let fullContext = (item.summary ?? "") + "\n\n--- Context ---\n" + accumulatedContext + sessionContext
        
        // Override location with Session Metadata if available to ensure LLM respects user edit
        var effectiveLocationName = item.location
        if let sessionID = item.sessionID {
            let sessionDesc = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
            if let session = try? modelContext.fetch(sessionDesc).first, let locName = session.locationName {
                effectiveLocationName = locName
            }
        }

        let currentData = EnrichmentData(
            title: item.title,
            descriptionText: fullContext,
            categories: item.tags,
            location: effectiveLocationName,
            price: item.price,
            rating: item.rating
        )
        
        do {
            print("🧠 [LocalPipeline] Starting LLM Analysis for item: \(item.id)")
            let (summary, questions, purpose, tags) = try await contextService.processContext(from: currentData)
            
            // Save generated questions for the UI to present
            item.questions = questions
            
            // Update summary with LLM refinement if available
            if let s = summary, !s.isEmpty {
                item.summary = s
                item.processingLog.append("\(Date().formatted()): LLM updated summary: \(s.prefix(50))...")
            }
            
            // Generate and merge purposes
            if let p = purpose, !p.isEmpty {
                if !item.purposes.contains(p) {
                    item.purposes.append(p)
                }
            }
            
            // Merge tags
            if !tags.isEmpty {
                let currentTags = Set(item.tags)
                let newTags = Set(tags)
                item.tags = Array(currentTags.union(newTags)).sorted()
            }
            
            item.status = .ready // Finalize status
            item.processingLog.append("\(Date().formatted()): LLM Analysis Complete. Finalized.")
            print("🏁 [LocalPipeline] LLM Analysis complete for \(item.id)")
            try modelContext.save()
            DiverLogger.pipeline.debug("LLM Analysis Complete for item \(item.id). Updated summary: \(summary != nil), Purpose: \(purpose != nil)")
        } catch {
            print("❌ [LocalPipeline] LLM Analysis Failed for \(item.id): \(error.localizedDescription)")
            item.failureCount += 1
            item.processingLog.append("\(Date().formatted()): LLM Analysis Failed: \(error.localizedDescription)")
            DiverLogger.pipeline.error("LLM Analysis Failed: \(error)")
            
            if item.failureCount > 2 {
                DiverLogger.pipeline.warning("Item \(item.id) suffered persistent LLM failure. Deleting.")
                modelContext.delete(item)
            } else {
                item.status = .reviewRequired
            }
            try? modelContext.save()
        }
    }
    
    // MARK: - Parallel Enrichment Helpers
    
    private struct ParallelEnrichmentResult: Sendable {
        var link: EnrichmentData?
        var foursquare: EnrichmentData?
        var duckDuckGo: EnrichmentData?
        var coverImagePath: String?
        var productConcepts: [String]?
        var weather: WeatherContext?
        var activity: ActivityContext?
        var liveEventContext: String?
    }

    private func performParallelEnrichment(
        resolvedId: String,
        descriptor: DiverItemDescriptor?,
        rawPayload: Data?,
        finalLocation: CLLocation?,
        isUserLocationFixed: Bool,
        inputURLString: String?,
        enrichmentService: LinkEnrichmentService?,
        locationService: LocationProvider?,
        foursquareService: ContextualEnrichmentService?,
        duckDuckGoService: ContextualEnrichmentService?,
        weatherService: WeatherEnrichmentService?,
        activityService: ActivityEnrichmentService?,
        contactService: ContactServiceProvider?
    ) async -> [ParallelEnrichmentResult] {
        
        await withTaskGroup(of: ParallelEnrichmentResult?.self) { group in
            // 1. Link Enrichment (Web Metadata)
            group.addTask {
                 guard let urlString = inputURLString, let url = URL(string: urlString), let enrichmentService else { return nil }
                 if url.scheme?.lowercased().hasPrefix("secretatomics") == true { return nil }
                 if let enrichment = try? await self.withTimeout(seconds: 30, operation: {
                     try await enrichmentService.enrich(url: url)
                 }) {
                    return ParallelEnrichmentResult(link: enrichment)
                 }
                 return nil
            }

            // 2. Foursquare + DuckDuckGo Chain
            group.addTask {
                guard let location = finalLocation else { return nil }
                if !isUserLocationFixed, let contactService = contactService,
                   let homeLoc = try? await contactService.getHomeLocation() {
                     if location.distance(from: homeLoc) < 75 {
                         let explicitLocationName = descriptor?.location
                         let isHomeName = explicitLocationName?.lowercased() == "home"
                         let isGenericOrEmpty = explicitLocationName == nil || explicitLocationName?.isEmpty == true
                         if isHomeName || isGenericOrEmpty {
                             let placeCtx = PlaceContext(name: "Home", categories: ["Home", "Personal"], placeID: "home-location", address: nil, rating: nil, isOpen: true)
                             let homeData = EnrichmentData(title: "Home", descriptionText: "User's Home Location", image: nil, categories: ["Home"], styleTags: ["Personal"], location: "Home", placeContext: placeCtx)
                             return ParallelEnrichmentResult(foursquare: homeData)
                         }
                     }
                }
                
                guard let foursquareService else { return nil }
                let coords = location.coordinate
                if let fsEnrichment = try? await self.withTimeout(seconds: 15, operation: {
                    try await foursquareService.enrich(location: coords)
                }) {
                    var result = ParallelEnrichmentResult(foursquare: fsEnrichment)
                    if let venueName = fsEnrichment.title {
                        if let ddgService = duckDuckGoService {
                            if let ddgEnrichment = try? await self.withTimeout(seconds: 10, operation: {
                                try await ddgService.enrich(query: venueName, location: coords)
                            }) {
                                result.duckDuckGo = ddgEnrichment
                            }
                            if let eventContext = try? await self.withTimeout(seconds: 10, operation: {
                                try await self.searchLiveEvents(place: venueName, service: ddgService)
                            }) {
                                result.liveEventContext = eventContext
                            }
                        }
                    }
                    return result
                }
                return nil
            }
            
            // 3. Weather
            group.addTask {
                guard let location = finalLocation, let weatherService else { return nil }
                if let weather = await weatherService.fetchWeather(for: location) {
                    return ParallelEnrichmentResult(weather: weather)
                }
                return nil
            }
            
            // 4. Activity
            group.addTask {
                guard let activityService else { return nil }
                if let activity = await activityService.fetchCurrentActivity() {
                    return ParallelEnrichmentResult(activity: activity)
                }
                return nil
            }
            
            // 5. Cover Image
            group.addTask {
                 let imageURL = descriptor?.coverImageURL
                 var imageData: Data?
                 if let url = imageURL {
                     if url.isFileURL { imageData = try? Data(contentsOf: url) }
                     else if let (data, _) = try? await URLSession.shared.data(from: url) { imageData = data }
                 }
                 if imageData == nil { imageData = rawPayload }
                 guard let data = imageData else { return nil }

                 do {
                     let filename = "\(resolvedId)-cover.jpg"
                     let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                     let dir = docs.appendingPathComponent("thumbnails", isDirectory: true)
                     try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                     let fileURL = dir.appendingPathComponent(filename)
                     try data.write(to: fileURL)
                     return ParallelEnrichmentResult(coverImagePath: fileURL.path)
                 } catch {
                     print("❌ LocalPipeline: Failed to save cover image: \(error)")
                     return nil
                 }
            }
            
            // 6. Product Concepts & URL
            let isProduct = descriptor?.type == .product
            let productQuery = descriptor?.title
            let ddgService = duckDuckGoService
            group.addTask {
                if isProduct, let query = productQuery, let service = ddgService {
                    do {
                         let data = try await self.withTimeout(seconds: 15, operation: {
                             try await service.enrich(query: query, location: nil)
                         })
                         return ParallelEnrichmentResult(duckDuckGo: data)
                    } catch {
                        print("Failed to enrich product: \(error)")
                    }
                }
                return nil
            }

            var results: [ParallelEnrichmentResult] = []
            for await result in group {
                if let r = result { results.append(r) }
            }
            return results
        }
    }

    private func processParallelResult(_ result: ParallelEnrichmentResult, to item: ProcessedItem, accumulatedContext: inout String) {
        if let linkData = result.link {
            applyEnrichment(linkData, to: item)
            if let desc = linkData.descriptionText { accumulatedContext += "\nLink Summary: \(desc)" }
        }
        if let fs = result.foursquare {
            applyEnrichment(fs, to: item)
            accumulatedContext += "\nNearby Context: \(fs.title ?? ""), Categories: \(fs.categories.joined(separator: ", "))"
        }
        if let ddg = result.duckDuckGo {
            applyEnrichment(ddg, to: item, overwriteTitle: true)
            accumulatedContext += "\nDuckDuckGo: \(ddg.title ?? "Unknown") - \(ddg.descriptionText ?? "")"
        }
        if let events = result.liveEventContext {
            accumulatedContext += "\n\nLIVE EVENTS:\n\(events)"
        }
        if let w = result.weather {
            accumulatedContext += "\nWeather: \(w.condition), \(Int(w.temperatureCelsius))°C"
            item.weatherContext = w
        }
        if let a = result.activity {
            accumulatedContext += "\nActivity: \(a.type) (\(a.confidence))"
            item.activityContext = a
        }
        if let path = result.coverImagePath {
            if item.webContext == nil { item.webContext = WebContext(snapshotURL: path) }
            else { item.webContext?.snapshotURL = path }
        }
        if let concepts = result.productConcepts {
            let currentTags = Set(item.tags)
            let newTags = Set(concepts)
            item.tags = Array(currentTags.union(newTags)).sorted()
        }
    }
    
    private func searchLiveEvents(place: String, service: ContextualEnrichmentService) async -> String? {
        let date = Date().formatted(date: .abbreviated, time: .omitted)
        let query = "\(place) events \(date)"
        
        do {
            if let result = try await service.enrich(query: query, location: nil) {
                // Return description if relevant
                let desc = result.descriptionText ?? ""
                if !desc.isEmpty && desc.count > 20 {
                     return "Events at \(place) on \(date): \(desc)"
                }
            }
        } catch {
            // ignore
        }
        return nil
    }
    // MARK: - Session Summarization
    private func generateAndSaveSessionSummary(sessionID: String) async {
        // Temporarily disabled to resolve CoreData migration conflict
        // TODO: Re-enable after introducing VersionedSchema
        /*
        let fetchItems = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.sessionID == sessionID })
        let fetchMeta = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
        
        do {
            let items = try modelContext.fetch(fetchItems)
            if items.isEmpty { return }
            
            // Limit to last 20 items to avoid token limits and keep it relevant
            let recentItems = items.sorted(by: { $0.createdAt < $1.createdAt }).suffix(20)
            
            var combinedText = ""
            for item in recentItems {
                combinedText += "Item: \(item.title ?? "Unknown")\n"
                if let summary = item.summary { combinedText += "Description: \(summary)\n" }
                if !item.purposes.isEmpty { combinedText += "Intents: \(item.purposes.joined(separator: ", "))\n" }
                combinedText += "---\n"
            }
            
            let service = ContextQuestionService()
            let summary = try await service.summarizeText(combinedText)
            
            if let meta = try modelContext.fetch(fetchMeta).first {
                meta.summary = summary
                try modelContext.save()
                DiverLogger.pipeline.info("✅ Auto-generated summary for session \(sessionID)")
            }
        } catch {
            DiverLogger.pipeline.error("Failed to auto-generate session summary: \(error)")
        }
        */
    }
    
    // MARK: - Helper Logic
    
    private func finalizeTitle(for item: ProcessedItem) {
        // 1. Check if current title is valid (Prominent Text / Metadata)
        let currentTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isPlaceholder = currentTitle.isEmpty || currentTitle == "Untitled" || currentTitle == item.id || currentTitle.contains("http") || currentTitle.contains("://")
        
        // If we have a good title, stick with it
        if !isPlaceholder { return }
        
        // 2. Try LLM Tags / Themes
        // Combine themes and tags, prioritize themes
        let candidates = item.themes + item.tags
        if let bestTag = candidates.first(where: { !$0.isEmpty }) {
            item.title = bestTag.capitalized
            return
        }
        
        // 3. Try Summary / Transcription (Prominent Text Fallback)
        if let text = item.transcription ?? item.summary, !text.isEmpty {
            // Take first sentence or first few words
            let cleanText = text.replacingOccurrences(of: "\n", with: " ")
            let prefix = String(cleanText.prefix(50))
            item.title = prefix + (cleanText.count > 50 ? "..." : "")
            return
        }
        
        // 4. UUID Fallback (Default)
        // If we are here, stick with ID or ensure it is set
        if item.title == nil {
            item.title = item.id
        }
    }
    // MARK: - Diagnostics
    public func runDataDiagnostics() {
        DiverLogger.pipeline.info("🔍 STARTING DATA DIAGNOSTICS...")
        
        do {
            // 1. Check ProcessedItems (The "Events")
            let itemDesc = FetchDescriptor<ProcessedItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            let items = try modelContext.fetch(itemDesc)
            DiverLogger.pipeline.info("📊 Total ProcessedItems found: \(items.count)")
            
            if items.isEmpty {
                DiverLogger.pipeline.error("⚠️ NO ProcessedItems found! Data might be zeroed out.")
            } else {
                for (i, item) in items.prefix(10).enumerated() {
                    DiverLogger.pipeline.info("   Item [\(i)]: \(item.title ?? "Untitled") (ID: \(item.id), Created: \(item.createdAt.formatted()))")
                    if !item.processingLog.isEmpty {
                         DiverLogger.pipeline.info("      Logs: \(item.processingLog.suffix(3))")
                    }
                }
            }
            
            // 2. Check DiverSession
            let sessionDesc = FetchDescriptor<DiverSession>()
            let sessions = try modelContext.fetch(sessionDesc)
            DiverLogger.pipeline.info("📊 Total DiverSession found: \(sessions.count)")
            
            if sessions.isEmpty && !items.isEmpty {
                DiverLogger.pipeline.warning("⚠️ No DiverSession found but Items exist. Attempting to REGENERATE Sessions...")
                try regenerateMissingSessions()
            } else {
                 for (i, session) in sessions.prefix(5).enumerated() {
                     DiverLogger.pipeline.info("   Session [\(i)]: ID \(session.sessionID) - Loc: \(session.locationName ?? "nil")")
                 }
            }
            
            // 3. Recover Stuck Items
            try recoverStuckItems()
            
            // 4. Consolidate Sessions
            try consolidateSessions()
            
        } catch {
            DiverLogger.pipeline.error("❌ Diagnostics failed to fetch data: \(error)")
        }
        
        DiverLogger.pipeline.info("🔍 DATA DIAGNOSTICS COMPLETE")
    }

    private func regenerateMissingSessions() throws {
        let itemDesc = FetchDescriptor<ProcessedItem>()
        let items = try modelContext.fetch(itemDesc)
        
        let grouped = Dictionary(grouping: items, by: { $0.sessionID })
        var restoredCount = 0
        
        for (sessionID, sessionItems) in grouped {
            guard let sessionID = sessionID else { continue }
            
            // Check if exists
            let fetch = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
            if (try? modelContext.fetch(fetch).count) == 0 {
                // Create new session
                let session = DiverSession(sessionID: sessionID)
                
                // Infer details from items
                let sorted = sessionItems.sorted(by: { $0.createdAt < $1.createdAt })
                if let first = sorted.first { session.createdAt = first.createdAt }
                if let last = sorted.last { session.updatedAt = last.updatedAt }
                
                // Try to find a location
                if let locItem = sorted.first(where: { $0.location != nil }) {
                    session.locationName = locItem.location
                    session.placeID = locItem.placeContext?.placeID
                }
                
                modelContext.insert(session)
                restoredCount += 1
            }
        }
        
        if restoredCount > 0 {
            try modelContext.save()
            DiverLogger.pipeline.info("✅ REGENERATED \(restoredCount) MISSING SESSIONS from items.")
        } else {
            DiverLogger.pipeline.info("ℹ️ No sessions needed regeneration.")
        }
    }


    private func recoverStuckItems() throws {
        // Fetch items stuck in 'processing' state
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.statusRaw == "processing" })
        
        let stuckItems = try modelContext.fetch(fetch)
        
        if !stuckItems.isEmpty {
            DiverLogger.pipeline.warning("⚠️ Found \(stuckItems.count) STUCK items in processing state. Resetting to QUEUED.")
            for item in stuckItems {
                item.status = .queued
                item.processingLog.append("\(Date().formatted()): System detected stuck state (crash recovery). Resetting to queued.")
            }
            try modelContext.save()
            DiverLogger.pipeline.info("✅ Recovered \(stuckItems.count) stuck items.")
        } else {
            DiverLogger.pipeline.info("ℹ️ No stuck items found.")
        }
    }
    
    private func consolidateSessions() throws {
        // Fetch all sessions sorted by time
        let desc = FetchDescriptor<DiverSession>(sortBy: [SortDescriptor(\.createdAt)])
        let sessions = try modelContext.fetch(desc)
        
        guard !sessions.isEmpty else { return }
        
        var sessionsToDelete: [DiverSession] = []
        var mergedCount = 0
        
        // O(N) pass - since sorted by createdAt, duplicates should be adjacent
        var master = sessions[0]
        
        for i in 1..<sessions.count {
            let current = sessions[i]
            
            // Check proximity
            let timeDelta = abs(current.createdAt.timeIntervalSince(master.createdAt))
            let isTimeClose = timeDelta < 5.0 // 5 second window for "Same Timestamp"
            
            // Location check
            var isLocClose = false
            if let lat1 = master.latitude, let lon1 = master.longitude,
               let lat2 = current.latitude, let lon2 = current.longitude {
                let dist = abs(lat1 - lat2) + abs(lon1 - lon2)
                isLocClose = dist < 0.0005 // Approx 50m
            }
            
            // Logic: Merge if time AND location match. 
            // If location is missing for both, but time matches exactly?
            // "consolidate reprocessed items with the same session timestamp and GPS coordinate" implies GPS is key.
            
            if isTimeClose && isLocClose {
                // Merge current into master
                let currentID = current.sessionID
                let masterID = master.sessionID
                
                // Re-assign items
                let itemDesc = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.sessionID == currentID })
                if let items = try? modelContext.fetch(itemDesc) {
                    for item in items {
                        item.sessionID = masterID
                    }
                }
                
                sessionsToDelete.append(current)
                mergedCount += 1
            } else {
                // Current becomes new master
                master = current
            }
        }
        
        if !sessionsToDelete.isEmpty {
            for session in sessionsToDelete {
                modelContext.delete(session)
            }
            try modelContext.save()
            DiverLogger.pipeline.info("✅ Consolidated \(mergedCount) fragmented sessions into master sessions.")
        } else {
             DiverLogger.pipeline.info("ℹ️ No fragmented sessions found to consolidate.")
        }
    }

    /// Helper to wrap an operation with a timeout
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            
            guard let result = try await group.next() else {
                throw URLError(.cannotParseResponse)
            }
            
            group.cancelAll()
            return result
        }
    }
}

private struct LocalPipelinePayload: Codable {
    let input: LocalInputSnapshot
    let descriptor: DiverItemDescriptor?
}

struct ParallelEnrichmentResult: Sendable {
    var foursquare: EnrichmentData?
    var duckDuckGo: EnrichmentData?
    var weather: WeatherContext?
    var activity: ActivityContext?
    var link: EnrichmentData?
    var coverImagePath: String?
    var productConcepts: [String]?
    var betterProductURL: URL?
    var liveEventContext: String?
    var productData: EnrichmentData?
}

private struct LocalInputSnapshot: Codable {
    let id: String
    let createdAt: Date
    let url: String?
    let text: String?
    let source: String?
    let inputType: String
    let rawPayload: Data?

    init(from input: LocalInput) {
        self.id = input.id.uuidString
        self.createdAt = input.createdAt
        self.url = input.url
        self.text = input.text
        self.source = input.source
        self.inputType = input.inputType
        self.rawPayload = input.rawPayload
    }
}
