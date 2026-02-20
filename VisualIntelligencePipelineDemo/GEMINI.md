# GEMINI.md

## Project Overview

This project, **Visual Intelligence Pipeline**, is an iOS application for capturing, organizing, and enriching visual information. It uses on-device machine learning, Apple's Vision framework, and Apple Intelligence (`SystemLanguageModel`) to transform captured images and unstructured data into structured, searchable insights. It also serves as a universal hub for saving and organizing links shared from Safari, TikTok, YouTube, and more.

The project is modularized using Swift Package Manager:

*   `VisualIntelligencePipeline/` — Main application target and UI.
*   `DiverKit/` — Core logic: ML, pipeline orchestration, services, and view models.
*   `DiverShared/` — Pure Swift shared data models and utilities.

**Key Technologies:**

*   **Swift & SwiftUI:** UI and application logic.
*   **SwiftData + CloudKit:** Local-first persistence with cross-device sync.
*   **Vision & CoreML:** Subject detection, sifting, aesthetics scoring, and ML embeddings.
*   **Apple Intelligence:** Uses `SystemLanguageModel` for on-device context generation. Requires **iOS 26.0+**.
*   **MapKit:** Reverse geocoding and location enrichment for captures.
*   **Foursquare API:** Venue-level location search in editing UI via `LocationSearchAggregator` (not used in automatic pipeline processing).

## Visual Intelligence Features

*   **Intelligent Sifting:** Uses Vision framework to detect subjects in images and "sift" them out from the background with proper alpha channel handling.
*   **Context Enrichment:** Enriches captured items with:
    *   **Location:** MapKit reverse geocoding (Landmarks/Addresses) with contact detection (Home, friends), and user-pinnable persistence. Foursquare is available in the location editing UI for manual searches.
    *   **Web:** Link metadata extraction and rich link previews for web URLs and QR codes.
    *   **Aesthetics:** Quality scoring bundled into the Vision analysis pass via `VNCalculateImageAestheticsScoresRequest`. Score displayed in detail view Media Information section.
    *   **Music:** Apple Music and Spotify recognition for music-related captures.
    *   **Documents:** Automatic perspective correction and saving of detected documents.
    *   **QR Codes:** Automatic detection and web enrichment of QR code URLs.
*   **AI-Powered Understanding:** LLM-generated summaries, purpose identification, concept tagging, and daily focus briefs via `SystemLanguageModel`.
*   **Session Management:** Captures are auto-grouped by location and time into `DiverSession`s with AI-generated summaries. Sessions support bulk location editing via `EditSessionLocationView`.

### Commerce Intelligence

*   **7 Scoring Engines:** Products detected via barcode or classification are scored across 7 strategies simultaneously: Ethics (ESG + 10 sub-dimensions), Brand Fit, Value, Durability, Social Proof, Health Fit, Total Cost.
*   **Modular Ranking System:** `RankingPolicy` protocol with pluggable `RankingDimension`s. 3 presets: `EthicalPolicy` (carbon/labor/certifications — default), `PriceFocusedPolicy` (price/shipping/returns), `SpeedFocusedPolicy` (delivery/stock/pickup). `AffiliateRoutingService` iterates policy dimensions dynamically.
*   **Open Product Database Cascade:** `ESGEnrichmentService` queries 4 free Open *Facts databases (Food → Beauty → Pet Food → Products Facts) with 24h cache. Returns 12+ text fields (ingredients, allergens, NOVA processing, nutrition, packaging, origins) plus numerical scores.
*   **Preference Learning:** `PreferenceLearner` derives per-strategy weights from `OwnedProduct` history. Sharing products (`.shared` source) gets 1.5× weight boost. Weights evolve as user's ownership patterns emerge.
*   **Score Snapshots:** `ScoreSnapshot` SwiftData model records per-strategy scores, price, quantity, and preference weights at each pipeline run — consumed by Swift Charts for time-series visualization.
*   **Free/Open Data Only:** No paid APIs. All data from ODbL/CC0 databases, gov APIs (CPSC, FDA, EPA, Energy Star), and free tiers (Reddit, iFixit).
*   **SLM Advisory:** `ProductRecommendationService` generates timing recommendations (Buy Now / Wait / Neutral) via `SystemLanguageModel` using enriched `contextSummary` from product databases.

