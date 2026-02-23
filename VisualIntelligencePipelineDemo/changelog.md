# Changelog

## 2026-02-23 (c)

### Pipeline Queue Stability
- **Orphaned item self-cancellation fix**: `processQueuedOrphanItems()` was calling `processItemImmediately()` which does `currentTask?.cancel()` — cancelling the very queue task it's running inside. Now uses `processItemByID()` which creates its own private `ModelContext` and runs the full pipeline without interrupting the queue.
- **URL enrichment whitelist**: Link enrichment now only runs on `http://` and `https://` URLs. Custom URL schemes like `foursquare://`, `secretatomics://` are skipped instead of timing out with `CancellationError`.
- `[MODIFY]` `DiverKit/Services/MetadataPipelineService.swift` — `processQueuedOrphanItems` uses `processItemByID` instead of `processItemImmediately`
- `[MODIFY]` `DiverKit/Services/LocalPipelineService.swift` — URL scheme whitelist for link enrichment

### Self-Healing Edge Transport
- **Connection invalidation on framing errors**: When `responseTooLarge`, `connectionFailed`, or any receive error occurs, the connection is now cancelled and removed from stores. The next request automatically creates a fresh TCP connection, preventing cascading failures where one bad frame corrupts all subsequent requests.
- **0-length response guard**: Daemon error responses (`Data()`) now return `Data()` immediately without calling `NWConnection.receive(minimumIncompleteLength: 0, maximumLength: 0)`, which has undefined behavior.
- **Diagnostic logging**: `responseTooLarge` now prints the raw 4-byte header in hex + ASCII, and `remoteCall` prints the first 200 bytes of failed decode responses.
- `[MODIFY]` `DiverKit/Services/Edge/NWTransportLayer.swift` — Added `invalidateConnection(to:)`, `onFramingError` callback, 0-length guard
- `[MODIFY]` `DiverKit/Services/Edge/VisualIntelligenceActorSystem.swift` — Diagnostic logging on decode failure

### Model-Aware Edge Node Routing
- **VLM/CLaRa model check**: `PipelineEdgeRouter.shouldOffload(.vlmInference)` now verifies the edge node's `availableModels` contains `clara` or `fastvlm` before offloading. Prevents routing CLaRa requests to the iPhone's own local EdgeDaemon (which can never run CLaRa on iOS).
- **Agentic search model check**: `.agenticSearch` now requires `clara` in `availableModels`.
- **Auto-connect tie-breaking by RAM**: `BonjourDiscoveryService` now sorts by TOPS (primary) then RAM (secondary). When TXT records haven't resolved yet (all 0 TOPS), the node with more RAM is preferred — Mac 96GB beats iPad 7GB.
- `[MODIFY]` `DiverKit/Services/Edge/EdgeNodeService.swift` — Model availability guards for `vlmInference` and `agenticSearch`
- `[MODIFY]` `DiverKit/Services/Edge/BonjourDiscoveryService.swift` — RAM tie-breaking in auto-connect sort

## 2026-02-23 (b)

### Edge Transport — Connection Serialization Fix
- **Root Cause**: `NWTransportLayer.send()` reused a single `NWConnection` per node for concurrent requests. Two simultaneous CLaRa calls would interleave their frames — the second caller's `receive()` would read the first caller's response body bytes as a 4-byte length header, interpreting text like `{"su` as a multi-GB value, triggering `responseTooLarge`.
- **Fix**: Added `ConnectionSerializer` actor that ensures only one send/receive pair is in-flight per connection at a time. Concurrent callers queue behind the actor's serialization boundary, preventing frame interleaving.
- **Timeout Bump**: `requestTimeout` increased from 10s to 30s to accommodate CLaRa 7B inference latency.
- `[MODIFY]` `DiverKit/Services/Edge/NWTransportLayer.swift` — Rewrote with `ConnectionSerializer` actor, separate `serializerStore`, non-nested lock access

### CLaRa RAG Index Persistence & Reconciliation
- **Disk-Cached Document Index**: CLaRa's in-memory RAG `DocumentChunk` index is now persisted as compressed JSON (`Application Support/CLaRa/document_index.json.gz`). On relaunch, chunks load from disk instantly instead of re-scanning all ProcessedItems. Incremental indexing now actually works — only items updated since the last index run are re-chunked.
- **`DocumentChunk` is `Codable`**: Added `Codable` conformance to enable JSON serialization of the term-indexed chunk store.
- **Debounced Saves**: Disk writes are batched with a 2-second debounce (`scheduleSave`) to avoid rapid I/O during bulk pipeline processing.
- **`removeDocument(id:)`**: New method to surgically remove a single document's chunks from the index when a ProcessedItem is deleted, with automatic debounced disk save.
- **Delete Database Reconciliation**: `SettingsView.deleteDatabase()` now calls `CLaRaLatentService.shared.clearIndex()` to wipe the index (memory + disk + UserDefaults high-water mark) when the user erases all data.
- **Rebuild Library Reconciliation**: After `maintainLibrary` completes, the CLaRa index is cleared and fully re-populated from the reconciled SwiftData container. Status shows "Rebuilding search index…" during this phase.
- **Session Deletion Reconciliation**: `deleteSelectedSessions()` calls `removeDocument(id:)` for each item before SwiftData deletion, keeping the index in sync.

### Chat with Librarian — Edge-Gated Visibility
- **Edge Node Polling**: `SidebarView` now polls `BonjourDiscoveryService.isEdgeNodeConnected` every 5 seconds via a `.task` and stores the result in `@State var edgeNodeAvailable`.
- **Conditional Display**: The "Chat with Librarian" button only appears when `edgeNodeAvailable || ContextQuestionService.isAvailable` — i.e., an actual inference backend (edge CLaRa or on-device SLM) can respond. Previously showed whenever RAM ≥ 8GB, which was misleading on iPads without a connected Mac.
- **`Services.shared.discoveryService`**: Exposed the `BonjourDiscoveryService` instance from `Services` singleton so views can query edge connectivity without threading through `PipelineEdgeRouter`.

### Reprocessing Pipeline Unification
- **No More Duplicates**: Reprocessing an existing item via ReprocessMetadataView no longer creates a duplicate `DiverQueueItem` through the queue. Instead, `commitReviewSave()` detects `reprocessingItemID` and calls `processItemByID` directly, updating the item in-place.
- **Same Pipeline for Both Paths**: Both first-time processing and reprocessing now go through `LocalPipelineService.process()` with the same order of operations: Vision → Location → Web → SLM/CLaRa → FastVLM → Commerce → Concepts.
- **`ReprocessContext` Removed**: The redundant `ReprocessContext` struct (which copied 6 fields from `ProcessedItem`) has been deleted. `Services.shared.pendingReprocessItemID` passes just the item ID; the ViewModel fetches the full `ProcessedItem` from SwiftData with access to all metadata fields.
- **Photos Library Fallback**: If `rawPayload` is missing during reprocessing (e.g., Live Photos where payload was the MOV component), the ViewModel now falls back to `PhotosAssetLoader` via `photosAssetIdentifier`.
- **User Choices Preserved**: The user's purpose selection and pinned location from the review UI are applied to the ProcessedItem before the pipeline runs, ensuring they survive the full reprocessing pass.

### Files Changed
- `[MODIFY]` `DiverKit/Services/CLaRaLatentService.swift` — Persistent index (Codable, zlib, load/save/scheduleSave), `removeDocument(id:)`, `clearIndex` wipes disk + UserDefaults
- `[MODIFY]` `DiverKit/Services/Services.swift` — Added `discoveryService: (any EdgeNodeDiscovering)?`; replaced `pendingReprocessContext: ReprocessContext?` with `pendingReprocessItemID: String?`; removed `ReprocessContext` struct
- `[MODIFY]` `DiverKit/ViewModel/SidebarViewModel.swift` — `rebuildLibrary` clears + repopulates CLaRa index, `deleteSelectedSessions` removes items from index
- `[MODIFY]` `DiverKit/ViewModel/VisualIntelligenceViewModel.swift` — Added `reprocessingItemID`; `checkPendingReprocess()` fetches full `ProcessedItem` by ID; `commitReviewSave()` routes reprocessing to `processItemByID` (no duplicate queue items); `reset()` clears reprocessingItemID; extracted `loadImageFromData` helper
- `[MODIFY]` `VisualIntelligencePipeline/View/SettingsView.swift` — `deleteDatabase` calls `CLaRaLatentService.shared.clearIndex()`
- `[MODIFY]` `VisualIntelligencePipeline/View/SidebarView.swift` — `edgeNodeAvailable` polling, conditional `agenticSearchSection`
- `[MODIFY]` `VisualIntelligencePipeline/View/ReprocessMetadataView.swift` — Simplified to just set `pendingReprocessItemID`; persists refreshed Photos data to `rawPayload` if missing
- `[MODIFY]` `VisualIntelligencePipeline/VisualIntelligencePipelineApp.swift` — Register `discoveryService` in `Services.shared`

