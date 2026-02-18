# Visual Intelligence Pipeline

**Visual Intelligence Pipeline** transforms the way you capture, organize, and understand the world around you. It combines real-time camera intelligence, rich contextual enrichment, and AI-powered semantic understanding into a single, elegant iOS experience. It also serves as a universal hub for saving and organizing links shared from Safari, TikTok, YouTube, and any app with a share sheet.

Point your camera at anything — a product on a shelf, a restaurant sign, a document, a landmark — and Visual Intelligence instantly identifies it, enriches it with contextual metadata, and organizes it into an intelligent, searchable library.

## Core Features

### Intelligent Sifting
Uses Apple's Vision framework (`VNGeneratePersonInstanceMaskRequest`) to automatically detect and isolate subjects in captures. Subjects are "sifted" out from the background, producing clean cutouts with proper alpha channels — ready for sharing or further analysis. A real-time glow overlay highlights detected subjects during the camera preview.

### Deep Contextual Enrichment
Every capture is automatically enriched with layers of real-world context:
- **Location** — Apple MapKit reverse geocoding and contact detection (Home, friends), with user-pinnable persistence and bidirectional session sync. Foursquare available in editing UI for manual venue searches.
- **Web Intelligence** — Link metadata extraction and rich link previews for web URLs and QR codes.
- **Aesthetics Scoring** — Image quality scores using `VNCalculateImageAestheticsScoresRequest` plus brightness, contrast, and sharpness analysis.
- **Document Detection** — Automatic perspective correction via `VNDetectDocumentSegmentationRequest` and saving of detected documents as separate child items.
- **Music Recognition** — Apple Music and Spotify identification for music-related captures.

### AI-Powered Understanding
On-device Apple Intelligence (`FoundationModels.LanguageModelSession`) generates summaries, identifies purposes, and suggests intelligent concept tags via `ContextQuestionService`. LLM prompts are enriched with weather, location, OCR text, and structured web data for deeply contextual results — all processed locally for maximum privacy. An optional **FastVLM** vision-language model (Apple FastVLM 0.5B via MLX Swift) adds multimodal image understanding.

### Smart Sessions
Captures are automatically grouped by location and time into cohesive **sessions** with AI-generated summaries. Multiple captures at the same venue merge into a single session history. Sessions support bulk location editing, context resumption, and reprocessing. Session summaries leverage the full metadata of every item — transcription, themes, tags, categories, location, weather, web/document/QR context, FastVLM analysis, product metadata, and more.

### Library Maintenance
A built-in **Rebuild Library** tool (Settings > Rebuild Library) repairs orphaned items, recovers stuck processing states, consolidates fragmented sessions, reconciles relationships, and regenerates all session summaries — with live progress status.

### Context Tags & Daily Focus
Add custom context tags (e.g., "Gift for Mom," "Home renovation ideas") to any capture. A **Daily Focus** summary aggregates the day's activity into an AI-generated brief.

### Universal Link Organization & Deep Linking
Save links from Safari, YouTube, TikTok, or any app via the Share Sheet extension. Links are wrapped in a proprietary format (HMAC-signed, tamper-proof URLs via `DiverLinkWrapper`) and processed through the enrichment pipeline for automatic metadata extraction. The app supports both Universal Links (`https://secretatomics.com/...`) and custom scheme links (`secretatomics://...`) for deep linking. Shared links appear in Apple's **Shared with You** section via `SharedWithYouManager`.

### Siri, Shortcuts & Widgets
Fully integrated with Apple's system — 5 App Intents (Save, Share, Search, Get Recent, Open), pre-built shortcut templates, and Home & Lock screen widgets.

## Architecture

The project is modularized using Swift Package Manager:

| Module | Purpose |
|--------|---------|
| `VisualIntelligencePipeline/` | Main application target and UI |
| `DiverKit/` | Core logic — ML pipeline, 36 services, 4 protocols, view models, models, storage |
| `DiverShared/` | Pure Swift shared data models and utilities |
| `ActionExtension/` | Share Sheet extension for link ingestion |
| `VisualIntelligencePipelineWidget/` | Home & Lock screen widgets |

