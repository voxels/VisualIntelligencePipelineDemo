# Visual Intelligence Pipeline

**Visual Intelligence Pipeline** transforms the way you capture, organize, and understand the world around you. It combines real-time camera intelligence, rich contextual enrichment, AI-powered semantic understanding, and **ethical commerce intelligence** into a single, elegant multi-platform experience. It also serves as a universal hub for saving and organizing links shared from Safari, TikTok, YouTube, and any app with a share sheet.

Point your camera at anything — a product on a shelf, a restaurant sign, a document, a landmark — and Visual Intelligence instantly identifies it, enriches it with contextual metadata, scores it across ethical and economic dimensions, and organizes it into an intelligent, searchable library. An optional **M-series Mac edge node** on your home network offloads heavy ML inference for faster processing and larger models.

## Core Features

### Intelligent Sifting
Uses Apple's Vision framework (`VNGenerateForegroundInstanceMaskRequest`) to automatically detect and isolate subjects in captures. Subjects are "sifted" out from the background, producing clean cutouts with proper alpha channels — ready for sharing or further analysis. A real-time glow overlay highlights detected subjects during the camera preview.

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
Captures are automatically grouped by location and time into cohesive **sessions** with AI-generated summaries. Multiple captures at the same venue merge into a single session history. Sessions support bulk location editing, context resumption, and reprocessing. Session summaries leverage the full metadata of every item — transcription, themes, tags, categories, location, web/document/QR context, FastVLM analysis, product metadata, and more.

### Lifecycle-Safe Reprocessing
The **Reprocess Pipeline** (Settings → Reprocess Pipeline) handles app termination mid-run gracefully. It uses a 3-phase durable design: **Phase 1** marks items `.queued` in SwiftData before any processing begins (crash-safe checkpoint). **Phase 2** processes each item via the unified `processItemByID` path. **Phase 3** regenerates session summaries. Interrupted pipelines resume automatically on next foreground. CloudKit multi-device **freshness guard** prevents two devices from redundantly reprocessing the same items.

### Library Maintenance
A built-in **Rebuild Library** tool (Settings > Rebuild Library) repairs orphaned items, recovers stuck processing states, consolidates fragmented sessions, reconciles relationships, and regenerates all session summaries — with live progress status.

### Context Tags, Daily Focus & Agentic Chat
Add custom context tags (e.g., "Gift for Mom," "Home renovation ideas") to any capture. A **Daily Focus** summary aggregates the day's activity into an AI-generated brief. You can also chat directly with your library via an built-in **Agentic Chat** interface powered by the FastVLM/SLM system.

### Commerce Intelligence
Products detected via barcode or visual classification are automatically scored across **7 strategies simultaneously**: Ethics (ESG + 10 sub-dimensions), Brand Fit, Value, Durability, Social Proof, Health Fit, and Total Cost of Ownership. Score data from free, open databases (Open Food Facts, Climate TRACE, gov APIs) — no paid API keys required.

- **Score History** — Swift Charts visualize how product scores, prices, and your preference profile evolve over time via `ScoreSnapshot` time-series.
- **Preference Learning** — `PreferenceLearner` derives per-strategy weights from your owned product history. Products you share with friends get 1.5× endorsement weight.
- **"I Own This" / "I Want This"** — Track products across ownership states: owned, wishlisted, considering, or returned. All states feed the preference model.
- **SLM Advisory** — On-device Apple Intelligence generates Buy Now / Wait / Neutral timing recommendations using enriched product context.
- **Government Safety** — Parallel checks against CPSC recalls, FDA enforcement alerts, EPA compliance, and Energy Star certification.
- **Price Nowcasting** — World Bank commodity prices + BLS Producer Price Index → Dynamic Factor Model (Accelerate vDSP) projects price trajectory with confidence intervals.
- **Ethical Affiliate Routing** — Ranks 5 commerce platforms (Thrive, Target, Amazon, Best Buy, eBay) by carbon, labor, and certification policies.

### Edge Computing & Load Balancing (Home Network ML Offloading)
Any device on your home network can offload ML inference to a more powerful M-series Mac or iPad via **Swift Distributed Actors** over Bonjour. The new `CapabilityRouter` evaluates devices across your network based on RAM, Neural Engine TOPS, and network speed. It then dynamically **load balances** heavy inference—such as FastVLM 7B encoding or SAM 2.1 video segmentation—across multiple Apple devices simultaneously, keeping your iPhone completely responsive.