## 2026-02-23

### Commerce Intelligence — Full Pipeline Hookup & AR Session Lifecycle
- **ARKit Raycast Anchoring**: Barcode world positions now use `ARView.raycast(from:allowing:alignment:)` for accurate surface-hit depth instead of fixed 0.5m estimate. Falls back to camera intrinsics at 0.4m if no surface found.
- **Unified Session Lifecycle**: `detector.isTracking` is the single source of truth for AR processing. Removed parallel `isActive` flag. Coordinator checks `detector.isTracking` on every frame — stops immediately when view dismisses.
  - `pauseSession()` / `resumeSession()` for app background/foreground via `scenePhase`.
  - `detector.arSession` weak reference wired from `makeUIView` so detector can pause/resume the underlying ARSession.
  - `dismantleUIView` calls `detector.stopTracking()` as safety net.
- **Parallel Data Fetching**: `scoreProduct()` now fetches all 5 data sources concurrently via `async let`:
  1. ESG Enrichment (Open Facts / UPC Item DB) — already existed
  2. Government Data (CPSC/FDA/EPA/Energy Star) — already existed
  3. Price Nowcast (World Bank / BLS PPI) — **newly wired**
  4. Company ESG / B Corp (OpenESG) — **newly wired**
  5. Affiliate Platforms (ethical routing) — **newly wired**
- **Price Trend Sparkline**: `ProductScoreAttachment` now accepts optional `PriceTrajectory`. When expanded, shows a compact Swift Charts sparkline with trend direction pill (Rising/Falling/Stable) and confidence percentage.
- **Company ESG Integration**: B Corp certification boosts Ethics score by 10%. Company certifications and controversies surface in summary text.
- **Visual Connector Lines**: Canvas layer draws connector line + indicator dot from barcode's screen position to the offset score card, making the spatial relationship clear.
- **`barcodeScreenPosition`**: New property on `SpatialDetectedProduct` tracks the raw projected barcode position separate from the offset card position.
- **AR Ownership Buttons**: "Want" and "Own" compact pill buttons on every AR score card. Tapping creates both:
  - `OwnedProduct` (SwiftData) with barcode, brand, status, composite score, strategy IDs, and `captureItemID` link.
  - `ProcessedItem` storing **all fetched metadata**: ESG enrichment, government data, nowcast trajectory, affiliate platforms, strategy scores, and summary. No commerce data is lost when marking a product from the AR view.
  - Products marked `.wishlisted` from AR can be reviewed in bulk via `OwnedProductsView`.

### Files Changed (Pipeline Hookup & Lifecycle)
- `[MODIFY]` `View/Commerce/Spatial/SpatialProductDetector.swift` — `pauseSession`/`resumeSession`/`arSession` ref, parallel fetches, B Corp integration, `priceTrajectory`/`companyESG`/`affiliatePlatforms` fields
- `[MODIFY]` `View/Commerce/Spatial/SpatialScoreOverlayView.swift` — Raycast anchoring, unified lifecycle, connector lines, `scenePhase` handling, `persistOwnership`, `modelContext`
- `[MODIFY]` `View/Commerce/Spatial/ProductScoreAttachment.swift` — Sparkline chart, trend pill, ownership buttons, `onOwnershipChange` closure

### Commerce Intelligence — Product Identity & Barcode Resolution
- **UPC Item DB Fallback**: Added `upcitemdb.com` as 5th barcode lookup cascade step in `ESGEnrichmentService`. Covers millions of non-food UPC/EAN barcodes (free tier, no API key). Returns product name, brand, category, and description.
- **Product Name & Brand from Open Facts**: `ESGEnrichment` now carries `productName` and `brand` fields parsed from Open Facts `product_name` / `brands` API fields. Context summary updated to prefer `productName` over `genericName`.
- **Barcode → Product Name in AR View**: `SpatialProductDetector.scoreProduct()` now calls `ESGEnrichmentService.enrich(barcode:)` first, resolving raw barcode strings (e.g., `0850004694268`) to real product names and brands before scoring.

### Commerce Intelligence — Meaningful Scores
- **ESG Score Fix**: Fixed critical bug where `CompanyESGProfile.overallScore` (already 0.0–1.0) was divided by 100, producing near-zero ESG scores in AR view.
- **Real Eco-Score/Nutri-Score/NOVA Scoring**: `scoreProduct()` now builds Ethics score from Eco-Score grade (A–E), carbon intensity, and certifications. Health score from NOVA ultra-processing level (1–4) and Nutri-Score grade. Safety score from government recall data.
- **Data-Driven Recommendations**: Recommendation text now explains *why* (e.g., "✅ Recommended — Ethics 85%" or "⏳ Wait — Health 35%, Ethics 42%") instead of generic labels.
- **Intelligence Summary**: Each detected product gets a `summary` string (e.g., "Eco-Score B · Certified: Fair Trade · NOVA 2/4 · via Open Food Facts") displayed in the AR card.

### Commerce Intelligence — AR View UI
- **Product Brand Display**: `ProductScoreAttachment` now shows brand name below product name.
- **Intelligence Summary Capsule**: Blue-tinted insight row with ✨ icon displays the intelligence summary (eco-score, certifications, origin, data source).
- **Card Width**: Expanded from 260pt to 280pt to accommodate richer content.

### Commerce Intelligence — Score Methodology Sheet
- **Info Button**: Added ⓘ button to `ProductScoreOverlayView` header (reference detail commerce section).
- **Methodology Sheet**: Tapping reveals a sheet with:
  - All 7 scoring strategies (Ethics, Brand Fit, Value, Durability, Social Proof, Health Fit, Total Cost) with icons, descriptions, data sources, and weights.
  - Recommendation logic thresholds (Buy Now ≥70%, Wait 40–70%, Not Recommended <40%, active recalls).
  - Data source attribution (Open Facts, UPC Item DB, CPSC/FDA/EPA, B Corp, Climate TRACE).
  - Privacy note: all data processed on-device.

### Camera Capture Fix
- **Dynamic Photo Dimensions**: `CameraManager.capturePhoto()` now reads `supportedMaxPhotoDimensions` from the active format instead of hardcoding 4032×3024, preventing `NSInvalidArgumentException` crashes on devices where the active format doesn't support that exact size.

### AR Barcode Detection
- **ARKit Frame Processing**: `SpatialScoreOverlayView.ARCameraView` now uses a `Coordinator` as `ARSessionDelegate` to run `VNDetectBarcodesRequest` on live AR frames at 2fps, feeding detected barcodes into `SpatialProductDetector`.
- **iOS Camera Polling**: `SpatialProductDetector.startTracking()` on iOS polls `CameraManager.extractedBarcodeURLs` for barcode detections at 500ms intervals.

### Files Changed
- `[MODIFY]` `DiverKit/Sources/DiverKit/Services/ESGEnrichmentService.swift` — Added `productName`/`brand` parsing, UPC Item DB fallback cascade
- `[MODIFY]` `DiverShared/Sources/DiverShared/CommerceTypes.swift` — Added `productName`/`brand` to `ESGEnrichment`
- `[MODIFY]` `View/Commerce/Spatial/SpatialProductDetector.swift` — Rewrote `scoreProduct()` with barcode lookup, real scores, reasoning
- `[MODIFY]` `View/Commerce/Spatial/ProductScoreAttachment.swift` — Added brand, summary, wider card
- `[MODIFY]` `View/Commerce/Spatial/SpatialScoreOverlayView.swift` — AR barcode detection, pass brand/summary
- `[MODIFY]` `View/Commerce/ProductScoreOverlayView.swift` — Added methodology info sheet with ⓘ button
- `[MODIFY]` `DiverKit/Sources/DiverKit/Services/CameraManager.swift` — Dynamic photo dimensions

### Commerce Intelligence — World-Anchored AR & Conditional Scoring
- **World-Anchored Score Cards (iOS)**: Rewrote `ARCameraView` to compute barcode world positions using ARFrame camera intrinsics + depth estimation. Score cards now track their physical product position in 3D space as the camera moves, creating a true AR experience instead of bottom-docked overlays.
- **Screen Projection Loop**: ARSessionDelegate projects all product world anchors to screen coordinates every frame via `ARView.project()`. Cards smoothly animate with 0.15s easing.
- **Inconclusive Data Hidden**: Products without real ESG or government data are silently hidden from the AR view. `SpatialDetectedProduct.hasData` flag gates card visibility — no more misleading default 50% scores.
- **Conditional Scores Only**: Scoring strategies only appear when backed by real data:
  - **Safety**: Only shown when CPSC recalls, FDA alerts, EPA violations, or Energy Star certification found.
  - **Energy Star**: Automatically hidden for food products (irrelevant metric).
  - **Durability**: Only shown for durable goods (electronics, appliances, tools, furniture).
  - **Health**: Only shown when NOVA group or Nutri-Score data exists.