**Key Technologies:** Swift, SwiftUI, SwiftData + CloudKit, Vision, Foundation Models, MLX Swift, MapKit

## Machine Learning Pipeline Architecture

### Pipeline Overview

Every capture flows through a multi-stage ML pipeline that transforms raw pixels into structured, searchable knowledge. All inference runs **on-device** — nothing leaves the phone.

```
Camera Frame
    │
    ▼
┌─────────────────────────────────────┐
│  Stage 1: Vision Analysis           │
│  IntelligenceProcessor              │
│  (6 VNRequests in a single pass)    │
│  OCR · QR · Semantic · Document     │
│  Sifting · Aesthetics Scoring       │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Stage 2: Contextual Enrichment     │
│  Location · Weather · Web · Music   │
│  → PipelineContext (structured)     │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Stage 3: FastVLM (Opt-In)          │
│  Apple FastVLM 0.5B via MLX Swift   │
│  Multimodal image understanding     │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Stage 4: LLM Summarization         │
│  Apple Intelligence                 │
│  (SystemLanguageModel / Foundation  │
│   Models, iOS 26+)                  │
└──────────────┬──────────────────────┘
               │
               ▼
         ProcessedItem
      (SwiftData + CloudKit)
```

---

### Stage 1: Vision Analysis — `IntelligenceProcessor`

Runs 6 Apple Vision requests in a **single pass** on the captured image:

| Request | Output | Maps To |
|---|---|---|
| `VNGeneratePersonInstanceMaskRequest` | Foreground mask | `.siftedSubject` → peel/glow overlay |
| `VNDetectBarcodesRequest` | QR codes, UPC/EAN | `.qr` / `.product` → child items |
| `VNRecognizeTextRequest` (.accurate) | OCR text | `.text` → full-text search |
| `VNClassifyImageRequest` | Semantic labels | `.semantic` → style tags |
| `VNDetectDocumentSegmentationRequest` | Document rect | `.document` → rectified child item |
| `VNCalculateImageAestheticsScoresRequest` | Quality score | `.aesthetics` → stored on `ProcessedItem` |

**Two modes:**
- **`liveSifting`** — Sifting request only (real-time camera preview)
- **`fullAnalysis`** — All 5 requests (after save)

**Service:** `DiverKit/Services/IntelligenceProcessor.swift` (conforms to `IntelligenceProcessing` protocol)

---

### Stage 2: Contextual Enrichment — `PipelineContext`

Each enrichment service populates a typed field on `PipelineContext`. Downstream consumers (FastVLM, SystemLanguageModel) read structured data rather than parsing text.

| Field | Source Service | Data |
|---|---|---|
| `ocrText` | Vision (Stage 1) | Recognized text |
| `visualTags` | Vision (Stage 1) | Classification labels |
| `placeEnrichment` | `MapKitEnrichmentService` | Reverse geocoding + contact detection |
| `linkEnrichment` | `LinkEnrichmentService` | Web page metadata |
| `qrURLs` | Vision (Stage 1) | Detected QR code URLs |

**Service:** `DiverKit/Services/PipelineContext.swift`

---

### Stage 3: FastVLM — `FastVLMEnrichmentService`