- **Automatic discovery** — Bonjour-based (`_visualintel._tcp`) with TLS 1.3 transport
- **Transparent fallback** — If no edge node is reachable, all inference runs locally on-device
- **macOS Edge Daemon** — Standalone menu-bar app with dashboard showing connected clients, model status, inference throughput, and data cache health
- **ML-Sharp Bridge** — On-demand 3D Gaussian Splat generation: image sent to EdgeDaemon, `enhance.py` executed via Foundation `Process()`, `.usdz` returned and saved to `ProcessedItem`
- **EdgeDaemon safety** — `APIKeyService` skips CloudKit initialization in EdgeDaemon process (no entitlement), silencing runtime warnings

### Universal Link Organization & Deep Linking
Save links from Safari, YouTube, TikTok, or any app via the Share Sheet extension. Links are wrapped in a proprietary format (HMAC-signed, tamper-proof URLs via `DiverLinkWrapper`) and processed through the enrichment pipeline for automatic metadata extraction. The app supports both Universal Links (`https://secretatomics.com/...`) and custom scheme links (`secretatomics://...`) for deep linking. Shared links appear in Apple's **Shared with You** section via `SharedWithYouManager`.

### Siri, Shortcuts & Widgets
Fully integrated with Apple's system — 6 App Intents (Save, Share, Search, Get Recent, Open, Ask CLaRa), pre-built shortcut templates, and Home & Lock screen widgets.

## Architecture

The project is modularized using Swift Package Manager:

| Module | Purpose |
|--------|---------|
| `VisualIntelligencePipeline/` | Main application target and UI |
| `DiverKit/` | Core logic — ML pipeline, 67 services, 18 protocols, view models, models, storage |
| `DiverShared/` | Pure Swift shared data models and utilities |
| `ActionExtension/` | Share Sheet extension for link ingestion |
| `VisualIntelligencePipelineWidget/` | Home & Lock screen widgets |
| `VisualIntelligenceEdge/` | macOS edge node daemon (menu bar app) |

**Key Technologies:** Swift, SwiftUI, SwiftData + CloudKit, Vision, Foundation Models, MLX Swift, MapKit, Swift Charts, Swift Distributed Actors, Network framework

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
│  (7 VNRequests in a single pass)    │
│  OCR · QR · Semantic · Document     │
│  Sifting · Aesthetics · Saliency    │
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
┌─────────────────────────────────────┐
│  Stage 5: Commerce Intelligence     │
│  7 scoring strategies + ESG         │
│  enrichment + preference learning   │
│  + SLM advisory (Buy/Wait/Neutral)  │
└──────────────┬──────────────────────┘
               │
               ▼
         ProcessedItem
      (SwiftData + CloudKit)
