# Changelog

## 2026-01-30

### Pipeline Enhancements
- **Semantic Search Integration**: Wired `performSemanticSearch` to the sidebar UI with 300ms debounce. Falls back to vector-based semantic search when keyword results are limited.
- **Aesthetics Scoring**: Photos and videos now receive visual quality scores during import via `AestheticsScoringService`. Videos use `extractBestFrames()` for optimal frame selection.
- **Context Utilization**: Expanded LLM prompts to include weather context, place tips, OCR/transcription text, and structured web data for richer AI-generated summaries.

### Code Cleanup
- **ActivityEnrichmentService Removal**: Removed CoreMotion activity tracking code due to stability concerns. This removes the `activityContext` field from enrichment.
- **Dead Code Removal**: Cleaned up 79 lines of legacy thumbnail code that was never invoked.

### Documentation
- Updated all project documentation to reflect current architecture (iOS 26.0+, no activity tracking, aesthetics scoring).

## 2026-01-27

### User Experience & Location
- **Intelligent Session Grouping**: Implemented persistent session grouping based on location. Captures taken at the same `Place ID` are now automatically merged into a single session history.
- **Location Persistence**: Introduced `SessionLocationBar` with pinning support. Users can now "Pin" a location to ensure subsequent captures remain associated with that specific place.
- **MapKit Priority**: Refactored `LocalPipelineService` to prioritize Apple MapKit results for location naming, ensuring consistency with the iOS ecosystem. Foursquare data is now used as a cross-referenced enhancement layer rather than the primary source.

### UI Refinements
- **Contextual Clarity**: Added `ContextChipBar` to surface intelligent suggestions and custom context entry more prominently.
- **Clutter Reduction**: Removed legacy floating context buttons and simplified the main preview overlay.
- **Unified Summary**: Session-level LLM summaries now aggregate context from all items in a location group, providing a holistic view of the visit.

## 2026-01-12

### Visual Intelligence Pipeline
- **Unified Location Search**: Implemented `LocationSearchAggregator` to parallelize and merge Foursquare and MapKit search results, ensuring consistent location data across `EditLocationView`, `EditSessionLocationView`, and `PlaceSelectionMapView`.
- **Persistence Fixes**:
    - Resolved issue where manual location overrides (e.g., from MapKit) were reverted by Foursquare auto-enrichment.
    - Updated `LocalPipelineService` to respect `preservePlaceIdentity` flag.
    - Explicitly linked `DiverSession` location updates to `ProcessedItem` location changes to ensure data consistency.
- **Duplicate Prevention**: Fixed a critical bug in `reprocessPipeline` where reprocessing items created duplicate entries. Now ensures existing item IDs are reused.
- **Renaming Feature**: Added context menu to `VisualIntelligenceView` location pills, allowing users to long-press and rename a detected place.

### Documentation & Architecture
- **Refreshed Documentation**: Updated `GEMINI.md` and `CLAUDE.md` to reflect the `VisualIntelligencePipeline` workspace.
- **Removed Legacy References**: Removed references to the defunct `Diver` directory and target.
- **Build Instructions**: Added specific `xcodebuild` commands for the `VisualIntelligencePipeline` scheme.

### Bug Fixes
- **Compiler Error**: Resolved `MapKitService` type mismatch (corrected to `MapKitEnrichmentService`).
- **Mutability Fix**: Resolved "cannot assign to property: 'placeContext' is a 'let' constant" error in `VisualIntelligenceViewModel` by correctly recreating immutable `EnrichmentData` structs during updates.

---

## Older Changes (Summary)

### Refinements
- **Queue Logic**: Improved `SidebarViewModel` sorting, fixed queue stalls, and implemented automatic deletion after failures.
- **Reprocessing UI**: Fixed missing location pills and status bar in reprocessing window.
- **LLM Context**: Prioritized location titles over visual labels for better context generation.

### Geocoding & Locations
- **Accuracy**: Fixed "Locations are all wrong next to images" by prioritizing enrichment location.
- **Home/Work**: Improved detection logic to prevent aggressive "Home" labeling.
- **Geocoding**: Added MapKit reverse geocoding fallback.

### Visual Intelligence
- **Video Processing**: Implemented frame extraction and ISO6709 location parsing from video metadata.
- **Sifting**: Added support for saving full image if no crop is detected and attaching sifted subjects as metadata.
