import Foundation
import SwiftData
import DiverShared
import CoreLocation
import ImageIO
import AVFoundation
import Vision
import Photos

@PipelineActor
public final class LocalPipelineService {
    nonisolated(unsafe) private let modelContext: ModelContext
    private var cachedHomeLocation: CLLocation?
    
    // MARK: - Caches
    
    /// CGImage decode cache keyed by data hash. Prevents re-decoding for Vision → FastVLM.
    /// NSCache auto-evicts under memory pressure.
    nonisolated(unsafe) private let cgImageCache = NSCache<NSString, CGImageWrapper>()
    
    /// Link enrichment cache keyed by URL string with 1-hour TTL.
    private var linkEnrichmentCache: [String: CachedEnrichment] = [:]
    
    /// Wrapper to store CGImage in NSCache (requires NSObject subclass)
    private final class CGImageWrapper: NSObject {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
    
    /// Link enrichment cache entry with TTL
    private struct CachedEnrichment {
        let data: EnrichmentData
        let timestamp: Date
        var isExpired: Bool { Date().timeIntervalSince(timestamp) > 3600 } // 1 hour TTL
    }

    nonisolated public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        cgImageCache.countLimit = 10 // Limit to 10 cached images
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
                context += "Place: \(name)"
                let categories = place.categories
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

        indexingService: KnowledgeGraphIndexingService? = nil,
        contextService: (any ContextProcessing)? = nil,
        fastVLMService: (any FastVLMAnalyzing)? = nil,
        scoringStrategies: [any ProductScoringStrategy] = [],
        recommender: (any ProductRecommending)? = nil
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
            do { try modelContext.save() } catch { DiverLogger.pipeline.error("Save failed (status update): \(error)") }

            if existing.inputId == nil {
                existing.inputId = input.id.uuidString
            }
            if existing.url == nil || existing.url?.isEmpty == true {
                let candidateURL = input.url?.trimmingCharacters(in: .whitespacesAndNewlines)
                existing.url = (candidateURL?.isEmpty == true) ? nil : candidateURL
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
            var pipelineContext = PipelineContext()
            
            if let urlString = input.url, let url = URL(string: urlString), let enrichmentService {
                if url.scheme?.lowercased().hasPrefix("secretatomics") == false {
                    do {
                        let enrichment = try await withTimeout(seconds: 10) {
                            try await self.cachedEnrich(url: url, service: enrichmentService)
                        }
                        
                        if let enrichment {
                            applyEnrichment(enrichment, to: existing)
                            pipelineContext.linkEnrichment = enrichment
                        }
                    } catch {
                        DiverLogger.pipeline.warning("⚠️ Link enrichment failed or timed out for \(url): \(error)")
                        // Proceed without enrichment
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
            if existing.siftedMask == nil, let mask = descriptor?.siftedMask {
                existing.siftedMask = mask
            }
            
            // CRITICAL: Ensure session is synced immediately for existing items too
            self.syncSession(for: existing)

            // Apply contextual Location -> Foursquare -> DuckDuckGo enrichment
            var effectiveLocation: CLLocation? = nil
            var hasUserOverride = false
            
            // 1. Check EXISTING overrides (manual edits) or Descriptor overrides (e.g. pinned from UI)
            // Priority: Descriptor (most recent user intent) > Existing Item (historical user intent)
            if let descLoc = descriptor?.location,
                let components = Optional(descLoc.split(separator: ",")),
                components.count == 2,
                let lat = Double(components[0].trimmingCharacters(in: .whitespaces)),
                let lon = Double(components[1].trimmingCharacters(in: .whitespaces)) {
                 
                 effectiveLocation = CLLocation(latitude: lat, longitude: lon)
                 hasUserOverride = true
                 DiverLogger.pipeline.debug("Using Descriptor Location Override (Pinned): \(lat), \(lon)")
            
            } else if let ctx = existing.placeContext, let lat = ctx.latitude, let lon = ctx.longitude {
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
            
            // 2. Metadata (high priority truth)
            // Check raw payload for location metadata if unavailable or if we want to augment "Home"
            // If explicit metadata exists, it trumps "Home" but NOT explicit user overrides.
            if effectiveLocation == nil || !hasUserOverride, let data = rawPayload, !isJSONData(data) {
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
                     
                     // Extract Original Date from EXIF
                     if let exif = props["{Exif}"] as? [String: Any],
                        let dateStr = exif["DateTimeOriginal"] as? String ?? exif["DateTimeDigitized"] as? String {
                         let formatter = DateFormatter()
                         formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                         if let date = formatter.date(from: dateStr) {
                             existing.originalDate = date
                             DiverLogger.pipeline.debug("Extracted Original Date from Image Metadata: \(date)")
                         }
                     }
                 } else {

                     // Fallback: Try Video Metadata
                     if let videoLocation = await extractLocationFromVideo(data: data, identifier: existing.photosAssetIdentifier) {
                         effectiveLocation = videoLocation
                         DiverLogger.pipeline.debug("Extracted Location from Video Metadata: \(videoLocation.coordinate.latitude), \(videoLocation.coordinate.longitude)")
                     }
                 }
             }

            // 3. Live Location (LOWEST priority - only if nothing else found)
            // CRITICAL: Only use live location if the item is NEW (recent). 
            // Do NOT update location of old items to current device location during edits/reprocessing.
            let isRecent = abs(input.createdAt.timeIntervalSinceNow) < 300 // 5 minutes
            
            if effectiveLocation == nil, let locationService, isRecent {
                effectiveLocation = await locationService.getCurrentLocation()
            }
            // If item is old and locationService is present but effectiveLocation is nil (was Home), we leave it nil 
            // to see if Metadata/Session can find better. If not, we fall back to existing Home context later?
            // Actually, if we return effectiveLocation = nil, no enrichment happens, so existing fields aren't touched.
                
                 
                 // 3. QR Code Detection (Fallback if NO URL)
                 // User Request: "if i photograph a sign and a qr code is found, the title should be the name of the page"
                 // 3. QR Code Detection (Fallback if NO URL or if URL is just a placeholder/local file)
                 // User Request: "if i photograph a sign and a qr code is found, the title should be the name of the page"
                 // Check if existing URL is nil OR starts with file scheme
                 let trimmedURL = existing.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                 let hasValidWebURL = !trimmedURL.isEmpty && 
                                      !trimmedURL.lowercased().hasPrefix("file://") &&
                                      !trimmedURL.lowercased().hasPrefix("diver-")
                 
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
                           await analyzeVisualContent(data: data, existing: existing, pipelineContext: &pipelineContext, enrichmentService: enrichmentService)
                       }
                 }
                 
                 // Session Context Override (Last Resort / Grouping)
                // CRITICAL: Only apply if NO user override and NO metadata found.
                // NOTE: Session merge logic moved to verify grouping, not override location data of the item itself blindly?
                // Actually, if an item is added to a session, it SHOULD inherit that session's location context if it has none.
                if effectiveLocation == nil, let descriptorSessionID = descriptor?.sessionID ?? existing.sessionID {
                     let fetchSession = FetchDescriptor<SessionMetadata>(predicate: #Predicate { $0.sessionID == descriptorSessionID })
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
                    _ = location.coordinate
                    
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
            let contactService = await MainActor.run { Services.shared.contactService }
            let inputURLString = input.url
            var localPipelineContext = pipelineContext
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
                    do { try modelContext.save() } catch { DiverLogger.pipeline.error("Save failed (enrichment): \(error)") }
                    return existing // Returning detached item, but it's deleted
                }
            }

            // ── Step 1b: Reverse Geocoding (update path) ──────────
            // Uses ReverseGeocodingService: MKLocalSearch → CLGeocoder → Foursquare
            if let location = effectiveLocation {
                let coords = location.coordinate
                if existing.placeContext == nil || !isUserLocationFixed {
                    if let placeContext = await Self.reverseGeocode(coordinate: coords) {
                        let placeEnrichment = EnrichmentData(
                            title: placeContext.name,
                            descriptionText: placeContext.address,
                            categories: placeContext.categories,
                            location: placeContext.address,
                            placeContext: placeContext
                        )
                        localPipelineContext.placeEnrichment = placeEnrichment
                        applyEnrichment(placeEnrichment, to: existing, preservePlaceIdentity: isUserLocationFixed)
                        DiverLogger.pipeline.debug("Reverse geocoding complete (update): \(placeContext.name ?? "Unknown")")
                    }
                } else {
                    DiverLogger.pipeline.debug("Skipping reverse geocoding (update) to preserve existing place context: \(existing.placeContext?.name ?? "Unknown")")
                    let existingPlace = existing.placeContext!
                    localPipelineContext.placeEnrichment = EnrichmentData(
                        title: existingPlace.name,
                        descriptionText: existingPlace.address,
                        categories: existingPlace.categories,
                        location: existingPlace.address ?? existing.location,
                        placeContext: existingPlace
                    )
                }
            }
            
            // ── Cancellation check: after Location + Visual Analysis ──
            guard !Task.isCancelled else {
                existing.status = .queued
                try? modelContext.save()
                throw CancellationError()
            }
            
            // Perform enrichment and LLM analysis (awaited for proper progress tracking)
            let results = await self.performParallelEnrichment(
                resolvedId: interimResolvedId,
                descriptor: descriptor,
                rawPayload: rawPayload,
                finalLocation: finalLocation,
                isUserLocationFixed: isUserLocationFixed,
                inputURLString: inputURLString,
                enrichmentService: enrichmentService,
                locationService: locationService,

                contactService: contactService,
                initialHomeLoc: self.cachedHomeLocation
            )
            
            for result in results {
                self.processParallelResult(result, to: existing, pipelineContext: &localPipelineContext)
            }
            
            // ── Cancellation check: after Parallel Enrichment ──
            guard !Task.isCancelled else {
                existing.status = .queued
                try? modelContext.save()
                throw CancellationError()
            }
            
            // Two-Stage Intelligence Pipeline:
            // Stage 1: SLM @Generable ContextAnalysis (fast, typed structured extraction)
            // Stage 2: FastVLM (multimodal synthesis using image + structured context)
            
            // Stage 1: SLM produces typed intermediate — always run for structured extraction
            await performLLMAnalysis(for: existing, descriptor: descriptor, pipelineContext: localPipelineContext)
            
            // ── Cancellation check: after SLM ──
            guard !Task.isCancelled else {
                existing.status = .queued
                try? modelContext.save()
                throw CancellationError()
            }
            
            // Stage 2: FastVLM analysis (enriches/overrides SLM output with multimodal understanding)
        if let fastVLMService, fastVLMService.isAvailable {
            let image: CGImage? = {
                guard let imageData = rawPayload ?? existing.rawPayload else { return nil }
                return createCGImage(from: imageData)
            }()
            
            var analysis: FastVLMAnalysis? = nil
            let router = await MainActor.run { Services.shared.edgeRouter }
            let system = await MainActor.run { Services.shared.actorSystem }
            
            if let router = router, let system = system, let imageData = rawPayload ?? existing.rawPayload {
                let decision = await router.shouldOffload(task: .vlmInference)
                if case .edge(let node, _) = decision {
                    do {
                        let identity = EdgeActorID(id: "EdgeInference", nodeName: node.deviceName)
                        let edgeActor = try EdgeInferenceActor.resolve(id: identity, using: system)
                        
                        let prompt: String
                        if let _ = image {
                            prompt = FastVLMEnrichmentService.buildGroundedPrompt(
                                visionTags: localPipelineContext.visualTags,
                                enrichmentContext: localPipelineContext.enrichmentContextString,
                                transcription: existing.transcription
                            )
                        } else {
                            prompt = FastVLMEnrichmentService.buildTextOnlyPrompt(
                                enrichmentContext: localPipelineContext.enrichmentContextString,
                                transcription: existing.transcription
                            )
                        }
                        
                        let resultText = try await edgeActor.runVLM(imageData: imageData, prompt: prompt)
                        analysis = FastVLMAnalysis(
                            imageDescription: resultText.imageDescription,
                            contextSummary: resultText.summary,
                            suggestedTitle: nil,
                            suggestedPurpose: resultText.purpose,
                            suggestedTags: resultText.tags,
                            statements: resultText.statements,
                            modelID: "EdgeInference"
                        )
                        DiverLogger.pipeline.info("🚀 [LocalPipeline] FastVLM offloaded to \(node.deviceName)")
                    } catch {
                        DiverLogger.pipeline.error("⚠️ [LocalPipeline] FastVLM offload failed, falling back to local: \(error)")
                    }
                }
            }
            
            if analysis == nil {
                analysis = try? await fastVLMService.analyze(
                    image: image,
                    visionTags: localPipelineContext.visualTags,
                    enrichmentContext: localPipelineContext.enrichmentContextString,
                    transcription: existing.transcription
                )
            }
            
            if let finalAnalysis = analysis {
                localPipelineContext.fastVLMAnalysis = finalAnalysis
                existing.fastVLMAnalysis = finalAnalysis
                existing.processingLog.append("\(Date().formatted()): FastVLM: grounded analysis complete")
                
                // Apply accurate fields
                if let title = finalAnalysis.suggestedTitle, existing.title == nil || existing.title?.isEmpty == true {
                    existing.title = title
                }
                if let purpose = finalAnalysis.suggestedPurpose {
                    if !existing.purposes.contains(purpose) {
                        existing.purposes.append(purpose)
                    }
                }
                
                if let contextSummary = finalAnalysis.contextSummary, !contextSummary.isEmpty {
                    // Prepend or overwrite the summary with the rich context from FastVLM
                    // FastVLMAnalysis natively tracks modelID, so conditionally use it.
                    let badgeModel = finalAnalysis.modelID ?? "FastVLM"
                    existing.summary = "\(contextSummary) [Model: \(badgeModel)]"
                }
                
                // Log remaining fields for debugging
                print("📝 [FastVLM] Item \(existing.id) — contextSummary: \(finalAnalysis.contextSummary ?? "nil")")
                print("📝 [FastVLM] Item \(existing.id) — suggestedTags: \(finalAnalysis.suggestedTags)")
                print("📝 [FastVLM] Item \(existing.id) — statements: \(finalAnalysis.statements)")
            }
        }
            
            // Stage ⑦: Commerce Intelligence (opt-in, all active strategies)
            if !scoringStrategies.isEmpty {
                await self.performCommerceEnrichment(
                    for: existing,
                    pipelineContext: &localPipelineContext,
                    scoringStrategies: scoringStrategies,
                    recommender: recommender
                )
            }
            
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
            siftedMask: descriptor?.siftedMask,
            photosAssetIdentifier: descriptor?.photosAssetIdentifier,
            categories: descriptor?.categories ?? [],
            location: descriptor?.location,
            latitude: descriptor?.latitude,
            longitude: descriptor?.longitude,
            placeID: descriptor?.placeID,
            price: descriptor?.price,
            isFavorite: descriptor?.isFavorite ?? false,
            purposes: descriptor?.purposes ?? []
        )
        print("💾 [DIAG] ProcessedItem created: id=\(resolvedId), sessionID=\(processed.sessionID ?? "NIL"), purposes=\(processed.purposes)")
        
        // Insert immediately for live UI updates
        processed.status = ProcessingStatus.processing
        processed.processingLog.append("\(Date().formatted()): Starting new item pipeline.")
        print("🚀 [LocalPipeline] Starting pipeline for item: \(processed.id)")
        
        // NOTE: syncSession is called AFTER enrichment (below) to use enriched location data.
        // Do NOT call it here prematurely.
        
        modelContext.insert(processed)
        do { try modelContext.save() } catch { DiverLogger.pipeline.error("Save failed (pipeline complete): \(error)") }
        
        var pipelineContext = PipelineContext()
        
        // 1.5 Barcode/QR Detection (Parity with Update Path)
        var analysisData = rawPayload
        if (analysisData == nil || isJSONData(analysisData!)), let assetId = descriptor?.photosAssetIdentifier {
             analysisData = await PhotosAssetLoader.shared.loadBestFrame(identifier: assetId)
        }
        
        if let data = analysisData, !isJSONData(data) {
             // UNIFIED VISUAL ANALYSIS
             // Replaces manual barcode scanning + separate runVisualIntelligenceAnalysis
             await analyzeVisualContent(data: data, existing: processed, pipelineContext: &pipelineContext, enrichmentService: enrichmentService)
        }
        
        // ── Cancellation check: after Visual Analysis ──
        guard !Task.isCancelled else {
            processed.status = .queued
            try? modelContext.save()
            throw CancellationError()
        }

        
        // Apply contextual Location -> Foursquare -> DuckDuckGo enrichment
        var currentLocation: CLLocation? = nil
        var hasUserOverride = false

        // 0. Explicit Descriptor Location (Pinned or Previously Set)
        if let lat = descriptor?.latitude, let lon = descriptor?.longitude {
             currentLocation = CLLocation(latitude: lat, longitude: lon)
             // Treat it as an override to prevent EXIF extraction from replacing it
             hasUserOverride = true
             DiverLogger.pipeline.debug("Using Descriptor Coordinates (Pinned/Existing): \(lat), \(lon)")
        } else if let descLoc = descriptor?.location,
           let components = Optional(descLoc.split(separator: ",")),
            components.count == 2,
            let lat = Double(components[0].trimmingCharacters(in: .whitespaces)),
            let lon = Double(components[1].trimmingCharacters(in: .whitespaces)) {
             
             currentLocation = CLLocation(latitude: lat, longitude: lon)
             hasUserOverride = true
             DiverLogger.pipeline.debug("Using Descriptor Location Override (String Parse): \(lat), \(lon)")
        }
        
        // 1. Try Metadata (image/video EXIF) first - explicit truth (Overrides "Home" or general GPS, but not Pinned/Existing)
        if currentLocation == nil, let data = rawPayload, !isJSONData(data) {
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
                  
                  // Extract Original Date from EXIF
                  if let exif = props["{Exif}"] as? [String: Any],
                     let dateStr = exif["DateTimeOriginal"] as? String ?? exif["DateTimeDigitized"] as? String {
                      let formatter = DateFormatter()
                      formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                      if let date = formatter.date(from: dateStr) {
                          processed.originalDate = date
                          DiverLogger.pipeline.debug("Extracted Original Date from New Item Metadata: \(date)")
                      }
                  }
              } else if let videoLocation = await extractLocationFromVideo(data: data, identifier: descriptor?.photosAssetIdentifier) {
                 currentLocation = videoLocation
                 DiverLogger.pipeline.debug("Extracted Location from New Item Video Metadata: \(videoLocation.coordinate.latitude), \(videoLocation.coordinate.longitude)")
             }
        }
        
