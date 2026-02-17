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

```bash
# Build for iOS Simulator
xcodebuild -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme VisualIntelligencePipeline \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run DiverKit package tests
cd DiverKit && swift test

# Run DiverShared package tests
cd DiverShared && swift test
```

## Development Conventions

*   **SwiftUI:** Views are organized in `VisualIntelligencePipeline/VisualIntelligencePipeline/View/`.
*   **View Models:** Located in `DiverKit/Sources/DiverKit/ViewModel/` — `VisualIntelligenceViewModel`, `SidebarViewModel`, `ReferenceDetailViewModel`, `ProcessedItemViewModel`.
*   **Services:** Located in `DiverKit/Sources/DiverKit/Services/` — 36 services covering camera, enrichment, pipeline, location, and more.
*   **Swift Packages:** Shared code modularized into `DiverKit` and `DiverShared`.
*   **Asynchronous Operations:** Uses `async/await` throughout for network requests, ML inference, and file I/O.
*   **Dependency Injection:** Services like `KnowMapsServiceContainer` and `DiverQueueProcessingService` are injected at initialization.

## Critical Development Rules (Read Carefully)

1.  **NEVER Compromise Data Integrity:**
    *   **Schema Changes:** Do **NOT** rename Core Data entities (e.g., `SessionMetadata`) or perform destructive schema changes without a fully tested migration plan.
    *   **Recovery:** Prioritize recovery mechanisms over wiping data.

2.  **Build Stability is Paramount:**
    *   After *any* refactoring (especially renaming types), verify the project builds.
    *   When renaming a type, ensure **ALL** references across the codebase are updated immediately.

3.  **Dependency Management (KnowMaps):**
    *   Local Swift Package dependencies can resolve to stale commits. If you encounter "inaccessible due to 'internal' protection level" errors, it is likely a stale dependency cache.
    *   Runtime reflection (using `Mirror`) is an acceptable *temporary* workaround when documented.

4.  **UI & MapKit Stability:**
    *   Use `.id` (UUID) rather than `placeID` for identifying MapKit results in SwiftUI lists.
    *   Use aspect-ratio based layouts for images instead of fixed dimensions.

5.  **Main Thread Safety:**
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
*   `View/SidebarView.swift` — Main navigation sidebar
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