- **Expanded Government Data**: Safety score now surfaces CPSC recall hazards, FDA alert classifications/reasons, EPA violation counts, and Energy Star kWh/cost — not just a binary hasConcerns check.
- **More ESG Data in Summaries**: Allergens, package quantity, retail availability now surfaced in intelligence summary when available.
- **Live Barcode Lookup (IntelligenceResultsView)**: Added `lookupBarcode()` to `VisualIntelligenceViewModel` — commerce section now runs real ESG + Government data lookups instead of showing placeholder "Scoring…" cards.
- **ProductProfileView**: Now passes `brand` and generates data-driven recommendation text with score reasoning.

### Files Changed (Commerce AR & Scoring)
- `[MODIFY]` `View/Commerce/Spatial/SpatialProductDetector.swift` — `hasData`/`isScoring`/`worldAnchor`/`screenPosition`/`esgEnrichment` on product, conditional scores, expanded gov data
- `[MODIFY]` `View/Commerce/Spatial/SpatialScoreOverlayView.swift` — World-anchored iOS AR, screen projection loop, filter by hasData
- `[MODIFY]` `View/Capture/IntelligenceResultsView.swift` — Live barcode lookup, loading state, real scores
- `[MODIFY]` `View/SpecializedProfiles/ProductProfileView.swift` — Brand pass-through, data-driven recommendation
- `[MODIFY]` `DiverKit/Sources/DiverKit/ViewModel/VisualIntelligenceViewModel.swift` — Commerce state properties, `lookupBarcode()` method

### ML-Sharp Edge Integration & RealityKit 3D
- **EdgeDaemon Capabilities**: Created `MLSharpService.swift` on the macOS daemon to wrap Apple's `ml-sharp` Python execution via `Process()`. Added the `runMLSharp` method to the distributed `EdgeInferenceActor`, securely exposing the capability to the iOS client.
- **Architecture Pivot (USDZ vs Splats)**: Transitioned from `LowLevelMesh` raw Gaussian Splats to native `.usdz` format for RealityKit performance improvements. Edge nodes now execute `python3 enhance.py --export-usdz`.
- **Spatial UI**: Created `MLSharpSplatView.swift` to natively load the 3D meshes using RealityKit's asynchronous `Entity.load(contentsOf:)`. Integrated seamless orbit and zoom gestures.
- **Auto-Provisioning**: Updated `EdgeModelProvisioner.swift` to automatically clone `apple/ml-sharp` on startup. Wire-framed `EdgeDaemonService.swift` `TXT` records to actively discover and broadcast `"ml-sharp"` capability.

### UI Logic Refactoring
- **Model UI Extraction**: Extracted SwiftUI-specific presentation properties (`displayTitle`, `relativeUpdatedDate`, `icon`, `levelColor`, `formattedDuration`) out of core SwiftData `@Model` classes (`ProcessedItem`, `SessionMetadata`, `DiverCollection`) and data enums. 
- **ModelUIExtensions.swift**: Moved all extracted formatters to a newly created `ModelUIExtensions.swift` file located in the `ViewModel` module to properly decouple the Data Core from the UI Presentation Layer.
- **Internal Schemes Update**: Enforced strict internal URL scheme routing by ensuring `ProcessedItem` display logic only registers `secretatomics://` as an internal scheme.

### Two-Phase Pipeline Split
- **Capture-Time Phase 1**: `LocalPipelineService.process()` now accepts `captureOnly` parameter. Phase 1 runs Vision analysis (OCR, QR, sift, aesthetics, saliency, classification), Location enrichment (GPS + MapKit), and Web metadata. Items appear in sidebar immediately with `.captured` status (~1-2s).
- **Background Phase 2**: `MetadataPipelineService.enrichCapturedItems()` sweeps `.captured` items after batch completion. Runs CLaRa/SLM analysis, FastVLM, Commerce scoring, Concept extraction, and Session sync. Items transition `.enriching` → `.ready`.
- **New ProcessingStatus States**: Added `.captured` (Phase 1 done, visible) and `.enriching` (Phase 2 in progress) between `.processing` and `.ready`.
- **Sidebar Queries Updated**: `readyItems` query now uses exclusion pattern (`!= queued && != processing && != failed`) to include captured/enriching items. Separate `enrichingItems` query for progress tracking.
- **processItemByID Unchanged**: User-triggered reprocessing still runs both phases synchronously (user is waiting for results).

### Commerce Edge Actor Wiring
- **Pipeline Commerce Edge Routing**: `performCommerceEnrichment` now routes government data → `EdgeESGActor.fetchGovernmentData`, nowcasting → `EdgeNowcastingActor.project`, and affiliate ranking → `EdgeCommerceActor.rankPlatforms` when Mac edge node is available. Falls back to local services.
- **AR Commerce Scoring**: `SpatialProductDetector.scoreProduct(at:)` calls all 4 commerce edge actors (gov, ESG, nowcast, affiliate) in parallel when products are detected. Populates `compositeScore`, `strategyScores`, and `recommendation` fields.
- **`performLocalNowcast` Helper**: Extracted local nowcast fallback (World Bank + BLS PPI → DFM engine) into reusable method.

### Edge Daemon Fixes
- **`summarizeStructured` Dispatch Fix**: Added explicit handler for `summarizeStructured` **before** the generic `summarize` handler. Previously, substring match routed it to `summarize`, returning a JSON string instead of `LLMAnalysisResult`.
- **`EdgeESGAActor` Typo Fix**: Corrected double-A typo (`EdgeESGAActor` → `EdgeESGActor`) in daemon dispatch for `fetchGovernmentData`.

### Edge-First Model Routing & Prompt Optimization
- **Edge-First CLaRa Routing**: Pipeline checks for edge CLaRa 7B before running SLM (Stage 1). If available, calls `EdgeContextActor.summarizeStructured()` for summary + tags + statements + purpose in a single call. Skips SLM and local FastVLM when edge succeeds.
- **`summarizeStructured()` Distributed Actor**: New method on `EdgeContextActor` returns `LLMAnalysisResult` with JSON-parsed structured output (summary, tags, statements, purpose). Falls back to plain summary if JSON parsing fails.
- **CLaRa-Only Edge Summarization**: Removed FastVLM from `EdgeContextActor.summarize()` — FastVLM 1.5B echoed input when given metadata-heavy summarization prompts (GIGO). CLaRa 7B handles long context properly. FastVLM reserved for dedicated image analysis only.
- **Specialized CLaRa Prompt**: CLaRa `summarizeStructured` prompt now includes detailed field descriptions (OCR, Vision tags, location, web, product), requests 3-7 tags, 3-5 statements, and purpose taxonomy (reference, shopping, travel, etc.).
- **Streamlined FastVLM Prompt**: `buildGroundedPrompt` simplified per Apple FastVLM best practices: short, image-focused, no large metadata dumps. Max 200 chars OCR, 8 vision tags as grounding anchors. Enrichment context removed (overwhelmed 1.5B model).
- **Fixed FastVLM Double-Wrapping**: Edge path was calling `buildGroundedPrompt` → passing result to `runVLM` → which called `buildGroundedPrompt` again inside `analyze()`. Now passes raw enrichment context.
- **Edge FastVLM Always Runs**: Stage 2 edge FastVLM (1.5B) always attempts when edge available. Only local FastVLM (0.5B) fallback skipped when CLaRa already summarized. Model ID updated to `Edge-FastVLM-1.5B`.
- **BackgroundSummaryService Predicate Fix**: Predicate had `[Model: FastVLM-` (trailing dash) but actual badge is `[Model: FastVLM]` — items never matched for upgrade. Simplified to `contains("[Model:") && !contains("[Model: Edge-CLaRa-7B]")`. Fixed `startDate` → `createdAt` on SessionMetadata sort key.
- **Splash Screen Freeze Fix**: Splash was blocking on CLaRa index population (291 items, 771 chunks, 598MB WAL). CLaRa index now builds progressively in background — splash dismisses immediately.

