# GEMINI.md

## Project Overview

This project, **Visual Intelligence Pipeline**, is an iOS application for capturing, organizing, and enriching visual information. It uses on-device machine learning, Apple's Vision framework, and Apple Intelligence (`SystemLanguageModel`) to transform captured images and unstructured data into structured, searchable insights. It also serves as a universal hub for saving and organizing links shared from Safari, TikTok, YouTube, and more.

The project is modularized using Swift Package Manager:

*   `VisualIntelligencePipeline/` — Main application target and UI.
*   `DiverKit/` — Core logic: ML, pipeline orchestration, services, and view models.
*   `DiverShared/` — Pure Swift shared data models and utilities.
*   `LocalPackages/YahooSearch` — Local package for web search enrichment.

**Key Technologies:**

*   **Swift & SwiftUI:** UI and application logic.
*   **SwiftData + CloudKit:** Local-first persistence with cross-device sync.
*   **Vision & CoreML:** Subject detection, sifting, aesthetics scoring, and ML embeddings.
*   **Apple Intelligence:** Uses `SystemLanguageModel` for on-device context generation. Requires **iOS 26.0+**.
*   **MapKit & WeatherKit:** Location enrichment and environmental context.
*   **Foursquare API:** Venue-level location enrichment via `LocationSearchAggregator`.

## Visual Intelligence Features

*   **Intelligent Sifting:** Uses Vision framework to detect subjects in images and "sift" them out from the background with proper alpha channel handling.
*   **Context Enrichment:** Enriches captured items with:
    *   **Location:** Foursquare (Venues) and MapKit (Landmarks/Addresses) via `LocationSearchAggregator`, with user-pinnable persistence.
    *   **Environmental:** WeatherKit (Current conditions).
    *   **Web:** DuckDuckGo enrichments, link metadata extraction, and rich link previews.
    *   **Aesthetics:** Quality scoring for images and video frames.
    *   **Music:** Apple Music and Spotify recognition for music-related captures.
    *   **Documents:** Automatic perspective correction and saving of detected documents.
*   **AI-Powered Understanding:** LLM-generated summaries, purpose identification, concept tagging, and daily focus briefs via `SystemLanguageModel`.
*   **Session Management:** Captures are auto-grouped by location and time into `DiverSession`s with AI-generated summaries.

### Pipeline Services

*   **`LocalPipelineService`:** The core orchestrator. Handles ingestion, enrichment, and persistence.
*   **`MetadataPipelineService`:** Converts queue items to `LocalInput` and orchestrates metadata extraction.
*   **`IntelligenceProcessor`:** Runs on-device LLM prompts for concept extraction and summarization.
*   **Reprocessing:** Supports silent background reprocessing (`reprocessPipeline`) to update metadata. Reuses existing item IDs to prevent duplicates.
*   **Session Sync:** Automatically synchronizes location edits between `ProcessedItem` and its parent `DiverSession`.

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
*   **Services:** Located in `DiverKit/Sources/DiverKit/Services/` — 33+ services covering camera, enrichment, pipeline, location, and more.
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
    *   Keep long-running pipeline tasks off the main thread. Use `Task.detached` or background actors for heavy processing.
    *   Provide immediate visual feedback on user actions even when underlying model updates are still in progress.

## Terminology

*   **DiverSession:** Typealias for `SessionMetadata`. Use `DiverSession` in new code.
*   **ProcessedItem:** The primary data model for enriched captures and links.
*   **SidebarViewModel:** Centralizes sidebar state, session management, drag-and-drop, and library maintenance.
*   **VisualIntelligenceViewModel:** Manages camera, detection, sifting, and capture review state.

## Key Files

### App & UI
*   `VisualIntelligencePipelineApp.swift` — App entry point, service initialization
*   `View/VisualIntelligenceView.swift` — Camera and capture UI
*   `View/SidebarView.swift` — Main navigation sidebar
*   `View/ReferenceDetailView.swift` — Item detail view
*   `View/CaptureReviewView.swift` — Post-capture review
*   `View/EditLocationView.swift` — Location editing

### Core Services (DiverKit)
*   `Services/LocalPipelineService.swift` — Core pipeline orchestrator
*   `Services/MetadataPipelineService.swift` — Metadata extraction
*   `Services/IntelligenceProcessor.swift` — On-device LLM processing
*   `Services/LocationSearchAggregator.swift` — Unified Foursquare + MapKit search
*   `Services/CameraManager.swift` — AVFoundation camera management
*   `Storage/DiverDataStore.swift` — SwiftData container management

### Models (DiverKit)
*   `Models/ProcessedItem.swift` — Primary enriched item model
*   `Models/DiverSession.swift` — Session grouping model
*   `Models/DiverCollection.swift` — User-created collections
*   `Models/UserConcept.swift` — Concept/tag model