An **opt-in** multimodal vision-language model running locally via [MLX Swift](https://github.com/ml-explore/mlx-swift).

- **Model:** `mlx-community/FastVLM-0.5B-bf16` (~500MB, downloaded on-demand)
- **Two-pass analysis:**
  1. **Image analysis** — VLM describes the image content (objects, text, activities)
  2. **Context synthesis** — VLM reads `PipelineContext.enrichmentContextString` + transcription to generate structured output
- **Output:** `FastVLMAnalysis` struct with `imageDescription`, `contextSummary`, `suggestedTitle`, `suggestedPurpose`, `suggestedTags`, `statements`
- **Memory management:** Monitors `DispatchSource.makeMemoryPressureSource` and unloads model under memory pressure

**Service:** `DiverKit/Services/FastVLMEnrichmentService.swift` (conforms to `FastVLMAnalyzing` protocol)

---

### Stage 4: LLM Summarization — `ContextQuestionService`

Uses Apple Intelligence (`FoundationModels.LanguageModelSession`) for on-device structured generation.

- **Input:** `EnrichmentData` with all context (title, OCR, location, weather, place, web, document, QR, knowledge graph)
- **Output:** Structured `ContextAnalysis` (via `@Generable` macro):
  - `summary` — concise activity summary
  - `visualStatements` + `locationStatements` — evidence-based statements
  - `purpose` — user intent
  - `tags` — descriptive labels
- **Context chaining:** If input exceeds 3,500 chars, buffers and chains summaries to stay within token limits
- **Fallback:** Returns `descriptionText` if SystemLanguageModel unavailable (< iOS 26)

**Service:** `DiverKit/Services/ContextQuestionService.swift` (conforms to `ContextProcessing` protocol)

---

### Stage 5: Aesthetics & Scoring — `AestheticsScoringService`

Scores image quality for thumbnail selection and context weighting. As of v1.1, the primary aesthetics score is computed inside the `IntelligenceProcessor` Vision pass (Stage 1) — a single `handler.perform()` request alongside OCR, QR, and semantic analysis.

- **Primary:** `VNCalculateImageAestheticsScoresRequest` (bundled into Stage 1 Vision pass)
- **Secondary metrics:** Brightness (luminance deviation from 0.5), Contrast (luminance std dev), Sharpness (edge detection)
- **Video support:** `AestheticsScoringService` samples up to 100 frames, scores each, deduplicates via `VNFeaturePrintObservation` similarity, returns top N diverse frames
- **Output:** `aestheticsScore` (0.0–1.0) stored on `ProcessedItem` via `IntelligenceResult.aesthetics`

**Service:** `DiverKit/Services/AestheticsScoringService.swift` (conforms to `AestheticsScoring` protocol)

---

### Pipeline Orchestration

`LocalPipelineService` orchestrates all stages:

1. **Ingest** — `DiverQueueItem` enters the processing queue
2. **Metadata** — `MetadataPipelineService` extracts EXIF, GPS, file metadata
3. **Vision** — `IntelligenceProcessor.performRequests()` runs Stage 1 (OCR, QR, semantic, document, sifting, aesthetics)
4. **Enrichment** — Location, web, music services populate `PipelineContext`
5. **QR Enrichment** — QR URLs discovered in Stage 1 get full web enrichment (title, summary, metadata)
6. **FastVLM** — If enabled, `FastVLMEnrichmentService.analyze()` adds multimodal context
7. **LLM** — `ContextQuestionService.processContext()` generates summary, tags, purpose
8. **Persist** — All results written to `ProcessedItem` (SwiftData) and synced via CloudKit
9. **Session** — Item auto-grouped into `DiverSession` by location+time proximity

**Service:** `DiverKit/Services/LocalPipelineService.swift`

> **Protocol-based DI:** `LocalPipelineService` and `MetadataPipelineService` accept `(any ContextProcessing)?` and `(any FastVLMAnalyzing)?` for testability. All 4 ML service protocols are defined in `DiverKit/Protocols/ServiceProtocols.swift`.

## Getting Started

1. Open `VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj` in Xcode.
2. Select the `VisualIntelligencePipeline` scheme.
3. Run on an iOS Simulator or Device (iOS 26.0+ required for Apple Intelligence).

## Testing

```bash
# Build for iOS Simulator
xcodebuild -project VisualIntelligencePipelineDemo/VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme VisualIntelligencePipeline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run DiverKit unit tests (requires iOS Simulator — UIKit dependency)
xcodebuild test -project VisualIntelligencePipelineDemo/VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme DiverTests_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run DiverShared package tests (pure Swift, no UIKit)
cd VisualIntelligencePipelineDemo/DiverShared && swift test
```

## Documentation

- [App Summary](VisualIntelligencePipelineDemo/Documentation/APP_SUMMARY.md)
- [Architecture Analysis](VisualIntelligencePipelineDemo/Documentation/analysis.md)
- [Beta Review Notes](VisualIntelligencePipelineDemo/Documentation/BETA_REVIEW_NOTES.md)
- [Changelog](VisualIntelligencePipelineDemo/changelog.md)

## Copyright

2026 Secret Atomics