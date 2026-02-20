# Changelog

## 2026-02-20

### Modular Ranking System & Edge Inference

#### Modular Commerce Ranking
- **RankingPolicy protocol** (DiverShared/CommerceTypes.swift): Pluggable ranking system replacing hardcoded ethical-only scoring. Defines `dimensions: [RankingDimension]`, `shouldExclude()`, and `platformPreferenceBonus()`.
- **3 policy presets**: `EthicalPolicy` (carbon/labor/certifications — default), `PriceFocusedPolicy` (price/shipping/returns), `SpeedFocusedPolicy` (delivery/stock/pickup).
- **PlatformMatch generalized**: `matchScore` replaces `ethicalMatchScore` (backward-compatible alias retained). New `dimensionScores: [String: Float]` for per-dimension breakdown.
- **AffiliateRoutingService**: Rewrote `rankPlatforms()` to iterate policy dimensions, build platform profile dict, and delegate filtering/scoring to the policy.

#### Edge Daemon Real Inference
- **EdgeDaemonService.processRequest**: Replaced stub with real dispatch — routes "vision", "vlm", "nowcast", "gov", "commerce" requests to `IntelligenceProcessor`, `FastVLMEnrichmentService`, `PricingDataService`/`NowcastingEngine`, `GovernmentDataService`, `AffiliateRoutingService`.
- **EdgeInferenceActor**: Uses `IntelligenceProcessor.process(image:mode:.fullAnalysis)` and converts `[IntelligenceResult]` → `VisionAnalysisResult` for transport. VLM uses `FastVLMEnrichmentService.analyze()`.
- **EdgeNowcastingActor**: Fetches real World Bank + BLS pricing data via `PricingDataService`.
- **EdgeFinancialActor**: Clear FinanceKit entitlement blocker documentation (no stubs).
- **discoverModels**: Checks for FastVLM 0.5B/1.5B/3B tiers + YOLOv8 CoreML.
- **ModelManagerView**: Added FastVLM 3B and YOLOv8 to available models list.

#### Chart & UI Fixes
- **ReferenceDetailView**: Fixed `allScores: []` → `first.option.scores` (real pipeline data).
- **NowcastChartView replaced**: Inline direction/confidence/projectedChange indicator — `NowcastResult` has no price data points.
- **APIKeyConfigView removed**: Deleted NavigationLink from SettingsView (free/open data only policy).
- **ImmersiveScoreView**: Available on iPad (rich 2D) + visionOS (spatial AR).

#### Documentation
- **edge-computing.html**: "Spatial Commerce (Multiplatform)" — iPad + visionOS columns. ModelManagerView lists all model families.
- **wiki stat counts**: 56 services, 38 views, 36 test files.

#### Final Stub Cleanup
- **VisualIntelligencePipelineApp**: Foursquare API key loaded from Keychain via `APIKeyService.retrieve(for: .foursquare)` — degrades gracefully if not configured.
- **ProcessedItemViewModel.shareItem**: Builds shareable content (title, summary, URL) and posts `.shareItemRequested` notification for UI layer.
- **ProcessedItemViewModel.relatedConcepts**: Queries SwiftData for `UserConcept`s matching item tags, sorted by weight.
- **ModelManagerView**: Real model download with URLSession progress tracking, per-model download IDs, actual storage size reporting via `ByteCountFormatter`.

#### APIKeyService → CloudKit Migration
- **APIKeyService**: Migrated from iOS Keychain to `CKContainer("iCloud.com.secretatomics.knowmaps.Keys")` private database. CKRecord per key with NSCache for fast synchronous reads. Added `prefetchKeys()` for app launch.
- **APIKeyConfigView**: Updated to async store/delete, shows save progress spinner, `.task` lifecycle for CloudKit prefetch.
- **VisualIntelligencePipelineApp**: Foursquare key loaded from CloudKit cache — degrades gracefully if not configured.

#### Database Hardening
- **CloudKitSyncMonitor** (NEW): Observes `NSPersistentCloudKitContainer.eventChangedNotification` for sync events. Logs setup/import/export outcomes, tracks last successful sync, posts `.syncErrorNotification` / `.syncSuccessNotification` for UI consumption.
- **VisualIntelligencePipelineApp**: Wired `CloudKitSyncMonitor.start()` after `DiverDataStore` creation.
- **GEMINI.md**: Added development rules 8 (SwiftData Storage), 9 (CloudKit Sync Monitoring), 10 (Sensitive Data Storage).

