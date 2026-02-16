# Changelog

## 2026-02-16

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