### Pipeline Services

*   **`LocalPipelineService`:** The core orchestrator. Handles ingestion, enrichment, and persistence.
*   **`MetadataPipelineService`:** Converts queue items to `LocalInput` and orchestrates metadata extraction. Uses `Task.detached(priority: .utility)` for all heavy processing.
*   **`IntelligenceProcessor`:** Runs on-device LLM prompts for concept extraction and summarization. Also runs 7 Vision requests (OCR, QR, semantic, document, sifting, aesthetics, saliency) in a single pass via `executePipeline`.
*   **`FastVLMEnrichmentService`:** Runs Apple's FastVLM 0.5B model locally via MLX Swift. Image analysis prompt focuses on subject matter (objects, text, activities) and explicitly excludes camera/capture equipment references to prevent hallucinations.
*   **Reprocessing:** Supports silent background reprocessing via `processItemByID` (private `ModelContext` per call) and bulk `reprocessPipeline` to update metadata. Reuses existing item IDs to prevent duplicates.
*   **Session Sync:** Automatically synchronizes location edits between `ProcessedItem` and its parent `DiverSession`.
*   **Enriched Session Summaries:** `generateAndSaveSessionSummary` aggregates all item metadata (transcription, themes, tags, categories, location, web/document/QR context, FastVLM analysis, product metadata, questions, media type) for LLM summarization.
*   **Library Maintenance (`maintainLibrary`):** A 6-step repair pipeline triggered from Settings > Rebuild Library:
    1. Assign orphaned inbox items to sessions by `createdAt` timestamp proximity (30-min window)
    2. Recover stuck items (reset processing → queued)
    3. Regenerate missing session records
    4. Consolidate fragmented sessions (5s/50m proximity)
    5. Reconcile SwiftData relationships
    6. Regenerate all session summaries (reverse chronological order)

## Building and Running

1.  **Open the project in Xcode:**
    ```bash
    open VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj
    ```
2.  **Select a target:** Choose the `VisualIntelligencePipeline` scheme.
3.  **Run the application:** `Cmd+R`. Requires iOS 26.0+ for Apple Intelligence features.

### Testing

> **Note:** `swift test` does not work for DiverKit — it compiles for macOS which lacks UIKit.
> Always use `xcodebuild test` with an iOS Simulator destination.

```bash
# Build for iOS Simulator
xcodebuild -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme VisualIntelligencePipeline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run DiverKit unit tests (service protocols, pipeline, view models)
xcodebuild test -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme DiverTests_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run app-level unit tests
xcodebuild test -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme VisualIntelligencePipeline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run DiverShared package tests (pure Swift, no UIKit)
cd DiverShared && swift test
```

**Test Schemes:**
| Scheme | Target | Contents |
|--------|--------|----------|
| `DiverTests_iOS` | DiverKit SPM tests | Service protocols, pipeline, enrichment, VM tests |
| `VisualIntelligencePipeline` | App test bundle | Integration, share intent, adapter tests |
| `DiverShared` | SharedLib SPM tests | Pure Swift model/utility tests |

## Development Conventions