#### @ModelActor Migration
- **PersistenceActor** (NEW): `@ModelActor` for actor-isolated background SwiftData operations. Replaces manual `ModelContext(container)` pattern.
- **SidebarViewModel.analyzeSession**: Migrated from manual bg context to `PersistenceActor`.
- **ReferenceDetailViewModel.fetchScoreHistory**: Migrated from manual bg context to `PersistenceActor`.
- **MetadataPipelineService.processItemByID**: Remains manual — complex service dependencies make actor migration impractical.

#### VersionedSchema Baseline
- **DiverSchemaMigration.swift** (NEW): V1 baseline (all 7 models). Empty migration plan — not wired into DiverDataStore. Formalizes current schema for future migration safety.

## 2026-02-19

### Commerce Integration Wiring

#### Pipeline Service Integration
- **LocalPipelineService.performCommerceEnrichment**: Wired `GovernmentDataService`, `PricingDataService`, `NowcastingEngine`, and `AffiliateRoutingService` into the commerce enrichment pipeline. ESG and government data now fetched in parallel via `async let`.
- **PipelineContext**: Added `governmentData: GovernmentEnrichment?`, `nowcastResult: NowcastResult?`, `affiliateMatches: [PlatformMatch]`.
- **ProcessedItem**: Added 3 Data blobs + computed accessors: `governmentContext`, `nowcastContext`, `affiliateContext`.
- **3 helper methods**: `mapCategoryToCommodity`, `mapCategoryToBLSSeries`, `loadEthicalPolicy` (UserDefaults-backed).

#### Unit Tests (4 files, 24 tests)
- **GovernmentDataServiceTests** (7 tests): URL construction, response parsing, parallel TaskGroup, hasConcerns.
- **NowcastingEngineTests** (7 tests): Rising/falling trends, confidence bounds, empty/single edge cases, direction validation.
- **AffiliateRoutingServiceTests** (5 tests): Default 5 platforms, strict carbon policy, preference ordering, score validation, URL generation.
- **EdgeComputingTests** (5 tests): EdgeNodeInfo Codable, status values, VisionAnalysisResult, LLMAnalysisResult, ModelState.

#### UI Integration
- **ReferenceDetailView**: Commerce Intelligence section (82 lines) after Media Info — `ProductScoreOverlayView`, `OwnershipButton`, `NowcastChartView`, `CommerceActionView`, government safety alerts.
- **SettingsView**: Commerce Intelligence section with 3 NavigationLinks (EthicalPolicyConfigView, APIKeyConfigView, OwnedProductsView).
- **Xcode project**: Added all 8 Commerce view files to main target via `xcodeproj` gem.
- **NowcastChartView**: Fixed `Decimal(double:)` init, `ForEach` Identifiable conformance.

#### Documentation
- **commerce-intelligence.html**: New wiki page covering 7 scoring engines, 9 commerce services, 8 UI components, pipeline integration.
- **edge-computing.html**: New wiki page covering distributed actors, Bonjour, transport, macOS daemon, visionOS spatial.
- **index.html**: Added Intelligence nav section, module cards, updated stat counts (55+ services, 32 views, 22+ tests).

### Commerce Intelligence (Spec v2)

#### Multi-Strategy Scoring Architecture
- **7 scoring engines** run simultaneously per item: Ethics (ESG + 10 sub-dimensions), Brand Fit, Value, Durability, Social Proof, Health Fit, Total Cost.
- **ESGScoringStrategy** expanded into full Ethics engine — bundles carbon intensity, data quality, certifications, Eco-Score, plus Phase 1a sub-dimensions (product safety, nutrition quality, packaging waste, data privacy, EPA compliance, energy efficiency).
- **BrandAlignmentStrategy**: Scores by brand match, category familiarity, preference strength from `UserConcept` knowledge graph.
- **ValueScoringStrategy**: Price trend direction, forecast confidence, price positioning.
- **DurabilityScoringStrategy**: Category longevity, brand durability, repairability (EU framework), material quality.
- **SocialProofScoringStrategy**: Reddit sentiment, expert review consensus, complaint/recall history, community repairability (iFixit), demand signals.
- **HealthFitScoringStrategy**: Nutritional alignment (HealthKit), allergen safety, dietary compliance, NOVA ultra-processing detection. Non-food products get neutral pass-through.
- **TotalCostScoringStrategy**: Energy cost (Energy Star), consumables, subscription fees, replacement cycle, resale value. Category-aware lifespan estimation.

