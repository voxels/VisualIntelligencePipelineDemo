# Changelog

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