```

---

### Stage 1: Vision Analysis — `IntelligenceProcessor`

Runs 7 Apple Vision requests in a **single pass** on the captured image:

| Request | Output | Maps To |
|---|---|---|
| `VNGenerateForegroundInstanceMaskRequest` | Foreground mask | `.siftedSubject` → peel/glow overlay |
| `VNDetectBarcodesRequest` | QR codes, UPC/EAN | `.qr` / `.product` → child items |
| `VNRecognizeTextRequest` (.accurate) | OCR text | `.text` → full-text search |
| `VNClassifyImageRequest` | Semantic labels | `.semantic` → style tags |
| `VNDetectDocumentSegmentationRequest` | Document rect | `.document` → rectified child item |
| `VNCalculateImageAestheticsScoresRequest` | Quality score | `.aesthetics` → stored on `ProcessedItem` |
| `VNGenerateAttentionBasedSaliencyImageRequest` | Saliency heatmap | `.saliency` → salient region data |

**Two modes:**
- **`liveSifting`** — Sifting request only (real-time camera preview)
- **`fullAnalysis`** — All 7 requests (after save)

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

- **Model tiers** (device-dependent):
  - **iPhone/iPad (on-device):** `mlx-community/FastVLM-0.5B-bf16` (~500MB, downloaded on-demand)
  - **M-series Edge Node (offloaded):** FastVLM 3B+ via MLX Swift (~2GB, managed by Edge Model Manager)
  - **Fallback:** On-device 0.5B when no edge node available
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
- **Output:** Structured `ContextAnalysis` (via `@Generable` macro, defined inline in `ContextQuestionService.swift`):
  - `summary` — concise activity summary
  - `visualStatements` + `locationStatements` — evidence-based statements
  - `purpose` — user intent
  - `tags` — descriptive labels
- **Commerce output:** Separate `@Generable` types in `CommerceGenerable.swift`: `AdvisorySignalOutput` (timing), `StrategyScoreSummary` (multi-engine), `ProductInsight`
- **Context chaining:** If input exceeds 3,500 chars, buffers and chains summaries to stay within token limits
- **Fallback:** Returns `descriptionText` if SystemLanguageModel unavailable (< iOS 26)

**Service:** `DiverKit/Services/ContextQuestionService.swift` (conforms to `ContextProcessing` protocol)

---

### Stage 5: Aesthetics & Scoring — `AestheticsScoringService`

Scores image quality for thumbnail selection and context weighting. As of v1.1, the primary aesthetics score is computed inside the `IntelligenceProcessor` Vision pass (Stage 1) — a single `handler.perform()` request alongside OCR, QR, and semantic analysis.

- **Primary:** `VNCalculateImageAestheticsScoresRequest` (bundled into Stage 1 Vision pass)
- **Secondary metrics:** Brightness (luminance deviation from 0.5), Contrast (luminance std dev), Sharpness (edge detection)
- **Planned:** Saliency analysis (`VNGenerateAttentionBasedSaliencyImageRequest`) for subject importance weighting and smart crop suggestions
- **Video support:** `AestheticsScoringService` samples up to 100 frames, scores each, deduplicates via `VNFeaturePrintObservation` similarity, returns top N diverse frames
- **Output:** `aestheticsScore` (0.0–1.0) stored on `ProcessedItem` via `IntelligenceResult.aesthetics`

**Service:** `DiverKit/Services/AestheticsScoringService.swift` (conforms to `AestheticsScoring` protocol)

---

### Pipeline Orchestration

`LocalPipelineService` orchestrates all stages using a **fast Two-Phase Pipeline**:

**Phase 1: Capture Fast Path (Instantaneous)**
1. **Ingest** — `DiverQueueItem` enters the processing queue
2. **Metadata** — `MetadataPipelineService` extracts EXIF, GPS, file metadata
3. **Vision** — `IntelligenceProcessor.performRequests()` runs Stage 1 (OCR, QR, semantic, document, sifting, aesthetics)
4. **Enrichment** — Location, web, music services populate `PipelineContext`
5. **QR Enrichment** — QR URLs discovered in Stage 1 get full web enrichment (title, summary, metadata)
6. **Save & Show** — Item is saved to SwiftData with `.captured` status and instantly appears in the sidebar.

**Phase 2: Heavy Intelligence (Background)**
7. **FastVLM** — If enabled, `FastVLMEnrichmentService.analyze()` adds multimodal context
8. **Commerce** — `performCommerceEnrichment()` runs 8-step pipeline (classification, scoring, ESG, recommendations)
9. **LLM** — `ContextQuestionService.processContext()` generates summary, tags, purpose (Edge CLaRa if available)
10. **Persist & Group** — Status updates to `.enriched`, item auto-grouped into `SessionMetadata` by location+time proximity

**Service:** `DiverKit/Services/LocalPipelineService.swift`

> **Protocol-based DI:** `LocalPipelineService` and `MetadataPipelineService` accept `(any ContextProcessing)?` and `(any FastVLMAnalyzing)?` for testability. All 7 ML/commerce service protocols are defined in `DiverKit/Protocols/`.

> **Edge routing:** When an edge node is available on the local network, stages 2–5 and 7 can be transparently offloaded via Swift Distributed Actors. Fallback to on-device is automatic.

## Getting Started

1. Open `VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj` in Xcode.
2. Select the `VisualIntelligencePipeline` scheme.
3. Run on an iOS Simulator or Device (iOS 26.0+ required for Apple Intelligence).

## Testing

**250+ tests** across 41 test files (177+ XCTest + 73+ Swift Testing `@Test`).

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

### Current Coverage

| Area | Test Files | Tests | Status |
|------|-----------|-------|--------|
| Pipeline & Orchestration | 5 | 26 | ✅ |
| Architecture / Concurrency | 2 | 34 | ✅ |
| Models & Data | 5 | 36+ | ✅ |
| Enrichment & Services | 8 | 30+ | ✅ |
| Commerce Intelligence | 5 | 58 | ✅ |
| Edge Computing | 1 | 5 | ✅ |
| ViewModels | 3 | 27 | ✅ |
| Performance | 2 | 24 | ⚠️ 3 flaky |

### Future Test Plans

**Priority 1 — Data integrity & sync** (highest risk if untested):

| Service | Test Focus |
|---------|-----------|
| `CloudKitSyncMonitor` | Event parsing, error detection, notification posting, edge cases (nil userInfo) |
| `PersistenceActor` | Actor isolation, concurrent fetch safety, modelContext lifecycle |
| `DiverSchemaMigration` | V1 model list matches DiverDataStore.coreTypes |
| `APIKeyService` | CloudKit store/retrieve roundtrip, cache invalidation, prefetch, no-network fallback |

**Priority 2 — Enrichment services** (critical pipeline path):

| Service | Test Focus |
|---------|-----------|
| `FastVLMEnrichmentService` | Prompt construction, result parsing, hallucination guard (no camera terms) |
| `ESGEnrichmentService` | 4-database cascade (Food → Beauty → Pet → Products), 24h cache, barcode lookup |
| `ProductRecommendationService` | Composite scoring, SLM prompt construction, timing recommendation logic |
| `LocationService` / `ReverseGeocodingService` | EXIF priority, contact detection, user-pinned persistence |
| `DailyContextService` | Daily summary aggregation, session filtering, LLM prompt construction |

**Priority 3 — Camera & import** (hardware-dependent, harder to mock):

| Service | Test Focus |
|---------|-----------|
| `CameraManager` | Session configuration, orientation handling, photo output delegate |
| `PhotoLibraryImportService` | Asset loading, EXIF extraction, batch import |
| `DocumentManager` | Perspective correction, save path, file cleanup |

**Priority 4 — Network enrichment** (requires mock HTTP):

| Service | Test Focus |
|---------|-----------|
| `FoursquareEnrichmentService` | URL construction, response parsing, no-API-key graceful degradation |
| `MapKitEnrichmentService` | Search result mapping, coordinate handling |
| `OpenESGService` | B Corp directory parsing, company-level ESG mapping |
| `PricingDataService` | World Bank + BLS PPI response parsing, commodity mapping |
| `SpotifyService` | Track matching, metadata extraction |
| `WeatherEnrichmentService` | Weather data parsing, context snapshot creation |

**Priority 5 — Edge & transport** (requires multi-process test harness):

| Service | Test Focus |
|---------|-----------|
| `VisualIntelligenceActorSystem` | Actor registration, message routing |
| `BonjourDiscoveryService` | Service publishing, peer discovery, TXT record parsing |
| `NWTransportLayer` | TLS 1.3 handshake, length-prefixed framing, reconnection |

**Known Flaky Tests** — `PipelinePerformanceTests`: 3 cache/geocoding tests timeout at 5 seconds. Consider increasing timeout to 10s for CI environments.

See the [Test Documentation Wiki](VisualIntelligencePipelineDemo/Documentation/wiki/diverkit-tests.html) for detailed per-file coverage.

## Future Plans (Spec v3)

| Feature | Description | Blocker |
|---------|-------------|---------|
| **Financial Integration** | Apple Wallet transactions via FinanceKit + Plaid bank accounts → budget-aware purchase decisions, spending charts, budget alerts | FinanceKit managed entitlement from Apple |

See the full [Spec v3 Roadmap](VisualIntelligencePipelineDemo/Documentation/spec_v3_roadmap.md) for details.

## Documentation

- [App Summary](VisualIntelligencePipelineDemo/Documentation/APP_SUMMARY.md)
- [Architecture Analysis](VisualIntelligencePipelineDemo/Documentation/analysis.md)
- [Beta Review Notes](VisualIntelligencePipelineDemo/Documentation/BETA_REVIEW_NOTES.md)
- [Spec v3 Roadmap](VisualIntelligencePipelineDemo/Documentation/spec_v3_roadmap.md)
- [Privacy Policy](PRIVACY.md)
- [Changelog](VisualIntelligencePipelineDemo/changelog.md)

## Copyright

2026 Secret Atomics