#### Open Product Database Cascade
- **ESGEnrichmentService** cascades 4 free databases (no API key required): Open Food Facts (3M+ food) → Open Beauty Facts (cosmetics) → Open Pet Food Facts → Open Products Facts.
- All share same API pattern (`/api/v2/product/{barcode}.json`). User-Agent header set per API guidelines.
- **ESGEnrichment expanded** with 12 text fields: `ingredientsText`, `allergens`, `traces`, `origins`, `manufacturingPlaces`, `novaGroup`, `nutriScore`, `nutriments` (9 nutrition facts), `packagingText`, `quantity`, `genericName`, `countriesSold`, `stores`.
- **`contextSummary` computed property** — builds SLM-ready text summary from all populated fields for richer product insights.

#### Preference Learning & Ownership
- **PreferenceLearner**: Derives per-strategy weights from `OwnedProduct` history. Squaring amplification, 5% floor per strategy, normalized to 1.0. Default equal weights across all 7 engines.
- **OutcomeSource.shared**: New acquisition source — sharing a product with a contact is treated as strongest endorsement (1.5× weight boost in `PreferenceLearner`).
- **`ProductRecommending` protocol** updated: accepts `strategyWeights: [String: Float]` for personalized composite scoring.

#### Score History & Charts
- **ScoreSnapshot** SwiftData `@Model` — records per-strategy scores, price, quantity, composite score, and preference weights at each pipeline run. Syncs via CloudKit.
- **StrategyScoreEntry** — lightweight `Codable` struct for chart data points, moved to `DiverShared` for cross-module testability.
- Pipeline `performCommerceEnrichment` auto-records a `ScoreSnapshot` after every scoring pass.

#### Ownership & Purchase Tracking
- **OwnedProduct** SwiftData `@Model` — syncs via CloudKit across devices. Records product ownership from tag scans, CTA taps, FinanceKit matches, manual marking, or sharing.
- **PurchaseOutcome** type — captures scoring context at recommendation time for RAG validation feedback loop.
- **Auto-create brand UserConcept** — pipeline auto-creates `UserConcept` with "Brand:" prefix when brand detected in product scan, incrementing weight for known brands.

#### Core Types & Services
- **CommerceTypes.swift** (DiverShared): 16 `Codable & Sendable` types including `PurchaseOutcome`, `OwnershipStatus`, `OutcomeSource`, `StrategyScoreEntry`.
- **ProductScoringStrategy** protocol with `ProductRecommending`, `ESGEnriching` protocol suite.
- **ProductRecommendationService**: Multi-strategy composite scoring + SLM advisory with learned preference weights.
- **CommerceGenerable.swift**: `@Generable` types — `AdvisorySignalOutput` (timing), `ProductInsight` (per-strategy summaries), `StrategyScoreSummary`.
- **Pipeline Stage ⑦**: 6-step enrichment (classify → enrich → score → learn → recommend → snapshot).
- **ProductScoreOverlayView**: 7-engine tab UI with timing pill and "I Own This" button.
- **CommerceTypesTests**: 11 Swift Testing tests covering all type encoding/decoding.
- **CommerceV2Tests**: 18 Swift Testing tests covering ESGEnrichment text expansion, StrategyScoreEntry, OutcomeSource edge cases.
- **ethical_commerce_spec.md** v0.3: 40-strategy catalog (§3.7), ownership tracking (§3.8), single-PR delivery.
- **Xcode MCP bridge**: Configured in `mcp_config.json` alongside Cupertino CLI.

#### Saliency Analysis (Vision Pipeline)
- **IntelligenceProcessor**: Added `VNGenerateAttentionBasedSaliencyImageRequest` as 7th Vision request in fullAnalysis mode. Extracts heatmap data and salient region bounding boxes.
- **IntelligenceResult.saliency**: New enum case wrapping `SaliencyResult` with heatmap width/height/values and normalized regions.
- Exhaustive switch updates in `verify()` and `DiverQueueItem+Intelligence`.

#### Edge Computing Types & Protocols
- **EdgeTypes.swift**: 7 Codable types — `EdgeNodeInfo`, `VisionAnalysisResult`, `SaliencyResult`, `NormalizedRect`, `LLMAnalysisResult`, `EdgeNodeStatus`, `ModelStatus`/`ModelState`.
- **ServiceProtocols.swift**: +3 protocols — `EdgeNodeDiscovering` (Bonjour node discovery), `CommerceRouting` (affiliate-enabled ethical platform ranking), `PriceNowcasting` (commodity price trajectory).
- **CommerceTypes.swift**: +`EthicalPolicy` (carbon threshold, certifications, labor violations), `PlatformMatch` (ethical match score + affiliate URL).