*   **SwiftUI:** Views are organized in `VisualIntelligencePipeline/VisualIntelligencePipeline/View/`.
*   **View Models:** Located in `DiverKit/Sources/DiverKit/ViewModel/` — `VisualIntelligenceViewModel`, `SidebarViewModel`, `ReferenceDetailViewModel`, `ProcessedItemViewModel`.
*   **Protocols:** Located in `DiverKit/Sources/DiverKit/Protocols/` — `IntelligenceProcessing`, `ContextProcessing`, `AestheticsScoring`, `FastVLMAnalyzing`, `ProductScoringStrategy`, `ProductRecommending`, `ESGEnriching`, `EdgeNodeDiscovering`, `CommerceRouting`, `PriceNowcasting`.
*   **Services:** Located in `DiverKit/Sources/DiverKit/Services/` — 55+ services covering camera, enrichment, pipeline, location, commerce scoring, edge computing, government APIs, and more.
*   **Commerce Services:** Located in `DiverKit/Sources/DiverKit/Services/Commerce/` — `GovernmentDataService`, `APIKeyService`, `OpenESGService`, `PricingDataService`, `NowcastingEngine`, `AffiliateRoutingService`.
*   **Edge Services:** Located in `DiverKit/Sources/DiverKit/Services/Edge/` — `VisualIntelligenceActorSystem`, `BonjourDiscoveryService`, `NWTransportLayer`, `EdgeNodeService` (5 distributed actors).
*   **Scoring Engines:** Located in `DiverKit/Sources/DiverKit/Services/Scoring/` — 7 strategy implementations conforming to `ProductScoringStrategy`.
*   **Test Mocks:** Located in `DiverKit/Tests/DiverKitTests/Mocks/` — `MockFastVLMService` (conforms to `FastVLMAnalyzing`), `MockEnrichmentService`, etc.
*   **Swift Packages:** Shared code modularized into `DiverKit` and `DiverShared`.
*   **Asynchronous Operations:** Uses `async/await` throughout for network requests, ML inference, and file I/O.
*   **Dependency Injection:** Services like `KnowMapsServiceContainer` and `DiverQueueProcessingService` are injected at initialization. `MetadataPipelineService` and `LocalPipelineService` accept `(any ContextProcessing)?` and `(any FastVLMAnalyzing)?` protocol types for testability.

## Critical Development Rules (Read Carefully)

1.  **Documentation Must Stay Current Between Every Commit:**
    *   **All markdown files** in the project must be updated to reflect code changes before every commit to GitHub.
    *   Files to check and update: `GEMINI.md`, `README.md`, `changelog.md`, `spec.md`, `Documentation/analysis.md`, `Documentation/APP_SUMMARY.md`, `Documentation/BETA_REVIEW_NOTES.md`, and the HTML wiki (`Documentation/wiki/`).
    *   `changelog.md` must have a dated entry for every commit with all changes.
    *   Service counts, protocol counts, test counts, and feature descriptions must match the current codebase.

2.  **Apple Documentation Lookup:**
    *   **Always use the Cupertino CLI** (`/opt/homebrew/bin/cupertino`) for Apple documentation queries. Prefer it over web searches for API details, concurrency patterns, framework behavior, and best practices.
    *   Available sources: `apple-docs`, `samples`, `hig`, `apple-archive`, `swift-evolution`, `swift-org`, `swift-book`, `packages`.
    *   Semantic searches: `search_symbols`, `search_property_wrappers`, `search_concurrency`, `search_conformances`.
    *   **Xcode MCP bridge** also provides Apple doc search with WWDC transcript coverage when Xcode is running. Use it as a complement to Cupertino.

3.  **NEVER Compromise Data Integrity:**
    *   **Schema Changes:** Do **NOT** rename Core Data entities (e.g., `SessionMetadata`) or perform destructive schema changes without a fully tested migration plan.
    *   **Recovery:** Prioritize recovery mechanisms over wiping data.

4.  **Build Stability is Paramount:**
    *   After *any* refactoring (especially renaming types), verify the project builds.
    *   When renaming a type, ensure **ALL** references across the codebase are updated immediately.

5.  **Dependency Management (KnowMaps):**
    *   Local Swift Package dependencies can resolve to stale commits. If you encounter "inaccessible due to 'internal' protection level" errors, it is likely a stale dependency cache.
    *   Runtime reflection (using `Mirror`) is an acceptable *temporary* workaround when documented.

6.  **UI & MapKit Stability:**
    *   Use `.id` (UUID) rather than `placeID` for identifying MapKit results in SwiftUI lists.
    *   Use aspect-ratio based layouts for images instead of fixed dimensions.

