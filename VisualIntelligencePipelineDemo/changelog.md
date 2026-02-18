# Changelog

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