        // 2. Fallback to Live GPS ONLY if item is Recent (Captured now) and no metadata/override
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
        
        // 3. SESSION CONTEXT OVERRIDE (Only if we still have no location)
        // If user explicitly adds to a session, they likely want that session's context if the item has none.
        if currentLocation == nil, let sessionID = descriptor?.sessionID ?? processed.sessionID {
             let fetchSession = FetchDescriptor<SessionMetadata>(predicate: #Predicate<SessionMetadata> { $0.sessionID == sessionID })
             if let session: SessionMetadata = try? modelContext.fetch(fetchSession).first {
                 if let lat = session.latitude, let lng = session.longitude {
                     // Use session location if explicitly set
                     currentLocation = CLLocation(latitude: lat, longitude: lng)
                     DiverLogger.pipeline.debug("Using Session Location Override: \(lat), \(lng)")
                 }

                 if let locName = session.locationName, !locName.isEmpty {
                     // If session has a name, we treat adoption as an override
                     hasUserOverride = true
                 }
             }
        }
        
        // 3b. Reverse Geocoding (part of Location Resolution)
        // Uses ReverseGeocodingService: MKLocalSearch → CLGeocoder → Foursquare
        // Runs before Vision so place context is available to all downstream stages.
        if let location = currentLocation {
            let coords = location.coordinate
            
            // If the item ALREADY has a placeContext (e.g. from a user edit that was preserved),
            // do not aggressively reverse geocode and overwrite it!
            if processed.placeContext == nil || !hasUserOverride {
                if let placeContext = await Self.reverseGeocode(coordinate: coords) {
                    let placeEnrichment = EnrichmentData(
                        title: placeContext.name,
                        descriptionText: placeContext.address,
                        categories: placeContext.categories,
                        location: placeContext.address,
                        placeContext: placeContext
                    )
                    pipelineContext.placeEnrichment = placeEnrichment
                    
                    applyEnrichment(placeEnrichment, to: processed, preservePlaceIdentity: hasUserOverride)
                    DiverLogger.pipeline.debug("Reverse geocoding complete: \(placeContext.name ?? "Unknown")")
                }
            } else {
                DiverLogger.pipeline.debug("Skipping reverse geocoding to preserve existing place context: \(processed.placeContext?.name ?? "Unknown")")
                let existingPlace = processed.placeContext!
                pipelineContext.placeEnrichment = EnrichmentData(
                    title: existingPlace.name,
                    descriptionText: existingPlace.address,
                    categories: existingPlace.categories,
                    location: existingPlace.address ?? processed.location,
                    placeContext: existingPlace
                )
            }
        }
        
        // Capture immutable copy for downstream tasks
        let finalLocation = currentLocation
        let isUserLocationFixed = hasUserOverride
        
        let contactService = await MainActor.run { Services.shared.contactService }
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
            contactService: contactService,
            initialHomeLoc: cachedHomeLocation
        )
        
        for result in results {
            processParallelResult(result, to: processed, pipelineContext: &pipelineContext)
        }
        processed.processingLog.append("\(Date().formatted()): Parallel enrichment complete.")
        print("✅ [LocalPipeline] Parallel enrichment complete for \(processed.id)")
        
        // ── Cancellation check: after Parallel Enrichment ──
        guard !Task.isCancelled else {
            processed.status = .queued
            try? modelContext.save()
            throw CancellationError()
        }
        