7.  **Main Thread Safety:**
    *   Keep long-running pipeline tasks off the main thread. Use `@PipelineActor` or `Task.detached` for heavy processing.
    *   **Never use `Task { }` in SwiftUI handlers** (`onAppear`, `onChange`, `onReceive`) for pipeline work — it inherits `@MainActor`. Always use `Task.detached(priority: .utility)` with explicit capture lists.
    *   **Use background `ModelContext`** for SwiftData fetches in pipeline/enrichment code. Create via `ModelContext(container)` with `autosaveEnabled = false`. Never use `dataStore.mainContext` or `manager.mainContext` from background tasks.
    *   **Use `processItemByID` (not `processItemImmediately`)** for reprocessing from UI/ViewModel code. `processItemByID` creates a private `ModelContext` per call, preventing shared-context corruption. `processItemImmediately` is internal to `MetadataPipelineService` batch processing only.
    *   **Never spawn N concurrent Tasks in a for-loop** that each mutate SwiftData models. Collect IDs first, then process sequentially in a single `Task.detached`.
    *   Provide immediate visual feedback on user actions even when underlying model updates are still in progress.

8.  **SwiftData Storage Rules:**
    *   **Never store large binary data inline on `@Model` classes.** Use `@Attribute(.externalStorage)` for `Data` properties over ~1KB (images, depth maps, payloads). SwiftData loads **all** non-external properties into memory on fetch.
    *   **Context `Data?` blobs** (weather, place, web, commerce, etc.) are small JSON (~1KB) and acceptable inline. If any grows beyond ~10KB, migrate to `.externalStorage` or file-path reference.
    *   **Prefer `FetchDescriptor` with `fetchLimit` and `propertiesToFetch`** over bare `@Query` for views that may display large datasets (sidebar, search results). `@Query` loads all matching objects eagerly.
    *   **All schema changes must be lightweight** when CloudKit sync is enabled. Custom migration = end of sync. Use `VersionedSchema` + `SchemaMigrationPlan` for any model changes.

9.  **CloudKit Sync Monitoring:**
    *   **Monitor `NSPersistentCloudKitContainer.eventChangedNotification`** for sync failures. Log errors and surface critical sync issues to the user (e.g., account problems, quota exceeded).
    *   **CloudKit throttles**: Minimum 30-second intervals between rapid sync operations. Battery, network, and system resources dynamically adjust sync frequency.
    *   **API keys** are stored in the `iCloud.com.secretatomics.knowmaps.Keys` CloudKit container (private database). Use `APIKeyService.prefetchKeys()` on app launch to populate the NSCache for synchronous reads.

10. **Sensitive Data Storage:**
    *   **API keys and tokens** belong in CloudKit (Keys container) or Keychain — **never** in UserDefaults or plist files.
    *   **Authentication secrets** (e.g., `diverLinkSecret`) use `KeychainService` with `kSecAttrAccessibleAfterFirstUnlock` for background task access.
    *   **UserDefaults** is acceptable only for user preferences (theme, font size, feature flags). It loads **everything** into memory at app startup.

## Data Model Relationships

*   **`masterCaptureID`** (String): Links sibling captures from the same session (e.g., a photo + its detected QR code URL + its detected document). Displayed in `ReferenceDetailView` via `CaptureSiblingsView`.
*   **`parentItem` / `childItems`** (SwiftData relationship): Purpose-based parent-child links created by `linkToParent(item:purpose:)`. Groups items by activity/intent. Only populated when the pipeline identifies a shared purpose across items.
*   **`sessionID`** (String): Links items to their `DiverSession`. Managed by `VisualIntelligenceViewModel.activeSessionID` — set once in `onAppear` and only changed by explicit session-start actions.

## Terminology

*   **DiverSession:** Typealias for `SessionMetadata`. Use `DiverSession` in new code.
*   **ProcessedItem:** The primary data model for enriched captures and links.
*   **SidebarViewModel:** Centralizes sidebar state, session management, drag-and-drop, and library maintenance.
*   **VisualIntelligenceViewModel:** Manages camera, detection, sifting, and capture review state.

