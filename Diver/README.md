# Testing Diver

This guide outlines how to verify the functionality of the Diver application, including Visual Intelligence capture, Session Management, and Link Enrichment.

## Setup Instructions

### Home Context Override
To enable accurate "Home" context detection for Location features:
1. Open the iOS Settings app (or Contacts app).
2. Go to your personal Contact Card (usually at the top).
3. Ensure you have an address labeled "Home".
4. In Diver, go to Settings.
5. Tap "Set Home Context".
6. Select your Contact Card. Diver will now use this address to prioritize Home-related concepts.

## Intelligence Pipeline Architecture

## Apple Intelligence Integration in Diver

Diver deeply integrates Apple Intelligence to provide a seamless and privacy-preserving user experience. By leveraging on-device models and the latest frameworks, Diver ensures that your data stays secure while offering powerful contextual insights.

### Privacy-First Architecture
- **On-Device Data Processing**: All visual sifting, text recognition, and vector embedding generation happen locally ensuring no personal data leaves the device unnecessarily.
- **Private Compute Cloud**: When cloud resources are needed for complex reasoning, Diver utilizes the Private Compute Cloud to ensure verifiable privacy without persistent data storage.

### Core Features
- **Smart Summarization**: Automatically generates concise, context-aware summaries of your sessions using the `SystemLanguageModel`, helping you recall content at a glance without scrubbing through details.
- **Intent Recognition**: Analyzes visual and textual context to infer user intent (e.g., "Shopping", "Researching", "Broadcasting") and tags items accordingly.
- **Contextual Writing Integration**: enhancing user editable text fields with Writing Tools for proofreading and rewriting content directly within the application.


Diver uses a sophisticated multi-stage intelligence pipeline (`LocalPipelineService`) that combines on-device vision, vector-based knowledge retrieval, and generative AI to enrich captured content.

### 1. Visual Capture & Sifting (CoreML + Vision)
The `VisualIntelligenceViewModel` drives the initial capture experience using advanced Computer Vision:
-   **Subject Lifting**: Uses `VNGenerateForegroundInstanceMaskRequest` to "sift" the primary subject from the background, creating a high-fidelity sticker-like asset.
-   **Optical Character Recognition (OCR)**: Extracts text from the scene to determine intent (e.g., reading a menu vs. looking at a landscape).
-   **Rectification**: Automatically detects and rectifies document edges using `VNInstanceMaskObservation`.

### 2. The KnowMaps Vector Space
Diver integrates with **KnowMaps** to ground visual data in the user's personal knowledge graph.
-   **Context Retrieval**: The `KnowMapsAdapter` retrieves relevant context (`UserTopic`, `IndustryCategory`) based on a weighted vector search.
-   **Concept Boosting**: Concepts with a weight `> 1.2` (e.g., "Coffee", "SwiftUI") are prioritized to bias the AI's understanding of the scene.
-   **Personalized Ranking**: Search results and auto-categorization are influenced by the user's "Taste Profile" stored in the local vector database.

### 3. Parallel Enrichment Pipeline
Once an item is captured, it passes through `LocalPipelineService`, which orchestrates multiple concurrent enrichment providers:
1.  **Link Enrichment**: Fetches OpenGraph metadata and readability-parsed text from URLs.
2.  **Place Context (Foursquare)**: Identifies the venue based on GPS and visual text matches.
3.  **Semantic Search (DuckDuckGo)**: Enhances place/product data with web knowledge.
4.  **Environmental Context**:
    -   **WeatherKit**: Captures ambient conditions (e.g., "Sunny, 24°C").
    -   **CoreMotion**: Logs user activity state (e.g., "Stationary", "Walking").

### 4. Generative Synthesis (Apple Intelligence)
The final stage uses `ContextQuestionService` to synthesize a cohesive narrative using **Apple's SystemLanguageModel** (iOS 26.0+):
-   **Input**: Aggregates Visuals (OCR/Objects) + Location + Vector Context + Environment.
-   **Output**: Generates a structured analysis including:
    -   **Definitive Statements**: "Reading a technical paper." (Visual priority).
    -   **Purpose**: "Researching iOS Development" (Inferred intent).
    -   **Tags**: Auto-generated semantic tags.

### Future CoreML Enhancements
-   **Fine-tuned Gaze Detection**: To support hands-free "Look to Capture" using strict attention metrics.
-   **Local Embedding Models**: Migrating the vector search from the shared `KnowMaps` container to a dedicated `Diver` embedding model for tighter privacy.

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
    -   Open Diver.
    -   **Verify**: The link appears in the Sidebar, grouped under a Session.
    -   **Verify**: The Detail View shows a rich preview or WebView of the link.

## Automated Testing

To run the full suite of unit and UI tests for the iOS target, execute the following command in Terminal:

```bash
xcodebuild test -scheme Diver_iOS -destination 'platform=iOS Simulator,name=iPhone 17'
```