### CLaRa iOS Download & Context Fixes
- **Skip CLaRa Download on iOS/iPadOS**: `downloadModel()` now has `#if !os(macOS)` early return — `apple/CLaRa-7B-Instruct` is PyTorch format that MLXLLM can't load. On mobile, CLaRa runs via the macOS EdgeDaemon over Bonjour.
- **Skip CLaRa HF Hub Load on iOS**: `loadModel()` no longer falls back to HuggingFace Hub on non-macOS platforms. Only loads from local cache directory (EdgeDaemon provisioned path).
- **CLaRa Summary Badge**: `claraFallback()` in `EdgeContextActor` now stamps `[Model: Edge-CLaRa-7B]` on generated summaries. `BackgroundSummaryService` detects existing `[Model:]` badges to avoid double-stamping.
- **Enriched CLaRa Context**: Rewrote CLaRa fallback prompt with structured system prompt explaining all metadata fields (OCR, tags, location, web, VLM, questions, aesthetics, product). Increased context limit from 3000 to 6000 chars.
- **Enriched Session Summaries**: `MetadataPipelineService.generatePendingSessionSummaries()` now passes all available item metadata (tags, categories, location, web context, FastVLM analysis, questions, aesthetics, media type, product metadata) — previously only passed Title, OCR, and Place.
- **Full Pipeline on Reprocess**: `processItemByID()` now passes `fastVLMService` to both `process()` calls, matching the normal queue path. Lightning bolt reprocess runs Vision → LLM → FastVLM → CLaRa ingestion.
- **Download Failure Tracking**: Records failed download repo in UserDefaults so `downloadModel()` won't retry an incompatible repo on every launch.

## 2026-02-21

### CLaRa RAG Pipeline & Agentic Chat UI
- **Context-First Query Architecture**: Rewrote `AgenticSearchService` — context assembly (document index + Knowledge Graph + recent items) always runs first on ALL devices. Inference routes to EdgeDaemon (sends assembled context via `contextPayload`) or local CLaRa as fallback. Fixes the critical bug where CLaRa returned generic answers because the EdgeDaemon had no library context.
- **Enriched Document Ingestion**: `CLaRaLatentService.composeDocument` now decodes and indexes 7 context blobs (place, web, weather, document, QR, FastVLM analysis, questions) from `DiverShared.ContextSnapshot` types. Items are indexed immediately after pipeline processing via both `processItemImmediately` and `processItemByID`.
- **Deep-Linkable Citations**: `AgenticSearchResult.citedDocumentIDs` now returns ProcessedItem IDs from the local document index. Tapping a citation in the chat navigates to the item's `ReferenceDetailView`.
- **EdgeDaemon Context Payload**: Added `contextPayload: String?` to `AgenticSearchQuery`. `EdgeAgenticSearchActor.search` prefers client-supplied context over its own empty `DiverDataStore`.
- **Agentic Chat in Content Pane**: Moved `AgenticChatView` from `.fullScreenCover` to the middle pane of `NavigationSplitView` on iPad. On iPhone (compact width), presented as a `.sheet`. Citations show thumbnails and are tappable for navigation.
- **RAM Threshold Lowered**: `CapabilityRouter.canRunLightVLM` threshold reduced from 8GB to 7GB — enables CLaRa and FastVLM on M2 MacBook Air (7.3GB) and A17 Pro/A18 iPhones (8GB).
- **Conditional Chat Button**: "Chat with Librarian" sidebar button only appears when `CLaRaLatentService.isAvailable` or an `AgenticSearchService` exists.
- **Context Retrieval Limit**: Increased `topK` default from 5 to 100 in `retrieveContext` and `performSearch` — CLaRa now retrieves up to 100 matching chunks per query.
- **FastVLM Re-Download Fix**: `hasOptimalModelCached` now uses a `UserDefaults` flag instead of checking a non-existent directory. Prevents re-downloading on every app launch.

### Edge Node Routing & GPS EXIF
- **EdgeDaemon TXT Record Fix**: Added missing `ram` key to Bonjour TXT record in `EdgeDaemonService.startListening()`. iOS clients previously saw 0GB RAM for all edge nodes. Changed TOPS format from `%.0f` to `%.1f` for precision.
- **Bonjour Debug Logging**: Added startup log in `EdgeDaemonService` showing published TXT record values (chip, tops, ram, models). Added parsed TXT log in `BonjourDiscoveryService` for each discovered node.
- **GPS EXIF Injection**: `CameraManager.photoOutput` now injects a full `{GPS}` EXIF dictionary (latitude, longitude, altitude, speed, course, UTC timestamps) into every captured photo using `CGImageSource`/`CGImageDestination`. Preserves all existing camera EXIF metadata (device model, lens, exposure, ISO, dimensions).
- **Camera Location Wiring**: Added `CameraManager.currentLocation: CLLocation?` (`nonisolated(unsafe)` for thread-safe delegate access). Wired at 3 location update points in `VisualIntelligenceViewModel` (`locateContextOnLoad`, enrichment pipeline, `enrichContent`).
- **FastVLM Model Resolution**: Reordered `resolveModelID()` to check HuggingFace Hub cache (via `hasOptimalModelCached` flag) first, then local `config.json`, then fallback to download. Cached resolved model ID in static `_resolvedModelID` to prevent repeated resolution and logging spam.
- **Edge VLM RAM Threshold**: Lowered `canRunMediumVLM` from 8GB to 7GB (enables M2 iPad 1.5B model). Lowered edge node VLM offload threshold from 8GB to 7GB in both `EdgeNodeService.shouldOffload` and `LocalPipelineService`.
- **CLaRa Citation Deduplication**: `AgenticSearchService.assembleContext` now deduplicates document IDs (highest Jaccard score wins) while preserving relevance order.
- **FastVLM 1.5B Config Fix**: Added `patchVisionConfigIfNeeded()` workaround for mlx-swift-lm v2.30.x bug — the `apple/FastVLM-1.5B-int8` ships with empty `vision_config: {}` but the library requires non-optional `cls_ratio`, `embed_dims`, etc. The patch injects the MobileCLIP-L encoder config (matching the working 0.5B model) into the HF Hub cache config.json before model loading.

### Architectural Specification (V3)
- **UI & HW Decoupling**: Updated `spec.md` to V3, formally separating User Interface forms (iPhone, visionOS) from Hardware ML capabilities, introducing the `CapabilityRouter` strategy.
- **Transient Edge Payloads**: Enforced strict `autoreleasepool` Unified Memory constraints for the Mac Edge Node so transient image frames are never written to disk.
- **Encrypted Edge Storage**: Mandated `SQLCipher` and `FileProtectionType.complete` for all local Edge Node sqlite DBs (Commerce, Price Time Series) and ML caches to protect financial/LLM data.
- **Complete Data Deletion**: Expanded the `Delete Database` routine from 4 to 6 steps to securely erase Edge Node cross-device data and individually purge the `.Keys` CloudKit container holding API elements.
- **Documentation Parity**: Added `AskCLaRaIntent`, `AgenticChatViewModel`, and `MetadataViewModel` to `spec.md` tables. Replaced all legacy YOLO/DETR mentions with `SAM 2.1` and `FastVLM 7B`.
- **System Stat Refresh**: Re-audited pipeline files and updated source code counts across `README.md`, `GEMINI.md`, and `spec.md` to accurately reflect 62 services, 42 views, and 20 models.
- **Future Expansion Spec**: Formally documented the upcoming "Live Event & Person Capture Mode" in `spec.md`, integrating Activity Synthesis and Contact Indexing into the potential enrichment context.

### V3 Architecture Migration (Implementation)
- **Phase 1 (Swift 6 Concurrency)**: Enabled `Concurrency = Complete` across DiverKit. Removed `@unchecked Sendable` waivers from `EdgeDaemonService` and `CameraManager`. Created `MockCapabilityRouter` and `MockEdgeNodeService` for robust unit testing.
- **Phase 2 (Encrypted Storage & Security)**: Ensured `AppGroupConfig` creates DiverQueueStore directories with native `FileProtectionType.complete`. Abstracted cryptographic erasure logic into `StorageClient` to securely wipe Edge Node transient caches without affecting vital CloudKit `.Keys` containers.
- **Phase 4 (ML Model Upgrades)**: Integrated SAM 2.1 (CoreML) for subject sifting. Wired `FastVLMEnrichmentService` to the `CapabilityRouter` to automatically boot the 7B FastVLM model when 16GB+ RAM is detected, or fallback to the 0.5B model. Integrated `CLaRaLatentService` natively as a seamless local fallback inside `AgenticSearchService`.
- **Phase 5 (Temporal & Social Base)**: Scaffolded `ContactServiceProvider` integrating Vision face detection with Apple Contacts. Created `DiverSchemaV2` to migrate `SessionMetadata` with optional `livePhotoVideoPath` and `[Contact]` identifier tracking attributes, mapping the `DiverMigrationPlan` directly to `ModelContainer` for automatic CloudKit-safe migrations on launch.

## 2026-02-20

### Distributed Edge Processing & AppIntents
- **Pipeline Edge Offloading**: Fully implemented stateless edge offloading in `LocalPipelineService`. It queries `PipelineEdgeRouter` to dynamically decide whether to run `FastVLMEnrichmentService` and Vision frameworks locally or distribute them via `EdgeInferenceActor`.
- **Swift 6 Concurrency Fixes**: Refactored `CameraManager` and pipeline callbacks to operate asynchronously using `@unchecked Sendable` structs (`UncheckedObservations`, `UncheckedBuffer`) as boundary bridges to resolve compilation failures.
- **AppIntents Integration**: Created `AskCLaRaIntent`, exposing Siri-based deep linking for memory search. Fixed widget target compilation to cleanly include the intent.
- **App Architecture**: Plumbed `BonjourDiscoveryService` and `NWTransportLayer` through `VisualIntelligencePipelineApp` app delegate for discovering edge nodes and TLS transport.
- **AgenticChatView**: Integrated `AgenticChatView` and `AgenticChatViewModel` to provide an interactive chat interface to the library, resolving UI index and scope compilation errors.

