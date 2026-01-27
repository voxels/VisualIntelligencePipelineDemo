# Diver: Visual Intelligence Pipeline Architecture & Guide

## 1. Executive Summary

**Diver** is a universal iOS and macOS application designed to act as a "second brain" for visual and digital content. It allows users to capture images, videos, and links from various sources (Safari, TikTok, Real World Camera), automatically organizing and enriching them with rich context.

The core differentiator is its **Visual Intelligence Pipeline**, which uses on-device computer vision to "sift" subjects from their background, recognizes text and objects, and then aggregates environmental data (Location, Weather, Activity) to understand user intent using Generative AI.

## 2. System Architecture

The project is built using a modular **Swift Package Manager (SPM)** architecture to ensure separation of concerns and testability.

### Module Hierarchy

1.  **`VisualIntelligencePipeline` (App Target)**
    *   **Role**: The main application layer containing all UI (SwiftUI), ViewModels, and OS-specific integrations (Camera, Widgets).
    *   **Key Responsibilities**: User Interaction, Navigation, Camera Feed Management, Location Editing.

2.  **`DiverKit` (Service Layer)**
    *   **Role**: The "Business Logic" framework. It contains the heavy lifting for Data Processing, Networking, Authentication, and Intelligence Services.
    *   **Key Responsibilities**:
        *   `LocalPipelineService`: Orchestrates the ingestion and enrichment flow.
        *   `IntelligenceProcessor`: Wraps Vision Framework for image analysis.
        *   `ContextQuestionService`: Interface for LLM/Generative AI.
    *   **Dependencies**: Depends on `DiverShared`.

3.  **`DiverShared` (Core Layer)**
    *   **Role**: The foundation layer containing pure Swift data models and shared utilities.
    *   **Key Components**:
        *   `DiverItemDescriptor`: The universal data transfer object.
        *   `DiverQueueStore`: File-based queue for Inter-Process Communication (App <-> Extensions).

## 3. The Visual Intelligence Pipeline

The pipeline describes the journey of an item from capture to storage. It is "Pull-Based," meaning the system actively pulls context based on the input.

### Step 1: Ingestion (Capture)
*   **Source**: Camera, Share Sheet, or Photo Library.
*   **Vision Processing**: The image is analyzed immediately to detect:
    *   **Subject Sifting**: Segments the main foreground subject (e.g., a coffee cup).
    *   **OCR**: Extracts text from signs, menus, or documents.
    *   **Classification**: Identifies objects (e.g., "Espresso", "Laptop").

### Step 2: Enrichment (Parallelized)
Once ingested, the `LocalPipelineService` triggers parallel enrichment tasks:
*   **Location**: MapKit identifies the native venue/address (Primary); Foursquare is cross-referenced for rich context (Secondary).
*   **Environment**: WeatherKit provides current conditions; CoreMotion provides activity (e.g., "Walking").
*   **Web**: If a URL is detected (via QR or OCR), it is scraped for metadata.

### Step 3: Synthesis (Generative AI)
All aggregated data is fed into an **On-Device LLM** (`ContextQuestionService`).
*   **Input**: "Image contains 'Latte', Location is 'Starbucks', Time is 9 AM, Weather is Raining."
*   **Output**:
    *   **Title**: "Morning Coffee at Starbucks"
    *   **Intent**: "working remotely" or "grabbing breakfast"
    *   **Summary**: "User is drinking a latte while working on a laptop at a coffee shop on a rainy morning."

### Step 4: Persistence
*   **Storage**: Data is saved to `SwiftData` (local database) and synced via **CloudKit**.
*   **Search**: Vector embeddings are generated for the item to enable semantic search (e.g., searching for "cozy vibes" finds this item).

## 4. Artificial Intelligence & Core ML Strategy

Diver uses a Hybrid AI approach, combining deterministic Computer Vision with probabilistic Generative AI.

### A. Vision Layer (The "Eyes")
**Class**: `IntelligenceProcessor`
*   **Framework**: Apple `Vision` Framework.
*   **Key Algorithms**:
    *   `VNGenerateForegroundInstanceMaskRequest`: For subject isolation.
    *   `VNRecognizeTextRequest`: For high-accuracy OCR.
    *   `VNDetectBarcodesRequest`: For QR/Barcode handling with RTL support.
*   **Smart ROI**: If a subject is detected, the system calculates a specific Region of Interest (ROI) and focuses subsequent requests (OCR, Classification) specifically on that area for higher accuracy.

### B. Semantic Layer (The "Memory")
**Service**: Know Maps Integration
*   **Model**: BERT-based `MiniLM` (Core ML).
*   **Function**: Converts text and concepts into vector embeddings. This allows the system to understand that "Latte" is related to "Coffee" and "Breakfast" without explicit tagging.

### C. Generative Layer (The "Brain")
**Service**: `ContextQuestionService`
*   **Model**: `SystemLanguageModel` (Apple Intelligence / Foundation Models).
*   **Function**:
    *   **Summarization**: Condenses logs and metadata into human-readable text.
    *   **Reasoning**: Infers user intent (e.g., distinguishing between "Buying a camera" vs "Taking a photo of a camera").
    *   **Sanitization**: Rules-based logic removes hallucinations (e.g., stopping the AI from guessing "Home" location when unknown).

## 5. Data Flow & Synchronization

### Queue-Based IPC
To handle data reliably between the lightweight App Extensions (Share Sheet) and the heavy Main App:
1.  Extension writes a JSON file to a shared App Group container (`DiverQueueStore`).
2.  Main App listens for file changes or checks on launch.
3.  `DiverQueueProcessingService` functions as a "garbage collector," processing files one by one into the database.

### Local-First Sync
*   **Primary Truth**: Local `SwiftData` store.
*   **Sync**: CloudKit mirrors the local store.
*   **Reprocessing**: Diver supports "Time Travel" reprocessing. If the user edits a location or the AI implementation improves, items can be "re-run" through the pipeline to update their metadata without losing the original capture asset.
