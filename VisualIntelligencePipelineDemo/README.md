# Visual Intelligence Pipeline

Visual Intelligence Pipeline is an advanced iOS application for capturing, organizing, and enriching visual information. It leverages on-device machine learning, Apple's Vision framework, and Large Language Models to transform captured images and unstructured data into structured, searchable insights.

## Core Features

*   **Visual Intelligence Sifting**: Automatically detects and isolates subjects in images (e.g., products, people, signs) using Vision.
*   **Contextual Enrichment**: Enriches captures with location data (MapKit, Foursquare), weather, and aesthetics scoring.
*   **Semantic Understanding**: Uses LLMs to generate summaries, identify purposes, and suggest relevant context tags.
*   **Session Management**: Groups captures by location and time into cohesive sessions with AI-generated summaries.
*   **Universal Link Organization**: Central repository for shared links and content from across the system.

## Recent Updates (v2.1 - Jan 2026)

*   **Location Persistence**: New pinning mechanism ensures your selected location stays locked across multiple captures.
*   **Intelligent Session Grouping**: Captures at the same location are now automatically grouped into a single session, preventing fragmentation.
*   **MapKit Integration**: Prioritizes Native Apple Maps location names for better accuracy, while seamlessly cross-referencing Foursquare for rich metadata.
*   **Refined UI**: Cleaner interface with a dedicated `SessionLocationBar` and `ContextChipBar` for easier context management.

## Architecture

The project is modularized using Swift Package Manager:
*   `VisualIntelligencePipeline`: Main application target and UI.
*   `DiverKit`: Core logic for machine learning, pipeline orchestration, and services.
*   `DiverShared`: Shared data models and utilities.

## Getting Started

1.  Open `VisualIntelligencePipeline.xcodeproj` in Xcode.
2.  Select the `VisualIntelligencePipeline` scheme.
3.  Run on an iOS Simulator or Device (iOS 26.0+ required for Apple Intelligence).

## Documentation

For deeper dives into specific systems:
*   [Architecture Guide](Diver_Architecture_and_Use_Guide.md)
*   [Machine Learning Strategy](Diver_Machine_Learning_and_Intelligence_Guide.md)
*   [Visual Intelligence Specs](Documentation/VISUAL_INTELLIGENCE.md)
