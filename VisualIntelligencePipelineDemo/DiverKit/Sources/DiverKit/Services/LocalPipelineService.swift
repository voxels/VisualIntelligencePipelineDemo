import Foundation
import SwiftData
import DiverShared
import CoreLocation
import ImageIO
import AVFoundation
import Vision
import Photos

@MainActor
public final class LocalPipelineService {
    private let modelContext: ModelContext
    private var cachedHomeLocation: CLLocation?

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Deterministic Context Builder
    
    /// Builds accumulated context deterministically from all available source material on an item.
    /// This ensures consistent LLM input regardless of whether processing is initial or reprocessing.
    private func buildDeterministicContext(from item: ProcessedItem, descriptor: DiverItemDescriptor? = nil) -> String {
        var context = ""
        
        // 1. OCR / Transcription (primary visual content)
        if let transcription = item.transcription, !transcription.isEmpty {
            context += "OCR TEXT: \(transcription)\n"
        }
        
        // 2. Web Content (link enrichment)
        if let webText = item.webContext?.textContent, !webText.isEmpty {
            context += "Link Summary: \(String(webText.prefix(500)))\n"
        }
        if let structured = item.webContext?.structuredData, !structured.isEmpty {
            context += "Structured Data: \(structured)\n"
        }
        
        // 3. Place Context (location enrichment)
        if let place = item.placeContext {
            if let name = place.name, !name.isEmpty {
                context += "Foursquare: \(name)"
                let categories = place.categories ?? []
                if !categories.isEmpty {
                    context += " - \(categories.joined(separator: ", "))"
                }
                context += "\n"
            }
            if let tips = place.tips, !tips.isEmpty {
                context += "Nearby Context: \(tips.prefix(2).joined(separator: "; "))\n"
            }
        }
        
        // NOTE: Weather is intentionally excluded - it's captured only during live preview,
        // not reconstructed during reprocessing (weather data is time-sensitive)
        
        // 5. Activity Context
        if let activity = item.activityContext {
            context += "Activity: \(activity.type)\n"
        }
        
        // 6. Descriptor context (from original share/capture)
        if let desc = descriptor?.descriptionText, !desc.isEmpty {
            context += "Original Description: \(desc)\n"
        }
        
        return context
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
                         if let videoLocation = await extractLocationFromVideo(data: data, identifier: existing.photosAssetIdentifier) {
                             effectiveLocation = videoLocation
                             DiverLogger.pipeline.debug("Extracted Location from Video Metadata: \(videoLocation.coordinate.latitude), \(videoLocation.coordinate.longitude)")
                         }
                     }
                 }
                 
                 // 3. QR Code Detection (Fallback if NO URL)
                 // User Request: "if i photograph a sign and a qr code is found, the title should be the name of the page"
                 // 3. QR Code Detection (Fallback if NO URL or if URL is just a placeholder/local file)
                 // User Request: "if i photograph a sign and a qr code is found, the title should be the name of the page"
                 // Check if existing URL is nil OR starts with file scheme
                 let hasValidWebURL = existing.url != nil && 
                                      !existing.url!.lowercased().hasPrefix("file://") &&
                                      !existing.url!.lowercased().hasPrefix("diver-")
                 
                 // CRITICAL: Check for data OR valid asset identifier for import support
                 if !hasValidWebURL {
                      var analysisData = rawPayload
                      
                      // On-demand load for imports if needed
                      // Use loadBestFrame (High Quality) instead of thumbnail to ensure QR/Barcode legibility
                      if (analysisData == nil || isJSONData(analysisData!)), let assetId = existing.photosAssetIdentifier {
                          analysisData = await PhotosAssetLoader.shared.loadBestFrame(identifier: assetId)
                      }
                      
                       if let data = analysisData, !isJSONData(data) {
                           // UNIFIED VISUAL ANALYSIS
                           // Replaces manual barcode scanning + separate runVisualIntelligenceAnalysis
                           await analyzeVisualContent(data: data, existing: existing, accumulatedContext: &accumulatedContext, enrichmentService: enrichmentService)
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
                         // NOTE: Session summary is intentionally NOT added to context.
                         // Session summaries are derived from item summaries, so including them
                         // creates feedback loops and contamination.
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
                            let isMapKitOverride = currentID.hasPrefix("mapkit-") || currentID.hasPrefix("mk-") || currentID == "home-location"
                            
                            // CRITICAL: Also preserve contact-set locations
                            let isContactLocation = existing.placeContext?.contactIdentifier != nil
                            
                            // If we have a MapKit override, contact location, session override, or other user-set identity,
                            // preserve the existing place name/ID during enrichment.
                            // hasUserOverride is set when the session has a specific locationName (user edited it)
                            
                            let shouldPreserve = hasUserOverride || isMapKitOverride || isContactLocation
                             
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

            // Perform enrichment and LLM analysis (awaited for proper progress tracking)
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
                contactService: contactService,
                itemSource: existing.source
            )
            
            for result in results {
                self.processParallelResult(result, to: existing, accumulatedContext: &localAccumulatedContext)
            }
            
            // Merge in any stored item data not captured by enrichment (deterministic context)
            let storedContext = buildDeterministicContext(from: existing, descriptor: descriptor)
            if !storedContext.isEmpty {
                localAccumulatedContext += "\n" + storedContext
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
            
            // Ensure session is synced with potentially new location data
            self.syncSession(for: existing)
            
            // Mark as ready after successful processing
            existing.status = .ready
            try? self.modelContext.save()
            
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
            wrappedLink: descriptor?.wrappedLink,
            attributionID: descriptor?.attributionID,
            masterCaptureID: descriptor?.masterCaptureID,
            sessionID: descriptor?.sessionID,
            photosAssetIdentifier: descriptor?.photosAssetIdentifier,
            categories: descriptor?.categories ?? [],
            location: descriptor?.location,
            price: descriptor?.price,
            purposes: descriptor?.purposes ?? []
        )
        
        // Insert immediately for live UI updates
        processed.status = ProcessingStatus.processing
        processed.processingLog.append("\(Date().formatted()): Starting new item pipeline.")
        print("🚀 [LocalPipeline] Starting pipeline for item: \(processed.id)")
        modelContext.insert(processed)
        try? modelContext.save()
        
        var accumulatedContext = ""
        
        // 1.5 Barcode/QR Detection (Parity with Update Path)
        var analysisData = rawPayload
        if (analysisData == nil || isJSONData(analysisData!)), let assetId = descriptor?.photosAssetIdentifier {
             analysisData = await PhotosAssetLoader.shared.loadBestFrame(identifier: assetId)
        }
        
        if let data = analysisData, !isJSONData(data) {
             // UNIFIED VISUAL ANALYSIS
             // Replaces manual barcode scanning + separate runVisualIntelligenceAnalysis
             await analyzeVisualContent(data: data, existing: processed, accumulatedContext: &accumulatedContext, enrichmentService: enrichmentService)
        }
        

        
        // Apply contextual Location -> Foursquare -> DuckDuckGo enrichment
        var currentLocation: CLLocation? = nil
        
        // 1. Try Metadata (image/video EXIF) first - explicit truth
        if let data = rawPayload, !isJSONData(data) {
             if let source = CGImageSourceCreateWithData(data as CFData, nil),
                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                let gps = props["{GPS}"] as? [String: Any],
                let lat = gps["Latitude"] as? Double,
                let latRef = gps["LatitudeRef"] as? String,
                let lng = gps["Longitude"] as? Double,
                let lngRef = gps["LongitudeRef"] as? String {
                 
                 let finalLat = latRef == "S" ? -lat : lat
                 let finalLng = lngRef == "W" ? -lng : lng
                 currentLocation = CLLocation(latitude: finalLat, longitude: finalLng)
                 DiverLogger.pipeline.debug("Extracted Location from New Item Metadata: \(finalLat), \(finalLng)")
             } else if let videoLocation = await extractLocationFromVideo(data: data, identifier: descriptor?.photosAssetIdentifier) {
                 currentLocation = videoLocation
                 DiverLogger.pipeline.debug("Extracted Location from New Item Video Metadata: \(videoLocation.coordinate.latitude), \(videoLocation.coordinate.longitude)")
             }
        }
        
        // 2. Fallback to Live GPS ONLY if item is Recent (Captured now) and no metadata
        // This prevents library imports from adopting "Home" location incorrectly
        if currentLocation == nil {
             let isRecent = abs(input.createdAt.timeIntervalSinceNow) < 300 // 5 minutes
             if isRecent {
                 currentLocation = await locationService?.getCurrentLocation()
                 DiverLogger.pipeline.debug("Using Live Device Location (Recent Capture)")
             } else {
                 DiverLogger.pipeline.debug("Skipping Live Device Location for non-recent item (Library Import)")
             }
        }
        
        // 3. SESSION CONTEXT OVERRIDE (Highest Priority for grouping)
        // If user explicitly adds to a session, they likely want that session's context
        // User Report: "current location is overriding the locaiton of the session" -> Fix: Apply this LAST to override.
        var hasUserOverride = false
        if let sessionID = descriptor?.sessionID ?? processed.sessionID {
             let fetchSession = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
             if let session: DiverSession = try? modelContext.fetch(fetchSession).first {
                 var useSessionLoc = false
                 if let lat = session.latitude, let lng = session.longitude {
                     // Use session location if explicitly set
                     currentLocation = CLLocation(latitude: lat, longitude: lng)
                     DiverLogger.pipeline.debug("Using Session Location Override: \(lat), \(lng)")
                     useSessionLoc = true
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
            contactService: contactService,
            itemSource: input.source
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
             
             // If QR payload is a URL, expand it with web scraping (same treatment as regular links)
             if let qrURL = URL(string: payload),
                let scheme = qrURL.scheme?.lowercased(),
                (scheme == "http" || scheme == "https"),
                let enrichmentService = enrichmentService {
                 
                 DiverLogger.pipeline.info("🔗 QR URL detected: \(payload) - starting web enrichment")
                 
                 if let enrichment = try? await self.withTimeout(seconds: 30, operation: {
                     try await enrichmentService.enrich(url: qrURL)
                 }) {
                     // Apply web enrichment to item
                     if processed.title == nil || processed.title?.isEmpty == true || processed.title == "QR Code Link" {
                         processed.title = enrichment.title
                     }
                     if processed.summary == nil || processed.summary?.isEmpty == true {
                         processed.summary = enrichment.descriptionText
                     }
                     processed.webContext = enrichment.webContext
                     processed.url = payload  // Store the full URL for future reference
                     
                     // Add web content to LLM context
                     if let textContent = enrichment.webContext?.textContent, !textContent.isEmpty {
                         accumulatedContext += "\n=== QR CODE WEB CONTENT ===\n" + textContent.prefix(2000)
                     }
                     
                     DiverLogger.pipeline.info("✅ QR URL enriched: \(enrichment.title ?? "No title")")
                     processed.processingLog.append("\(Date().formatted()): QR URL expanded via web scraping.")
                 }
             }
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

        // INTELLIGENT SESSION GROUPING
        // Re-assign Session ID based on Location to ensure all items at the same place are grouped (User Request).
        // Try to find an existing Session that matches this item's Place ID.
        if let placeID = processed.placeContext?.placeID, !placeID.isEmpty {
             let desc = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.placeID == placeID })
             if let existingSession: DiverSession = try? modelContext.fetch(desc).first {
                 // Check if we are currently using a random/new session ID that differs from the persistent one
                 if existingSession.sessionID != processed.sessionID {
                     DiverLogger.pipeline.info("MERGING: Moving item \(processed.id) from session \(processed.sessionID ?? "nil") into existing Location Session \(existingSession.sessionID) (\(existingSession.locationName ?? "Unknown"))")
                     processed.sessionID = existingSession.sessionID
                 }
             }
        }

        // Sync Session Data (Ensures Session exists and is updated with latest Item location)
        // Uses properties from 'processed' which may have been enriched or regrouped above.
        syncSession(for: processed)

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
        processed.status = ProcessingStatus.ready
        try? modelContext.save()

        return processed
    }


    public func refreshProcessedItems(
        enrichmentService: LinkEnrichmentService? = nil,
        locationService: LocationProvider? = nil,
        foursquareService: ContextualEnrichmentService? = nil,
        duckDuckGoService: ContextualEnrichmentService? = nil,
        weatherService: WeatherEnrichmentService? = nil,
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
                indexingService: indexingService
            )
        }
        try modelContext.save()

        try modelContext.save()

        DiverLogger.pipeline.info("✅ Saved refreshed processed items to SwiftData. Total items: \(inputs.count)")
    }

    // MARK: - Post-Processing / Regeneration
    
    /// Regenerates the item's summary, questions, and metadata using the current context and any user edits.
    /// This effectively re-runs the LLM analysis step without performing expensive OCR/Extraction.
    public func regenerateSummary(for item: ProcessedItem) async {
        DiverLogger.pipeline.info("🔄 Regenerating summary for item \(item.id) via standard pipeline logic.")
        // Delegate to the standard deterministic logic
        // We pass empty accumContext because performLLMAnalysis now constructs it from the item fields directly.
        await performLLMAnalysis(for: item, descriptor: nil, accumulatedContext: "")
    }
    


    public func reprocessPipeline(
        cutoffDate: Date,
        enrichmentService: LinkEnrichmentService? = nil,
        locationService: LocationProvider? = nil,
        foursquareService: ContextualEnrichmentService? = nil,
        duckDuckGoService: ContextualEnrichmentService? = nil,
        weatherService: WeatherEnrichmentService? = nil,
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
                    
                    // CRITICAL: Clear parent session summary so it regenerates with new item data
                    if let sessionID = freshItem.sessionID {
                        let sessionFetch = FetchDescriptor<DiverSession>(
                            predicate: #Predicate { $0.sessionID == sessionID }
                        )
                        if let session = try? self.modelContext.fetch(sessionFetch).first, session.summary != nil {
                            session.summary = nil
                            session.updatedAt = Date()
                            freshItem.processingLog.append("\(Date().formatted()): Cleared parent session summary for regeneration.")
                        }
                    }
                    
                    do {
                        // Create a minimal descriptor with the existing ID to force an update instead of insert.
                        // This prevents duplicate items from being created during reprocessing.
                        let maintenanceDescriptor = DiverItemDescriptor(
                            id: freshItem.id, // CRITICAL: Use existing ID
                            url: freshItem.url ?? "",
                            title: freshItem.title ?? "Untitled",
                            location: freshItem.location,
                            photosAssetIdentifier: freshItem.photosAssetIdentifier
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
        // CRITICAL: When preservePlaceIdentity is true, skip title update entirely 
        // This protects contact-set names like "Uncle Bob" from being overwritten
        if preservePlaceIdentity {
            DiverLogger.pipeline.info("🛡️ Preserving place identity - skipping title update for '\(item.title ?? "")'")
        } else if let title = enrichment.title {
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
        
        if let newPlace = enrichment.placeContext {
            if !preservePlaceIdentity {
                // Full overwrite
                item.placeContext = newPlace
            } else if let existingPlace = item.placeContext {
                // Merge logic: Keep Identity (Name, ID, Address) but enrich with Details (Phone, Website, Photos, Tips)
                // if they are missing in existing.
                
                let mergedPlace = PlaceContext(
                    name: existingPlace.name, // Keep
                    categories: existingPlace.categories.isEmpty ? newPlace.categories : existingPlace.categories, // Enrich if empty
                    placeID: existingPlace.placeID, // Keep
                    address: existingPlace.address, // Keep
                    rating: existingPlace.rating ?? newPlace.rating, // Enrich
                    isOpen: existingPlace.isOpen ?? newPlace.isOpen, // Enrich
                    latitude: existingPlace.latitude, // Keep coordinates of override
                    longitude: existingPlace.longitude,
                    priceLevel: existingPlace.priceLevel ?? newPlace.priceLevel, // Enrich
                    phoneNumber: existingPlace.phoneNumber ?? newPlace.phoneNumber, // Enrich
                    website: existingPlace.website ?? newPlace.website, // Enrich
                    photos: (existingPlace.photos ?? []) + (newPlace.photos ?? []), // Merge lists
                    tips: (existingPlace.tips ?? []) + (newPlace.tips ?? [])
                )
                item.placeContext = mergedPlace
            } else {
                 // Should not happen if preservePlaceIdentity is true (implies there IS an identity to preserve), 
                 // but if placeContext was nil, just take the new one.
                 item.placeContext = newPlace
            }
        }
        
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

    private func extractLocationFromVideo(data: Data, identifier: String? = nil) async -> CLLocation? {
        // 1. Prefer PHAsset if available (Better metadata access, no temp file needed)
        if let identifier = identifier {
            DiverLogger.pipeline.debug("Attempting to extract location from PHAsset: \(identifier)")
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            if let asset = fetchResult.firstObject {
                 // Request AVAsset
                let options = PHVideoRequestOptions()
                options.version = .current
                options.isNetworkAccessAllowed = true
                options.deliveryMode = .highQualityFormat
                
                let assetLocation: CLLocation? = await withCheckedContinuation { continuation in
                    PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                        if let urlAsset = avAsset as? AVURLAsset {
                            // Helper to read metadata from AVAsset
                            Task {
                                let loc = await self.readLocationFromAVAsset(urlAsset)
                                continuation.resume(returning: loc)
                            }
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                }
                
                if let loc = assetLocation {
                    DiverLogger.pipeline.debug("Found location in PHAsset metadata: \(String(describing:loc.coordinate))")
                    return loc
                }
                
                // Also check PHAsset location directly (fast path)
                if let phLocation = asset.location {
                    DiverLogger.pipeline.debug("Found location in PHAsset property: \(String(describing:phLocation.coordinate))")
                    return phLocation
                }
            }
        }

        // 2. Fallback: Data-based extraction (Write to temp file)
        // AVAsset requires a URL. Write data to a temporary file.
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        
        do {
            try data.write(to: tempFile)
            defer {
                try? FileManager.default.removeItem(at: tempFile)
            }
            
            let asset = AVAsset(url: tempFile)
            return await readLocationFromAVAsset(asset)
            
        } catch {
            DiverLogger.pipeline.error("Failed to extract video location: \(error)")
        }
        
        return nil
    }
    
    private func readLocationFromAVAsset(_ asset: AVAsset) async -> CLLocation? {
        // Try Common Key first
        let commonItems = try? await asset.load(.commonMetadata)
        if let locationItem = commonItems?.first(where: { $0.commonKey == .commonKeyLocation }),
           let locationString = try? await locationItem.load(.stringValue) {
            return parseISO6709(locationString)
        }
        
        // Try QuickTime Metadata
        let metadata = try? await asset.load(.metadata)
        if let qtLocation = metadata?.first(where: { $0.identifier?.rawValue == "mdta/com.apple.quicktime.location.ISO6709" }),
           let locationString = try? await qtLocation.load(.stringValue) {
            return parseISO6709(locationString)
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

    // MARK: - Intelligence Processor Integration
    // Unified "Vision Engine" - replaces duplicate internal logic
    private let processor = IntelligenceProcessor()
    
    private func analyzeVisualContent(data: Data, existing: ProcessedItem, accumulatedContext: inout String, enrichmentService: LinkEnrichmentService?) async {
        guard !data.isEmpty else { return }
        
        let processor = IntelligenceProcessor()
        
        // Use EXIF orientation if available, otherwise default to Up
        var orientation: CGImagePropertyOrientation = .up
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let exifOrientation = properties[kCGImagePropertyOrientation as String] as? UInt32 {
            orientation = CGImagePropertyOrientation(rawValue: exifOrientation) ?? .up
        }
        
        // Create CGImage
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        
        print("🔍 [LocalPipeline] Analyzing Visual Content: \(data.count) bytes, \(cgImage.width)x\(cgImage.height), Orientation: \(orientation.rawValue)")
        
        do {
            // UNIFIED: Use IntelligenceProcessor for EVERYTHING (Sifting, Barcodes, Text, Classification)
            let results = try await processor.process(image: cgImage, orientation: orientation, mode: .fullAnalysis)
            
            DiverLogger.pipeline.info("📸 [LocalPipeline] IntelligenceProcessor returned \(results.count) results")
            
            // Integrate Results
            await integrateIntelligenceResults(results, to: existing, accumulatedContext: &accumulatedContext, enrichmentService: enrichmentService)
            
        } catch {
             DiverLogger.pipeline.error("❌ Visual Intelligence Failed: \(error)")
        }
    }
    
    // Unified Result Integrator
    private func integrateIntelligenceResults(_ results: [IntelligenceResult], to item: ProcessedItem, accumulatedContext: inout String, enrichmentService: LinkEnrichmentService?) async {
        var contextLog = ""
        var newTags: [String] = []
        
        for result in results {
            switch result {
            case .qr(let url):
                contextLog += "• QR Code: \(url.absoluteString)\n"
                newTags.append("QR Code")
                
                // QR Priority for URL: Write if empty OR if currently a local/placeholder placeholder
                let currentUrl = item.url?.lowercased() ?? ""
                let isPlaceholder = currentUrl.isEmpty || 
                                    currentUrl.hasPrefix("file://") || 
                                    currentUrl.contains("diver-storage") ||
                                    currentUrl.contains("diver-")
                
                if isPlaceholder {
                    item.url = url.absoluteString
                    accumulatedContext += "\nQR Code Link: \(url.absoluteString)"
                    
                    // Trigger immediate enrichment for this URL
                    if let enrichmentService, let url = URL(string: url.absoluteString) {
                         // We don't await here to keep pipeline fast, or we could?
                         // For now, let's just set the URL and let the next pass handle it
                    }
                }
                
            case .text(let text, let url):
                if let url = url, item.url == nil { 
                    item.url = url.absoluteString 
                    accumulatedContext += "\nOCR Link: \(url.absoluteString)"
                }
                // Only log significant text
                if text.count > 10 {
                    contextLog += "• OCR: \(text.prefix(50))...\n"
                    // Add to accumulated context for LLM
                    accumulatedContext += "\nDetected Text: \(text)"
                }
                
            case .product(let code, let type, _):
                contextLog += "• Product: \(code) (\(type.rawValue))\n"
                newTags.append(type.rawValue.uppercased())
                // Append to productMetadata
                let current = item.productMetadata ?? ""
                item.productMetadata = current.isEmpty ? "Product: \(code)" : current + "\nProduct: \(code)"
                
            case .semantic(let label, let confidence):
                if confidence > 0.6 {
                    // Filter common/boring labels
                    if !["screenshot", "text", "paper", "document"].contains(label.lowercased()) {
                         contextLog += "• Object: \(label)\n"
                         newTags.append(label)
                    }
                }
                
            case .siftedSubject(_, let label):
                if let label = label {
                    contextLog += "• Subject: \(label)\n"
                    newTags.append(label)
                }
                
            case .entertainment(let title, let type, _):
                 contextLog += "• Media: \(title) (\(type))\n"
                 newTags.append(String(describing: type))
                 accumulatedContext += "\nIdentify Media: \(title) (\(type))"
                 
            case .document(_, let text, let label):
                contextLog += "• Document: \(label ?? "Scanned")\n"
                newTags.append("Document")
                if let t = text { accumulatedContext += "\nDocument Content: \(t)" }
                
            default: break
            }
        }
        
        // Merge Tags
        for tag in newTags {
            if !item.tags.contains(tag) { item.tags.append(tag) }
        }
        
        if !contextLog.isEmpty {
            accumulatedContext += "\n--- Visual Analysis ---\n" + contextLog
        }
    }


    private func analyzeVideoAsset(id: String, item: ProcessedItem, accumulatedContext: inout String, enrichmentService: LinkEnrichmentService?) async {
        print("🎥 [LocalPipeline] Starting Multi-Frame Video Analysis for asset: \(id)")
        
        // 1. Fetch Asset
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetchResult.firstObject else {
            DiverLogger.pipeline.error("Could not find PHAsset \(id) for video analysis")
            return
        }
        
        // 2. Request AVAsset
        let options = PHVideoRequestOptions()
        options.version = .current
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        let videoURL: URL? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        
        guard let url = videoURL else {
            DiverLogger.pipeline.error("Failed to load AVURLAsset for video analysis (Asset was not file-backed)")
            return
        }
        
        // If we have a URL, use the scoring service
        if let url = videoURL {
            if #available(iOS 17.0, macOS 14.0, *) {
                let scorer = AestheticsScoringService()
                do {
                    // Extract 5 best frames
                    let thumbnails = try await scorer.extractBestFrames(from: url, count: 5)
                    print("🎥 [LocalPipeline] Extracted \(thumbnails.count) keyframes for analysis")
                    
                    let processor = IntelligenceProcessor()
                    
                    // 4. Analyze each frame
                    for (index, thumb) in thumbnails.enumerated() {
                        print("   - Analyzing frame \(index + 1)")
                        let results = try await processor.process(image: thumb.image, mode: .fullAnalysis)
                        await integrateIntelligenceResults(results, to: item, accumulatedContext: &accumulatedContext, enrichmentService: enrichmentService)
                    }
                    
                    item.processingLog.append("\(Date().formatted()): Video Analysis complete. Processed \(thumbnails.count) frames.")
                    
                } catch {
                    DiverLogger.pipeline.error("Frame extraction/analysis failed: \(error)")
                }
            } else {
                 DiverLogger.pipeline.warning("Video analysis requires iOS 17+")
            }
        } else {
             DiverLogger.pipeline.warning("Could not get file URL for video asset. Skipping multi-frame analysis.")
        }
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

    public func extractConcepts(from item: ProcessedItem) async {
        // Build comprehensive input from multiple sources
        var combinedText = ""
        
        // Primary: Web content
        if let text = item.webContext?.textContent, !text.isEmpty {
            combinedText += text
        }
        
        // Include structured data from web context (e.g., JSON-LD, OpenGraph)
        if let structured = item.webContext?.structuredData, !structured.isEmpty {
            combinedText += "\n\nStructured Data: \(structured)"
        }
        
        // Include transcription/OCR text from photos
        if let transcription = item.transcription, !transcription.isEmpty {
            combinedText += "\n\nOCR/Transcription: \(transcription)"
        }
        
        // Include place tips for local context
        if let tips = item.placeContext?.tips, !tips.isEmpty {
            combinedText += "\n\nPlace Tips: \(tips.prefix(3).joined(separator: "; "))"
        }
        
        // Include purpose/activity in the analysis input so concepts reflect both content and intent
        if !item.purposes.isEmpty {
            combinedText += "\n\nUser Context/Purpose: \(item.purposes.joined(separator: ", "))"
        }
        if let activity = item.activityContext {
            combinedText += "\n\nPhysical Activity: \(activity.type)"
        }
        
        guard !combinedText.isEmpty else { return }
        
        let contextService = ContextQuestionService()
        let enrichmentData = EnrichmentData(title: item.title, descriptionText: combinedText)

        if let (summary, statements, _, tags) = try? await contextService.processContext(from: enrichmentData) {
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

    public func autoCreateConcepts(from item: ProcessedItem) async throws {
        // CRITICAL: Only use SOURCE-EXTRACTED data, NOT LLM-generated content
        // This prevents session context contamination from polluting concepts
        
        var candidates = Set<String>()
        
        // 1. Visual classification (from Vision framework, not LLM)
        if let entityType = item.entityType, !entityType.isEmpty {
            candidates.insert(entityType.lowercased())
        }
        
        // 2. QR code domain (from barcode/QR scanning)
        if let qrPayload = item.qrContext?.payload, !qrPayload.isEmpty {
            // Add the domain as a concept if it's a URL
            if let url = URL(string: qrPayload), let host = url.host {
                candidates.insert(host)
            }
        }
        
        // 3. Place categories (from Foursquare/MapKit, not session context)
        if let placeCategories = item.placeContext?.categories {
            for cat in placeCategories where !cat.isEmpty {
                candidates.insert(cat.lowercased())
            }
        }
        
        // 4. Document file type (from document detection)
        if let fileType = item.documentContext?.fileType, !fileType.isEmpty {
            candidates.insert(fileType.lowercased())
        }
        
        // 5. OCR keywords (from Vision OCR, not LLM) - extract key terms
        if let transcription = item.transcription, !transcription.isEmpty {
            // Extract significant words (3+ chars, not common words)
            let commonWords = Set(["the", "and", "for", "are", "but", "not", "you", "all", "can", "had", "her", "was", "one", "our", "out", "day", "get", "has", "him", "his", "how", "its", "may", "new", "now", "old", "see", "way", "who", "boy", "did", "own", "say", "she", "two", "use"])
            let words = transcription
                .lowercased()
                .components(separatedBy: .alphanumerics.inverted)
                .filter { $0.count >= 4 && !commonWords.contains($0) }
            
            // Take top 3 longest unique words as keywords
            let uniqueWords = Set(words).sorted { $0.count > $1.count }.prefix(3)
            for word in uniqueWords {
                candidates.insert(word)
            }
        }
        
        guard !candidates.isEmpty else { return }

        for candidate in candidates {
            // Check if concept exists
            let descriptor = FetchDescriptor<UserConcept>(
                predicate: #Predicate<UserConcept> { $0.name == candidate }
            )
            
            // All source-extracted concepts have equal weight
            let weight = 1.0
            
            if let count = try? modelContext.fetchCount(descriptor), count == 0 {
                let concept = UserConcept(
                    name: candidate,
                    definition: "Auto-created from source media",
                    weight: weight
                )
                modelContext.insert(concept)
                DiverLogger.pipeline.debug("Auto-created UserConcept: '\(candidate)' from source extraction")
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
        
        // AUDIT: Unified Context Engine
        // We ignore the legacy 'accumulatedContext' string and instead rely on structured item fields
        // to ensure consistency across all pipeline entry points (process, reprocess, regenerate).

        
        // Fetch Session Context to inform intelligence
        var sessionContext = ""
        if let sessionID = item.sessionID {
            let currentID = item.id
            let oneHour: TimeInterval = 3600
            let minDate = item.createdAt.addingTimeInterval(-oneHour)
            let maxDate = item.createdAt.addingTimeInterval(oneHour)
            
            let sessionDesc = FetchDescriptor<ProcessedItem>(
                predicate: #Predicate { 
                    $0.sessionID == sessionID && 
                    $0.id != currentID &&
                    $0.createdAt >= minDate && 
                    $0.createdAt <= maxDate
                },
                sortBy: [SortDescriptor(\.createdAt)]
            )
            
            if let siblings = try? modelContext.fetch(sessionDesc) {
                // CRITICAL: Use ONLY raw OCR transcriptions from siblings.
                // DO NOT use titles or summaries - they are LLM-generated and 
                // cause contamination where one item's wrong analysis pollutes all others.
                let siblingContext = siblings.compactMap { sibling -> String? in
                    // ONLY raw OCR text and Visual Tags - no titles, no summaries, no LLM content
                    var parts: [String] = []
                    if let transcription = sibling.transcription, !transcription.isEmpty {
                        parts.append("OCR: \(transcription.prefix(150))")
                    }
                    if !sibling.tags.isEmpty {
                        parts.append("Tags: \(sibling.tags.prefix(5).joined(separator: ", "))")
                    }
                    return parts.isEmpty ? nil : "- \(parts.joined(separator: "; "))"
                }.joined(separator: "\n")
                
                if !siblingContext.isEmpty {
                    sessionContext = siblingContext
                }
            }
        }
        
        // Fallback: If Session Context is empty, use the item's own context to inform purpose
        // This is crucial for single imported items that have no siblings yet.
        if sessionContext.isEmpty {
            var parts: [String] = []
            if let t = item.title, t != "Untitled" && t != "Photo Import" { parts.append("Title: \(t)") }
            if let d = descriptor?.descriptionText { parts.append("Description: \(d)") }
            // Use transcription for context if available
            if let transcript = item.transcription { parts.append("Text: \(transcript.prefix(100))") }
            if !parts.isEmpty {
                sessionContext = "Item Content: " + parts.joined(separator: "; ")
            }
        }
        
        // 1. Determine explicit Location context
        // We defer to the Session's location name if available, as it represents the user's manual override or clustered location.
        var effectiveLocationName = item.location
        if let sessionID = item.sessionID {
             let sessionDesc = FetchDescriptor<DiverSession>(predicate: #Predicate { $0.sessionID == sessionID })
             if let session = try? modelContext.fetch(sessionDesc).first, let locName = session.locationName {
                 effectiveLocationName = locName
             }
        }

        // 2. Identify Descriptions (Priority: Descriptor > Transcription > Existing Summary)
        // We specifically check transcription first as it's the rawest source.
        let rawDescription = descriptor?.descriptionText ?? item.transcription ?? item.summary
        
        // 3. Construct Structured Data
        let finalCategories = Array(Set(item.tags + item.purposes)).sorted()
        
        let currentData = EnrichmentData(
            title: item.title,
            descriptionText: rawDescription,
            categories: finalCategories,
            location: effectiveLocationName,
            price: item.price,
            rating: item.rating,
            webContext: item.webContext,
            placeContext: item.placeContext,
            weatherContext: item.weatherContext,
            activityContext: item.activityContext,
            sessionContext: sessionContext.isEmpty ? nil : sessionContext,
            productContext: item.productMetadata,
            visualContext: accumulatedContext,
            sourceURL: item.url
        )
        
        do {
            print("🧠 [LocalPipeline] Starting LLM Analysis for item: \(item.id)")
            let (summary, questions, purpose, tags) = try await contextService.processContext(from: currentData, sessionID: item.sessionID)
            
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
            
            item.statusRaw = ProcessingStatus.ready.rawValue // Finalize status
            item.processingLog.append("\(Date().formatted()): LLM Analysis Complete. Finalized.")
            print("🔍 [DEBUG LocalPipeline] Setting statusRaw=\(item.statusRaw) for item.id=\(item.id)")
            do {
                try modelContext.save()
                print("✅ [DEBUG LocalPipeline] Save succeeded for item.id=\(item.id), statusRaw=\(item.statusRaw)")
            } catch {
                print("❌ [DEBUG LocalPipeline] Save FAILED for item.id=\(item.id): \(error)")
            }
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
                item.statusRaw = ProcessingStatus.reviewRequired.rawValue
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
        contactService: ContactServiceProvider?,
        itemSource: String? = nil  // Set to "photoLibraryImport" to skip weather API
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
                
                // 1. Prioritize MapKit (Native Apple Data)
                // User Request: "Default to using the mapkit enrichment reverse geocoding to find place locations rather than defaulting to the foursquare place"
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
                        styleTags: [],
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
                
                // 2. Foursquare Cross-Reference (Augmentation)
                // User Request: "I want the foursquare place to be identified by cross searching for the correct foursquare id for a mapkit identified place location"
                if let foursquareService {
                    if let placeID = descriptor?.placeID, !placeID.isEmpty {
                        // A. Explicit ID Override (Metadata Pipeline)
                        let detailed = try? await self.withTimeout(seconds: 15) {
                            try await foursquareService.fetchDetails(for: placeID)
                        }
                        if let d = detailed { fsEnrichment = d }
                        
                    } else if let mapKitName = fsEnrichment?.title, mapKitName != "Location" {
                        // B. Cross-Search using MapKit Name
                        // If we have a specific name from MapKit, find the Foursquare equivalent to get the ID/Details
                        let match = try? await self.withTimeout(seconds: 15) {
                             try await foursquareService.enrich(query: mapKitName, location: coords)
                        }
                        if let m = match {
                            // Merge Foursquare data (ID, Photos, etc) but ideally preserve the MapKit Identity if we trust it more?
                            // User request implies finding the "Correct Foursquare ID", suggests we want the Foursquare Identity once verified.
                            fsEnrichment = m
                        }
                        
                    } else if fsEnrichment == nil {
                        // C. Fallback: If MapKit failed completely (e.g. wilderness), try generic Foursquare nearby
                         fsEnrichment = try? await self.withTimeout(seconds: 15) {
                            try await foursquareService.enrich(location: coords)
                        }
                    }
                }

                // 3. Last Resort Fallback: Contact Detection (Home or Friends)
                // Use cached contact locations to identify "Mom's House" or "Work" if standard Places fail.
                let isGeneric = fsEnrichment == nil || fsEnrichment?.title == "Location"
                if isGeneric, !isUserLocationFixed, let contactService = contactService {
                    var matchFound = false
                    
                    // A. Check Home (Fastest)
                    var homeLoc: CLLocation? = initialHomeLoc
                    if homeLoc == nil {
                        homeLoc = try? await contactService.getHomeLocation()
                        if let homeLoc {
                            await MainActor.run { self.cachedHomeLocation = homeLoc }
                        }
                    }
                    
                    if let homeLoc = homeLoc, location.distance(from: homeLoc) < 300 {
                         let explicitLocationName = descriptor?.location
                         let isHomeName = explicitLocationName?.lowercased() == "home"
                         let isGenericOrEmpty = explicitLocationName == nil || explicitLocationName?.isEmpty == true
                         if isHomeName || isGenericOrEmpty {
                             let placeCtx = PlaceContext(name: "Home", categories: ["Home", "Personal"], placeID: "home-location", address: nil, rating: nil, isOpen: true)
                             fsEnrichment = EnrichmentData(title: "Home", descriptionText: "User's Home Location", image: nil, categories: ["Home"], styleTags: ["Personal"], location: "Home", placeContext: placeCtx)
                             matchFound = true
                         }
                    }
                    
                    // B. Check Nearby Contacts (Cached)
                    if !matchFound {
                        let nearby = await contactService.fetchContactsWithAddresses(sortedByDistanceFrom: location)
                        if let bestMatch = nearby.first, let dist = bestMatch.distance, dist < 150 { // 150m radius
                            let name = bestMatch.displayTitle // e.g., "John Doe's Home"
                            let placeCtx = PlaceContext(
                                name: name,
                                categories: ["Contact", "Personal"],
                                placeID: "contact-\(bestMatch.id)",
                                address: bestMatch.formattedAddress,
                                rating: nil,
                                isOpen: nil
                            )
                            fsEnrichment = EnrichmentData(
                                title: name,
                                descriptionText: "Contact Location: \(bestMatch.contactName)",
                                image: nil,
                                categories: ["Contact", "Personal"],
                                styleTags: ["Personal", "Contact"],
                                location: name,
                                placeContext: placeCtx
                            )
                            print("📍 LocalPipeline: Matched Contact Location: \(name) (\(Int(dist))m)")
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
            
            // 3. Weather (Skip for historical photo library imports)
            let sourceForWeather = itemSource
            group.addTask {
                // Skip WeatherKit API calls for historical imports - weather data isn't available for past dates
                if sourceForWeather == "photoLibraryImport" {
                    print("⏭️ Skipping WeatherKit for historical photo library import")
                    return nil
                }
                
                guard let location = finalLocation, let weatherService else { return nil }
                
                let weather = try? await self.withTimeout(seconds: 10, operation: {
                    await weatherService.fetchWeather(for: location)
                })
                
                if let weather = weather {
                    return ParallelEnrichmentResult(weather: weather)
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
    public func generateAndSaveSessionSummary(sessionID: String) async {
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
            
            // NUCLEAR OPTION: Scrub "Home" from the input text entirely to prevent LLM bias
            // We replace "Home" with "Location" or remove it if it looks like "At Home"
            // Case insensitive replace
            let scrubbedText = combinedText.replacingOccurrences(of: "Home", with: "Location", options: .caseInsensitive)
                                         .replacingOccurrences(of: "At Location", with: "At Unknown Location")
            
            let service = ContextQuestionService()
            let summary = try await service.summarizeText(scrubbedText)
            
            if let meta = try modelContext.fetch(fetchMeta).first {
                meta.summary = summary
                try modelContext.save()
                DiverLogger.pipeline.info("✅ Auto-generated summary for session \(sessionID)")
            }
        } catch {
            DiverLogger.pipeline.error("Failed to auto-generate session summary: \(error)")
        }
    }
    

    
    private func finalizeTitle(for item: ProcessedItem) {
        // 1. Check if current title is valid (Prominent Text / Metadata)
        let idString = item.id
        let currentTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isPlaceholder = currentTitle.isEmpty || currentTitle == "Untitled" || currentTitle == "Photo Import" || currentTitle == idString || currentTitle.contains("http") || currentTitle.contains("://") || isAddressString(currentTitle)
        
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
        
        // NOTE: Session summary is NOT set here anymore.
        // Session summaries are generated via LLM in MetadataPipelineService.generatePendingSessionSummaries()
        // which aggregates item transcriptions for a more meaningful summary.
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