#### Government Data APIs
- **GovernmentDataService**: Queries 4 free US gov APIs in parallel — CPSC recalls (`saferproducts.gov`), FDA openFDA enforcement, EPA ECHO facility compliance, Energy Star product database. No auth required.
- **ESGScoringStrategy**: Live data wiring — safety uses CPSC/FDA recall counts, EPA compliance uses violation data, energy efficiency uses Energy Star certification. Graceful fallback to heuristics.
- **SocialProofScoringStrategy**: Complaint History dimension uses live CPSC/FDA data when available.

#### Commerce Data Services
- **APIKeyService**: iOS Keychain + iCloud Keychain sync for Foursquare, Reddit, iFixit API keys.
- **OpenESGService**: B Corp directory lookup, company-level ESG profiles.
- **PricingDataService**: World Bank Commodities + BLS PPI data. Conforms to `PriceNowcasting`.
- **NowcastingEngine**: Dynamic Factor Model via Accelerate vDSP — linear regression slope, weighted composite momentum, agreement-based confidence.
- **AffiliateRoutingService**: 5 platforms (Thrive Market, Target, Amazon, Best Buy, eBay) with ethical profiles (carbon, labor, certifications). Conforms to `CommerceRouting`.

#### Edge Computing Infrastructure
- **VisualIntelligenceActorSystem**: Full `DistributedActorSystem` — `EdgeActorID`, `EdgeInvocationEncoder`/`Decoder`, `EdgeResultHandler`, `EdgeTransportProtocol`.
- **BonjourDiscoveryService**: NWBrowser actor scanning `_visualintel._tcp`. TXT record parsing for chip family, neural engine TOPS, available models. Conforms to `EdgeNodeDiscovering`.
- **NWTransportLayer**: TLS 1.3 via Network framework. `OSAllocatedUnfairLock` connection pool, length-prefixed framing, 50MB response limit. Conforms to `EdgeTransportProtocol`.
- **EdgeNodeService**: 5 distributed actors (Inference, Nowcasting, Commerce, ESG, Financial) + `PipelineEdgeRouter` with TOPS-based routing and local fallback.

#### Commerce UI Views
- **OwnershipButton**: "I Own This" / "I Want This" / Considering / Returned toggle with spring animations and symbol effects.
- **OwnedProductsView**: Brand-grouped product list with overview stats (total, brands, wishlist).
- **ScoreHistoryChartView**: Swift Charts time-series with LineMark + AreaMark gradient, per-strategy colors.
- **NowcastChartView**: Price trajectory with trend direction pill (Rising/Falling/Stable), confidence gauge.
- **CommerceActionView**: Ethically-ranked platform CTAs with match score badges and affiliate deep links.
- **EthicalPolicyConfigView**: Carbon threshold slider, labor violation toggle, certification multi-select, drag-to-reorder platform ranking.
- **APIKeyConfigView**: Keychain API key management with iCloud sync, per-key status indicators.

#### macOS Edge Daemon (8 source files)
- **EdgeDaemonApp**: `MenuBarExtra` SwiftUI app (no dock icon, `LSUIElement`).
- **EdgeDaemonService**: `NWListener` with TLS 1.3, Bonjour advertising (`_visualintel._tcp`), TXT records (chip/TOPS/models), length-prefixed frame protocol, `@Observable`.
- **EdgeDaemonMenu**: Menu bar popover with stat badges, connected clients, start/stop/settings/quit.
- **EdgeDaemonDashboardView**: Stats grid, throughput chart (Swift Charts), model list, client list.
- **EdgeDaemonSettingsView**: 3-tab settings (General, Models, Network) with `AppStorage`.
- **ModelManagerView**: Available/downloaded model management with download buttons.
- **ClientListView**: Connected iOS client details.
- **EdgeDaemonStatusBar**: SF Symbol status indicator with pulse/variableColor effects.

#### visionOS Spatial Commerce (5 source files)
- **SpatialCommerceApp**: visionOS app with `ImmersiveSpace` (mixed immersion).
- **SpatialCommerceView**: Product detection list, immersive space toggle, recent scan display.
- **ProductScoreAttachment**: Glass-background score card with circular ring, expandable strategy bars.
- **SpatialProductDetector**: ARKit `SceneReconstructionProvider` anchor tracking, `@Observable`.
- **ImmersiveScoreView**: `RealityView` with `BillboardComponent` spatial attachments floating above detected objects.

> **Note:** Both targets are source-only — user must create Xcode targets and add the files.


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
