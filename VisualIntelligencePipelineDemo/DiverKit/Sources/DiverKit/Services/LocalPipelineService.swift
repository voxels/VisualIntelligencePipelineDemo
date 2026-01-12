import Foundation
import SwiftData
import DiverShared
import CoreLocation
import ImageIO
import AVFoundation
import Vision

@MainActor
public final class LocalPipelineService {
    private let modelContext: ModelContext
    private var cachedHomeLocation: CLLocation?

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
        let rawPayload = input.rawPayload

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
                    do {
                        let enrichment = try await withTimeout(seconds: 10) {
                            try await enrichmentService.enrich(url: url)
                        }
                        
                        if let enrichment {
                            applyEnrichment(enrichment, to: existing)
                            if let desc = enrichment.descriptionText { accumulatedContext += "\nLink Summary: \(desc)" }
                        }
                    } catch {
                        DiverLogger.pipeline.warning("⚠️ Link enrichment failed or timed out for \(url): \(error)")
                        // Proceed without enrichment
                    }
                }
            }
            
            // Apply contextual Location -> Foursquare -> DuckDuckGo enrichment
            var effectiveLocation: CLLocation? = nil
            var hasUserOverride = false
            
            // 1. Check EXISTING overrides (manual edits)
            if let ctx = existing.placeContext, let lat = ctx.latitude, let lon = ctx.longitude {
                // Downgrade "Home" priority: Treat it as NOT a user override to allow content-based refinement (e.g. from photo metadata)
                let isHome = ctx.placeID == "home-location"
                
                if !isHome {
                    effectiveLocation = CLLocation(latitude: lat, longitude: lon)
                    hasUserOverride = true
                    DiverLogger.pipeline.debug("Using Existing Item Location Override: \(lat), \(lon)")
                } else {
                    DiverLogger.pipeline.debug("Existing location is 'Home'. Treating as non-override to allow refinement.")
                }
            } else if let locStr = existing.location,
                      let components = Optional(locStr.split(separator: ",")),
                      components.count == 2,
                      let lat = Double(components[0].trimmingCharacters(in: .whitespaces)),
                      let lon = Double(components[1].trimmingCharacters(in: .whitespaces)) {
                
                // Also check if this raw coordinate matches cached Home, if we had access to it easily.
                // For now, assume raw string might be a manual override if placeContext is nil.
                effectiveLocation = CLLocation(latitude: lat, longitude: lon)
                hasUserOverride = true 
            }
            
            // 2. Live Location (if no override)
            // CRITICAL: Only use live location if the item is NEW (recent). 
            // Do NOT update location of old items to current device location during edits/reprocessing.
            let isRecent = abs(input.createdAt.timeIntervalSinceNow) < 300 // 5 minutes
            
            if effectiveLocation == nil, let locationService, isRecent {
                effectiveLocation = await locationService.getCurrentLocation()
            }
            // If item is old and locationService is present but effectiveLocation is nil (was Home), we leave it nil 
            // to see if Metadata/Session can find better. If not, we fall back to existing Home context later?
            // Actually, if we return effectiveLocation = nil, no enrichment happens, so existing fields aren't touched.
                
                // Fallback: Check raw payload for location metadata if unavailable (e.g. reprocessing)
                // This now runs even if item was "Home" (since we set effectiveLocation = nil for Home above)
                if effectiveLocation == nil, let data = rawPayload, !isJSONData(data) {
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
                     } else {
                         // Fallback: Try Video Metadata
                         if let videoLocation = await extractLocationFromVideo(data: data) {
                             effectiveLocation = videoLocation
                             DiverLogger.pipeline.debug("Extracted Location from Video Metadata: \(videoLocation.coordinate.latitude), \(videoLocation.coordinate.longitude)")
                         }
                     }
                 }
                 
                 // 3. QR Code Detection (Fallback if NO URL)
                 // User Request: "if i photograph a sign and a qr code is found, the title should be the name of the page"
                 if input.url == nil, let data = rawPayload, !isJSONData(data) {
                      if let qrURL = detectQRCode(data: data) {
                          DiverLogger.pipeline.info("Detected QR Code URL: \(qrURL)")
                          input.url = qrURL
                          existing.url = qrURL
                          
                          // Run enrichment immediately to get the title
                          if let enrichmentService, let url = URL(string: qrURL) {
                               if let enrichment = try await enrichmentService.enrich(url: url) {
                                   // QR Code titles should heavily override "Visual Capture"
                                   // applyEnrichment will handle weak titles, but if we just found this, 
                                   // let's be explicit
                                   applyEnrichment(enrichment, to: existing, overwriteTitle: true)
                                   accumulatedContext += "\nQR Link: \(enrichment.title ?? url.host ?? "")"
                               }
                          }
                      }
                 }
                 
                 // Session Context Override
                // CRITICAL: Only apply if NO user override.
                if !hasUserOverride, let descriptorSessionID = descriptor?.sessionID ?? existing.sessionID {
                     let fetchSession = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == descriptorSessionID })
                     if let session = try? modelContext.fetch(fetchSession).first {
                         if let lat = session.latitude, let lng = session.longitude {
                             effectiveLocation = CLLocation(latitude: lat, longitude: lng)
                             DiverLogger.pipeline.debug("Using Session Location Override for Update: \(lat), \(lng)")
                         }
                         if let summary = session.summary {
                             accumulatedContext += "\n\nSESSION CONTEXT:\n\(summary)\n"
                         }
                         // If we are adopting the Session location, do we treat it as an override?
                         // If the Session has a specific name, yes.
                         if let locName = session.locationName, !locName.isEmpty {
                             hasUserOverride = true
                         }
                     }
                }

                if let location = effectiveLocation {
                    let coords = location.coordinate
                    
                    // 1. Contextual Place Lookup
                    if let foursquareService {
                        var matchedEnrichment: EnrichmentData?
                        
                        // IF User specified a place (Override active), try to match IT specifically
                        if hasUserOverride, let overrideName = existing.placeContext?.name ?? existing.location {
                             // Try search by name + location to verify/enrich the specific place
                             matchedEnrichment = try await foursquareService.enrich(query: overrideName, location: coords)
                             
                              
                              if matchedEnrichment == nil {
                                  // User specified a place, but Foursquare didn't find it.
                                  // DO NOT overwrite with a random nearby place.
                                  // Keep the MapKit/Manual data.
                                  DiverLogger.pipeline.debug("Retaining specific location override '\(overrideName)'; Foursquare verify failed.")
                                  
                                  // Fallback to coordinates for metadata only (weather etc), 
                                  // BUT enforce preservation of identity
                                  matchedEnrichment = try await foursquareService.enrich(location: coords)
                              }
                         } else {
                              // Standard Auto-Enrichment (Best guess nearby)
                              
                              // User Request: "if i take a picture ofthe sign of a business it should show up... and match to the gps coordinate"
                              // STRATEGY: Run a specific query-based search using the input text (OCR/Caption) first.
                              // If that finds a match at this location, prefer it over the generic "nearest neighbor".
                              var textBasedMatch: EnrichmentData? = nil
                              let queryText = input.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                              
                              // Heuristic: Only search if text is concise (likely a name/caption) and not a full LLM summary
                              // "Visual Capture" is the default empty text, ignore it.
                              if !queryText.isEmpty && queryText.count < 100 && queryText != "Visual Capture" {
                                   textBasedMatch = try await foursquareService.enrich(query: queryText, location: coords)
                                   if let match = textBasedMatch {
                                        DiverLogger.pipeline.debug("Found Verified Text-Based Match: \(match.title ?? "Unknown")")
                                   }
                              }
                              
                              if let textMatch = textBasedMatch {
                                  // Found it! Use the specific place from the sign.
                                  matchedEnrichment = textMatch
                              } else {
                                  // Fallback to generic proximity search
                                  matchedEnrichment = try await foursquareService.enrich(location: coords)
                              }
                          }
                         
                        if let fsEnrichment = matchedEnrichment {
                            // Determine if we should preserve existing identity
                            // If `hasUserOverride` matches `existing.placeContext` AND `fsEnrichment` is different/generic,
                            // we should probably preserve.
                            // Simplified: If manual override failed verification (matchedEnrichment was nil above), 
                            // we fetched coords-based enrichment. We MUST preserve in that case.
                            // If user didn't override, we overwrite.
                            
                            // Check ID types
                            let currentID = existing.placeContext?.placeID ?? ""
                            let isMapKitOverride = currentID.starts(with: "mapkit-") || currentID == "home-location"
                            
                            // If we have a MapKit override and found a Foursquare result, 
                            // check if names match loosely? Or just prefer MapKit if user chose it?
                            // User Request: "Both Foursquare and MapKit information should be saved... reverted to old data"
                            // If user picked MapKit, keep it.
                            
                            let shouldPreserve = isMapKitOverride
                             
                            applyEnrichment(fsEnrichment, to: existing, preservePlaceIdentity: shouldPreserve)
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
                finalPurposes.insert(legacyPurpose)
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
                 existing.purposes = Array(combinedPurposes)
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
                
                // Extract high-level concepts (User Request: "reprocess button should run analyze context")
                if existing.webContext?.textContent != nil {
                    await self.extractConcepts(from: existing)
                }
                
                // Auto-create UserConcepts
                do {
                    try await self.autoCreateConcepts(from: existing)
                } catch {
                    DiverLogger.pipeline.error("Failed to auto-create concepts during reprocessing for \(existing.id): \(error)")
                }
                
                // Ensure session is synced with potentially new location data (User Request: "recreate the session if it doesn't already exist")
                await MainActor.run {
                    self.syncSession(for: existing)
                    try? self.modelContext.save()
                }
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
            finalPurposes.insert(legacyPurpose)
        }
        

        // 5. LLM Analysis (Background "Second Pass")
        // User Requirement: "verification pass should always be run in the background after running the first UI pass"
        // We spawn a task to allow the function to return the 'ready' item immediately for UI display.
        Task {
            await performLLMAnalysis(for: processed, descriptor: descriptor, accumulatedContext: accumulatedContext)
        }

        if !finalPurposes.isEmpty {
            processed.purposes = Array(finalPurposes).sorted()
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
        progressHandler: ((Double) -> Void)? = nil,
        logHandler: ((String) -> Void)? = nil
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
            let msg = "Clearing \(queuedItems.count) items from queue before reprocessing."
            DiverLogger.pipeline.info("\(msg)")
            await MainActor.run { logHandler?(msg) }
            
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
        let countMsg = "Reprocessing \(items.count) items created after \(cutoffDate.formatted(date: .abbreviated, time: .shortened))"
        DiverLogger.pipeline.info("\(countMsg)")
        await MainActor.run { logHandler?(countMsg) }
        
        var completedCount = 0
        let totalCount = Double(items.count)
        
        // Batched Processing for Concurrency Control
        // Lowered from 10 to 3 to prevent Simulator WebContent process exhaustion/crashes
        let batchSize = 3
        let batches = items.chunked(into: batchSize)
        
        for (batchIndex, batch) in batches.enumerated() {
            let batchMsg = "Processing batch \(batchIndex + 1)/\(batches.count)"
            DiverLogger.pipeline.debug("\(batchMsg)")
            await MainActor.run { logHandler?(batchMsg) }
            
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
                    
                    // User Request: "if i'm reprocessing my data at home it should not override my content location"
                    // Strip existing "Home" location to force a fresh lookup (e.g. from Image Metadata or Session)
                    // We check if the ID is explicitly "home-location"
                    if freshItem.placeContext?.placeID == "home-location" {
                         freshItem.placeContext = nil
                         freshItem.location = nil
                         freshItem.processingLog.append("\(Date().formatted()): Stripped generic 'Home' location to allow content-based discovery.")
                    }
                    
                    // User Request: "All the items named home shjould have their titles replaced by the document semantic context"
                    // If title is "Home" or "Untitled", strip it so it can be regenerated by LLM or Enrichment
                    if freshItem.title == "Home" || freshItem.title == "Untitled" {
                        freshItem.title = nil
                        freshItem.processingLog.append("\(Date().formatted()): Stripped generic title to allow semantic generation.")
                    }
                    
                    do {
                        // Create a minimal descriptor with the existing ID to force an update instead of insert.
                        // This prevents duplicate items from being created during reprocessing.
                        let maintenanceDescriptor = DiverItemDescriptor(
                            id: freshItem.id, // CRITICAL: Use existing ID
                            url: freshItem.url ?? "",
                            title: freshItem.title ?? "Untitled",
                            location: freshItem.location
                        )
                        
                        logHandler?("Analyzing: \(freshItem.title ?? "Untitled")")
                        
                        // Trigger process
                        let processed = try await self.process(
                            input: input,
                            descriptor: maintenanceDescriptor,
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
            try await saveWithRetry()
            
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

    private func applyEnrichment(_ enrichment: EnrichmentData, to item: ProcessedItem, overwriteTitle: Bool = false, preservePlaceIdentity: Bool = false) {
        if let title = enrichment.title {
            let currentTitle = item.title ?? ""
            let weakTitles = ["Untitled", "Visual Capture", "Captured Moment", "Scanned Document", "Web Link", "Recognized Link", "QR Code Link", "Home"]
            let isWeak = currentTitle.isEmpty || 
                         currentTitle.contains("://") || 
                         currentTitle.contains("www.") || 
                         weakTitles.contains(currentTitle) ||
                         currentTitle.hasPrefix("Detected Media:") ||
                         isAddressString(currentTitle) // Check for address-like titles

            
            // Quality Gate: Don't overwrite a strong title with an address string
            let newIsAddress = isAddressString(title)
            let shouldUpdate = (overwriteTitle || isWeak || (item.url != nil && currentTitle == URL(string: item.url!)?.host))
            
            if shouldUpdate {
                // If the new title is just an address, AND the current title is NOT weak (e.g. "Starbucks"), keep the strong title.
                // Unless the current title IS weak (e.g. "Untitled"), then an address is better than nothing.
                if newIsAddress && !isWeak {
                     DiverLogger.pipeline.info("🛡️ Preventing title downgrade: Kept '\(currentTitle)' instead of address '\(title)'")
                } else {
                     item.title = title
                }
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
        if let location = enrichment.location, !preservePlaceIdentity {
            // Always update location if enriched, as it might be more specific than the initial generic coordinate string,
            // UNLESS we are preserving identity (e.g. manual MapKit override)
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
        if let place = enrichment.placeContext, !preservePlaceIdentity { item.placeContext = place }
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

    private func extractLocationFromVideo(data: Data) async -> CLLocation? {
        // AVAsset requires a URL. Write data to a temporary file.
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        
        do {
            try data.write(to: tempFile)
            defer {
                try? FileManager.default.removeItem(at: tempFile)
            }
            
            let asset = AVAsset(url: tempFile)
            
            // Try Common Key first
            let commonItems = try? await asset.load(.commonMetadata)
            if let locationItem = commonItems?.first(where: { $0.commonKey == .commonKeyLocation }),
               let locationString = try? await locationItem.load(.stringValue) {
                // Determine format. ISO6709 is standard.
                // Simple parser
                return parseISO6709(locationString)
            }
            
            // Try QuickTime Metadata
            let metadata = try? await asset.load(.metadata)
            if let qtLocation = metadata?.first(where: { $0.identifier?.rawValue == "mdta/com.apple.quicktime.location.ISO6709" }),
               let locationString = try? await qtLocation.load(.stringValue) {
                return parseISO6709(locationString)
            }
            
        } catch {
            DiverLogger.pipeline.error("Failed to extract video location: \(error)")
        }
        
        return nil
    }
    
    private func parseISO6709(_ string: String) -> CLLocation? {
        // Format: +27.5916+086.5640+8850/
        // Pattern: ([+-]\d+\.?\d*)([+-]\d+\.?\d*)
        let pattern = "([+-]\\d+\\.?\\d*)([+-]\\d+\\.?\\d*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = string as NSString
        guard let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: string.count)),
              match.numberOfRanges >= 3 else { return nil }
        
        let latString = nsString.substring(with: match.range(at: 1))
        let lonString = nsString.substring(with: match.range(at: 2))
        
        if let lat = Double(latString), let lon = Double(lonString) {
            return CLLocation(latitude: lat, longitude: lon)
        }
        return nil
    }

    private func detectQRCode(data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        
        if let result = request.results?.first(where: { $0.payloadStringValue != nil }) {
            return result.payloadStringValue
        }
        return nil
    }

    private func isAddressString(_ title: String) -> Bool {
        // Heuristic: Starts with a number, contains a comma?
        // e.g. "603 W 29th St, New York, NY"
        let range = NSRange(location: 0, length: title.utf16.count)
        let regex = try? NSRegularExpression(pattern: "^\\d+.*,")
        if let match = regex?.firstMatch(in: title, options: [], range: range) {
            return true
        }
        return false
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
        var fullContext = (item.summary ?? "") + "\n\n--- Context ---\n" + accumulatedContext + sessionContext
        
        // Override location with Session Metadata if available to ensure LLM respects user edit
        var effectiveLocationName = item.location
        if let sessionID = item.sessionID {
            let sessionDesc = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
            if let session = try? modelContext.fetch(sessionDesc).first, let locName = session.locationName {
                effectiveLocationName = locName
            }
        }
        
        // Anti-Bias: If location is "Home", strip it from LLM input so it relies on visual context
        if let loc = effectiveLocationName, loc.localizedCaseInsensitiveContains("home-location") || loc.localizedCaseInsensitiveContains("home") {
            effectiveLocationName = nil
            
            // Also scrub "Home" from the text context to prevent leakage
            // We use a simple replacement for common location patterns
            // This prevents "Foursquare: Home" or "Location: Home" from biasing the prompt
            var sanitized = fullContext
            sanitized = sanitized.replacingOccurrences(of: "Home Location", with: "Location", options: .caseInsensitive)
            sanitized = sanitized.replacingOccurrences(of: "Home", with: "", options: .caseInsensitive) // Aggressive strip for now as per user report "still says at home"
            
            // Re-assign strict fullContext
            fullContext = sanitized
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

            let initialHomeLoc = self.cachedHomeLocation
            // 2. Foursquare + DuckDuckGo Chain
            group.addTask {
                guard let location = finalLocation else { return nil }
                let coords = location.coordinate
                
                var fsEnrichment: EnrichmentData?
                
                // 1. Prioritize Foursquare lookup
                if let foursquareService {
                    if let placeID = descriptor?.placeID, !placeID.isEmpty {
                        fsEnrichment = try? await self.withTimeout(seconds: 15) {
                            try await foursquareService.fetchDetails(for: placeID)
                        }
                    } else {
                        fsEnrichment = try? await self.withTimeout(seconds: 15) {
                            try await foursquareService.enrich(location: coords)
                        }
                    }
                }
                
                // 2. Fallback: MapKit Reverse Geocoding
                if fsEnrichment == nil {
                    let geocoder = CLGeocoder()
                    if let placemarks = try? await geocoder.reverseGeocodeLocation(location), let first = placemarks.first {
                        let name = first.name ?? first.thoroughfare ?? "Location"
                        let address = [first.subThoroughfare, first.thoroughfare, first.locality, first.administrativeArea].compactMap { $0 }.joined(separator: ", ")
                        let categories = first.areasOfInterest ?? ["Location"]
                        
                        fsEnrichment = EnrichmentData(
                            title: name,
                            descriptionText: address,
                            image: nil,
                            categories: categories,
                            styleTags: ["MapKit"],
                            location: address,
                            placeContext: PlaceContext(
                                name: name,
                                categories: categories,
                                placeID: "mapkit-\(coords.latitude)-\(coords.longitude)",
                                address: address,
                                rating: nil,
                                isOpen: nil
                            )
                        )
                    }
                }

                // 3. Last Resort Fallback: Home Detection (Only if generic or failed)
                let isGeneric = fsEnrichment == nil || fsEnrichment?.title == "Location"
                if isGeneric, !isUserLocationFixed, let contactService = contactService {
                    var homeLoc: CLLocation? = initialHomeLoc
                    if homeLoc == nil {
                        homeLoc = try? await contactService.getHomeLocation()
                        if let homeLoc {
                            await MainActor.run { self.cachedHomeLocation = homeLoc }
                        }
                    }
                    
                    if let homeLoc = homeLoc {
                         if location.distance(from: homeLoc) < 100 {
                             let explicitLocationName = descriptor?.location
                             let isHomeName = explicitLocationName?.lowercased() == "home"
                             let isGenericOrEmpty = explicitLocationName == nil || explicitLocationName?.isEmpty == true
                             if isHomeName || isGenericOrEmpty {
                                 let placeCtx = PlaceContext(name: "Home", categories: ["Home", "Personal"], placeID: "home-location", address: nil, rating: nil, isOpen: true)
                                 fsEnrichment = EnrichmentData(title: "Home", descriptionText: "User's Home Location", image: nil, categories: ["Home"], styleTags: ["Personal"], location: "Home", placeContext: placeCtx)
                             }
                         }
                    }
                }
                
                if let fsEnrichment {
                    var result = ParallelEnrichmentResult(foursquare: fsEnrichment)
                    if let venueName = fsEnrichment.title {
                        if let ddgService = duckDuckGoService {
                            if let ddgEnrichment = try? await self.withTimeout(seconds: 10, operation: {
                                try await ddgService.enrich(query: venueName, location: coords)
                            }) {
                                result.duckDuckGo = ddgEnrichment
                            }
                            if let eventContext = try? await self.withTimeout(seconds: 10, operation: {
                                await self.searchLiveEvents(place: venueName, service: ddgService)
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
                
                let weather = try? await self.withTimeout(seconds: 10, operation: {
                    await weatherService.fetchWeather(for: location)
                })
                
                if let weather = weather {
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
                 guard let data = imageData, !self.isJSONData(data) else { return nil }

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
    }
    
    // MARK: - Helper Logic
    
    private func finalizeTitle(for item: ProcessedItem) {
        // 1. Check if current title is valid (Prominent Text / Metadata)
        let idString = item.id
        let currentTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isPlaceholder = currentTitle.isEmpty || currentTitle == "Untitled" || currentTitle == idString || currentTitle.contains("http") || currentTitle.contains("://") || isAddressString(currentTitle)
        
        // If we have a good title, stick with it
        if !isPlaceholder { return }
        
        // 2. Try LLM Tags / Themes / Purposes
        // Combine themes, tags and purposes, prioritize themes
        let candidates = item.themes + item.tags + item.purposes.filter { !$0.starts(with: "At: ") }
        if let bestTag = candidates.first(where: { !$0.isEmpty && $0.count > 3 }) {
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
        
        // 4. Location Fallback
        if let loc = item.location, !loc.isEmpty {
            item.title = "At: \(loc)"
            return
        }

        // 5. UUID Fallback (Default)
        if item.title == nil || item.title == idString {
            item.title = "Visual Capture \(item.createdAt.formatted(date: .abbreviated, time: .shortened))"
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
    
    private func saveWithRetry(attempts: Int = 3) async throws {
        var lastError: Error?
        for i in 0..<attempts {
            do {
                try modelContext.save()
                return
            } catch {
                lastError = error
                let nsError = error as NSError
                if nsError.code == 256 || nsError.code == 134080 || nsError.localizedDescription.contains("busy") {
                    try? await Task.sleep(nanoseconds: UInt64(200_000_000 * (i + 1)))
                    continue
                }
                throw error
            }
        }
        if let lastError { throw lastError }
    }

    nonisolated private func isJSONData(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let firstByte = data[0]
        // JSON objects start with '{' or '['
        return firstByte == 0x7B || firstByte == 0x5B
    }

    private func syncSession(for item: ProcessedItem) {
        // Ensure valid session ID
        let sessionID = item.sessionID ?? UUID().uuidString
        if item.sessionID == nil { item.sessionID = sessionID }
        
        // Fetch or Create Session
        let fetch = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
        let session: DiverSession
        
        if let existingSession = try? modelContext.fetch(fetch).first {
            session = existingSession
        } else {
            // Create new if missing
            session = DiverSession(sessionID: sessionID, createdAt: item.createdAt)
            modelContext.insert(session)
            DiverLogger.pipeline.info("Created new/restored DiverSession for item \(item.id)")
        }
        
        // Sync Location Data if Item has it (User Override wins)
        if let place = item.placeContext {
            if let lat = place.latitude, let lon = place.longitude {
                session.latitude = lat
                session.longitude = lon
            }
            if let name = place.name {
                session.locationName = name
            } else if let locName = item.location, session.locationName == nil {
                session.locationName = locName
            }
        } else if let locStr = item.location,
                  let components = Optional(locStr.split(separator: ",")),
                  components.count == 2,
                  let lat = Double(components[0].trimmingCharacters(in: .whitespaces)),
                  let lon = Double(components[1].trimmingCharacters(in: .whitespaces)) {
            // Fallback to coord string
            session.latitude = lat
            session.longitude = lon
        }
        
        // Ensure Session has a title/summary if empty
        if session.summary == nil {
            session.summary = item.summary ?? item.title
        }
    }
}


struct ParallelEnrichmentResult {
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