### EdgeDaemon & SpatialCommerce Standalone Projects
- **EdgeDaemon**: Generated standalone macOS Xcode project via `xcodegen`. Menu bar app (LSUIElement) with Bonjour advertising on port 8847. Routes Vision, FastVLM, Nowcast, and GovernmentData requests from iOS clients. **Builds successfully for macOS.**
- **SpatialCommerce**: Generated standalone visionOS Xcode project via `xcodegen`. Uses DiverShared for commerce types (no DiverKit dependency). Requires visionOS 26.3+ SDK.
- **`project.yml` specs**: Created `EdgeDaemon/project.yml` and `SpatialCommerce/project.yml` for reproducible project generation.

### DiverKit Cross-Platform Compilation
- **`UIImage+Extensions.swift`**: Wrapped entire file in `#if canImport(UIKit)` guard for macOS compatibility.
- **`CameraManager.swift`**: Added `#if os(iOS)` guards around triple/dual camera selection, depth data format configuration, depth data delivery, and depth data extraction. macOS falls back to built-in wide-angle camera.
- **`VisualIntelligenceViewModel.swift`**: Added `#if canImport(UIKit)` with AppKit fallback in `handleDocumentSelection` for pre-rectified image loading.
- **`FastVLMEnrichmentService.swift`**: Added explicit `import CoreImage` — macOS requires this (iOS gets it via UIKit).
- **`PricingDataService.swift`**: Made `fetchWorldBankPrices` and `fetchBLSPPI` `public` for cross-module access from EdgeDaemon.

### EdgeDaemonService Fixes
- **`import ImageIO`**: Required for `CGImageSourceCreateWithData` and `CGImageSourceCreateImageAtIndex`.
- **`@unchecked Sendable`**: Added conformance for `EdgeDaemonService` to satisfy Sendable requirements in dispatch handler captures.
- **NWTXTRecord**: Changed `let` → `var` (value type requires mutation), removed `.rawData` call (pass `txtRecord` directly to `NWListener.Service`).
- **Type annotations**: Added explicit `[PriceDataPoint]` types for `sorted(by:)` disambiguation.

### Commerce UI Target Membership Fix
- **Added 8 missing Commerce views** to the `VisualIntelligencePipeline` iOS target: `APIKeyConfigView`, `CommerceActionView`, `EthicalPolicyConfigView`, `NowcastChartView`, `OwnedProductsView`, `OwnershipButton`, `ProductScoreOverlayView`, `ScoreHistoryChartView`. Created Commerce group in Xcode project. iOS app now **builds successfully**.

### Documentation
- **GEMINI.md**: Added EdgeDaemon and SpatialCommerce to Project Overview module list. Added Building and Running sections for both standalone targets. Corrected DiverKit macOS compilation note — DiverKit now compiles on macOS with platform guards.

### SpatialCommerce Integration into Main App
- **Folded SpatialCommerce** from standalone visionOS project into `VisualIntelligencePipeline` target under `View/Commerce/Spatial/`.
- **`SpatialProductDetector.swift`**: ARKit scene reconstruction wrapped in `#if os(visionOS)`. iOS/iPadOS uses existing camera pipeline for product detection.
- **`SpatialScoreOverlayView.swift`**: visionOS uses `RealityView` with `attachments` + `BillboardComponent`. iOS uses `RealityView` (single closure) with SwiftUI overlay cards.
- **`ProductScoreAttachment.swift`**: Compact score card with composite ring, strategy bars, and recommendation label. Cross-platform (no visionOS-only APIs).
- **`ReferenceDetailView.swift`**: Added `ProductScoreAttachment` as at-a-glance card above `ProductScoreOverlayView` in Commerce Intelligence section.
- **`VisualIntelligenceView.swift`**: Added AR Mode button (`cube.transparent`) to camera shutter HUD. Added Commerce Intelligence section to `IntelligenceResultsView` showing `ProductScoreAttachment` + `OwnershipButton` when `.product` (barcode) detected.
- **Workspace**: Removed `SpatialCommerce.xcodeproj` from `VisualIntelligence.xcworkspace`.

### Ethical Policy Persistence
- **`EthicalPolicySettings.swift`** [NEW]: SwiftData `@Model` with singleton pattern. Properties: `carbonThreshold`, `excludeLaborViolations`, `certifications`, `platformRanking`, `updatedAt`. Syncs via CloudKit.
- **`DiverDataStore.swift`**: Registered as 8th model in `coreTypes`.
- **`EthicalPolicyConfigView.swift`**: Migrated from volatile `@State` to `@Query` + SwiftData bindings with explicit `save()` calls. Settings now persist and sync across devices.

## 2026-02-19

### Crash Fixes

#### WKWebView EXC_GUARD Fix
- **WebViewLinkEnrichmentService**: Replaced offscreen `WKWebView` with `LPMetadataProvider` + `URLSession` HTML fetch. Eliminates WebKit XPC process crashes (`EXC_GUARD` in MobileSafari) caused by headless WebView lifecycle issues. Preserves `WebContext` fields (siteName, textContent, structuredData) via lightweight HTML parsing. JSON-LD extraction and 3000-char text content limit match original behavior.

#### SwiftData EXC_BAD_ACCESS Fix
- **MetadataPipelineService.processItemByID()**: New method that creates a private `ModelContext(modelContainer)` per call, safe to invoke from any isolation context. Prevents shared-context mutations that caused `Set.resize` use-after-free crashes.
- **EditLocationView**: Fixed both `updateSessionLocation` (N concurrent Tasks → single `Task.detached` with sequential loop) and `updateItemLocation` (moved `Task` outside `MainActor.run`).
- **SidebarViewModel**: Migrated 5 methods — `processItemNow`, `reprocessItem`, `processNow`, `reprocessSession` (had same N-concurrent-tasks crash), `analyzeSession` (now creates background ModelContext).
- **ProcessedItemViewModel.reprocessItem**: Migrated to `processItemByID`.
- **ReferenceDetailViewModel.refreshLinkMetadata**: Migrated to `processItemByID`.
- **Stuck queue toast**: Fixed as side effect — the concurrent crash left `isProcessingQueue` permanently true.
- **Tests**: Added 4 regression tests (`BackgroundSafetyTests`) + 2 architecture guard tests (`ArchitectureTests`) that scan source for `processItemImmediately` calls in ViewModels.

#### Pull-to-Refresh CloudKit Sync
- **SidebarView**: Enhanced `.refreshable` to call `modelContext.save()` before processing queue, pushing local changes to CloudKit immediately.
- **SessionItemsView (ContentView)**: Added `.refreshable` with `modelContext.save()` — previously had no pull-to-refresh support.
- **DiverDataStore**: Documented CloudKit sync behavior — SwiftData handles `NSPersistentHistoryTrackingKey` and remote change notifications internally via `ModelContainer`.

#### Stale View Code Cleanup
- **SidebarView**: Removed stale `analyzeSession` function that duplicated `SidebarViewModel.analyzeSession` with unsafe `modelContext`-in-background-Task pattern. Redirected caller to ViewModel.
- **ContentView (SessionItemsView)**: Removed 3 stale functions (`deleteItem`, `deleteSession`, `analyzeSession`) — all duplicated ViewModel methods with unsafe patterns. Redirected callers to ViewModel's safe versions.

#### FastVLM UI Freeze Fix
- **FastVLMEnrichmentService**: Memory pressure `unloadModel()` now dispatched to `Task.detached(priority: .background)` — GPU resource deallocation was blocking UI. Model loading (`ensureLoaded()`) moved inside the detached inference task so GPU allocation never blocks the calling thread. Memory pressure dispatch queue changed from `.global()` to `.global(qos: .utility)`.
- **MetadataPipelineService**: `cancelProcessing()` now dispatches `unloadModel()` to background instead of calling it synchronously on the main thread.

#### Contact Geocode Fallback
- **ContactService**: When `MKGeocodingRequest` fails for a contact's address (e.g., street doesn't exist in MapKit), falls back to user's current GPS location instead of silently dropping the contact.