        // Two-Stage Intelligence Pipeline:
        // Stage 1: SLM @Generable ContextAnalysis (fast, typed structured extraction)
        // Stage 2: FastVLM (multimodal synthesis using image + structured context)
        
        // Stage 1: SLM produces typed intermediate — always run for structured extraction
        await performLLMAnalysis(for: processed, descriptor: descriptor, pipelineContext: pipelineContext)
        
        // ── Cancellation check: after SLM ──
        guard !Task.isCancelled else {
            processed.status = .queued
            try? modelContext.save()
            throw CancellationError()
        }
        
        // Stage 2: FastVLM analysis (replaces SLM summary when available)
        if let fastVLMService, fastVLMService.isAvailable {
            let image: CGImage? = {
                guard let imageData = rawPayload else { return nil }
                return createCGImage(from: imageData)
            }()
            
            var analysis: FastVLMAnalysis? = nil
            let router = await MainActor.run { Services.shared.edgeRouter }
            let system = await MainActor.run { Services.shared.actorSystem }
            
            if let router = router, let system = system, let imageData = rawPayload {
                let decision = await router.shouldOffload(task: .vlmInference)
                if case .edge(let node, _) = decision {
                    do {
                        let identity = EdgeActorID(id: "EdgeInference", nodeName: node.deviceName)
                        let edgeActor = try EdgeInferenceActor.resolve(id: identity, using: system)
                        
                        let prompt: String
                        if let _ = image {
                            prompt = FastVLMEnrichmentService.buildGroundedPrompt(
                                visionTags: pipelineContext.visualTags,
                                enrichmentContext: pipelineContext.enrichmentContextString,
                                transcription: processed.transcription
                            )
                        } else {
                            prompt = FastVLMEnrichmentService.buildTextOnlyPrompt(
                                enrichmentContext: pipelineContext.enrichmentContextString,
                                transcription: processed.transcription
                            )
                        }
                        
                        let resultText = try await edgeActor.runVLM(imageData: imageData, prompt: prompt)
                        analysis = FastVLMAnalysis(
                            imageDescription: resultText.imageDescription,
                            contextSummary: resultText.summary,
                            suggestedTitle: nil,
                            suggestedPurpose: resultText.purpose,
                            suggestedTags: resultText.tags,
                            statements: resultText.statements,
                            modelID: "EdgeInference"
                        )
                        DiverLogger.pipeline.info("🚀 [LocalPipeline] FastVLM Reprocess offloaded to \(node.deviceName)")
                    } catch {
                        DiverLogger.pipeline.error("⚠️ [LocalPipeline] FastVLM Reprocess offload failed, falling back to local: \(error)")
                    }
                }
            }
            
            if analysis == nil {
                analysis = try? await fastVLMService.analyze(
                    image: image,
                    visionTags: pipelineContext.visualTags,
                    enrichmentContext: pipelineContext.enrichmentContextString,
                    transcription: processed.transcription
                )
            }
            
            if let analysis = analysis {
                pipelineContext.fastVLMAnalysis = analysis
                processed.fastVLMAnalysis = analysis
                processed.processingLog.append("\(Date().formatted()): FastVLM: grounded analysis complete")
                
                // Apply accurate fields
                if let title = analysis.suggestedTitle, processed.title == nil || processed.title?.isEmpty == true {
                    processed.title = title
                }
                if let purpose = analysis.suggestedPurpose {
                    if !processed.purposes.contains(purpose) {
                        processed.purposes.append(purpose)
                    }
                }
                
                if let contextSummary = analysis.contextSummary, !contextSummary.isEmpty {
                    let badgeModel = analysis.modelID ?? "FastVLM"
                    processed.summary = "\(contextSummary) [Model: \(badgeModel)]"
                }
                
                // Log remaining fields for debugging
                print("📝 [FastVLM] Item \(processed.id) — contextSummary: \(analysis.contextSummary ?? "nil")")
                print("📝 [FastVLM] Item \(processed.id) — suggestedTags: \(analysis.suggestedTags)")
                print("📝 [FastVLM] Item \(processed.id) — statements: \(analysis.statements)")
            }
        }
        
        // Stage ⑦: Commerce Intelligence (opt-in, all active strategies)
        if !scoringStrategies.isEmpty {
            await performCommerceEnrichment(
                for: processed,
                pipelineContext: &pipelineContext,
                scoringStrategies: scoringStrategies,
                recommender: recommender
            )
        }
        
        // Trigger live UI update
        do { try modelContext.save() } catch { DiverLogger.pipeline.error("Save failed (reprocess): \(error)") }
        
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
                     try await self.cachedEnrich(url: qrURL, service: enrichmentService)
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
                     
