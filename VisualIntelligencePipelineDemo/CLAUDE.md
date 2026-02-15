# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Visual Intelligence Pipeline** is an iOS application for capturing, organizing, and enriching visual information using on-device ML, Apple's Vision framework, and Apple Intelligence (`SystemLanguageModel`). It also serves as a universal hub for saving and organizing links shared from Safari, TikTok, YouTube, and more.

**Platform Requirements:** iOS 26.0+ (required for Apple Intelligence features)

## Essential Commands

### Building and Testing

```bash
# Build for iOS Simulator
xcodebuild -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme VisualIntelligencePipeline \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run DiverKit package tests
cd DiverKit && swift test

# Run DiverShared package tests
cd DiverShared && swift test

# Run a single test
swift test --filter DiverSharedTests.LinkWrappingTests/testWrapURL
```

## Module Architecture

### Three-Layer Package Structure

1. **DiverShared** (Pure Swift, no dependencies)
   - Shared utilities for app + extensions
   - Key components: `DiverItemDescriptor`, `DiverQueueStore`, `DiverLinkWrapper`, `Validation`, `AppGroupConfig`
   - Location: `DiverShared/Sources/DiverShared/`

2. **DiverKit** (Core framework, depends on DiverShared)
   - ML pipeline, services, view models, models, storage
   - Key components: `LocalPipelineService`, `MetadataPipelineService`, `IntelligenceProcessor`, `SidebarViewModel`, `VisualIntelligenceViewModel`
   - Location: `DiverKit/Sources/DiverKit/`

3. **VisualIntelligencePipeline** (Main App Target)
   - SwiftUI app with camera, sifting, enrichment, sidebar, detail views
   - App-level services: `KnowMapsServiceContainer`, `DiverQueueProcessingService`, `KnowMapsAdapter`
   - AppIntents: 5 intents (Save, Share, Search, GetRecent, Open) + Widget extension
   - Location: `VisualIntelligencePipeline/VisualIntelligencePipeline/`

4. **LocalPackages/YahooSearch** — Local package for web search enrichment

### Key Architectural Patterns

**Local-First Data Flow:**
```
Camera/Import/ShareSheet → LocalPipelineService → SwiftData + CloudKit
```

**Service Wiring:**
- `KnowMapsServiceContainer`: Consolidates ML, search, cache, analytics services
- `KnowMapsAdapter`: Maps Visual Intelligence models to Know Maps `ItemMetadata`
- `DiverQueueProcessingService`: Drains the file-based queue on app launch

**Visual Intelligence Pipeline Services:**
- **`LocalPipelineService`**: Core orchestrator — ingestion, enrichment, persistence
- **`MetadataPipelineService`**: Queue item → `LocalInput` conversion, metadata extraction
- **`IntelligenceProcessor`**: On-device LLM prompts for concept extraction and summarization
- **`LocationSearchAggregator`**: Unified Foursquare + MapKit parallel search with merged results
- **Reprocessing**: Items can be reprocessed silently; existing IDs are reused to prevent duplicates
- **Session Sync**: Location edits propagate between `ProcessedItem` and parent `DiverSession`

## Key Implementation Files

### App & UI
- `VisualIntelligencePipelineApp.swift` — App entry point, service initialization
- `View/VisualIntelligenceView.swift` — Camera and capture UI
- `View/SidebarView.swift` — Main navigation sidebar
- `View/ReferenceDetailView.swift` — Item detail view
- `View/CaptureReviewView.swift` — Post-capture review
- `View/EditLocationView.swift` — Item location editing
- `View/EditSessionLocationView.swift` — Bulk session location editing
- `View/SettingsView.swift` — App settings
- `View/ShortcutGalleryView.swift` — Shortcuts discovery

### View Models (DiverKit)
- `ViewModel/VisualIntelligenceViewModel.swift` — Camera, detection, sifting, capture review
- `ViewModel/SidebarViewModel.swift` — Sidebar state, session management, drag-and-drop, library maintenance
- `ViewModel/ReferenceDetailViewModel.swift` — Item detail logic
- `ViewModel/ProcessedItemViewModel.swift` — Individual item reprocessing and deletion

