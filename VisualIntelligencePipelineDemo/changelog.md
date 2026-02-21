# Changelog

## 2026-02-21

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