## Key Files

### App & UI
*   `VisualIntelligencePipelineApp.swift` — App entry point, service initialization, foreground/background lifecycle
*   `View/VisualIntelligenceView.swift` — Camera and capture UI
*   `View/SidebarView.swift` — Main navigation sidebar (889 lines, delegates to 7 child views in `View/Sidebar/`)
*   `View/Sidebar/` — Extracted child views: `SessionRowLabel`, `SidebarSessionRow`, `ItemRow`, `ItemRowWithActions`, `ThumbnailView`, `DailySummaryCard`, `ItemIconConfig`
*   `View/ReferenceDetailView.swift` — Item detail view (media info, aesthetics score, capture siblings, references)
*   `View/CaptureReviewView.swift` — Post-capture review
*   `View/EditLocationView.swift` — Location editing for individual items
*   `View/EditSessionLocationView.swift` — Bulk location editing for sessions
*   `View/SettingsView.swift` — App settings and library maintenance UI
*   `View/QueueProgressView.swift` — Pipeline queue processing progress
*   `View/ReprocessingWizardView.swift` — Guided reprocessing workflow
*   `View/Commerce/ProductScoreOverlayView.swift` — 7-engine score overlay with timing pill
*   `View/Commerce/OwnershipButton.swift` — "I Own This" / "I Want This" toggle with spring animations
*   `View/Commerce/OwnedProductsView.swift` — Brand-grouped owned products list
*   `View/Commerce/ScoreHistoryChartView.swift` — Swift Charts time-series score history
*   `View/Commerce/NowcastChartView.swift` — Price trajectory with trend pills
*   `View/Commerce/CommerceActionView.swift` — Ethical platform ranking with affiliate CTAs
*   `View/Commerce/EthicalPolicyConfigView.swift` — RankingPolicy preferences (carbon/labor/certification/platform/price/speed)

### Core Services (DiverKit)
*   `Services/LocalPipelineService.swift` — Core pipeline orchestrator
*   `Services/MetadataPipelineService.swift` — Metadata extraction and queue processing
*   `Services/IntelligenceProcessor.swift` — On-device LLM processing
*   `Services/FastVLMEnrichmentService.swift` — FastVLM multimodal image analysis
*   `Services/LocationSearchAggregator.swift` — Unified Foursquare + MapKit search
*   `Services/SessionClusteringService.swift` — Time/location-based session grouping
*   `Services/CameraManager.swift` — AVFoundation camera management
*   `Services/DailyContextService.swift` — Daily focus summary generation
*   `Services/ESGEnrichmentService.swift` — 4-database Open *Facts cascade + Climate TRACE
*   `Services/ProductRecommendationService.swift` — Multi-strategy composite scoring + SLM advisory
*   `Services/PreferenceLearner.swift` — Ownership history → learned strategy weights
*   `Services/Scoring/` — 7 scoring engines (ESG, Brand, Value, Durability, Social, Health, TotalCost)
*   `Services/Commerce/GovernmentDataService.swift` — CPSC, FDA, EPA, Energy Star (4 APIs, parallel)
*   `Services/Commerce/APIKeyService.swift` — CloudKit-backed key storage (iCloud.com.secretatomics.knowmaps.Keys container)
*   `Services/Commerce/OpenESGService.swift` — B Corp directory, company-level ESG
*   `Services/Commerce/PricingDataService.swift` — World Bank + BLS PPI (PriceNowcasting)
*   `Services/Commerce/NowcastingEngine.swift` — Dynamic Factor Model via Accelerate vDSP
*   `Services/Commerce/AffiliateRoutingService.swift` — 5 platforms, ethical profiles (CommerceRouting)
*   `Services/Edge/VisualIntelligenceActorSystem.swift` — Custom DistributedActorSystem
*   `Services/Edge/BonjourDiscoveryService.swift` — NWBrowser actor, Bonjour TXT records
*   `Services/Edge/NWTransportLayer.swift` — TLS 1.3, OSAllocatedUnfairLock, length-prefixed framing
*   `Services/Edge/EdgeNodeService.swift` — 5 distributed actors + PipelineEdgeRouter
*   `Storage/DiverDataStore.swift` — SwiftData container management (7 models incl. OwnedProduct, ScoreSnapshot)
*   `Storage/PersistenceActor.swift` — `@ModelActor` for actor-isolated background SwiftData operations
*   `Storage/DiverSchemaMigration.swift` — VersionedSchema baseline (V1) and migration plan