### Xcode MCP Bridge Integration
- **GEMINI.md**: Added "Xcode MCP Bridge (Xcode 26.3+)" section with setup, environment variables, capabilities table, and usage rules. Updated Apple Documentation Lookup rule to include bridge doc search with WWDC transcript coverage.
- **AGENTS.md**: Added "Xcode MCP Bridge" subsection under Build, Test, and Development Commands — bridge-first build, test, preview capture, and doc search with CLI fallback.
- **CLAUDE.md**: Added matching "Xcode MCP Bridge" subsection for Claude Code/Agent compatibility.
- **Workflows**: Created `.agents/workflows/build.md`, `test.md`, and `instruments.md` — all bridge-first with CLI fallback for headless/CI environments.

### Ethical Commerce Spec Rewrite
- **Extracted §14** from `spec.md` into standalone `Documentation/ethical_commerce_spec.md`. Section replaced with a cross-reference.
- **Replaced Python stack** (Docker, FastAPI, LangChain, Kafka) with Apple-native architecture: Swift `Distributed` framework (Bonjour/`NWConnection`), CoreML on Neural Engine, MLX Swift for LLM inference.
- **Multi-platform support** — clients: iOS, iPadOS, visionOS; edge nodes: macOS (M-series), iPadOS (M-series).
- **Universal ML offloading** — all intelligence work (existing pipeline + ethical commerce) can be offloaded from any client to a more powerful device on the home network via distributed actors.
- **Commerce path** — procurement API with ethical filtering, deep-link affiliate routing to user's preferred platforms, "Buy" CTA on product overlays.
- **Personal finance integration** — FinanceKit (on-device Apple Wallet data) + Plaid (bank accounts via OAuth2) for budget validation and purchase planning.
- **Advisory decisions** — user-initiated, system-assisted (RECOMMEND/REVIEW/DELAY/OVER_BUDGET). User always confirms.
- **Real ESG data sources** for Phase 0: Climate TRACE (free), Open Food Facts (free, 3M products), OpenESG (free), World Bank Commodities (free).
- **PCAF data quality tiers** — expanded 5-tier explanation adapted from PCAF financial methodology to consumer product context.
- **Degraded-mode design** — explicit handling when ESG/pricing/financial data is unavailable.
- **Added Phase 0** — pure-Swift PoC with real data sources on iOS/Mac.
- **Removed 4 glossary terms** from `spec.md` §13 (moved to standalone document glossary).

### Deep Integration — `spec.md` v2.0
- **§1 Product Vision**: Added 2 new value propositions: Ethical Commerce Intelligence, Home Network ML Offloading.
- **§2 Architecture**: Added §2.2 Multi-Platform & Edge Computing with device compute table, distributed actor topology diagram, `VisualIntelligenceActorSystem` interface. Added distributed actor row to concurrency model. Added edge-offload decision branch to data flow diagram.
- **§3 Data Model**: Added `esgContext`, `commerceContext`, `financialContext` to ProcessedItem. Added ESG/commerce/financial fields to PipelineContext. New §3.6 with `ProductClassification`, `ESGEnrichment`, `PurchaseOption`, `FinancialSnapshot` type definitions.
- **§4 Services**: Added §4.7 Edge Node Services — 6 distributed actors: `InferenceService`, `NowcastingService`, `CommerceService`, `ESGEnrichmentService`, `PricingDataService`, `FinancialContextService`.
- **§5 Pipeline Flow**: Added stage 1a (edge decision), stage ⑧ (ESG/commerce enrichment). Annotated stages ②–⑤ with `[local OR edge]` routing.
- **§6 UI**: Added 5 future ethical commerce views (iOS + visionOS).
- **§7 Integration**: Added §7.6 Distributed Actor Edge Node — Bonjour registration, NWConnection, Info.plist config, discovery flow.
- **§8 Storage**: Added §8.4 Edge Node Storage — 5 local caches (ESG, pricing, financial, commerce, model).
- **§9 Security**: Added edge transport TLS, financial data isolation, commerce privacy, audit logging.
- **§10 Platform**: Expanded to multi-platform table (iOS/iPadOS/macOS/visionOS) with per-platform frameworks, APIs, and entitlements.
- **§11 Conventions**: Added critical rule #9 — distributed actor Codable/Sendable boundary safety.
- **§13 Glossary**: Added 9 terms (Edge Node, Data Quality Tier, Nowcasting, Advisory Decision, Distributed Actor, VisualIntelligenceActorSystem, Procurement API, FinanceKit, Affiliate Routing).
- **§14**: Updated cross-reference with section back-links to all integrated pieces.

### Version Bump & Swift Charts
- **Platform minimums**: iOS 26.0, macOS 26.0, visionOS 26.3 across `spec.md`, `ethical_commerce_spec.md`, and `DiverKit/Package.swift`.
- **Frameworks**: Added Swift Charts and FinanceKit to platform requirements table.
- **Swift Charts**: All statistical and chronological HUD visualizations use `Charts` framework (`LineMark`, `BarMark`, `AreaMark`).
- **FinanceKit entitlement**: Added to iOS client entitlements list.

## 2026-02-18

### Performance Refactor — Phase 1 (Continued)

#### SidebarView Decomposition
- **SidebarView** reduced from 1,447 → 889 lines by extracting 7 helper views into `View/Sidebar/`:
  - `SessionRowLabel.swift` (156 lines), `SidebarSessionRow.swift` (167 lines), `ItemRow.swift` (73 lines), `ItemRowWithActions.swift` (50 lines), `ThumbnailView.swift` (65 lines), `DailySummaryCard.swift` (56 lines), `ItemIconConfig.swift` (53 lines).
- All 7 files added to `project.pbxproj` with PBXBuildFile, PBXFileReference, and PBXGroup entries.

#### Dead Code Removal
- **Deleted** standalone `PipelineStatusView.swift` and inline duplicate in `VisualIntelligenceView.swift` (~70 lines). Neither was ever instantiated.
- `VisualIntelligenceView.swift` reduced from 1,698 → 1,625 lines.

#### AsyncStream Progress Delivery
- **New File**: `DiverKit/Sources/DiverKit/Models/QueueProgressEvent.swift` — `Sendable` enum with `.started`, `.processingItem`, `.itemCompleted`, `.completed`, `.cancelled` cases. Includes computed `progress` (0.0–1.0) and `isProcessing` properties.
- **MetadataPipelineService**: Added `progressStream: AsyncStream<QueueProgressEvent>` with `emitProgress()` calls at start, cancel, item-processing, item-completed, and queue-completed points. Backward compatible — existing mutable properties preserved.

#### TDD Tests
- **New File**: `DiverKit/Tests/DiverKitTests/QueueProgressEventTests.swift` — 10 tests in 2 suites:
  - *QueueProgressEventTests* (6): progress calculation, isProcessing, divide-by-zero guard.
  - *QueueProgressStreamTests* (4): cancellation emission, multi-cancel safety, fraction calculation, isProcessing for all event types.

#### SidebarView AsyncStream Subscription
- **SidebarView**: Migrated queue progress display from direct `MetadataPipelineService` property reads to reactive `AsyncStream` consumption via `.task { for await event in pipelineService.progressStream }`. Added 7 `@State` properties for queue progress. `QueueProgressView` now reads from local state instead of the service.
- SidebarView grew from 889 → 945 lines (net +56 from `.task` handler).

#### @Observable Migration (Phase 2A)
- **SidebarViewModel**: Removed `ObservableObject` conformance, added `@Observable` macro. Removed all 22 `@Published` property wrappers. Updated 6 consumer sites: `@StateObject` → `@State` (SidebarView, ContentView), `@ObservedObject` → `var` (SettingsView, SidebarSessionRow, ContentView×2).
- **VisualIntelligenceViewModel**: Same migration, 31 `@Published` removed. Updated 12+ consumer sites across 5 files. `@AppStorage` wrapped with `@ObservationIgnored`, `objectWillChange.send()` removed. 3 sub-views use `@Bindable` for `$viewModel.` binding projections.
- Per-property tracking via Observation framework eliminates `objectWillChange` over-broadcasting — only views reading specific changed properties re-render.

#### Inter-Stage Cancellation + Autorelease Pools (Phase 2A)
- **`LocalPipelineService.process()`**: Added 6 `Task.isCancelled` guards (3 per pipeline path) between: Location/Visual Analysis → Parallel Enrichment → SLM → FastVLM. On cancellation, item status resets to `.queued` and partial progress is saved, enabling retry without data loss.
- **`createCGImage(from:)`**: Wrapped in `autoreleasepool` to prevent CGImage decode buffer accumulation during batch processing.

#### Pipeline Caching (Phase 4)
- **`ReverseGeocodingService`**: Coordinate-keyed cache with 1-hour TTL. Key rounds to 4 decimal places (≈11m radius), preventing redundant MKLocalSearch/MapKit/Foursquare calls for items at the same GPS coordinates.
- **`LocalPipelineService.createCGImage`**: `NSCache<NSString, CGImageWrapper>` with `countLimit=10`. Prevents re-decoding the same image data for Vision → FastVLM within a pipeline run.
- **`LocalPipelineService.cachedEnrich`**: URL-keyed enrichment cache with 1-hour TTL. Prevents redundant web scraping for duplicate URLs across items.

