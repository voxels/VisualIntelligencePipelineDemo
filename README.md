Visual Intelligence Pipeline

Visual Intelligence Pipeline is a universal application for iOS designed for capturing, organizing, and enriching visual intelligence. It leverages on-device computer vision, generative AI, and a multi-stage enrichment pipeline to turn captured moments into structured, actionable data.

## Project Structure

The workspace is organized into modular components:

- **Visual Intelligence (App)**: The main application target (iOS).
- **DiverKit**: A Swift Package containing the core business logic, services (`LocalPipelineService`, `EnrichmentService`), and ViewModels (`VisualIntelligenceViewModel`).
- **DiverShared**: A library for shared data models, persistence layers (`SwiftData`, `DiverQueueStore`), and utilities used across the App, Extensions, and Widgets.

## User Experience Walkthrough

### 1. Unified Sifting & Capture
The **Visual Intelligence View** is the primary entry point, designed for rapid, context-aware capture.
-   **Smart Shutter**: The camera interface continuously analyzes the scene in real-time.
    -   **Subject Sifting**: Automatically identifies and lifts the primary subject (e.g., a coffee cup, a landmark) from the background, creating a high-fidelity cutout.
    -   **Multi-Modal Capture**: Simultaneously scans for **QR Codes**, **Text**, and **Barcodes** without changing modes.
-   **Photo Library Import**: Users can import photos, which are processed with the same full-fidelity intelligence pipeline as live captures.

### 2. The Enrichment Pipeline
Once an item is captured, it enters a background enrichment queue where multiple services layer context onto the visual data:
-   **Location Precision**: Fuses data from **Apple Maps** to pinpoint the exact venue (e.g., "Blue Bottle Coffee" vs just "5th Avenue").
-   **Environmental Awareness**: Tags the moment with **Weather** (e.g., "Sunny, 20°C").
-   **Semantic Analysis**: Uses on-device models to label objects (e.g., "Espresso", "Laptop") and extract text for indexing.
-   **Aesthetic Scoring**: Evaluates the visual quality of the image to surface the best shots in imported video summaries.

### 3. Review & Organize
The **Review Stack** appears immediately after capture, allowing for quick curation before saving:
-   **The Stack**: Browse through your recent captures in a card-style interface.
-   **Review & Edit**: Tap any item to inspect its lifted subject, read extracted text, or see the initial location guess.
-   **Save to Session**: Commit your captures to a **Session**. Sessions are smart containers that group related moments (e.g., "Afternoon Hike", "Project Research").

### 4. Library & Sidebar
The Sidebar provided a unified home for all your visual intelligence:
-   **Inbox & Sessions**: Recent captures are organized chronologically into Sessions.
-   **Smart Collections**: Create collections to group sessions by topic.
-   **Drag & Drop**: Effortlessly move items unique between sessions, or drag entire sessions into collections for organization.
-   **Favorites**: Pin your most important sessions for quick access.

### 5. Silent Reprocessing & Data Refinement
Your data is never static. Visual Intelligence allows for continuous improvement through both AI updates and manual curation.
-   **Manual Refinement**: You have full control to correct or enhance widely inferred data:
    -   **Location Edit**: Fix incorrect venue matches by searching Apple Maps or pinning a "Home" context.
    -   **Text & Notes**: Edit recognized text or add personal notes that persist alongside the visual data.
-   **Background Reprocessing**: The pipeline can re-run on saved items to apply newer models or deeper analysis.
-   **Non-Destructive Integrity**: Reprocessing is smart—it enhances missing metadata.


## Automated Testing

To run the full suite of unit and UI tests for the iOS target, execute the following command in Terminal:

```bash
xcodebuild test -scheme VisualIntelligence -destination 'platform=iOS Simulator,name=iPhone 17'
```