Visual Intelligence Pipeline

Visual Intelligence Pipeline is a universal application for iOS and macOS designed for capturing, organizing, and enriching visual intelligence. It leverages on-device computer vision, generative AI, and a multi-stage enrichment pipeline to turn captured moments into structured, actionable data.

## Project Structure

The workspace is organized into modular components:

- **Visual Intelligence (App)**: The main application target (iOS/macOS).
- **DiverKit**: A Swift Package containing the core business logic, services (`LocalPipelineService`, `EnrichmentService`), and ViewModels (`VisualIntelligenceViewModel`).
- **DiverShared**: A library for shared data models, persistence layers (`SwiftData`, `DiverQueueStore`), and utilities used across the App, Extensions, and Widgets.
- **LocalPackages/**: Contains local dependencies such as the YahooSearch SDK wrapper.

## User Experience Walkthrough

### 1. Visual Sifting & Context Capture
The app's primary interface is the **Visual Intelligence View**, accessible via the "Scan for context" button or the floating Camera action.
- **Unified Shutter**: The camera interface uses a custom `AVCaptureSession` bridged to SwiftUI. It performs real-time **subject sifting** (isolating objects) while simultaneously scanning for **QR codes** and **Text**.
- **Photo Library Integration**: Users can tap the photo picker icon to load an image from their library. The app immediately transitions to a "Reviewing" state, running the full `IntelligenceProcessor` on the selected static image just as it would for a live capture.
- **Context Accumulation**: As you capture multiple items in a session, Visual Intelligence aggregates the context (visual labels, location, text) from *all* images to build a richer "Session History".

### 2. Daily Context Narrative
New in this version is the **Daily Context Narrative**, located at the top of the Sidebar.
- **Live Summarization**: As you capture visual context throughout the day, the `DailyContextService` appends these events to a running log.
- **LLM Synthesis**: An on-device LLM (via `ContextQuestionService`) periodically analyzes this log to generate a narrative summary (e.g., *"Morning spent debugging SwiftUI at a coffee shop, followed by researching camera gear."*).
- **Persistence**: This narrative persists for the day, giving users an at-a-glance understanding of their digital footprint.

## Dependencies

This project relies on the following external and open-source libraries. Please refer to their original documentation for detailed usage instructions.

### 1. swift-eventsource
Used to handle Server-Sent Events (SSE) for real-time data streaming within the intelligence pipeline.
- **Source**: [https://github.com/launchdarkly/swift-eventsource](https://github.com/launchdarkly/swift-eventsource)
- **README**: [View README](https://github.com/launchdarkly/swift-eventsource/blob/main/README.md)
- **License**: Apache 2.0

### 2. SpotifyAPI
A Swift library for the Spotify Web API, used for enriching identifying and enriching music-related entities.
- **Source**: [https://github.com/Peter-Schorn/SpotifyAPI](https://github.com/Peter-Schorn/SpotifyAPI)
- **README**: [View README](https://github.com/Peter-Schorn/SpotifyAPI/blob/master/README.md)
- **License**: MIT

### 3. KnowMaps (Service)
The app integrates with the KnowMaps knowledge graph for vector-based context retrieval. This is handled via the `KnowMapsAdapter` within `Visual IntelligenceKit`.

## Building the Project

### Prerequisites
- **Xcode 15+** (Recommended: Xcode 16 beta for iOS 26.0/macOS 15.0 SDK support).
- **Swift 6.0** toolchain.

### installation
1. Clone the repository.
2. Open `VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj`.
3. Xcode will automatically resolve the SPM packages (`DiverKit`, `DiverShared`, `swift-eventsource`, `SpotifyAPI`).
4. Select the **VisualIntelligence** scheme and your target device.
5. Build and Run (`Cmd+R`).

---

# Testing Visual Intelligence

This guide outlines how to verify the functionality of the application, including Visual Intelligence capture, Session Management, and Link Enrichment.

## Setup Instructions

### Home Context Override
To enable accurate "Home" context detection for Location features:
1. Open the iOS Settings app (or Contacts app).
2. Go to your personal Contact Card (usually at the top).
3. Ensure you have an address labeled "Home".
4. In Visual Intelligence Demo, go to Settings.
5. Tap "Set Home Context".
6. Select your Contact Card. Visual Intelligence will now use this address to prioritize Home-related concepts.

## Intelligence Pipeline Architecture

## Apple Intelligence Integration in Visual Intelligence

Visual Intelligence deeply integrates Apple Intelligence to provide a seamless and privacy-preserving user experience. By leveraging on-device models and the latest frameworks, Visual Intelligence ensures that your data stays secure while offering powerful contextual insights.

### Privacy-First Architecture
- **On-Device Data Processing**: All visual sifting, text recognition, and vector embedding generation happen locally ensuring no personal data leaves the device unnecessarily.
- **Private Compute Cloud**: When cloud resources are needed for complex reasoning, Visual Intelligence utilizes the Private Compute Cloud to ensure verifiable privacy without persistent data storage.

### Core Features
- **Smart Summarization**: Automatically generates concise, context-aware summaries of your sessions using the `SystemLanguageModel`, helping you recall content at a glance without scrubbing through details.
- **Intent Recognition**: Analyzes visual and textual context to infer user intent (e.g., "Shopping", "Researching", "Broadcasting") and tags items accordingly.
- **Contextual Writing Integration**: enhancing user editable text fields with Writing Tools for proofreading and rewriting content directly within the application.


Visual Intelligence uses a sophisticated multi-stage intelligence pipeline (`LocalPipelineService`) that combines on-device vision, vector-based knowledge retrieval, and generative AI to enrich captured content.

### 1. Visual Capture & Sifting (Vision + CoreML)
The `VisualIntelligenceViewModel` drives the initial capture experience using advanced Computer Vision in a **two-pass analysis approach**:
-   **Pass 1: Subject Sifting**: Uses `VNGenerateForegroundInstanceMaskRequest` (Vision Framework) to "sift" the primary subject from the background, creating a high-fidelity sticker-like asset.
-   **Pass 2: Semantic Targeting**: Uses the bounds of the sifted subject to focus `VNClassifyImageRequest` (CoreML) specifically on the object. This allows Diver to **semantically label** the sticker (e.g., "Coffee Mug" vs "Table").
-   **Optical Character Recognition (OCR)**: Uses `VNRecognizeTextRequest` (Vision Framework) to extract text from the scene to determine intent.
-   **Rectification**: Automatically detects and rectifies document edges using `VNDetectRectanglesRequest` and `VNInstanceMaskObservation`.

### 2. The KnowMaps Vector Space
Visual Intelligence integrates with **KnowMaps** (1st party Service) to ground visual data in the user's personal knowledge graph.
-   **Context Retrieval**: The `KnowMapsAdapter` retrieves relevant context (`UserTopic`, `IndustryCategory`) based on a weighted vector search.
-   **Concept Boosting**: Concepts with a weight `> 1.2` (e.g., "Coffee", "SwiftUI") are prioritized to bias the AI's understanding of the scene.
-   **Personalized Ranking**: Search results and auto-categorization are influenced by the user's "Taste Profile" stored in the local vector database.

### 3. Parallel Enrichment Pipeline
Once an item is captured, it passes through `LocalPipelineService`, which orchestrates multiple concurrent enrichment providers:
1.  **Link Enrichment (`LinkEnrichmentService`)**: Uses `MetadataExtractor` (1st party) and `swift-eventsource` (3rd party) to fetch OpenGraph metadata and readability-parsed text.
2.  **Place Context (`FoursquareService`)**: Uses the **Foursquare Places API** (3rd party SDK) to identify venues based on GPS and visual text matches.
3.  **Semantic Search (`DuckDuckGoService`)**: Uses the **DuckDuckGo Search API** (3rd party) to enhance place/product data with web knowledge.
4.  **Environmental Context**:
    -   **WeatherKit** (Apple SDK): Captures ambient conditions (e.g., "Sunny, 24°C").
    -   **CoreMotion** (Apple SDK): Logs user activity state (e.g., "Stationary", "Walking").
    -   **CarPlay**: Detects automotive state for mobile context.
5.  **Music Enrichment**: Uses **SpotifyAPI** (3rd party SDK) for identifying and enriching music entities.
6.  **Legacy Search**: Deprecated. (Formerly YahooSearchKit, now replaced by DuckDuckGo).

### 4. Generative Synthesis (Apple Intelligence)
The final stage uses `ContextQuestionService` to synthesize a cohesive narrative using **Apple's SystemLanguageModel** (iOS 26.0+):
-   **Input**: Aggregates Visuals (OCR/Objects) + Location + Vector Context + Environment.
-   **Output**: Generates a structured analysis including:
    -   **Definitive Statements**: "Reading a technical paper." (Visual priority).
    -   **Purpose**: "Researching iOS Development" (Inferred intent).
    -   **Tags**: Auto-generated semantic tags.

### Future CoreML Enhancements
-   **Fine-tuned Gaze Detection**: To support hands-free "Look to Capture" using strict attention metrics.
-   **Local Embedding Models**: Migrating the vector search from the shared `KnowMaps` container to a dedicated `Visual Intelligence` embedding model for tighter privacy.

## Manual Verification Scenarios

### 1. Visual Capture & Hierarchy
**Objective**: Verify that images are captured, processed, and grouped correctly.

1.  **Capture Flow**:
    -   Tap the Visual Intelligence button (Camera icon).
    -   Take a picture (e.g., of a food item or product).
    -   **Verify**: A new Session group appears in the Sidebar.
    -   **Verify**: The item inside shows "Processing..." then updates to "Ready".
    -   **Verify**: The Detail View displays the original photo at the top.
2.  **Re-Capture**:
    -   Tap "Reset/Re-capture".
    -   Take a *different* picture.
    -   **Verify**: A *new* Session group is created. The old session remains if not empty, or handled by logic.
3.  **Hierarchy**:
    -   **Verify**: If the image contains products or recognized web entities, they appear as children nested under the Master item.

4.  **Reference Detail View**:
    -   **Verify**: The Detail View shows a "Web Preview" header for linked content.
    -   **Verify**: Extracted entities (source thumbnails, text) persist even after reprocessing.

### 2. Session Management
**Objective**: Verify organizing, renaming, duplicating, and deleting sessions.

1.  **Session Renaming**:
    -   Open an item in a Session.
    -   Tap one of the blue Semantic Tags (chips) in the Detail View (e.g., "Food", "Technology").
    -   **Verify**: The Session Header in the Sidebar updates to use the tag name (e.g., "Food").
    -   **Verify**: The original timestamp moves to the subtitle position.
2.  **Duplicate Session**:
    -   Long-press (or Right Click) a Session Header.
    -   Select "Duplicate Session".
    -   **Verify**: A new session appears titled "Copy of [Original Name]".
    -   **Verify**: All items are duplicated with their original thumbnails, web previews, and metadata preserved.
3.  **Reprocess Session**:
    -   Long-press (or Right Click) a Session Header.
    -   Select "Reprocess Session".
    -   **Verify**: All items in the session re-enter the "Processing..." state and then return to "Ready".
    -   **Verify**: Existing data is preserved if the new enrichment fails or returns partial data.
4.  **Delete Session**:
    -   Long-press (or Right Click on macOS) a Session Header in the Sidebar.
    -   Select "Delete Session".
    -   **Verify**: The entire session and all its items are removed from the list and database.

### 3. Link Enrichment & QR Codes
**Objective**: Verify that external links and QR codes are processed and interactive.

1.  **QR Code**:
    -   Scan a QR code containing a URL using the camera.
    -   **Verify**: The Detail View displays a `WKWebView` rendering the target page (not just raw text).
2.  **Shared with You**:
    -   Send a link to yourself in Messages.
    -   Open Visual Intelligence.
    -   **Verify**: The link appears in the Sidebar, grouped under a Session.
    -   **Verify**: The Detail View shows a rich preview or WebView of the link.

## Automated Testing

To run the full suite of unit and UI tests for the iOS target, execute the following command in Terminal:

```bash
xcodebuild test -scheme VisualIntelligence -destination 'platform=iOS Simulator,name=iPhone 17'
```

---

## Appendix: Enrichment Data Models

Visual Intelligence's intelligence pipeline produces structured metadata using several key data models. These are used to store and pass context across services.

### Core Model: `EnrichmentData`
Defined in [LinkEnrichmentService.swift](file:///Users/voxels/Documents/dev/VisualIntelligence/VisualIntelligencePipelineDemo/DiverKit/Sources/DiverKit/Services/LinkEnrichmentService.swift). This is the carrier for all enriched metadata.

| Field | Type | Description |
| :--- | :--- | :--- |
| `title` | `String?` | The primary name or heading of the entity. |
| `descriptionText`| `String?` | A summary or abstract description. |
| `image` | `String?` | URL or path to a representative image. |
| `categories` | `[String]` | Classification tags (e.g., "Restaurant", "Song"). |
| `location` | `String?` | Formatted address or place name. |
| `price` | `Double?` | Numeric price if applicable. |
| `rating` | `Double?` | User rating (usually 0.0 - 5.0). |
| `webContext` | `WebContext?` | Metadata specific to web pages. |
| `placeContext` | `PlaceContext?` | Detailed venue information. |
| `documentContext`| `DocumentContext?`| Metadata for files and documents. |
| `qrContext` | `QRCodeContext?` | Data extracted from QR codes. |

### Contextual Models
Defined in [ContextSnapshot.swift](file:///Users/voxels/Documents/dev/VisualIntelligence/VisualIntelligencePipelineDemo/DiverShared/Sources/DiverShared/ContextSnapshot.swift).

#### `WebContext`
| Field | Type | Description |
| :--- | :--- | :--- |
| `siteName` | `String?` | The name of the website (e.g., "Wikipedia"). |
| `faviconURL` | `String?` | URL to the site's icon. |
| `textContent` | `String?` | Extracted readable text content. |
| `structuredData` | `String?` | JSON String of structured data (e.g., Schema.org). |

#### `PlaceContext`
| Field | Type | Description |
| :--- | :--- | :--- |
| `name` | `String?` | Venue name. |
| `address` | `String?` | Full mailing address. |
| `phoneNumber` | `String?` | Contact number. |
| `website` | `String?` | Official URL. |
| `rating` | `Double?` | Venue rating. |
| `photos` | `[String]?` | Array of image URLs. |
| `tips` | `[String]?` | Short user reviews or hints. |

#### `WeatherContext`
| Field | Type | Description |
| :--- | :--- | :--- |
| `condition` | `String` | Description (e.g., "Rainy", "Cloudy"). |
| `temperatureCelsius`| `Double` | Current temperature. |
| `symbolName` | `String` | SF Symbol name for the weather. |

#### `ActivityContext`
| Field | Type | Description |
| :--- | :--- | :--- |
| `type` | `String` | Motion type (e.g., "walking", "automotive"). |
| `confidence` | `String` | confidence level ("high", "medium", "low"). |

### Media Metadata: `MediaMetadata`
Defined in [ProcessedItem.swift](file:///Users/voxels/Documents/dev/VisualIntelligence/VisualIntelligencePipelineDemo/DiverKit/Sources/DiverKit/Models/ProcessedItem.swift).

| Field | Type | Description |
| :--- | :--- | :--- |
| `mediaType` | `String?` | MIME type or category (e.g., "image/jpeg"). |
| `filename` | `String?` | Original filename. |
| `fileSize` | `Int?` | Size in bytes. |
| `transcription` | `String?` | Extracted text or speech-to-text. |
| `themes` | `[String]` | Visual themes identified by AI. |