                     // Add web content to pipeline context
                     if let textContent = enrichment.webContext?.textContent, !textContent.isEmpty {
                         if let existing = pipelineContext.documentContent {
                             pipelineContext.documentContent = existing + "\n" + String(textContent.prefix(2000))
                         } else {
                             pipelineContext.documentContent = String(textContent.prefix(2000))
                         }
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
        

        // LLM "Second Pass" removed — performLLMAnalysis already runs at Stage 1 above.
        // Running it again was pure duplication, doubling processing time.

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
        // SKIP if the item already has a sessionID from the descriptor (user-assigned or prior pipeline run).
        // Only group NEW items that have no pre-existing session assignment.
        let hasPreAssignedSession = descriptor?.sessionID != nil
        if !hasPreAssignedSession, let placeID = processed.placeContext?.placeID, !placeID.isEmpty {
             let desc = FetchDescriptor<SessionMetadata>(predicate: #Predicate<SessionMetadata> { $0.placeID == placeID })
             if let existingSession: SessionMetadata = try? modelContext.fetch(desc).first {
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
        print("💾 [DIAG] After syncSession: id=\(processed.id), sessionID=\(processed.sessionID ?? "NIL"), session=\(processed.session?.sessionID ?? "NIL")")

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

        // Session summary generation is deferred — caller batches session IDs
        // to avoid redundant LLM calls when multiple items share a session.

        // Mark as ready before returning
        processed.status = ProcessingStatus.ready
        do { try modelContext.save() } catch { DiverLogger.pipeline.error("Save failed (batch reprocess): \(error)") }

        return processed
    }


    public func refreshProcessedItems(
        enrichmentService: LinkEnrichmentService? = nil,
        locationService: LocationProvider? = nil,
        indexingService: KnowledgeGraphIndexingService? = nil
    ) async throws {
        let inputs = try modelContext.fetch(FetchDescriptor<LocalInput>())
        DiverLogger.pipeline.info("Refreshing \(inputs.count) processed items")

        for input in inputs {
            _ = try await process(
                input: input,
                enrichmentService: enrichmentService,
                locationService: locationService,
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
        // We pass empty PipelineContext because performLLMAnalysis now constructs data from the item fields directly.
        await performLLMAnalysis(for: item, descriptor: nil, pipelineContext: PipelineContext())
    }
    


    public func reprocessPipeline(
        cutoffDate: Date,
        enrichmentService: LinkEnrichmentService? = nil,
        locationService: LocationProvider? = nil,
        indexingService: KnowledgeGraphIndexingService? = nil,
        fastVLMService: (any FastVLMAnalyzing)? = nil,
        progressHandler: (@Sendable (Double) -> Void)? = nil,
        logHandler: (@Sendable (String) -> Void)? = nil
    ) async throws {
        // 1. Clear existing queue items (processing or queued) to avoid duplicates or stalls
        // We delete the ProcessedItem but ensure the LocalInput is preserved for the main loop if within date range,
        // OR we just reset them to be processed immediately.
        // The user asked to "take everything ... out first", implying a reset of the queue.
        // We will fetch all pending items, delete them, and recreate them as inputs if needed.
        let queueFetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate {
                $0.createdAt >= cutoffDate && (
                    $0.statusRaw == "queued" ||
                    $0.statusRaw == "processing" ||
                    $0.statusRaw == "failed"
                )
            }
        )
        if let queuedItems: [ProcessedItem] = try? modelContext.fetch(queueFetch) {
            let msg = "Resetting \(queuedItems.count) stalled items in queue for reprocessing."
            DiverLogger.pipeline.info("\(msg)")
            await MainActor.run { logHandler?(msg) }
            
            for item in queuedItems {
                // Reset status to queued instead of deleting, to preserve sessionID and other metadata
                item.status = .queued
                item.processingLog.append("\(Date().formatted()): Reset to queued during maintenance.")
                
                // Safety: Still ensure a LocalInput exists for the main loop fallback, 
                // but the batch logic below will handle the actual processing efficiently.
                if let inputIdStr = item.inputId, let inputID = UUID(uuidString: inputIdStr) {
                    let inputDesc = FetchDescriptor<LocalInput>(predicate: #Predicate { $0.id == inputID })
                    let existingInputs: [LocalInput]? = try? modelContext.fetch(inputDesc)
                    if existingInputs?.isEmpty ?? true {
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
            }
            do { try modelContext.save() } catch { DiverLogger.pipeline.error("Save failed (library maintain): \(error)") }
        }

        // Fetch items created after the cutoff
        let fetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.createdAt >= cutoffDate }
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
                
                let task = Task(priority: .utility) { @PipelineActor in
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
                        let sessionFetch = FetchDescriptor<SessionMetadata>(
                            predicate: #Predicate<SessionMetadata> { $0.sessionID == sessionID }
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
                            categories: freshItem.categories,
                            location: freshItem.location,
                            createdAt: freshItem.createdAt,
                            type: DiverItemType(rawValue: freshItem.entityType ?? "web") ?? .web,
                            attributionID: freshItem.attributionID,
                            masterCaptureID: freshItem.masterCaptureID,
                            photosAssetIdentifier: freshItem.photosAssetIdentifier,
                            sessionID: freshItem.sessionID,
                            purposes: Set(freshItem.purposes)
                        )
                        
                        logHandler?("Analyzing: \(freshItem.title ?? "Untitled")")
                        
                        // Trigger process
                        let processed = try await self.process(
                            input: input,
                            descriptor: maintenanceDescriptor,
                            enrichmentService: enrichmentService,
                            locationService: nil, // Prevent using current GPS for historical items; rely on Session location
                            indexingService: indexingService,
                            fastVLMService: fastVLMService
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
            // Sync top-level location fields for efficient spatial queries
            if let lat = newPlace.latitude { item.latitude = lat }
            if let lon = newPlace.longitude { item.longitude = lon }
            if let pid = newPlace.placeID { item.placeID = pid }

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
                    latitude: existingPlace.latitude ?? newPlace.latitude, // Keep coordinates of override, or enrich
                    longitude: existingPlace.longitude ?? newPlace.longitude,
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
            // Update sessionID if the parent doesn't have one yet
            if parent.sessionID == nil, let sid = item.sessionID {
                parent.sessionID = sid
                syncSession(for: parent)
            }
        } else {
            parent = ProcessedItem(
                id: UUID().uuidString,
                title: purpose,
                entityType: "activity",
                status: .ready,
                sessionID: item.sessionID
            )
            modelContext.insert(parent)
            syncSession(for: parent)
        }
        
        item.parentItem = parent
        DiverLogger.pipeline.info("Linked item \(item.id) to parent activity '\(purpose)'")
    }

    /// Extracts GPS location from video metadata. `nonisolated` — uses PHAsset/AVFoundation only, no SwiftData.
    nonisolated private func extractLocationFromVideo(data: Data, identifier: String? = nil) async -> CLLocation? {
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
            
            let asset = AVURLAsset(url:tempFile)
            return await readLocationFromAVAsset(asset)
            
        } catch {
            DiverLogger.pipeline.error("Failed to extract video location: \(error)")
        }
        
        return nil
    }
    
    nonisolated private func readLocationFromAVAsset(_ asset: AVURLAsset) async -> CLLocation? {
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
    
    nonisolated private func parseISO6709(_ string: String) -> CLLocation? {
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
    // NOTE: IntelligenceProcessor is created inside Task.detached closures
    // since it must cross actor boundaries. No stored instance needed.
    
    private func analyzeVisualContent(data: Data, existing: ProcessedItem, pipelineContext: inout PipelineContext, enrichmentService: LinkEnrichmentService?) async {
        guard !data.isEmpty else { return }
        
        // Items already typed as "document" were rectified + text-extracted by the camera capture pipeline.
        // Re-running full analysis would double-rectify the already-corrected image.
        if existing.entityType == "document" {
            DiverLogger.pipeline.debug("⏭️ Skipping visual analysis for pre-rectified document item: \(existing.id)")
            return
        }
        
        // Run CPU-heavy Vision processing OFF the main thread.
        // IntelligenceProcessor is Sendable and does no SwiftData work.
        let results: [IntelligenceResult]
        do {
            let capturedData = data
            results = try await Task.detached(priority: .userInitiated) {
                // Bail if cancelled (e.g. app backgrounded) before submitting GPU work
                guard !Task.isCancelled else { return [IntelligenceResult]() }
                
                let router = await MainActor.run { Services.shared.edgeRouter }
                let system = await MainActor.run { Services.shared.actorSystem }
                
                if let router = router, let system = system {
                    let decision = await router.shouldOffload(task: .visionAnalysis)
                    if case .edge(let node, _) = decision {
                        do {
                            let identity = EdgeActorID(id: "EdgeInference", nodeName: node.deviceName)
                            let edgeActor = try EdgeInferenceActor.resolve(id: identity, using: system)
                            let visionResult = try await edgeActor.analyzeImage(capturedData)
                            DiverLogger.pipeline.info("🚀 [LocalPipeline] Vision Analysis offloaded to \(node.deviceName)")
                            
                            var edgeResults: [IntelligenceResult] = []
                            if let text = visionResult.ocrText, !text.isEmpty {
                                edgeResults.append(.text(text, nil))
                            }
                            for qr in visionResult.qrURLs {
                                if let url = URL(string: qr) {
                                    edgeResults.append(.qr(url))
                                }
                            }
                            for tag in visionResult.semanticTags {
                                edgeResults.append(.semantic(tag, confidence: 0.99))
                            }
                            if visionResult.hasDocument {
                                edgeResults.append(.document(VNRectangleObservation(), text: nil, label: "Document", rectifiedImage: nil))
                            }
                            if visionResult.hasForegroundSubject {
                                // Omitted: VNInstanceMaskObservation can't be easily reconstituted. FastVLM handles descriptions.
                            }
                            if let score = visionResult.aestheticsScore {
                                edgeResults.append(.aesthetics(score: score))
                            }
                            // Omitted: SaliencyResult map types differ and are purely analytical right now
                            
                            return edgeResults
                        } catch {
                            DiverLogger.pipeline.error("⚠️ [LocalPipeline] Edge offload failed, falling back to local: \(error)")
                        }
                    }
                }
                
                let processor = IntelligenceProcessor()
                
                // Single image source parse for both EXIF orientation and CGImage creation
                guard let source = CGImageSourceCreateWithData(capturedData as CFData, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [IntelligenceResult]() }
                
                var orientation: CGImagePropertyOrientation = .up
                if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                   let exifOrientation = properties[kCGImagePropertyOrientation as String] as? UInt32 {
                    orientation = CGImagePropertyOrientation(rawValue: exifOrientation) ?? .up
                }
                
                print("🔍 [LocalPipeline] Analyzing Visual Content: \(capturedData.count) bytes, \(cgImage.width)x\(cgImage.height), Orientation: \(orientation.rawValue)")
                
                // UNIFIED: Use IntelligenceProcessor for EVERYTHING (Sifting, Barcodes, Text, Classification)
                return try await processor.process(image: cgImage, orientation: orientation, mode: .fullAnalysis)
            }.value
            
            guard !results.isEmpty else { return }
            DiverLogger.pipeline.info("📸 [LocalPipeline] IntelligenceProcessor returned \(results.count) results")
            
            // Integrate results ON main actor (writes to ProcessedItem / SwiftData)
            await integrateIntelligenceResults(results, to: existing, pipelineContext: &pipelineContext, enrichmentService: enrichmentService)
            
        } catch {
             DiverLogger.pipeline.error("❌ Visual Intelligence Failed: \(error)")
        }
    }
    
    // Unified Result Integrator
    private func integrateIntelligenceResults(_ results: [IntelligenceResult], to item: ProcessedItem, pipelineContext: inout PipelineContext, enrichmentService: LinkEnrichmentService?) async {
        var contextLog = ""
        var newTags: [String] = []
        
        for result in results {
            switch result {
            case .qr(let url):
                contextLog += "• QR Code: \(url.absoluteString)\n"
                newTags.append("QR Code")
                pipelineContext.qrPayloads.append(url.absoluteString)
                
                // QR Priority for URL: Write if empty OR if currently a local/placeholder placeholder
                let currentUrl = item.url?.lowercased() ?? ""
                let isPlaceholder = currentUrl.isEmpty || 
                                    currentUrl.hasPrefix("file://") || 
                                    currentUrl.contains("diver-storage") ||
                                    currentUrl.contains("diver-")
                
                if isPlaceholder {
                    item.url = url.absoluteString
                    
                    // Enrich the QR URL with web scraping for richer context
                    if let enrichmentService,
                       let scheme = url.scheme?.lowercased(),
                       scheme == "http" || scheme == "https" {
                        DiverLogger.pipeline.info("🔗 QR URL detected in Vision pass: \(url.absoluteString) - enriching")
                        if let enrichment = try? await self.withTimeout(seconds: 15, operation: {
                            try await enrichmentService.enrich(url: url)
                        }) {
                            if item.title == nil || item.title?.isEmpty == true {
                                item.title = enrichment.title
                            }
                            if item.summary == nil || item.summary?.isEmpty == true {
                                item.summary = enrichment.descriptionText
                            }
                            item.webContext = enrichment.webContext
                            
                            if let textContent = enrichment.webContext?.textContent, !textContent.isEmpty {
                                pipelineContext.documentContent = (pipelineContext.documentContent ?? "") + "\n" + String(textContent.prefix(2000))
                            }
                        }
                    }
                }
                
            case .text(let text, let url):
                if let url = url, item.url == nil { 
                    item.url = url.absoluteString 
                }
                // Accumulate ALL OCR text into transcription (not just documents)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if item.transcription == nil {
                        item.transcription = text
                    } else {
                        item.transcription! += "\n" + text
                    }
                }
                // Add to structured context
                if text.count > 3 {
                    contextLog += "• OCR: \(text.prefix(50))...\n"
                    // Append to existing OCR text in pipeline context
                    if let existing = pipelineContext.ocrText {
                        pipelineContext.ocrText = existing + "\n" + text
                    } else {
                        pipelineContext.ocrText = text
                    }
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
                         pipelineContext.visualTags.append(label)
                    }
                }
                
            case .siftedSubject(_, _, let label):
                if let label = label {
                    contextLog += "• Subject: \(label)\n"
                    newTags.append(label)
                    pipelineContext.visualTags.append(label)
                }
                
            case .entertainment(let title, let type, _):
                 contextLog += "• Media: \(title) (\(type))\n"
                 newTags.append(String(describing: type))
                 pipelineContext.identifiedMedia = "\(title) (\(type))"
                 
            case .document(_, let text, let label, let rectifiedImage):
                contextLog += "• Document: \(label ?? "Scanned")\n"
                newTags.append("Document")
                if let t = text { 
                    pipelineContext.documentContent = t
                    // CRITICAL: Set transcription if not already set (fixes TextEditor issue)
                    if item.transcription == nil {
                         item.transcription = t
                    } else {
                         item.transcription! += "\n" + t
                    }
                }
                
                // Save Rectified Image to DocumentContext
                if let rectified = rectifiedImage {
                    let newContext: DocumentContext
                    if let existing = item.documentContext {
                         newContext = DocumentContext(
                            fileType: existing.fileType,
                            pageCount: existing.pageCount,
                            author: existing.author,
                            rectifiedPayload: rectified // Update with new image
                         )
                    } else {
                         newContext = DocumentContext(
                            fileType: "image/jpeg",
                            rectifiedPayload: rectified
                         )
                    }
                    item.documentContext = newContext
                }
                
                
            case .aesthetics(let score):
                item.aestheticsScore = Double(score)
                contextLog += "• Quality Score: \(String(format: "%.0f%%", score * 100))\n"
                
            default: break
            }
        }
        
        // Merge Tags
        for tag in newTags {
            if !item.tags.contains(tag) { item.tags.append(tag) }
        }
        
        if !contextLog.isEmpty {
            pipelineContext.visualAnalysisLog = contextLog
        }
    }


    private func analyzeVideoAsset(id: String, item: ProcessedItem, pipelineContext: inout PipelineContext, enrichmentService: LinkEnrichmentService?) async {
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
        
        guard videoURL != nil else {
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
                        let results = try await processor.process(image: thumb.image, orientation: .up, mode: .fullAnalysis)
                        await integrateIntelligenceResults(results, to: item, pipelineContext: &pipelineContext, enrichmentService: enrichmentService)
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
        if regex?.firstMatch(in: title, options: [], range: range) != nil {
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
            let nameValue = candidate
            // Check if concept exists
            let descriptor = FetchDescriptor<UserConcept>(
                predicate: #Predicate<UserConcept> { $0.name == nameValue }
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
            } else {
                // Increment weight for existing concept
                if let existing = try? modelContext.fetch(descriptor).first {
                    existing.weight += weight
                    DiverLogger.pipeline.debug("Incremented UserConcept '\(candidate)' weight to \(existing.weight)")
                }
            }
        }
    }
    private func updateSessionMetadata(from descriptor: DiverItemDescriptor) async {
        guard let sessionID = descriptor.sessionID else { return }
        
        // Fetch existing or create new
        let fetch = FetchDescriptor<SessionMetadata>(
            predicate: #Predicate<SessionMetadata> { $0.sessionID == sessionID }
        )
        
        let session: SessionMetadata
        if let existing = try? modelContext.fetch(fetch).first {
             session = existing
        } else {
             session = SessionMetadata(sessionID: sessionID)
             modelContext.insert(session)
             DiverLogger.pipeline.debug("Created new SessionMetadata for session: \(sessionID)")
        }
        
        // Update fields if present in descriptor
        // We prioritize the most recent location info
        if let lat = descriptor.latitude { session.latitude = lat }
        if let lng = descriptor.longitude { session.longitude = lng }
        if let pid = descriptor.placeID { session.placeID = pid }
        if let loc = descriptor.location {
            // Only set locationName if it's a human-readable name, not coordinates
            let isCoordinates = loc.contains(",") && loc.split(separator: ",").allSatisfy { Double($0.trimmingCharacters(in: .whitespaces)) != nil }
            if !isCoordinates {
                session.locationName = loc
            } else if session.locationName == nil {
                // Fallback: coordinates only if no name exists yet
                session.locationName = loc
            }
        }
        
        // Update timestamp to now to reflect latest activity
        session.updatedAt = Date()
        
        // If title is currently nil or date-based, try to set a better one based on the master item?
        // For now, we leave title management to the user or later inference.
    }

    // MARK: - Stage ⑦: Commerce Intelligence
    
    /// Performs opt-in commerce enrichment: product classification → multi-strategy scoring → recommendations.
    /// Runs ALL passed strategies, collecting independent `ProductScore` per engine.
    /// Brand affinity is used as the primary weight for composite recommendation ranking.
    private func performCommerceEnrichment(
        for item: ProcessedItem,
        pipelineContext: inout PipelineContext,
        scoringStrategies: [any ProductScoringStrategy],
        recommender: (any ProductRecommending)?
    ) async {
        // Step 1: Determine product classification from available context
        let classification: ProductClassification?
        
        if let barcode = pipelineContext.qrPayloads.first(where: { isBarcode($0) }) {
            classification = ProductClassification(
                productID: barcode,
                name: item.title ?? "Unknown Product",
                category: inferCategory(from: item),
                brand: extractBrand(from: item),
                barcode: barcode,
                confidence: 0.9
            )
        } else if !pipelineContext.productConcepts.isEmpty {
            let primaryConcept = pipelineContext.productConcepts.first ?? "product"
            classification = ProductClassification(
                productID: UUID().uuidString,
                name: item.title ?? primaryConcept,
                category: inferCategory(from: item),
                brand: extractBrand(from: item),
                barcode: nil,
                confidence: 0.6
            )
        } else if item.categories.contains("product") || item.productMetadata != nil {
            classification = ProductClassification(
                productID: item.id,
                name: item.title ?? "Detected Product",
                category: inferCategory(from: item),
                brand: extractBrand(from: item),
                barcode: nil,
                confidence: 0.4
            )
        } else {
            return // No product detected
        }
        
        guard let classification else { return }
        pipelineContext.productClassification = classification
        
        // Step 1b: Auto-create ownership record for barcode scans
        // Only creates for high-confidence detections (barcodes) to avoid noise
        if classification.barcode != nil {
            let owned = OwnedProduct(
                productID: classification.productID,
                productName: classification.name,
                brand: classification.brand,
                category: classification.category,
                barcode: classification.barcode,
                source: .tagScan,
                scoringStrategyIDs: scoringStrategies.map(\.strategyID),
                captureItemID: item.id
            )
            modelContext.insert(owned)
        }
        
        // Step 1c: Auto-create brand UserConcept for brand tracking
        if let brand = classification.brand, !brand.isEmpty {
            let brandFetch = FetchDescriptor<UserConcept>(
                predicate: #Predicate { $0.name == brand }
            )
            let existing = try? modelContext.fetch(brandFetch)
            if let concept = existing?.first {
                // Increment weight for known brands
                concept.weight += 1.0
            } else {
                // Create new brand concept
                let concept = UserConcept(
                    name: brand,
                    definition: "Brand: \(brand) — auto-detected from product scan",
                    weight: 1.0
                )
                modelContext.insert(concept)
            }
        }
        
        // Step 2: Fetch enrichment data once (shared across strategies that need it)
        let esgService = ESGEnrichmentService()
        let govService = GovernmentDataService()
        
        // Step 2a: Parallel fetch — ESG product data + Government safety data
        // Both are independent and can run concurrently
        async let govFuture = govService.enrich(product: classification)
        
        let esgEnrichment: ESGEnrichment?
        if let barcode = classification.barcode {
            esgEnrichment = try? await esgService.enrich(barcode: barcode)
        } else {
            esgEnrichment = try? await esgService.enrich(category: classification.category)
        }
        
        let govEnrichment: GovernmentEnrichment? = await govFuture
        
        pipelineContext.governmentData = govEnrichment
        item.governmentContext = govEnrichment
        
        if let gov = govEnrichment, gov.hasConcerns {
            DiverLogger.pipeline.info("⚠️ Commerce: Government data flags concerns for \(classification.name) — \(gov.recalls.count) recalls, \(gov.fdaAlerts.count) FDA alerts")
        }
        
        // Step 2b: Price trajectory + nowcast
        let pricingService = PricingDataService()
        let nowcastEngine = NowcastingEngine()
        
        let commodityID = mapCategoryToCommodity(classification.category)
        if !commodityID.isEmpty {
            if let trajectory = try? await pricingService.project(commodityID: commodityID) {
                pipelineContext.priceTrend = trajectory
                
                // Run DFM nowcast on raw price series
                let worldBankSeries = await pricingService.fetchWorldBankPrices(commodityID: commodityID)
                let blsSeries = await pricingService.fetchBLSPPI(seriesID: mapCategoryToBLSSeries(classification.category))
                
                let allSeries = [worldBankSeries, blsSeries].filter { !$0.isEmpty }
                if !allSeries.isEmpty {
                    let nowcast = nowcastEngine.nowcast(series: allSeries)
                    pipelineContext.nowcastResult = nowcast
                    item.nowcastContext = nowcast
                    DiverLogger.pipeline.info("📈 Nowcast: trend=\(nowcast.direction.rawValue), confidence=\(String(format: "%.0f%%", nowcast.confidence * 100))")
                }
            }
        }
        
        // Step 3: Score with ALL active strategies
        var allScores: [ProductScore] = []
        let strategyNames = scoringStrategies.map(\.displayName)
        
        for strategy in scoringStrategies {
            // Each strategy gets appropriate enrichment data
            let enrichment: (any Sendable)?
            switch strategy.strategyID {
            case "esg": enrichment = (esgEnrichment, govEnrichment) as (ESGEnrichment?, GovernmentEnrichment?)
            case "value": enrichment = pipelineContext.priceTrend
            case "social": enrichment = govEnrichment  // complaint/recall history
            default: enrichment = nil
            }
            
            if let score = try? await strategy.score(classification, enrichment: enrichment) {
                allScores.append(score)
            }
        }
        
        pipelineContext.productScores = allScores
        
        // Step 4: Derive preference weights from ownership history
        let ownedFetch = FetchDescriptor<OwnedProduct>()
        let ownedProducts = (try? modelContext.fetch(ownedFetch)) ?? []
        let scoringHistory = PreferenceLearner.fetchScoringHistory(
            ownedProducts: ownedProducts,
            modelContext: modelContext
        )
        let learnedWeights = PreferenceLearner.deriveWeights(
            from: ownedProducts,
            allScores: scoringHistory
        )
        
        // Step 5: Generate recommendations using learned weights
        if let recommender, let primaryStrategy = scoringStrategies.first {
            let brandAffinities = fetchBrandAffinities()
            let recommendations = try? await recommender.recommend(
                for: classification,
                using: primaryStrategy,
                brandAffinities: brandAffinities,
                priceTrend: pipelineContext.priceTrend,
                strategyWeights: learnedWeights
            )
            
            if let recommendations, !recommendations.isEmpty {
                pipelineContext.recommendations = recommendations
                item.commerceContext = recommendations
                item.processingLog.append("\(Date().formatted()): Stage ⑦: Scored by \(strategyNames.joined(separator: ", ")), \(recommendations.count) rec(s)")
                DiverLogger.pipeline.info("🛒 Commerce: \(allScores.count) strategy scores, weights=\(learnedWeights), \(recommendations.count) rec(s) for \(classification.name)")
            }
        }
        
        // Step 5b: Affiliate routing with ethical policy
        let affiliateService = AffiliateRoutingService()
        let ethicalPolicy = loadEthicalPolicy()
        if let platforms = try? await affiliateService.rankPlatforms(for: classification, policy: ethicalPolicy) {
            pipelineContext.affiliateMatches = platforms
            item.affiliateContext = platforms
            DiverLogger.pipeline.info("🏪 Affiliate: \(platforms.count) platforms ranked for \(classification.name)")
        }
        
        // Step 6: Record historical snapshot for time-series charts
        let snapshot = ScoreSnapshot(
            productID: classification.productID,
            productName: classification.name,
            brand: classification.brand,
            category: classification.category,
            strategyScores: allScores.map { score in
                StrategyScoreEntry(
                    strategyID: score.strategyID,
                    displayName: scoringStrategies.first { $0.strategyID == score.strategyID }?.displayName ?? score.strategyID,
                    score: score.overallScore
                )
            },
            price: pipelineContext.recommendations.first.map { Double(truncating: $0.option.price as NSDecimalNumber) },
            currency: pipelineContext.recommendations.first?.option.currency,
            quantity: esgEnrichment?.quantity,
            compositeScore: pipelineContext.recommendations.first.map { Double($0.compositeScore) },
            preferenceWeights: learnedWeights,
            source: esgEnrichment?.source
        )
        modelContext.insert(snapshot)
        DiverLogger.pipeline.info("📊 Snapshot recorded for \(classification.name) (\(allScores.count) strategies)")
    }
    
    // MARK: - Commerce Helpers
    
    private func isBarcode(_ payload: String) -> Bool {
        // EAN-13, UPC-A, or other barcode formats (all digits, 8-14 chars)
        let digits = payload.filter(\.isNumber)
        return digits.count >= 8 && digits.count <= 14 && digits.count == payload.count
    }
    
    private func inferCategory(from item: ProcessedItem) -> String {
        // Derive category from existing item classification
        if item.categories.contains("food") { return "food" }
        if item.categories.contains("electronics") { return "electronics" }
        if item.categories.contains("clothing") { return "clothing" }
        if item.categories.contains("product") { return "general" }
        return item.categories.first ?? "general"
    }
    
    private func extractBrand(from item: ProcessedItem) -> String? {
        // Extract brand from product metadata or tags
        if let metadata = item.productMetadata, !metadata.isEmpty {
            return metadata.components(separatedBy: " ").first
        }
        return nil
    }
    
    private func fetchBrandAffinities() -> [BrandProfile] {
        // Fetch UserConcepts that represent brands (definition starts with "Brand:")
        // This avoids a SwiftData schema change — brand concepts are identified by convention
        let fetch = FetchDescriptor<UserConcept>()
        guard let concepts = try? modelContext.fetch(fetch) else { return [] }
        
        return concepts
            .filter { $0.definition.hasPrefix("Brand:") }
            .map { concept in
                BrandProfile(
                    name: concept.name,
                    category: nil,
                    userAffinity: Float(min(concept.weight / 5.0, 1.0)), // Normalize weight to 0-1
                    productCount: Int(concept.weight)
                )
            }
    }
    
    /// Maps product category to World Bank commodity code for price tracking.
    private func mapCategoryToCommodity(_ category: String) -> String {
        let mapping: [String: String] = [
            "food": "WHEAT",
            "coffee": "COFFEE_ARABICA",
            "electronics": "ALUMINUM",
            "clothing": "COTTON_A_INDX",
            "energy": "CRUDE_BRENT",
            "metals": "GOLD",
        ]
        let lower = category.lowercased()
        for (key, value) in mapping {
            if lower.contains(key) { return value }
        }
        return ""
    }
    
    /// Maps product category to BLS Producer Price Index series ID.
    private func mapCategoryToBLSSeries(_ category: String) -> String {
        let mapping: [String: String] = [
            "food": "WPU01",          // Farm Products
            "electronics": "WPU117",   // Electronic Components
            "clothing": "WPU0381",     // Apparel
            "general": "WPU00000000",  // All Commodities
        ]
        let lower = category.lowercased()
        for (key, value) in mapping {
            if lower.contains(key) { return value }
        }
        return "WPU00000000"
    }
    
    /// Loads user's ethical purchasing policy from SwiftData (synced via CloudKit).
    private func loadEthicalPolicy() -> EthicalPolicy {
        let settings = EthicalPolicySettings.current(in: modelContext)
        return EthicalPolicy(
            carbonThreshold: settings.carbonThreshold,
            preferredCertifications: settings.certifications,
            platformRanking: settings.platformRanking,
            excludeLaborViolations: settings.excludeLaborViolations
        )
    }

    private func performLLMAnalysis(for item: ProcessedItem, descriptor: DiverItemDescriptor?, pipelineContext: PipelineContext) async {
        let contextService = ContextQuestionService()
        
        // Use PipelineContext's structured serialization instead of the legacy string blob.
        // The SLM receives a clean, typed context for @Generable ContextAnalysis extraction.

        
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
             let sessionDesc = FetchDescriptor<SessionMetadata>(predicate: #Predicate<SessionMetadata> { $0.sessionID == sessionID })
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
            visualContext: pipelineContext.asContextString,
            sourceURL: item.url
        )
        
        do {
            if !ContextQuestionService.isAvailable {
                // Fallback: Just skip LLM refinement.
                // Status moves to ready, minimal heuristics applied if needed (but title extraction happens elsewhere)
                 print("⚠️ [LocalPipeline] LLM not available. Skipping deep analysis.")
                 item.statusRaw = ProcessingStatus.ready.rawValue
                 item.processingLog.append("\(Date().formatted()): LLM Analysis Skipped (Unavailable). Finalized.")
                 try modelContext.save()
                 return
            }
            
            print("🧠 [LocalPipeline] Starting LLM Analysis for item: \(item.id)")
            let (summary, questions, purpose, tags) = try await contextService.processContext(from: currentData, sessionID: item.sessionID)
            
            // Save generated questions for the UI to present
            item.questions = questions
            
            // Update summary with LLM refinement if available
            if let s = summary, !s.isEmpty {
                item.summary = "\(s) [Model: SystemLanguageModel-iOS26]"
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
        var place: EnrichmentData?
        var coverImagePath: String?
        var activity: ActivityContext?
    }

    /// Runs enrichment tasks (geocoding, link metadata, cover image) in parallel.
    private func performParallelEnrichment(
        resolvedId: String,
        descriptor: DiverItemDescriptor?,
        rawPayload: Data?,
        finalLocation: CLLocation?,
        isUserLocationFixed: Bool,
        inputURLString: String?,
        enrichmentService: LinkEnrichmentService?,
        locationService: LocationProvider?,
        contactService: ContactServiceProvider?,
        initialHomeLoc: CLLocation? = nil
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

            // Geocoding moved inline to Location Resolution step (runs before Vision)
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
            

            var results: [ParallelEnrichmentResult] = []
            for await result in group {
                if let r = result { results.append(r) }
            }
            return results
        }
    }

    private func processParallelResult(_ result: ParallelEnrichmentResult, to item: ProcessedItem, pipelineContext: inout PipelineContext) {
        if let linkData = result.link {
            applyEnrichment(linkData, to: item)
            pipelineContext.linkEnrichment = linkData
        }
        if let place = result.place {
            applyEnrichment(place, to: item)
            pipelineContext.placeEnrichment = place
        }
        if let a = result.activity {
            pipelineContext.activityContext = a
            item.activityContext = a
        }
        if let path = result.coverImagePath {
            pipelineContext.coverImagePath = path
            if item.webContext == nil { item.webContext = WebContext(snapshotURL: path) }
            else { item.webContext?.snapshotURL = path }
        }
    }
    
    /// Searches for live events at a place. `nonisolated` — pure network I/O, no SwiftData.
    /// Reverse-geocode a coordinate using the priority-ranked ReverseGeocodingService.
    /// `@MainActor` because `ReverseGeocodingService` is MainActor-isolated.
    @MainActor
    private static func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> PlaceContext? {
        let service = ReverseGeocodingService(foursquareService: Services.shared.foursquareService)
        return await service.lookup(coordinate: coordinate)
    }
    
    nonisolated private func searchLiveEvents(place: String, service: ContextualEnrichmentService) async -> String? {
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
        let fetchMeta = FetchDescriptor<SessionMetadata>(predicate: #Predicate<SessionMetadata> { $0.sessionID == sessionID })
        
        do {
            let items = try modelContext.fetch(fetchItems)
            if items.isEmpty { return }
            
            // Use all items sorted chronologically
            let sortedItems = items.sorted(by: { $0.createdAt < $1.createdAt })
            
            var combinedText = ""
            for (index, item) in sortedItems.enumerated() {
                combinedText += "--- Item \(index + 1) of \(sortedItems.count) ---\n"
                combinedText += "Title: \(item.title ?? "Unknown")\n"
                
                if let summary = item.summary, !summary.isEmpty {
                    combinedText += "Description: \(summary)\n"
                }
                
                // OCR / Transcription (full text from capture)
                if let transcription = item.transcription, !transcription.isEmpty {
                    combinedText += "OCR Text: \(transcription)\n"
                }
                
                // Themes and tags
                if !item.visualTags.isEmpty {
                    combinedText += "Visual Tags: \(item.visualTags.joined(separator: ", "))\n"
                }
                if !item.tags.isEmpty {
                    combinedText += "Tags: \(item.tags.joined(separator: ", "))\n"
                }
                if !item.categories.isEmpty {
                    combinedText += "Categories: \(item.categories.joined(separator: ", "))\n"
                }
                
                // Purposes / intents
                if !item.purposes.isEmpty {
                    combinedText += "Intents: \(item.purposes.joined(separator: ", "))\n"
                }
                
                // Location context
                if let place = item.placeContext {
                    combinedText += "Place: \(place.name ?? "Unknown")"
                    if let address = place.address, !address.isEmpty {
                        combinedText += " (\(address))"
                    }
                    if !place.categories.isEmpty {
                        combinedText += " [Categories: \(place.categories.joined(separator: ", "))]"
                    }
                    combinedText += "\n"
                } else if let location = item.location, !location.isEmpty {
                    combinedText += "Location: \(location)\n"
                }
                
                // Weather
                if let weather = item.weatherContext {
                    combinedText += "Weather: \(weather.condition), \(weather.temperatureCelsius)°C\n"
                }
                
                // Activity
                if let activity = item.activityContext {
                    combinedText += "Activity: \(activity.type) (confidence: \(activity.confidence))\n"
                }
                
                // Web context
                if let web = item.webContext {
                    if let siteName = web.siteName, !siteName.isEmpty {
                        combinedText += "Web Site: \(siteName)\n"
                    }
                    if let textContent = web.textContent, !textContent.isEmpty {
                        combinedText += "Web Content: \(String(textContent.prefix(500)))\n"
                    }
                }
                if let url = item.url, !url.isEmpty {
                    combinedText += "URL: \(url)\n"
                }
                
                // Document context
                if let doc = item.documentContext {
                    combinedText += "Document Type: \(doc.fileType)\n"
                    if let pageCount = doc.pageCount {
                        combinedText += "Page Count: \(pageCount)\n"
                    }
                    if let author = doc.author, !author.isEmpty {
                        combinedText += "Document Author: \(author)\n"
                    }
                }
                
                // QR code
                if let qr = item.qrContext {
                    combinedText += "QR Code Payload: \(qr.payload)\n"
                }
                
                // FastVLM analysis
                if let vlm = item.fastVLMAnalysis {
                    if let description = vlm.imageDescription, !description.isEmpty {
                        combinedText += "Visual Analysis: \(description)\n"
                    }
                }
                
                // Product metadata
                if let product = item.productMetadata, !product.isEmpty {
                    combinedText += "Product Info: \(product)\n"
                }
                
                // Questions
                if !item.questions.isEmpty {
                    combinedText += "Questions: \(item.questions.joined(separator: "; "))\n"
                }
                
                // Media type
                if let mediaType = item.mediaType, !mediaType.isEmpty {
                    combinedText += "Media Type: \(mediaType)\n"
                }
                
                combinedText += "\n"
            }
            var summary = ""
            
            // Fetch session metadata for location context
            let session = try modelContext.fetch(fetchMeta).first
            let locationName = session?.locationName ?? "Location"
            
            // 1. Try to offload to Edge Context Actor first
            var summaryGenerated = false
            let nodeName = "Edge Node" // Default for logging
            
            if let router = await Services.shared.edgeRouter, let system = await Services.shared.actorSystem {
                let decision = await router.shouldOffload(task: .vlmInference)
                if case .edge(let node, _) = decision {
                    do {
                        let identity = EdgeActorID(id: "EdgeContext", nodeName: node.deviceName)
                        let edgeActor = try EdgeContextActor.resolve(id: identity, using: system)
                        
                        let contextPrompt = "Summarize the following session data concisely:\n\(combinedText)"
                        // Select the best representative image for FastVLM (same logic as local path)
                        let bestImagePayload: Data? = sortedItems
                            .sorted { ($0.aestheticsScore ?? 0) > ($1.aestheticsScore ?? 0) }
                            .first { $0.rawPayload != nil }?.rawPayload
                        summary = try await edgeActor.summarize(text: contextPrompt, imageData: bestImagePayload)
                        summaryGenerated = true
                        DiverLogger.pipeline.info("✅ generated summary for session \(sessionID) using EdgeContextActor (\(node.deviceName))")
                    } catch {
                        DiverLogger.pipeline.error("⚠️ EdgeContextActor failed, falling back to local: \(error)")
                    }
                }
            }
            
            // 2. Fallback to Local Summary Generation
            if !summaryGenerated {
                if FastVLMEnrichmentService.isAvailable {
                    let service = FastVLMEnrichmentService()
                    // Select the best representative image from session items
                    // (highest aesthetics score, or first item with rawPayload)
                    let bestImageItem = sortedItems
                        .sorted { ($0.aestheticsScore ?? 0) > ($1.aestheticsScore ?? 0) }
                        .first { $0.rawPayload != nil }
                    if let bestItem = bestImageItem,
                       let data = bestItem.rawPayload,
                       let representativeImage = self.createCGImage(from: data) {
                        let visionTags = bestItem.visualTags
                        let analysis = try? await service.analyze(
                            image: representativeImage,
                            visionTags: visionTags,
                            enrichmentContext: combinedText,
                            transcription: nil
                        )
                        if let result = analysis?.contextSummary, !result.isEmpty {
                            let modelBadge = analysis?.modelID ?? FastVLMEnrichmentService.modelID
                            summary = "\(result) [Model: \(modelBadge)]"
                            summaryGenerated = true
                            DiverLogger.pipeline.info("✅ generated summary for session \(sessionID) using local FastVLM (\(modelBadge))")
                        }
                    }
                }
                
                if !summaryGenerated && ContextQuestionService.isAvailable {
                    let service = ContextQuestionService()
                    summary = try await service.summarizeText(combinedText)
                    // Ensure local LLM gets its badge too if missing
                    if !summary.contains("[Model:") {
                        summary = "\(summary) [Model: SystemLanguageModel-iOS26]"
                    }
                    summaryGenerated = true
                    DiverLogger.pipeline.info("✅ generated summary for session \(sessionID) using SystemLanguageModel")
                } 
                
                if !summaryGenerated {
                     let titleList = sortedItems
                         .compactMap { $0.title }
                         .filter { $0 != "Untitled" && $0 != "Visual Capture" && !$0.isEmpty }
                         .prefix(3)
                         .joined(separator: ", ")
                     
                     summary = "Session with \(items.count) items at \(locationName). Includes: \(titleList.isEmpty ? "Captured Media" : titleList)."
                     DiverLogger.pipeline.info("✅ generated summary for session \(sessionID) using heuristics")
                }
            }
            
            if let meta = session {
                meta.summary = summary
                try modelContext.save()
                DiverLogger.pipeline.info("✅ generated summary for session \(sessionID)")
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
        let candidates = item.visualTags + item.tags + item.purposes.filter { !$0.starts(with: "At: ") }
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
        
        // 4. Date-based Fallback (Location is NOT a good title)
        // User feedback: "location address is always being used as the default name even though it is not the most relevant piece of information"
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
            
            // 2. Check SessionMetadata
            let sessionDesc = FetchDescriptor<SessionMetadata>()
            let sessions = try modelContext.fetch(sessionDesc)
            DiverLogger.pipeline.info("📊 Total SessionMetadata found: \(sessions.count)")
            
            if sessions.isEmpty && !items.isEmpty {
                DiverLogger.pipeline.warning("⚠️ No SessionMetadata found but Items exist. Attempting to REGENERATE Sessions...")
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

    /// Assigns orphaned items (nil sessionID — "Inbox" items) to the nearest existing session
    /// by timestamp AND location proximity, or creates a new session if no match exists.
    public func assignOrphanedItems() throws {
        let orphanFetch = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate<ProcessedItem> { $0.sessionID == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let orphans = try modelContext.fetch(orphanFetch)
        guard !orphans.isEmpty else {
            DiverLogger.pipeline.info("ℹ️ No orphaned inbox items found.")
            return
        }
        
        DiverLogger.pipeline.info("📬 Found \(orphans.count) orphaned inbox items. Attempting session assignment...")
        
        // Fetch all sessions sorted by creation time
        let sessionFetch = FetchDescriptor<SessionMetadata>(sortBy: [SortDescriptor(\.createdAt)])
        let sessions = try modelContext.fetch(sessionFetch)
        
        // Time windows
        let timeWindowWithLocation: TimeInterval = 30 * 60   // 30 min when location matches
        let timeWindowNoLocation: TimeInterval = 5 * 60       // 5 min when no location data
        // ~500m in coordinate delta (rough approximation)
        let locationThreshold: Double = 0.005
        
        var assignedCount = 0
        var createdCount = 0
        
        for orphan in orphans {
            let itemTime = orphan.createdAt
            let itemLat = orphan.latitude
            let itemLon = orphan.longitude
            
            var bestSession: SessionMetadata? = nil
            var bestDelta: TimeInterval = .greatestFiniteMagnitude
            
            for session in sessions {
                let timeDelta = abs(itemTime.timeIntervalSince(session.createdAt))
                
                // Check location proximity if both have coordinates
                if let iLat = itemLat, let iLon = itemLon,
                   let sLat = session.latitude, let sLon = session.longitude {
                    let coordDelta = abs(iLat - sLat) + abs(iLon - sLon)
                    let isLocationClose = coordDelta < locationThreshold
                    
                    // Require location match + time within 30 min
                    if isLocationClose && timeDelta <= timeWindowWithLocation && timeDelta < bestDelta {
                        bestDelta = timeDelta
                        bestSession = session
                    }
                } else {
                    // No location data — use tighter 5-min window (time-only)
                    if timeDelta <= timeWindowNoLocation && timeDelta < bestDelta {
                        bestDelta = timeDelta
                        bestSession = session
                    }
                }
            }
            
            if let match = bestSession {
                // Assign to existing session
                orphan.sessionID = match.sessionID
                orphan.session = match
                match.updatedAt = Date()
                assignedCount += 1
                DiverLogger.pipeline.debug("📬 Assigned '\(orphan.title ?? orphan.id)' → session '\(match.title ?? match.sessionID)' (Δ\(Int(bestDelta))s)")
            } else {
                // No nearby session — create a new one
                let newSessionID = UUID().uuidString
                let newSession = SessionMetadata(sessionID: newSessionID, createdAt: orphan.createdAt)
                newSession.title = orphan.title
                newSession.locationName = orphan.placeContext?.name ?? orphan.location
                if let lat = itemLat, let lon = itemLon {
                    newSession.latitude = lat
                    newSession.longitude = lon
                }
                modelContext.insert(newSession)
                
                orphan.sessionID = newSessionID
                orphan.session = newSession
                createdCount += 1
                DiverLogger.pipeline.debug("📬 Created new session for orphan '\(orphan.title ?? orphan.id)'")
            }
        }
        
        try modelContext.save()
        DiverLogger.pipeline.info("✅ Orphan assignment complete: \(assignedCount) assigned to existing sessions, \(createdCount) new sessions created.")
    }
    
    public func regenerateMissingSessions() throws {
        let itemDesc = FetchDescriptor<ProcessedItem>()
        let items = try modelContext.fetch(itemDesc)
        
        let grouped = Dictionary(grouping: items, by: { $0.sessionID })
        var restoredCount = 0
        
        for (sessionID, sessionItems) in grouped {
            guard let sessionID = sessionID else { continue }
            
            // Check if exists
            let fetch = FetchDescriptor<SessionMetadata>(predicate: #Predicate<SessionMetadata> { $0.sessionID == sessionID })
            if (try? modelContext.fetch(fetch).count) == 0 {
                // Create new session
                let session = SessionMetadata(sessionID: sessionID)
                
                // Infer details from items
                let sorted = sessionItems.sorted(by: { $0.createdAt < $1.createdAt })
                if let first = sorted.first { session.createdAt = first.createdAt }
                if let last = sorted.last { session.updatedAt = last.updatedAt }
                
                if let locItem = sorted.first(where: { $0.location != nil }) {
                    session.locationName = locItem.placeContext?.name ?? locItem.location
                    session.placeID = locItem.placeContext?.placeID
                } else if let actItem = sorted.first(where: { $0.activityContext != nil || !$0.purposes.isEmpty }) {
                    // Fallback to Semantic Activity / Purpose
                    if let purpose = actItem.purposes.first(where: { !$0.isEmpty }) {
                         session.title = purpose
                    } else if let type = actItem.activityContext?.type {
                        session.title = "Activity: \(type.capitalized)"
                    }
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


    public func recoverStuckItems() throws {
        // Fetch items stuck in 'processing' state
        let fetch = FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.statusRaw == "processing" })
        
        let stuckItems = try modelContext.fetch(fetch)
        
        if !stuckItems.isEmpty {
            DiverLogger.pipeline.warning("⚠️ Found \(stuckItems.count) STUCK items in processing state. Resetting to QUEUED.")
            for item in stuckItems {
                item.status = .queued
                item.processingLog.append("\(Date().formatted()): System detected stuck state (crash recovery). Resetting to queued.")
                
                // Re-create LocalInput so MetadataPipelineService can re-process the item.
                // Without this, the item stays "queued" forever since there's no queue entry.
                let localInput = LocalInput(
                    createdAt: item.createdAt,
                    url: item.url,
                    text: item.transcription,
                    source: item.source,
                    inputType: item.modality ?? "image",
                    rawPayload: item.rawPayload,
                    sessionID: item.sessionID,
                    purposes: item.purposes
                )
                modelContext.insert(localInput)
            }
            try modelContext.save()
            DiverLogger.pipeline.info("✅ Recovered \(stuckItems.count) stuck items with LocalInput re-creation.")
        } else {
            DiverLogger.pipeline.info("ℹ️ No stuck items found.")
        }
    }
    
    public func consolidateSessions() throws {
        // Fetch all sessions sorted by time
        let desc = FetchDescriptor<SessionMetadata>(sortBy: [SortDescriptor(\.createdAt)])
        let sessions = try modelContext.fetch(desc)
        
        guard !sessions.isEmpty else { return }
        
        var sessionsToDelete: [SessionMetadata] = []
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
    /// Wraps an async operation with a timeout. `nonisolated` — pure task group logic.
    nonisolated private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
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

    /// URL-keyed link enrichment with 1-hour TTL cache.
    /// Prevents redundant web scraping for duplicate URLs.
    private func cachedEnrich(url: URL, service: LinkEnrichmentService) async throws -> EnrichmentData? {
        let key = url.absoluteString
        
        // Check cache
        if let cached = linkEnrichmentCache[key], !cached.isExpired {
            DiverLogger.pipeline.debug("Link enrichment cache HIT for \(key)")
            return cached.data
        }
        
        // Cache miss — perform enrichment
        let result = try await service.enrich(url: url)
        
        // Cache result
        if let result {
            linkEnrichmentCache[key] = CachedEnrichment(data: result, timestamp: Date())
        }
        
        return result
    }

    nonisolated private func isJSONData(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let firstByte = data[0]
        // JSON objects start with '{' or '['
        return firstByte == 0x7B || firstByte == 0x5B
    }

    /// Convert raw image Data to a CGImage for FastVLM multimodal analysis.
    /// Uses NSCache to avoid re-decoding the same data within a pipeline run.
    nonisolated private func createCGImage(from data: Data) -> CGImage? {
        let cacheKey = "\(data.hashValue)" as NSString
        
        // Check cache first
        if let cached = cgImageCache.object(forKey: cacheKey) {
            return cached.image
        }
        
        // Decode with autoreleasepool
        let image: CGImage? = autoreleasepool {
            guard !data.isEmpty, !isJSONData(data) else { return nil }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) > 0 else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        
        // Cache result
        if let image {
            cgImageCache.setObject(CGImageWrapper(image), forKey: cacheKey)
        }
        
        return image
    }

    /// Internal test-accessible wrapper for `createCGImage(from:)`.
    /// Only visible via `@testable import DiverKit`.
    nonisolated internal func createCGImageForTesting(from data: Data) -> CGImage? {
        createCGImage(from: data)
    }

    /// Finds an existing session matching the item by time, location, and topic similarity.
    /// Used as a fallback when no explicit sessionID is provided.
    /// - Time window: 30 minutes
    /// - Distance threshold: 500 meters
    /// - Tiebreaker: tag overlap (topic similarity)
    private func findMatchingSession(for item: ProcessedItem) -> SessionMetadata? {
        let windowSeconds: TimeInterval = 30 * 60 // 30 minutes
        let distanceThreshold: Double = 500 // meters
        
        let itemDate = item.originalDate ?? item.createdAt
        let windowStart = itemDate.addingTimeInterval(-windowSeconds)
        let windowEnd = itemDate.addingTimeInterval(windowSeconds)
        
        // Fetch recent sessions within time window
        let fetch = FetchDescriptor<SessionMetadata>(
            predicate: #Predicate<SessionMetadata> {
                $0.createdAt >= windowStart && $0.createdAt <= windowEnd
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        guard let candidates = try? modelContext.fetch(fetch), !candidates.isEmpty else {
            return nil
        }
        
        // Filter by location proximity
        let itemLocation: CLLocation? = {
            if let lat = item.latitude, let lon = item.longitude {
                return CLLocation(latitude: lat, longitude: lon)
            }
            return nil
        }()
        
        var scored: [(session: SessionMetadata, score: Int)] = []
        
        for session in candidates {
            var score = 0
            
            // Location check
            if let itemLoc = itemLocation, let sLat = session.latitude, let sLon = session.longitude {
                let sessionLoc = CLLocation(latitude: sLat, longitude: sLon)
                let distance = itemLoc.distance(from: sessionLoc)
                if distance > distanceThreshold {
                    continue // Too far — skip
                }
                score += 2 // Location proximity bonus
            } else if itemLocation == nil && session.latitude == nil {
                // Both have no location — compatible
                score += 1
            }
            
            // Topic similarity: tag overlap (lightweight set intersection)
            if !item.tags.isEmpty, let sessionItems = session.items, !sessionItems.isEmpty {
                let itemTags = Set(item.tags)
                let sessionTags = Set(sessionItems.flatMap { $0.tags })
                let overlap = itemTags.intersection(sessionTags).count
                score += overlap
            }
            
            scored.append((session, score))
        }
        
        // Return highest scoring session, if any matched
        return scored.sorted(by: { $0.score > $1.score }).first?.session
    }
    
    func syncSession(for item: ProcessedItem) {
        // Ensure robust relationship exists (Transition fallback)
        if item.session == nil {
            let sessionID: String
            
            if let existingID = item.sessionID {
                // Priority 1: Explicit sessionID (from activeSessionID / descriptor)
                sessionID = existingID
            } else if let matchedSession = findMatchingSession(for: item) {
                // Priority 2: Find matching session by time/location/topic similarity
                sessionID = matchedSession.sessionID
                item.sessionID = sessionID
                item.session = matchedSession
                DiverLogger.pipeline.info("Matched item \(item.id) to existing session \(sessionID) via similarity")
                // Skip the fetch below since we already have the session
                return syncSessionMetadata(for: item)
            } else {
                // Priority 3: Create new session
                sessionID = UUID().uuidString
                item.sessionID = sessionID
            }
            
            let fetch = FetchDescriptor<SessionMetadata>(predicate: #Predicate<SessionMetadata> { $0.sessionID == sessionID })
            if let existing = try? modelContext.fetch(fetch).first {
                item.session = existing
            } else {
                let session = SessionMetadata(sessionID: sessionID, createdAt: item.createdAt)
                modelContext.insert(session)
                item.session = session
                DiverLogger.pipeline.info("Created new SessionMetadata for item \(item.id)")
            }
        }
        
        syncSessionMetadata(for: item)
    }
    
    /// Propagates item metadata to its parent session (location, thumbnail, title, favorite).
    private func syncSessionMetadata(for item: ProcessedItem) {
        
        guard let session = item.session else { return }
        
        // Sync Session Metadata
        session.updatedAt = Date()
        
        // Propagate Favorite Status (Additive only - once a session is favorited via an item, it stays)
        if item.isFavorite {
            session.isFavorite = true
        }

        // Propagate Location if session is empty
        if session.latitude == nil || session.longitude == nil {
            if let lat = item.latitude, let lon = item.longitude {
                session.latitude = lat
                session.longitude = lon
                session.placeID = item.placeID
                session.locationName = item.placeContext?.name ?? item.location
            }
        }
        
        // Sync Thumbnail Logic
        // We pick the best thumbnail path from items in the session based on aestheticsScore
        let targetSID = session.sessionID
        let itemsFetch: FetchDescriptor<ProcessedItem> = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate<ProcessedItem> { $0.sessionID == targetSID },
            sortBy: [SortDescriptor(\.aestheticsScore, order: .reverse)]
        )
        
        if let sessionItems = try? modelContext.fetch(itemsFetch) {
            // 1. Update thumbnailAssetIdentifier from highest scoring photo
            if let bestPhotoItem = sessionItems.first(where: { $0.photosAssetIdentifier != nil }) {
                session.thumbnailAssetIdentifier = bestPhotoItem.photosAssetIdentifier
            }
            
            // 2. Update thumbnailPaths (file-based backups) from top 3 scoring items
            let topPaths = sessionItems
                .filter { $0.webContext?.snapshotURL != nil }
                .prefix(3)
                .compactMap { $0.webContext?.snapshotURL }
            
            session.thumbnailPaths = Array(topPaths)
        }
        
        // Finalize Title logic
        if session.title == nil || session.title?.isEmpty == true {
             // Fallback: If session has no title, use item title
             session.title = item.title
        }
    }

    // MARK: - SwiftData Transition (Backward Compatibility)
    
    /// Reconciles string-based IDs with SwiftData @Relationship pointers.
    /// This ensures that existing records are correctly linked via the new robust relationships.
    public func reconcileRelationships() async {
        DiverLogger.pipeline.info("🛠️ Starting SwiftData relationship reconciliation...")
        
        // 1. Link ProcessedItem to SessionMetadata
        let itemsFetch: FetchDescriptor<ProcessedItem> = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate<ProcessedItem> { $0.session == nil && $0.sessionID != nil }
        )
        
        if let items = try? modelContext.fetch(itemsFetch), !items.isEmpty {
            DiverLogger.pipeline.info("🔗 Reconciling \(items.count) items to sessions...")
            for item in items {
                if let sessID = item.sessionID {
                    let sessionFetch: FetchDescriptor<SessionMetadata> = FetchDescriptor<SessionMetadata>(
                        predicate: #Predicate<SessionMetadata> { $0.sessionID == sessID }
                    )
                    if let session = (try? modelContext.fetch(sessionFetch))?.first {
                        item.session = session
                    }
                }
            }
        }
        
        // 2. Link SessionMetadata to SessionCollection
        let sessionsFetch: FetchDescriptor<SessionMetadata> = FetchDescriptor<SessionMetadata>(
            predicate: #Predicate<SessionMetadata> { $0.parentCollection == nil && $0.collectionID != nil }
        )
        
        if let sessions = try? modelContext.fetch(sessionsFetch), !sessions.isEmpty {
            DiverLogger.pipeline.info("🔗 Reconciling \(sessions.count) sessions to collections...")
            for session in sessions {
                if let collID = session.collectionID {
                    let collectionFetch: FetchDescriptor<SessionCollection> = FetchDescriptor<SessionCollection>(
                        predicate: #Predicate<SessionCollection> { $0.collectionID == collID }
                    )
                    if let collection = (try? modelContext.fetch(collectionFetch))?.first {
                        session.parentCollection = collection
                    }
                }
            }
        }
        
        do { try modelContext.save() } catch { DiverLogger.pipeline.error("Save failed (session sync): \(error)") }
        DiverLogger.pipeline.info("✅ Relationship reconciliation complete.")
    }

    public func maintainLibrary(progressHandler: (@Sendable (Double) -> Void)? = nil, statusHandler: (@Sendable (String) -> Void)? = nil) async throws {
        DiverLogger.pipeline.info("🧹 Starting Library Maintenance...")
        
        // 1. Recover stuck items FIRST (so they can be assigned to sessions in step 2)
        let stuckCount = (try? modelContext.fetch(FetchDescriptor<ProcessedItem>(predicate: #Predicate { $0.statusRaw == "processing" })).count) ?? 0
        statusHandler?("Recovering \(stuckCount) stuck…")
        try recoverStuckItems()
        progressHandler?(0.15)
        
        // 2. Assign orphaned inbox items to sessions by timestamp proximity
        let orphanCount = (try? modelContext.fetch(FetchDescriptor<ProcessedItem>(predicate: #Predicate<ProcessedItem> { $0.sessionID == nil })).count) ?? 0
        statusHandler?("Assigning \(orphanCount) orphans…")
        try assignOrphanedItems()
        progressHandler?(0.30)
        
        // 3. Regenerate missing sessions
        statusHandler?("Checking sessions…")
        try regenerateMissingSessions()
        progressHandler?(0.45)
        
        // 4. Consolidate fragmented sessions
        statusHandler?("Consolidating…")
        try consolidateSessions()
        progressHandler?(0.60)
        
        // 5. Reconcile relationships
        statusHandler?("Reconciling…")
        await reconcileRelationships()
        progressHandler?(0.75)
        
        // 6. Regenerate ALL session summaries
        let sessionFetch = FetchDescriptor<SessionMetadata>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let sessions = try? modelContext.fetch(sessionFetch) {
            DiverLogger.pipeline.info("📝 Regenerating summaries for \(sessions.count) sessions...")
            let total = sessions.count
            for (index, session) in sessions.enumerated() {
                _ = total - index
                statusHandler?("Summaries \(index + 1)/\(total)")
                await generateAndSaveSessionSummary(sessionID: session.sessionID)
                let sessionProgress = 0.75 + (Double(index + 1) / Double(total) * 0.25)
                progressHandler?(sessionProgress)
            }
        }
        
        do { try modelContext.save() } catch { DiverLogger.pipeline.error("Save failed (thumbnail update): \(error)") }
        DiverLogger.pipeline.info("✅ Library Maintenance Complete.")
    }
}


struct ParallelEnrichmentResult {
    var place: EnrichmentData?
    var activity: ActivityContext?
    var link: EnrichmentData?
    var coverImagePath: String?
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