### Core Services (DiverKit)
- `Services/LocalPipelineService.swift` — Core pipeline orchestrator
- `Services/MetadataPipelineService.swift` — Metadata extraction
- `Services/IntelligenceProcessor.swift` — On-device LLM processing
- `Services/LocationSearchAggregator.swift` — Unified location search
- `Services/CameraManager.swift` — AVFoundation camera management
- `Services/SessionClusteringService.swift` — Location/time-based session grouping
- `Services/DailyContextService.swift` — Daily Focus summary generation
- `Services/PhotoLibraryImportService.swift` — Photo/video import from library
- `Services/AestheticsScoringService.swift` — Image quality scoring
- `Services/WeatherEnrichmentService.swift` — WeatherKit integration
- `Services/DuckDuckGoEnrichmentService.swift` — Web enrichment
- `Services/FoursquareEnrichmentService.swift` — Venue enrichment
- `Services/MapKitEnrichmentService.swift` — Apple Maps enrichment
- `Services/AppleMusicEnrichmentService.swift` — Music recognition
- `Services/SpotifyService.swift` — Spotify integration
- `Services/DocumentManager.swift` — Document detection and saving
- `Services/ContactService.swift` — Contact enrichment

### Models (DiverKit)
- `Models/ProcessedItem.swift` — Primary enriched item model
- `Models/DiverSession.swift` — Session grouping model (typealias for `SessionMetadata`)
- `Models/DiverCollection.swift` — User-created collections
- `Models/UserConcept.swift` — Concept/tag model
- `Models/LocalInput.swift` — Raw input before processing

### Storage (DiverKit)
- `Storage/DiverDataStore.swift` — SwiftData container management (single entry point)
- `Storage/UnifiedDataManager.swift` — Wraps DiverDataStore
- `Storage/ReferencePayloadStore.swift` — Compressed JSON blob storage

### App-Level Services (VisualIntelligencePipeline)
- `Services/KnowMapsServiceContainer.swift` — Service dependency injection
- `Services/KnowMapsAdapter.swift` — Model mapping to Know Maps
- `Services/DiverQueueProcessingService.swift` — Queue drain + cache storage
- `Services/SharedWithYouManager.swift` — Shared With You integration

## Testing Strategy

```
VisualIntelligencePipeline/VisualIntelligencePipelineTests/  # App logic, adapters, intents
DiverKit/Tests/DiverKitTests/                                # Package tests
DiverShared/Tests/DiverSharedTests/                          # Queue, link wrapping, validation
```

```bash
# Single test class
swift test --filter LinkWrappingTests

# Single test method
swift test --filter DiverSharedTests.LinkWrappingTests/testWrapURL

# All tests in a module
cd DiverShared && swift test
```

## Common Patterns & Best Practices

### Dependency Injection
Services accept dependencies via constructor:
```swift
MetadataPipelineService(queueStore: queueStore, modelContext: context)
KnowMapsServiceContainer(configuration: config, analyticsService: analytics)
```

### Error Handling
- Use typed errors (e.g., `DiverLinkError`, `APIErrorResponse`)
- Fallback strategies: in-memory SwiftData if CloudKit unavailable
- Safe-mode paths for extensions (lightweight, no heavy ML)

### Main Thread Safety
- Keep long-running pipeline tasks off the main thread
- Use `Task.detached` or background actors for heavy processing
- Provide immediate visual feedback on user actions even when model updates are in progress

### Extension Constraints
- Extensions should only enqueue to `DiverQueueStore` and exit quickly
- Heavy ML/search operations MUST run in main app, not extensions

## Critical Development Rules

1. **NEVER Compromise Data Integrity** — Do NOT rename Core Data entities or perform destructive schema changes without a tested migration plan.
2. **Build Stability is Paramount** — After any refactoring, verify the project builds. When renaming a type, update ALL references immediately.
3. **Stable UI Identifiers** — Use `.id` (UUID) for MapKit results in SwiftUI lists. Use aspect-ratio layouts for images.

## Terminology

- **DiverSession:** Typealias for `SessionMetadata`. Use `DiverSession` in new code.
- **ProcessedItem:** Primary data model for enriched captures and links.
- **SidebarViewModel:** Centralizes sidebar state, session management, drag-and-drop.
- **VisualIntelligenceViewModel:** Manages camera, detection, sifting, and capture review state.

## Additional Resources

- **App Summary:** `Documentation/APP_SUMMARY.md`
- **Beta Notes:** `Documentation/BETA_REVIEW_NOTES.md`
- **Changelog:** `changelog.md`