### Models (DiverKit)
*   `Models/ProcessedItem.swift` — Primary enriched item model
*   `Models/DiverSession.swift` — Session grouping model
*   `Models/DiverCollection.swift` — User-created collections
*   `Models/UserConcept.swift` — Concept/tag model
*   `Models/AestheticsTypes.swift` — Image quality scoring types
*   `Models/QueueProgressEvent.swift` — AsyncStream event enum for queue progress delivery
*   `Models/OwnedProduct.swift` — Product ownership tracking (CloudKit synced)
*   `Models/ScoreSnapshot.swift` — Time-series score history for Swift Charts
*   `Models/CommerceGenerable.swift` — `@Generable` types for SLM commerce prompts
*   `Models/EdgeTypes.swift` — Edge computing types: `EdgeNodeInfo`, `VisionAnalysisResult`, `SaliencyResult`, `LLMAnalysisResult`, `EdgeNodeStatus`, `ModelStatus`

## Code Cleanliness & Known Technical Debt

### Concurrency Patterns (Validated against Apple Docs)
*   **SE-0466 (`defaultIsolation`):** `Task {}` inside `@MainActor` contexts inherits main actor isolation. Always use `Task.detached(priority: .utility)` with explicit `[weak self]` capture lists for ML/Vision/LLM work. Use `await MainActor.run { }` for UI-only property updates.
*   **`LanguageModelSession`:** `final class` with no actor isolation — safe to run from any thread.
*   **`IntelligenceProcessor`:** `Sendable` with no actor isolation — must not be called from `@MainActor` tasks.
*   **Vision framework (iOS 18+):** Native Swift concurrency support — runs naturally on background threads.
*   **`@unchecked Sendable`:** ~20 usages across the codebase. Each must be audited to verify thread safety is enforced via locking (e.g., `OSAllocatedUnfairLock`).
*   **`CaptureInput`:** Marked `@unchecked Sendable` because it contains `PhotosPickerItem` (not `Sendable`). Safe because it's consumed exactly once after crossing the isolation boundary.
*   **`processItemByID` vs `processItemImmediately`:** `processItemByID` creates a private `ModelContext(modelContainer)` per call — safe from any isolation context and prevents shared-context corruption. `processItemImmediately` uses the service's shared `activeContext` and must only be called internally during batch processing (inside `processPendingQueue`'s `bgContext`). Architecture tests enforce this boundary.

### ViewModel Bloat
*   **`VisualIntelligenceViewModel`:** ~2900 lines, 31 properties. Migrated to `@Observable` — per-property tracking eliminates `objectWillChange` over-broadcasting.
*   **`SidebarViewModel`:** ~1200 lines, 22 properties. Migrated to `@Observable`.
*   **`SidebarView`:** 945 lines (decomposed from ~1450; 7 child views extracted to `View/Sidebar/`).

### Service Coupling
*   **`MetadataPipelineService`:** Views directly read mutable progress properties (`isProcessingQueue`, `queueTotalCount`, etc.). AsyncStream-based `progressStream` added alongside for incremental migration to `for await` event delivery.
*   **`Services.shared`:** Global singleton accessed from `@MainActor` context. Accesses from `Task.detached` must use `await MainActor.run { Services.shared.someService }`.
*   **Protocol extraction complete:** `ProductScoringStrategy`, `ProductRecommending`, `ESGEnriching` — all commerce services use protocol-based DI. Remaining: `IntelligenceProcessor`.

