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

### Pipeline Services

*   **`LocalPipelineService`:** The core orchestrator. Handles ingestion, enrichment, and persistence.
*   **`MetadataPipelineService`:** Converts queue items to `LocalInput` and orchestrates metadata extraction. Uses `Task.detached(priority: .utility)` for all heavy processing.
*   **`IntelligenceProcessor`:** Runs on-device LLM prompts for concept extraction and summarization. Also runs 6 Vision requests (OCR, QR, semantic, document, sifting, aesthetics) in a single pass via `executePipeline`.
*   **`FastVLMEnrichmentService`:** Runs Apple's FastVLM 0.5B model locally via MLX Swift. Image analysis prompt focuses on subject matter (objects, text, activities) and explicitly excludes camera/capture equipment references to prevent hallucinations.
*   **Reprocessing:** Supports silent background reprocessing (`reprocessPipeline`) to update metadata. Reuses existing item IDs to prevent duplicates.
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
*   **Protocols:** Located in `DiverKit/Sources/DiverKit/Protocols/` — `IntelligenceProcessing`, `ContextProcessing`, `AestheticsScoring`, `FastVLMAnalyzing`.
*   **Services:** Located in `DiverKit/Sources/DiverKit/Services/` — 36 services covering camera, enrichment, pipeline, location, and more.
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
    *   Provide immediate visual feedback on user actions even when underlying model updates are still in progress.

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

### Core Services (DiverKit)
*   `Services/LocalPipelineService.swift` — Core pipeline orchestrator
*   `Services/MetadataPipelineService.swift` — Metadata extraction and queue processing
*   `Services/IntelligenceProcessor.swift` — On-device LLM processing
*   `Services/FastVLMEnrichmentService.swift` — FastVLM multimodal image analysis
*   `Services/LocationSearchAggregator.swift` — Unified Foursquare + MapKit search
*   `Services/SessionClusteringService.swift` — Time/location-based session grouping
*   `Services/CameraManager.swift` — AVFoundation camera management
*   `Services/DailyContextService.swift` — Daily focus summary generation
*   `Storage/DiverDataStore.swift` — SwiftData container management

### Models (DiverKit)
*   `Models/ProcessedItem.swift` — Primary enriched item model
*   `Models/DiverSession.swift` — Session grouping model
*   `Models/DiverCollection.swift` — User-created collections
*   `Models/UserConcept.swift` — Concept/tag model
*   `Models/AestheticsTypes.swift` — Image quality scoring types
*   `Models/QueueProgressEvent.swift` — AsyncStream event enum for queue progress delivery

## Code Cleanliness & Known Technical Debt

### Concurrency Patterns (Validated against Apple Docs)
*   **SE-0466 (`defaultIsolation`):** `Task {}` inside `@MainActor` contexts inherits main actor isolation. Always use `Task.detached(priority: .utility)` with explicit `[weak self]` capture lists for ML/Vision/LLM work. Use `await MainActor.run { }` for UI-only property updates.
*   **`LanguageModelSession`:** `final class` with no actor isolation — safe to run from any thread.
*   **`IntelligenceProcessor`:** `Sendable` with no actor isolation — must not be called from `@MainActor` tasks.
*   **Vision framework (iOS 18+):** Native Swift concurrency support — runs naturally on background threads.
*   **`@unchecked Sendable`:** ~20 usages across the codebase. Each must be audited to verify thread safety is enforced via locking (e.g., `OSAllocatedUnfairLock`).
*   **`CaptureInput`:** Marked `@unchecked Sendable` because it contains `PhotosPickerItem` (not `Sendable`). Safe because it's consumed exactly once after crossing the isolation boundary.

### ViewModel Bloat
*   **`VisualIntelligenceViewModel`:** ~2900 lines, 31 properties. Migrated to `@Observable` — per-property tracking eliminates `objectWillChange` over-broadcasting.
*   **`SidebarViewModel`:** ~1200 lines, 22 properties. Migrated to `@Observable`.
*   **`SidebarView`:** 945 lines (decomposed from ~1450; 7 child views extracted to `View/Sidebar/`).

### Service Coupling
*   **`MetadataPipelineService`:** Views directly read mutable progress properties (`isProcessingQueue`, `queueTotalCount`, etc.). AsyncStream-based `progressStream` added alongside for incremental migration to `for await` event delivery.
*   **`Services.shared`:** Global singleton accessed from `@MainActor` context. Accesses from `Task.detached` must use `await MainActor.run { Services.shared.someService }`.
*   **Protocol extraction needed:** `FastVLMEnrichmentService`, `ContextQuestionService`, `AestheticsService`, `IntelligenceProcessor` — extract protocols for testability and dependency injection.

### Performance Debt
*   **Apple's 100ms hang threshold:** Per Apple's "Improving App Responsiveness" guide, any main-thread delay >100ms is noticeable. Less than half that time is available for app work due to event handling and rendering overhead.
*   **No cancellation between pipeline stages:** `LocalPipelineService.process()` chains 6 stages sequentially without `Task.isCancelled` checks.
*   **No `autoreleasepool`** in image processing loops — potential memory pressure during batch operations.
*   **No caching:** Reverse geocoding, CGImage decoding, and link enrichment repeat work on every call.
*   **`sortAndFilter` in views:** O(n log n) computed on every render — should cache results.

### Apple Documentation References (via Cupertino CLI)
*   **`@ModelActor` macro (SwiftData, iOS 17+):** Generates boilerplate for `ModelActor` protocol conformance; creates isolated `ModelContext` for background SwiftData access. Preferred over raw `ModelContext(container)` for actor-based background persistence.
*   **`DefaultSerialModelExecutor` (SwiftData):** Safely performs storage tasks on an isolated model context. Used internally by `@ModelActor`.
*   **`@ObservationIgnored` (Observation framework):** Disables observation tracking for specific properties. Use for caches, debug logs, and internal bookkeeping that shouldn't trigger view updates during `@Observable` migration.
*   **SE-0449 `nonisolated` inference cutoff (Swift 6.1):** Allows `nonisolated` on declarations to prevent global actor inference from protocols/supertypes. Applied when a struct conforming to an `@MainActor` protocol has pure-computation methods that shouldn't require main-thread execution.
*   **SE-0461 Isolation regions:** Defines sending rules between nonisolated, actor-isolated, and `@concurrent` contexts. Governs how values cross isolation boundaries in `Task.detached` closures.

