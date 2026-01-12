# GEMINI.md

## Project Overview

This project, named "Diver," is a universal application for iOS and macOS designed for saving and organizing links from various applications like Safari, TikTok, YouTube, and more. It acts as a central repository for shared content, automatically extracting metadata like titles, descriptions, and thumbnails.

The project is structured as a multi-repository setup, with the main application in the `Diver` directory, and shared components in `DiverKit` and `DiverShared` Swift Packages.

**Key Technologies:**

*   **Swift & SwiftUI:** The application is built using modern Swift and SwiftUI for the user interface.
*   **Swift Package Manager:** Dependencies and project modules are managed using Swift Package Manager.
*   **knowmaps:** The application appears to use a cloud service called "KnowMaps" for storing and caching the shared links.
*   **XCTest:** The project includes a suite of unit and UI tests.
*   **Apple Intelligence:** Uses `SystemLanguageModel` for on-device context generation. Requires **iOS 26.0+**.

**Architecture:**

1.  **VisualIntelligencePipeline (Main Application):** The main application target, containing the UI and the application's entry point.
2.  **DiverShared (Swift Package):** This package contains the shared data models, such as `DiverQueueItem` and `DiverItemDescriptor`, and the `DiverQueueStore` for persisting shared links to the filesystem.
3.  **DiverKit (Swift Package):** This package provides authentication, networking, and other shared utilities for communicating with backend services, including what appears to be a "KnowMaps" API.
4.  **VisualIntelligencePipeline (Demo App):** A standalone harness for testing the Visual Intelligence features (Camera, Sifting, Reprocessing) in isolation.
5.  **Queue-based Processing:** The app uses a file-based queue to reliably process shared links. The `DiverQueueProcessingService` picks up items from the queue and stores them in the `KnowMapsCacheStore`.

## Visual Intelligence Features

The project includes a sophisticated "Visual Intelligence" capability:

*   **Intelligent Sifting:** Uses Vision framework to detect subjects in images and "sift" them out from the background.
*   **Context Enrichment:** Enriches captured items with:
    *   **Location:** Foursquare (Venues) and MapKit (Landmarks/Addresses) via `LocationSearchAggregator`.
    *   **Environmental:** WeatherKit (Current conditions) and CoreMotion (Activity type).
    *   **Web:** Metadata extraction for related links.
*   **Pipeline Services:**
    *   **LocalPipelineService:** The core orchestrator. Handles ingestion, enrichment, and persistence.
    *   **Reprocessing:** Supports silent background reprocessing of items (`reprocessPipeline`) to update metadata or apply new algorithms. Includes logic to **prevent duplicates** by reusing existing item IDs.
    *   **Session Sync:** Automatically synchronizes location edits between `ProcessedItem` and its parent `DiverSession`.

## Building and Running

This is a standard Xcode project. To build and run the application:

1.  **Open the project in Xcode:**
    ```bash
    open VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj
    ```
2.  **Select a target:** Choose the "VisualIntelligencePipeline" scheme.
3.  **Run the application:** Click the "Run" button in Xcode or press `Cmd+R`.

### Testing

To run the tests:

1.  **Open the project in Xcode.**
2.  **Select a test scheme:** Choose the "DiverTests" or "DiverUITests" scheme.
3.  **Run the tests:** Press `Cmd+U`.

Alternatively, you can run the tests from the command line using `xcodebuild`:

```bash
xcodebuild -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj -scheme VisualIntelligencePipeline -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Development Conventions

*   **SwiftUI:** The UI is built with SwiftUI, and views are organized in the `VisualIntelligencePipeline/VisualIntelligencePipeline/View` directory.
*   **Swift Packages:** Shared code is modularized into Swift Packages (`DiverKit`, `DiverShared`).
*   **Asynchronous Operations:** The app uses `async/await` for asynchronous operations, especially for network requests and file I/O.
*   **Dependency Injection:** Services like `KnowMapsServiceContainer` and `DiverQueueProcessingService` are initialized and passed to the relevant components.

## Critical Development Rules (Read Carefully)

The following rules have been established based on past incidents and must be followed strictly:

1.  **NEVER Compromise Data Integrity:**
    *   **Schema Changes:** Do **NOT** rename Core Data entities (e.g., `SessionMetadata`) or perform destructive schema changes without a fully tested migration plan. The user's data is sacred. "Data loss" incidents are unacceptable.
    *   **Recovery:** If widespread data inaccessibility occurs due to schema issues, prioritize implementing recovery mechanisms (like `regenerateMissingSessions`) over wiping data.

2.  **Build Stability is Paramount:**
    *   **Check Your Work:** After *any* refactoring (especially renaming types), you **MUST** verify that the project builds. Do not leave the user with a broken build state.
    *   **Reference Consistency:** When renaming a type (e.g., `SessionMetadata` to `DiverSession`), ensure **ALL** references across the codebase (Views, ViewModels, Services) are updated immediately. A partial rename is a broken build.

3.  **Dependency Management (KnowMaps):**
    *   **Staleness:** Be aware that local Swift Package dependencies (like `knowmaps`) can resolve to stale commits. If you encounter "inaccessible due to 'internal' protection level" errors for properties that *should* be public, it is likely a stale dependency cache.
    *   **Workarounds:** While clean fixes are preferred, runtime reflection (using `Mirror`) is an acceptable *temporary* workaround to bypass strict access control/staleness issues to get the feature working immediately, provided it is documented.

## Terminology Updates

*   **DiverSession:** The entity previously known as `SessionMetadata` is now referred to as `DiverSession` in the codebase.
    *   **Technical Note:** For data compatibility and CloudKit sync reasons, the underlying class is still named `SessionMetadata`, but `DiverSession` is provided as a global typealias. Continue to use `DiverSession` in new code.