#### Performance Test Stubs + Instruments Workflow (Phase 3)
- **`PipelinePerformanceTests.swift`**: Added 6 new `measure {}` benchmarks (12 total): reverse geocoding cache hit/miss, nearby coordinate sharing, CGImage decode cache, cancellation recovery throughput, pipeline initialization, concurrent fetch.
- **`.agent/workflows/instruments.md`**: Step-by-step Instruments profiling guide covering Time Profiler, Allocations, Leaks, and Hangs analysis.

### Performance Refactor — Phase 0 & Phase 1 (Partial)

#### @MainActor Fix (Phase 0)
- **Root Cause Fix**: Changed 5 `Task { @MainActor in ... }` closures → `Task.detached(priority: .utility)` in `VisualIntelligenceViewModel` to move Vision/LLM/sifting work off the main thread.

#### @unchecked Sendable Audit (Phase 1D)
- **Safety Documentation**: Added `/// Safety:` comments to all 10 production `@unchecked Sendable` types (`FoursquareEnrichmentService`, `MapKitEnrichmentService`, `DuckDuckGoEnrichmentService`, `AestheticsScoringService`, `KeychainService`, `CameraManager`, `LocationService`, `SSEStreamService`, `FastVLMEnrichmentService`, `MetadataPipelineService`). All verified safe via immutability, statelessness, serial queues, or explicit locks.

#### Service Protocol Extraction (Phase 2B)
- **New File**: `DiverKit/Sources/DiverKit/Protocols/ServiceProtocols.swift` — 4 protocols: `IntelligenceProcessing`, `ContextProcessing`, `AestheticsScoring`, `FastVLMAnalyzing`.
- **Conformances Added**: `IntelligenceProcessor`, `ContextQuestionService`, `AestheticsScoringService`, `FastVLMEnrichmentService` now conform to their respective protocols.
- **Instance `isAvailable`**: Added instance property to `FastVLMEnrichmentService` (delegates to static `isAvailable`) for protocol-based DI.

#### Pipeline DI Integration
- **MetadataPipelineService**: Stored properties changed from concrete types → protocol existentials: `contextService: (any ContextProcessing)?`, `fastVLMService: (any FastVLMAnalyzing)?`.
- **LocalPipelineService**: `process()` and `reprocessPipeline()` params changed to protocol types. `FastVLMEnrichmentService.isEnabled` static checks → `fastVLMService.isAvailable` instance checks (2 sites).
- **Protocol Updated**: Added `unloadModel()` to `FastVLMAnalyzing` (required by `cancelProcessing()`).

#### TDD Tests
- **New File**: `DiverKit/Tests/DiverKitTests/ServiceProtocolTests.swift` — 15 tests in 2 suites:
  - *Service Protocol Conformance* (10): concrete conformance, mock call tracking, lifecycle, errors, type-erased DI.
  - *Service Protocol DI Injection* (5): mock injection, availability gating, lifecycle management, nil-service skip.
- **Updated Mock**: `MockFastVLMService` now conforms to `FastVLMAnalyzing`.

#### Documentation
- **GEMINI.md**: Added testing section (schemes, `swift test` caveat, table), protocols section, DI documentation, documentation update convention.
- **Wiki** (`diverkit-services.html`): Added "Service Protocols" section with 4 protocols. Updated `LocalPipelineService`, `MetadataPipelineService`, `IntelligenceProcessor`, `FastVLMEnrichmentService`, `AestheticsScoringService`, `ContextQuestionService` descriptions.
- **Implementation Plan**: Phase 2B updated with actual protocol names and marked complete.

### Pipeline Performance & Enrichment Trimming
- **Foreground Freeze Fix**: Removed the 200ms `Task.sleep` and ~12 unnecessary `MainActor.run` wrappers from `processPendingQueue`, eliminating the multi-second UI freeze when returning to the foreground.
- **PipelineActor Isolation**: Created `@globalActor PipelineActor` and moved `LocalPipelineService` off `@MainActor`. De-isolated `MetadataPipelineService`.
- **Removed Weather Enrichment**: WeatherKit calls removed from the capture pipeline — weather data added marginal value and latency.
- **Removed Foursquare from Pipeline**: Foursquare venue matching removed from automatic capture processing. Location enrichment now relies solely on MapKit reverse geocoding + contact detection. Foursquare remains available in the location editing UI for user-initiated searches.
- **Removed DuckDuckGo Venue/Product Enrichment**: DuckDuckGo contextual search removed from location and product tasks. DuckDuckGo is now only used for web URL and QR code metadata extraction via `LinkEnrichmentService`.

### Enriched Session Summaries
- **Full Metadata Aggregation**: Updated `generateAndSaveSessionSummary` to include all available item metadata in LLM summarization: transcription, themes, tags, categories, location/place context, activity context, web context, document context, QR codes, FastVLM analysis, product metadata, questions, URLs, and media type.
- **Consolidated Summary Generation**: Refactored `SidebarViewModel.generateSessionSummary` to delegate to `LocalPipelineService.generateAndSaveSessionSummary`, ensuring all summary generation paths use the same enriched metadata.

### Library Maintenance Enhancements
- **Orphan Item Assignment**: Added `assignOrphanedItems()` as step 1 of `maintainLibrary`. Matches inbox items (nil sessionID) to the nearest existing session by `createdAt` timestamp proximity within a 30-minute window. Creates new sessions for truly orphaned items with no nearby match.
- **Reverse Chronological Processing**: Session summary regeneration now processes sessions newest-first.
- **Live Status Labels**: Replaced the progress spinner in the Rebuild Library settings row with a descriptive subtitle label showing step-by-step status (e.g., "Assigning 3 orphans…", "Summaries 4/12").
- **6-Step Pipeline**: `maintainLibrary` now runs: (1) assign orphans, (2) recover stuck, (3) regenerate missing sessions, (4) consolidate fragmented sessions, (5) reconcile relationships, (6) regenerate summaries.

### FastVLM Rename
- **Gemma → FastVLM**: Renamed all references from "Gemma" to "FastVLM" across the codebase — classes, properties, enums, comments, UI strings, and documentation — to accurately reflect the switch to Apple's FastVLM 0.5B model.

### Pipeline Audit & Code Quality
- **Aesthetics Bundled into Vision Pass**: Rewrote `AestheticsScoringService` to bundle aesthetics scoring and feature printing into `IntelligenceProcessor.executePipeline()` as a single `handler.perform()` call, eliminating the standalone `scoreImage` method and redundant image decoding.
- **New `IntelligenceResult.aesthetics`**: Added `.aesthetics(score: Float)` case to `IntelligenceResult` with `Hashable`, `Equatable`, `title`, `subtitle`, and `icon` support.
- **QR URL Enrichment**: Fixed dead QR enrichment code — QR URLs discovered during Vision analysis now get full web enrichment (metadata extraction, title, summary) via `enrichmentService.enrich(url:)` with a 15-second timeout.
- **26× Silent Save Fix**: Replaced all `try? modelContext.save()` calls with error-logging `do { try } catch { ... }` blocks across `LocalPipelineService` (8), `SidebarViewModel` (16), and `PhotoLibraryImportService` (2).
- **Removed 11× Unnecessary `Task` Wrappers**: Stripped `Task { @MainActor in ... }` from `SidebarViewModel` — the class is already `@MainActor`, making the wrappers no-ops.
- **Fixed deleteSession Race**: `isPerformingAction` now resets after a synchronous save, not before a deferred Task that hasn't run yet.
- **Dead Code Removed**: Removed empty `if let enrichmentService` block in `LocalPipelineService` that performed no enrichment.
- **Redundant Allocation Removed**: Removed unused stored `IntelligenceProcessor` instance from `LocalPipelineService` — detached tasks create their own instances.
- **Double Image Parse Consolidated**: Merged two `CGImageSourceCreateWithData` calls in `analyzeVisualContent` into one.
- **Stale Label Fixed**: Renamed "Foursquare" → "Place" in `buildDeterministicContext` to reflect current data sources.
- **Temp Video Cleanup**: Added `FileManager.removeItem(at:)` in `VisualIntelligenceViewModel.resetState()` and `reCapture()` to prevent temp `.mov` file accumulation during long sessions.

## 2026-02-15

### Documentation Cleanup
- **Agent Config Refresh**: Rewrote `GEMINI.md`, `CLAUDE.md`, and `AGENTS.md` to reflect the current Visual Intelligence Pipeline architecture.
- **Documentation Folder**: Removed 19 outdated markdown files from `Documentation/` (legacy "Diver" phase plans, one-time branch reports, external project notes). Only `APP_SUMMARY.md` and `BETA_REVIEW_NOTES.md` remain.
- **README Consolidation**: Merged inner `VisualIntelligencePipelineDemo/README.md` into the parent `README.md` and fixed broken documentation links.
- **App Summary**: Created `APP_SUMMARY.md` as the canonical product description.