### Performance Debt
*   **Apple's 100ms hang threshold:** Per Apple's "Improving App Responsiveness" guide, any main-thread delay >100ms is noticeable. Less than half that time is available for app work due to event handling and rendering overhead.
*   **Inter-stage cancellation (implemented):** `LocalPipelineService.process()` has 6 `Task.isCancelled` guards (3 per path) between Location/Visual → Parallel Enrichment → SLM → FastVLM. On cancellation, items reset to `.queued` with partial progress saved.
*   **Autorelease pools (implemented):** `createCGImage(from:)` uses `autoreleasepool` to prevent CGImage decode buffer accumulation during batch processing.
*   **Caching (implemented):** Reverse geocoding uses a coordinate-keyed cache (4-decimal places ≈ 11m, 1hr TTL). CGImage decoding uses `NSCache<NSString, CGImageWrapper>` (countLimit=10). Link enrichment uses URL-keyed cache (1hr TTL).
*   **`sortAndFilter` in views:** O(n log n) computed on every render — should cache results.

### Apple Documentation References (via Cupertino CLI)
*   **`@ModelActor` macro (SwiftData, iOS 17+):** Generates boilerplate for `ModelActor` protocol conformance; creates isolated `ModelContext` for background SwiftData access. Preferred over raw `ModelContext(container)` for actor-based background persistence.
*   **`DefaultSerialModelExecutor` (SwiftData):** Safely performs storage tasks on an isolated model context. Used internally by `@ModelActor`.
*   **`@ObservationIgnored` (Observation framework):** Disables observation tracking for specific properties. Use for caches, debug logs, and internal bookkeeping that shouldn't trigger view updates during `@Observable` migration.
*   **SE-0449 `nonisolated` inference cutoff (Swift 6.1):** Allows `nonisolated` on declarations to prevent global actor inference from protocols/supertypes. Applied when a struct conforming to an `@MainActor` protocol has pure-computation methods that shouldn't require main-thread execution.
*   **SE-0461 Isolation regions:** Defines sending rules between nonisolated, actor-isolated, and `@concurrent` contexts. Governs how values cross isolation boundaries in `Task.detached` closures.

## Xcode MCP Bridge (Xcode 26.3+)

The Xcode MCP bridge (`xcrun mcpbridge`) exposes Xcode's internal tools to external agents via the Model Context Protocol over STDIO. When Xcode is running with a project open, the bridge auto-detects and connects.

### Setup

1.  **Enable in Xcode:** Settings → Intelligence → Model Context Protocol → Toggle **"Xcode Tools"** On.
2.  **Bridge command:** `xcrun mcpbridge` (STDIO transport, JSON-RPC 2.0).

### Environment Variables

| Variable | Purpose |
|---|---|
| `MCP_XCODE_PID` | Target a specific Xcode instance by PID. Auto-detects if unset. |
| `MCP_XCODE_SESSION_ID` | UUID identifying an Xcode tool session (optional). |

### Available Capabilities

| Capability | When to Use |
|---|---|
| **Build projects** | Prefer over raw `xcodebuild` — returns structured diagnostics (file, line, column, severity). |
| **Read build logs** | Parse errors/warnings after builds without scraping terminal output. |
| **Run tests** | Iterate on failures with structured results. Use for `DiverTests_iOS`, `VisualIntelligencePipeline`, and `DiverShared` targets. |
| **Capture SwiftUI previews** | Verify UI changes visually — the only way to get preview screenshots programmatically. |
| **Search Apple documentation** | Includes WWDC transcripts. Complements Cupertino CLI for broader coverage. |
| **Manage project files** | Query and modify the `.xcodeproj` structure natively. |
| **Structured diagnostics** | Receive compiler errors/warnings with file paths and line numbers. |

### Rules

*   **Prefer bridge for builds and tests** when Xcode is running. Fall back to CLI `xcodebuild` / `swift test` in headless/CI environments.
*   **Use bridge preview capture** to verify SwiftUI UI changes after modifying views.
*   **Combine with Cupertino CLI** — bridge covers WWDC transcripts, Cupertino covers structured API docs, sample code, HIG, and Swift Evolution.