## 2026-02-14

### Context Tag Persistence
- **Session Context Preservation**: Fixed a bug where context tags (purposes) were not being persisted with the correct session ID, causing them to end up in the inbox instead of their respective sessions.
- **Document Orientation**: Fixed photo orientation issues in `ReferenceDetailView` so imported images display correctly, matching sidebar thumbnails.
- **DocumentManager Update**: Improved document saving and handling.

## 2026-02-12

### Widget & Stability Fixes
- **Widget Extension**: Fixed widget rendering and data access issues in `VisualIntelligencePipelineWidget`.
- **Graceful Degradation**: Added fallback behavior for older devices that lack certain capabilities.
- **Session ID Bug**: Fixed a critical bug where items were assigned incorrect session IDs during processing.
- **Drag and Drop**: Fixed drag-and-drop interactions in the sidebar, along with sifting behavior regressions.
- **Document Handling**: Resolved issues with document detection and saving in the capture pipeline.

## 2026-02-11

### Bug Fixes
- Minor stability fixes across the pipeline.

## 2026-02-04

### Text Notes & Editing
- **Text Notes**: Added the ability to attach personal text notes to captures. Notes persist alongside visual data and are editable in `ReferenceDetailView`.
- **Document Editing**: Fixed bugs in document editing workflows — corrected issues with the "Open" button behavior and text view presentation.
- **Processing Bugfix**: Fixed a pipeline processing issue in `IntelligenceProcessor` that caused intermittent failures during concept extraction.

### Location Improvements
- **Relaxed Home Detection**: Reduced the aggressiveness of automatic "Home" labeling in `MapKitEnrichmentService` and `PhotoLibraryImportService`, preventing incorrect location assignments.
- **Location Bug Fix**: Fixed a location persistence issue in `VisualIntelligenceViewModel`.

## 2026-02-02

### Bug Fixes & UI Updates
- Assorted bug fixes and UI polish across the capture and review experience.

## 2026-01-31

### Upgrades
- Dependency and infrastructure upgrades across the project.

## 2026-01-30

### Pipeline Enhancements
- **Semantic Search Integration**: Wired `performSemanticSearch` to the sidebar UI with 300ms debounce. Falls back to vector-based semantic search when keyword results are limited.
- **Aesthetics Scoring**: Photos and videos now receive visual quality scores during import via `AestheticsScoringService`. Videos use `extractBestFrames()` for optimal frame selection.
- **Context Utilization**: Expanded LLM prompts to include weather context, place tips, OCR/transcription text, and structured web data for richer AI-generated summaries.

### Code Cleanup
- **ActivityEnrichmentService Removal**: Removed CoreMotion activity tracking code due to stability concerns.
- **Dead Code Removal**: Cleaned up 79 lines of legacy thumbnail code that was never invoked.

## 2026-01-27

### User Experience & Location
- **Intelligent Session Grouping**: Implemented persistent session grouping based on location. Captures taken at the same Place ID are now automatically merged into a single session history.
- **Location Persistence**: Introduced `SessionLocationBar` with pinning support. Users can now "Pin" a location to ensure subsequent captures remain associated with that specific place.
- **MapKit Priority**: Refactored `LocalPipelineService` to prioritize Apple MapKit results for location naming. Foursquare data is now used as a cross-referenced enhancement layer.

### UI Refinements
- **Contextual Clarity**: Added `ContextChipBar` to surface intelligent suggestions and custom context entry more prominently.
- **Clutter Reduction**: Removed legacy floating context buttons and simplified the main preview overlay.
- **Unified Summary**: Session-level LLM summaries now aggregate context from all items in a location group.

## 2026-01-12

### Visual Intelligence Pipeline
- **Unified Location Search**: Implemented `LocationSearchAggregator` to parallelize and merge Foursquare and MapKit search results.
- **Persistence Fixes**: Resolved issue where manual location overrides were reverted by Foursquare auto-enrichment. Updated `LocalPipelineService` to respect `preservePlaceIdentity` flag.
- **Duplicate Prevention**: Fixed a critical bug in `reprocessPipeline` where reprocessing items created duplicate entries.
- **Renaming Feature**: Added context menu to location pills, allowing users to long-press and rename a detected place.

### Bug Fixes
- **Type Mismatch**: Resolved `MapKitService` type mismatch (corrected to `MapKitEnrichmentService`).
- **Mutability Fix**: Resolved immutable `EnrichmentData` struct assignment errors in `VisualIntelligenceViewModel`.

## 2026-01-11

### Initial Release
- **Project Setup**: Established the Visual Intelligence Pipeline project with `VisualIntelligencePipeline` app target, `DiverKit` and `DiverShared` Swift packages.
- **Core Pipeline**: Implemented `LocalPipelineService`, `MetadataPipelineService`, and the enrichment architecture.
- **Camera & Sifting**: Built the `VisualIntelligenceView` camera interface with real-time subject detection and sifting via Vision framework.
- **Apple Music Integration**: Added `AppleMusicEnrichmentService` and `AppleMusicReferenceView` for music recognition.
- **Daily Context Service**: Implemented `DailyContextService` for generating daily focus summaries.
- **Settings View**: Built `SettingsView` with app configuration and diagnostics.
- **Sidebar & Navigation**: Created `SidebarView` with session-based navigation, favorites, and collections.
- **Build Fixes**: Resolved DiverKit build errors and improved startup performance.

## 2026-02-22

**Fixes:**
- **Splash Screen Main Thread Deadlock**: 
  - Refactored `SessionRowLabel` and `SidebarIntelligenceSection` to aggressively prevent `O(N^2)` SwiftData `@Attribute(.externalStorage)` blocking the `@MainActor` during app start.
  - Replaced synchronous `UIImage(data:)` with an async detached task using a novel, background-only `ModelContext`.
  - Upgraded image rendering to use `CGImageSourceCreateThumbnailAtIndex` for 300px memory-efficient fast downsampling.
  - Implemented `ThumbnailCache` (`NSCache`) to ensure split-second redraws across navigation views without repeated disk hits.
- **Edge Node Capabilities Discovery Timeout**:
  - Found that stale mDNS Bonjour cache led to the 60s default TCP timeout hanging iOS routing pipelines on startup.
  - Reduced `__capabilities__` query to a strict 3-second `Task.sleep` limit inside a `TaskGroup` array.
  - Refitted `EdgeNodeInfo.isAvailable` to be mutable (`var`) and implemented `BonjourDiscoveryService.markNodeUnavailable(nodeName:)` to immediately sever stale routes automatically.

## 2026-02-20

### Features & Refactoring
* **EdgeDaemon CLI Migration:** Transitioned `EdgeDaemon` from a background UIElement macOS app to a standalone interactive CLI `tool`.
* Bypasses macOS Local Network Privacy restrictions that block Bonjour mDNS advertising for ad-hoc signed apps.
* Restored management functionality lost from UI removal by implementing a REPL prompt inside the CLI.
* Added `run_daemon.sh` utility script to compile and launch the daemon intuitively from the terminal.

### Files Changed
* `[NEW]` `EdgeDaemonCLI.swift` — Replaces `EdgeDaemonApp.swift` as the `@main` entry point.
* `[NEW]` `run_daemon.sh` — Terminal convenience script to build and launch the daemon.
* `[MODIFY]` `EdgeDaemonService.swift` — Added `downloadModel(name:)`, removed `autoStart`, and integrated `print` statements for stdout tracking.
* `[MODIFY]` `project.yml` — Changed `EdgeDaemon` target `type` to `tool` and removed Info.plist generation rules.
* `[DELETE]` `ModelManagerView.swift`, `EdgeDaemonApp.swift`, `EdgeDaemonSettingsView.swift`, `EdgeDaemonStatusBar.swift`, `EdgeDaemonDashboardView.swift`, `EdgeDaemonMenu.swift`, `ClientListView.swift` — Removed all SwiftUI dependencies.

---

## Older Changes (Summary)

### Refinements
- **Queue Logic**: Improved `SidebarViewModel` sorting, fixed queue stalls, and implemented automatic deletion after failures.
- **Reprocessing UI**: Fixed missing location pills and status bar in reprocessing window.
- **LLM Context**: Prioritized location titles over visual labels for better context generation.

### Geocoding & Locations
- **Accuracy**: Fixed location accuracy issues by prioritizing enrichment location data.
- **Home/Work**: Improved detection logic to prevent aggressive "Home" labeling.
- **Geocoding**: Added MapKit reverse geocoding fallback.

### Visual Intelligence
- **Video Processing**: Implemented frame extraction and ISO6709 location parsing from video metadata.
- **Sifting**: Added support for saving full image if no crop is detected and attaching sifted subjects as metadata.
