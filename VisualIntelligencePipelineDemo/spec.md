# Visual Intelligence Pipeline — Project Specification

> **Version:** 2.0  
> **Last Updated:** 2026-02-19  
> **Platforms:** iOS 26.0+, iPadOS 26.0+, macOS 26.0+ (edge node), visionOS 26.3+ (future)  
> **Bundle ID:** `com.secretatomics.VisualIntelligencePipeline`

---

## 1. Product Vision

Visual Intelligence Pipeline transforms the iPhone camera into an intelligence layer for everyday life. Point your camera at anything — a product, a sign, a document, a landmark — and the app instantly identifies it, enriches it with contextual metadata, and organizes it into a searchable personal knowledge base.

Beyond the camera, it serves as a universal hub for saving and organizing links shared from Safari, TikTok, YouTube, iMessage, and any app with a share sheet.

### 1.1 Core Value Propositions

1. **Capture → Enrich → Understand** — A single tap triggers a multi-stage pipeline that sifts subjects from backgrounds, enriches captures with location/web/music/document context, and generates AI summaries.
2. **Local-First Intelligence** — All ML inference runs on-device by default: Apple Vision framework, Apple Intelligence (Foundation Models), and FastVLM 0.5B via MLX Swift. No data leaves the device for processing unless routed to a user-owned edge node on the home network.
3. **Universal Link Organization** — Links from any source are wrapped in tamper-proof HMAC-signed URLs, processed through the same enrichment pipeline, and surfaced alongside visual captures.
4. **Cross-Device Sync** — SwiftData + CloudKit provides seamless, automatic sync across all devices.
5. **Ethical Commerce Intelligence** — When viewing a physical product, the system surfaces real-time ESG sustainability data, pricing nowcasts, and a commerce CTA filtered by the user's ethical preferences. Advisory-only — the user always confirms.
6. **Home Network ML Offloading** — Any device on the local network can transparently offload heavy ML inference (Vision analysis, SLM, FastVLM, object detection, nowcasting) to the most powerful available device via Swift distributed actors. Falls back to on-device processing when no edge node is reachable.

---

## 2. Architecture Overview

### 2.1 Module Structure

```
VisualIntelligencePipelineDemo/
├── VisualIntelligencePipeline/     # Main app target — UI, App Intents, Widgets
├── DiverKit/                       # Core logic package — Services, Models, ViewModels
├── DiverShared/                    # Pure Swift shared data models & utilities
├── VisualIntelligencePipelineWidget/  # Home & Lock screen widgets
└── VisualIntelligencePipelineTests/   # Test target
```

| Module | Responsibility | Key Contents |
|--------|---------------|--------------|
| **VisualIntelligencePipeline** | App entry point, UI layer, App Intents | 30 SwiftUI views, 7 app services, 14 App Intent definitions |
| **DiverKit** | Business logic, ML pipelines, persistence | 36 services, 4 service protocols, 4 view models, 14 models, 56 API schemas, storage layer |
| **DiverShared** | Cross-target shared types | `AppGroupConfig`, `QueueStore`, `LinkWrapping`, `IntelligenceCapability`, `ContextSnapshot` |

**Future targets** (Ethical Commerce phases):
| Target | Platform | Role |
|--------|----------|------|
| **VisualIntelligenceEdge** | macOS (M-series) | Edge node daemon — hosts distributed actors for ML offloading, ESG/commerce enrichment |
| **VisualIntelligenceVision** | visionOS | AR client — spatial HUD with product overlays, RealityKit rendering |

### 2.2 Multi-Platform & Edge Computing

The system distributes work across Apple Silicon devices on the home network based on computational capability:

| Device | Chip | Neural Engine | Role |
|--------|------|--------------|------|
| **Mac edge node** | M4+ | 16-core, **38 TOPS** | Heavy ML inference, nowcasting, LLM reasoning, ESG/commerce enrichment |
| **iPad edge node** | M5+ | TBD (~40+ TOPS expected) | Same as Mac when available; also a client |
| **Vision Pro** | M2 + R1 | M2: ~15.8 TOPS; R1: sensor fusion (12ms) | ARKit tracking, HUD rendering, lightweight on-device classification |
| **iPhone** | A18+ | 16-core NE | Primary client — on-device inference when no edge node available |

**Why offload:**
- M4's 38 TOPS Neural Engine has ~2.4× the throughput of M2/A18, with no competition from foreground UI or OS intelligence
- Mac supports larger memory (up to 128GB unified on M4 Max) for hosting 3B+ LLM models via MLX Swift — the iPhone's FastVLM 0.5B can be upgraded to a larger model transparently
- Offloading preserves client battery life and UI responsiveness

**Transport: Swift Distributed Actors**

Communication uses the `Distributed` framework (iOS 16+ / macOS 13+, SE-0336, SE-0344):

- **Discovery:** `NWBrowser` / `NWListener` (Network framework) with Bonjour service type `_visualintel._tcp`
- **Serialization:** `Codable`-based envelope encoding (Apple's TicTacFish `WebSocketActorSystem` pattern)
- **Connection:** `NWConnection` (TLS 1.3, LAN-only)

```
┌──────────────────────┐
│  iPhone / iPad       │           ┌────────────────────────────┐
│  (iOS/iPadOS Client) │◀────────▶│  Mac / iPad Edge Node      │
├──────────────────────┤  Bonjour  │  (macOS/iPadOS Service)    │
│  Camera / ARKit      │  + NW    ├────────────────────────────┤
│  Lightweight CoreML  │  Framework│  distributed actor:        │
│  Distributed Actor   │  (LAN)   │    InferenceService        │
│    Client (resolver) │           │    NowcastingService       │
└──────────────────────┘           │    CommerceService         │
                                   │                            │
┌──────────────────────┐           │  CoreML YOLO/DETR (NE)     │
│  Apple Vision Pro    │◀────────▶│  MLX Swift LLM (~3B)       │
│  (visionOS Client)   │  Bonjour  │  Nowcasting Engine (Swift) │
├──────────────────────┤           └────────────┬───────────────┘
│  ARKit Object Track  │                        │ HTTPS
│  RealityKit HUD      │           ┌────────────▼───────────────┐
│  Barcode Detection   │           │  External APIs             │
└──────────────────────┘           │  (ESG, Pricing, Commerce,  │
                                   │   Plaid, FinanceKit)       │
                                   └────────────────────────────┘
```

**Key distributed actor interface:**

```swift
import Distributed

distributed actor InferenceService {
    typealias ActorSystem = VisualIntelligenceActorSystem

    distributed func analyzeVisual(imageData: Data) async throws -> VisionAnalysisResult
    distributed func analyzeLLM(imageData: Data, context: PipelineContext) async throws -> LLMAnalysisResult
    distributed func classify(frameData: Data, boundingBox: CGRect) async throws -> ProductClassification
    distributed func nowcast(commodityID: String) async throws -> PriceTrajectory
    distributed func enrichESG(productID: String) async throws -> ESGEnrichment?
}
```

### 2.3 Concurrency Model

| Context | Mechanism | Usage |
|---------|-----------|-------|
| Pipeline processing | `@PipelineActor` (custom global actor) | `LocalPipelineService`, heavy enrichment tasks |
| Heavy computation | `Task.detached(priority: .utility)` | ML inference, image analysis, metadata extraction |
| Background SwiftData | `ModelContext(container)` with `autosaveEnabled = false` | All pipeline/enrichment SwiftData access |
| UI updates | `@MainActor` | View models, published properties |
| Progress reporting | `AsyncStream` (SE-0314) | Queue progress, pipeline status events |
| Edge node transport | `distributed actor` (SE-0336) via `VisualIntelligenceActorSystem` | ML offloading, ESG/commerce enrichment over LAN |

#### Threading Rules (Apple Documentation Validated)

> **Critical Rule:** Never use `Task { }` in SwiftUI handlers (`onAppear`, `onChange`, `onReceive`) or inside `@MainActor`-annotated types for pipeline work — it inherits `@MainActor` isolation (SE-0466). Always use `Task.detached(priority: .utility)` with explicit capture lists.

**Actor isolation inheritance (SE-0466, Swift 6.2):**
- `Task { }` inside an `@MainActor` class/method → inherits `@MainActor` isolation
- `Task.detached { }` → runs on the cooperative thread pool, no actor isolation inherited
- Inner `Task { }` inside an outer `Task { @MainActor }` → also inherits `@MainActor`

**ML service threading (confirmed via Apple docs):**
- `LanguageModelSession` (Foundation Models) — `final class`, no actor isolation. Pure `async/await`. Safe to call from any thread.
- `VisionRequest` (Vision, iOS 18+) — Swift concurrency native. Designed for background execution.
- `IntelligenceProcessor` — `Sendable`, no actor annotation. Can run on any thread.
- `FastVLMEnrichmentService` — MLX Swift inference. No `@MainActor` requirement.
- `distributed actor InferenceService` — runs on edge node; calls are `async throws` and cross the network boundary transparently.

**Use `@MainActor` only for:**
- Updating `@Published` / `@Observable` properties that drive SwiftUI views
- Accessing UIKit/AppKit objects that require main thread
- Brief hops via `await MainActor.run { ... }` for 1–2 property assignments

### 2.4 Data Flow

The pipeline is **sequential** — each stage feeds its output into `PipelineContext`. When an edge node is available on the home network, stages ②–⑤ can be routed to the remote `InferenceService` transparently.

```
┌──────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│  Camera /     │    │  MetadataPipeline │    │  LocalPipeline      │
│  Share Sheet  │───▶│  Service          │───▶│  Service            │
│  / Import     │    │  (Queue → Input)  │    │  (Orchestrator)     │
└──────────────┘    └──────────────────┘    └─────────────────────┘
                                                      │
                                              ┌───────▼────────┐
                                              │  Edge Decision  │  NWBrowser check:
                                              │  (Bonjour)      │  edge node available?
                                              └──┬──────────┬──┘
                                          LOCAL  │          │  REMOTE
                                                 ▼          ▼
                                          ┌───────────────────────┐
                                     ①    │  Location Resolution   │  Pinned → EXIF → GPS
                                          │  + Geocoding           │  → Session fallback
                                          └──────┬────────────────┘
                                                 ▼
                                          ┌───────────────────────┐
                                     ②    │  Vision Framework      │  OCR, QR, visual tags,
                                          │  (6 requests)          │  sifting, aesthetics,
                                          │  [local OR edge]       │  document detection
                                          └──────┬────────────────┘
                                                 ▼
                                    ┌────────────┼────────────────┐
                               ③    ▼                              ▼   (parallel)
                            ┌──────────┐                     ┌──────────┐
                            │ Link     │                     │ Cover    │
                            │ Metadata │                     │ Image    │
                            └────┬─────┘                     └────┬─────┘
                                 └──────────────┬─────────────────┘
                                                ▼
                                         ┌───────────────┐
                                    ④    │  SLM           │  @Generable structured
                                         │  (Foundation   │  extraction: summary,
                                         │   Models)      │  intent, tags
                                         │  [local OR     │
                                         │   edge]        │
                                         └──────┬────────┘
                                                ▼
                                         ┌───────────────┐
                                    ⑤    │  FastVLM       │  Multimodal synthesis
                                         │  (MLX Swift)   │  (0.5B local / 3B+ edge)
                                         │  [local OR     │
                                         │   edge]        │
                                         └──────┬────────┘
                                                ▼
                                         ┌───────────────┐
                                    ⑥    │  Session       │  Cluster, merge,
                                         │  Assignment    │  generate summary
                                         └──────┬────────┘
                                                ▼
                                         ┌───────────────┐
                                    ⑦    │  ESG / Commerce│  Product classification,
                                         │  Enrichment    │  carbon scoring, nowcast,
                                         │  (opt-in,      │  purchase options
                                         │   edge only)   │
                                         └──────┬────────┘
                                                ▼
                                         ┌───────────────┐
                                         │  SwiftData     │
                                         │  + CloudKit    │
                                         └───────────────┘
```

---

## 3. Data Model

All models are SwiftData `@Model` classes synced via CloudKit.

### 3.1 ProcessedItem

The primary data entity for all enriched captures and links.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID primary key |
| `inputId` | `String?` | Original input identifier |
| `url` | `String?` | Source URL (web link, QR code, deep link) |
| `title` | `String?` | AI-generated or extracted title |
| `summary` | `String?` | AI-generated summary |
| `entityType` | `String?` | Classified entity type |
| `modality` | `String?` | Input modality (photo, video, link, document) |
| `tags` | `[String]` | AI-generated descriptive tags |
| `categories` | `[String]` | Classification categories |
| `latitude` / `longitude` | `Double?` | Geo-coordinates |
| `location` | `String?` | Lat,lon string for geo-coordinates (display/search) |
| `placeID` | `String?` | MapKit place identifier |
| `sessionID` | `String?` | Parent session link |
| `masterCaptureID` | `String?` | Links sibling captures (photo + QR + document from same session) |
| `purposes` | `[String]` | User-assigned context tags |
| `rawPayload` | `Data?` | Original capture image data (external storage) |
| `depthPayload` | `Data?` | LiDAR/TrueDepth depth map data (external storage) |
| `transcription` | `String?` | OCR text or video transcription |
| `visualTags` | `[String]` | Vision-derived semantic classification tags |
| `aestheticsScore` | `Float?` | Vision-computed quality score |
| `processingStatus` | `String` | Current pipeline state (`queued`, `processing`, `completed`, `failed`) |
| `processingLog` | `[String]` | Timestamped processing events |
| `failureCount` | `Int` | Retry tracking |

**Relationships:**
- `parentItem` / `childItems` — Purpose-based parent-child hierarchy
- `session` → `SessionMetadata` — Session membership

**Context Data:** Encoded as `Data?` blobs with computed property accessors:
- `weatherContext`, `activityContext`, `placeContext`, `webContext`, `documentContext`, `qrContext`, `fastVLMAnalysis`
- `esgContext`, `commerceContext`, `financialContext` *(Ethical Commerce — populated when edge node enrichment runs)*

### 3.2 SessionMetadata

Groups captures by location and time.

| Field | Type | Description |
|-------|------|-------------|
| `sessionID` | `String` | UUID primary key |
| `title` | `String?` | AI-generated or location-based title |
| `summary` | `String?` | Aggregated AI summary of all items |
| `latitude` / `longitude` | `Double?` | Session location |
| `placeID` | `String?` | MapKit place identifier |
| `locationName` | `String?` | Display location name |
| `collectionID` | `String?` | Parent collection link |
| `thumbnailPaths` | `[String]` | Aesthetics-scored thumbnails |
| `isFavorite` | `Bool` | User favorite status |

**Relationships:**
- `items` → `[ProcessedItem]` (cascade delete)
- `parentCollection` → `SessionCollection`

### 3.3 SessionCollection

User-created or auto-imported album groupings.

| Field | Type | Description |
|-------|------|-------------|
| `collectionID` | `String` | UUID primary key |
| `name` | `String` | Collection name |
| `userSummary` | `String?` | User-written summary |
| `llmSummary` | `String?` | Auto-generated LLM summary |
| `sessionIDs` | `[String]` | Ordered session references |
| `sourceAlbumName` | `String?` | Photos library origin |
| `coverImagePath` | `String?` | Display cover image |

**Relationships:**
- `sessions` → `[SessionMetadata]` (nullify on delete)

### 3.4 UserConcept

Semantic concepts extracted from user activity.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `String` | Concept label |
| `definition` | `String` | Concept definition |
| `anchorEmbedding` | `[Double]?` | Vector embedding for similarity |
| `weight` | `Double` | Relevance weight (incremented on reoccurrence) |

### 3.5 PipelineContext

In-memory structured context aggregated during pipeline processing. Not persisted directly — individual fields are saved to `ProcessedItem` context data blobs.

**Vision fields:** `ocrText`, `visualTags`, `identifiedMedia`, `documentContent`, `qrPayloads`, `visualAnalysisLog`

**Enrichment fields:** `linkEnrichment`, `placeEnrichment`, `duckDuckGoEnrichment`, `weatherContext`, `activityContext`, `liveEventContext`, `productConcepts`

**ML fields:** `fastVLMAnalysis`, `knowledgeGraphContext` (weighted entries)

**Commerce fields** *(populated by edge node enrichment)*:
- `productClassification` — Barcode/visual → product entity resolution
- `esgEnrichment` — Carbon data, data quality tier, certifications
- `priceTrajectory` — 14-day nowcast with confidence interval
- `purchaseOptions` — Ethically-filtered commerce options with affiliate links
- `financialSnapshot` — Budget/transaction context from FinanceKit + Plaid

Provides three serialization outputs:
- `asContextString` — Full context for SystemLanguageModel
- `enrichmentContextString` — Priority-ordered, truncated context for FastVLM
- `commerceContextString` — ESG + pricing + financial context for advisory engine

### 3.6 Commerce & Finance Types

These types support the Ethical Commerce pipeline and are shared between client and edge node via `Codable` + `Sendable`.

```swift
struct ProductClassification: Codable, Sendable {
    let productID: String
    let name: String
    let category: String
    let barcode: String?
    let confidence: Float
}

struct ESGEnrichment: Codable, Sendable {
    let carbonIntensity: Float?      // kg CO₂e per revenue unit
    let dataQualityTier: Int         // 1 (verified) – 5 (sector average)
    let certifications: [String]     // ["Carbon Trust", "EPD"]
    let source: String               // "Climate TRACE", "Open Food Facts"
    let retrievedAt: Date
}

struct PurchaseOption: Codable, Sendable {
    let platform: String             // "amazon", "ebay", "thrive_market"
    let price: Decimal
    let currency: String
    let carbonScore: Float?
    let certifications: [String]
    let affiliateURL: URL
    let ethicalMatch: EthicalMatch   // .full, .partial, .none
}

struct FinancialSnapshot: Codable, Sendable {
    let monthlySpendToDate: Decimal
    let monthlyBudgetRemaining: Decimal?
    let recentTransactions: [RecentTransaction]
    let averageCategorySpend: Decimal?
}
```

---

## 4. Pipeline Services

### 4.1 Core Orchestration

| Service | File | Responsibility |
|---------|------|----------------|
| **LocalPipelineService** | `LocalPipelineService.swift` (135KB) | Master orchestrator — ingestion, enrichment coordination, persistence, session management, reprocessing, library maintenance. Routes stages to edge node when available. |
| **MetadataPipelineService** | `MetadataPipelineService.swift` (47KB) | Converts queue items → `LocalInput`, dispatches metadata extraction tasks via `Task.detached` |
| **PipelineContext** | `PipelineContext.swift` | Typed context struct aggregated across enrichment stages |
| **PipelineActor** | `PipelineActor.swift` | Custom `@globalActor` for pipeline isolation |

### 4.2 ML & Intelligence

| Service | Isolation | Responsibility |
|---------|-----------|---------------|
| **IntelligenceProcessor** | `Sendable`, no actor | Runs 6 Vision requests in a single `executePipeline` pass (OCR, QR, semantic classification, document detection, subject sifting, aesthetics scoring). Also drives on-device LLM for concept extraction and summarization. **Must run off `@MainActor`.** |
| **FastVLMEnrichmentService** | `@unchecked Sendable` | Apple FastVLM 0.5B via MLX Swift. Single-pass grounded analysis: image + Vision tags + enrichment context → structured output. ~500MB on-demand download, memory-pressure eviction. On edge node: can run 3B+ models. **Must run off `@MainActor`.** |
| **ContextQuestionService** | No actor isolation | Apple Foundation Models (`LanguageModelSession`) structured generation via `@Generable` macro. `LanguageModelSession` is a `final class` with no actor annotation — pure `async/await`. **Must run off `@MainActor`.** |
| **FoundationModelsIntentClassifier** | No actor isolation | LLM-based intent classification for incoming items. |
| **AestheticsScoringService** | `@unchecked Sendable` | Wraps `VNCalculateImageAestheticsScoresRequest` (Vision, iOS 18+). Vision requests support Swift concurrency natively. **Must run off `@MainActor`.** |

### 4.3 Location & Places

| Service | Responsibility |
|---------|---------------|
| **LocationService** | CLLocationManager wrapper for GPS coordinates |
| **ReverseGeocodingService** | MapKit reverse geocoding with landmark/address resolution |
| **MapKitEnrichmentService** | MapKit place search with contact detection (Home, friends) |
| **LocationSearchAggregator** | MapKit search for location editing UI |
| **ContactService** | Contacts framework integration for address matching |
| **SessionClusteringService** | Time/location-based session grouping with proximity thresholds (5s/50m for consolidation, 30-min creation window) |

### 4.4 Web & Link Enrichment

| Service | Responsibility |
|---------|---------------|
| **LinkEnrichmentService** | URL metadata extraction (title, summary, image) |
| **WebViewLinkEnrichmentService** | WKWebView-based link metadata extraction for dynamic pages |
| **DuckDuckGoEnrichmentService** | DuckDuckGo search for QR code URL context |
| **DiverLinkGenerator** | HMAC-signed tamper-proof URL wrapping |

### 4.5 Media & Music

| Service | Responsibility |
|---------|---------------|
| **CameraManager** | AVFoundation camera management (preview, capture, orientation) |
| **PhotosAssetLoader** | Photos framework import with EXIF extraction; on-demand PHAsset loading, thumbnails, and best-frame selection for video |
| **DocumentManager** | Document detection, perspective correction, and file management |
| **AppleMusicEnrichmentService** | Apple Music catalog matching |
| **SpotifyService** | Spotify API track/album matching |

### 4.6 Other Services

| Service | Responsibility |
|---------|---------------|
| **DailyContextService** | "Today's Focus" daily summary generation |

### 4.7 Edge Node Services (Distributed Actors)

> [!NOTE]
> These services run on the Mac/iPad edge node and are accessed by clients via `VisualIntelligenceActorSystem`. See §2.2 for transport details. All require `import Distributed`.

| Service | Type | Responsibility |
|---------|------|---------------|
| **InferenceService** | `distributed actor` | Routes Vision analysis, SLM, and FastVLM inference to edge node Neural Engine. Runs CoreML YOLO/DETR for product detection. |
| **NowcastingService** | `distributed actor` | Dynamic Factor Model (DFM) via Accelerate framework (BLAS/LAPACK). Produces 14-day price trajectory projections from public commodity price APIs. |
| **CommerceService** | `distributed actor` | Matches products to purchase options filtered by user's ethical policy and platform preferences. Generates affiliate deep links. |
| **ESGEnrichmentService** | `distributed actor` | Queries Climate TRACE, Open Food Facts, OpenESG APIs. Local cache with 24h TTL. |
| **PricingDataService** | `distributed actor` | Consumes World Bank, BLS PPI, FRED APIs. SQLite time-series on edge node. |
| **FinancialContextService** | `distributed actor` | Aggregates FinanceKit (on-device Apple Wallet) + Plaid (OAuth2 bank accounts) into `FinancialSnapshot`. Financial data never leaves edge node. |

### 4.8 Library Maintenance Pipeline

Triggered from **Settings > Rebuild Library**, the 6-step `maintainLibrary` process:

1. **Recover stuck items** — Reset `processing` → `queued` for stalled items, re-create `LocalInput` records so they can be re-processed
2. **Assign orphaned items** — Match inbox items (nil sessionID) to nearest session by `createdAt` within a 30-minute window and by location proximity
3. **Regenerate missing sessions** — Create sessions for items with no session record
4. **Consolidate fragmented sessions** — Merge sessions within 5s/50m proximity
5. **Reconcile relationships** — Fix broken SwiftData relationships
6. **Regenerate summaries** — Rebuild all session summaries (newest-first)

---

## 5. Enrichment Pipeline Flow

When a capture or link enters the system, it proceeds through these stages **sequentially**. Each stage populates fields on a shared `PipelineContext` struct, which downstream stages read. When an edge node is discovered via Bonjour, stages ②–⑤ are transparently routed to the remote `InferenceService`; otherwise they execute locally.

```
1. Ingestion
   └─ Camera capture / Share Sheet / Photo import / URL deep link
   └─ Item inserted with `processingStatus = "processing"`
   └─ Item saved to SwiftData immediately for live UI updates

1a. Edge Decision (NWBrowser)
   ├─ Edge node available on LAN     → route stages ②–⑤ to remote InferenceService
   └─ No edge node                   → execute locally (existing behavior)

2. Location Resolution (runs first when location is not already pinned)
   ├─ Descriptor override          (user-pinned location from UI — skip if present)
   ├─ EXIF GPS metadata            (image/video embedded coordinates)
   ├─ Live GPS                     (CLLocationManager, only if item is <5 min old)
   ├─ Session context fallback     (inherit parent session's location)
   └─ MapKit reverse geocoding     → pipelineContext.placeEnrichment

3. Vision Analysis (single `analyzeVisualContent` pass — `IntelligenceProcessor.executePipeline`)
   ├─ OCR text recognition        → pipelineContext.ocrText
   ├─ QR code detection            → pipelineContext.qrPayloads (+ web enrichment if URL)
   ├─ Semantic classification      → pipelineContext.visualTags
   ├─ Document segmentation        → pipelineContext.documentContent (perspective-corrected)
   ├─ Subject sifting              → item.siftedImageData (alpha-channel cutout)
   └─ Aesthetics scoring           → item.aestheticsScore
   [local OR edge — identical Vision requests, different Neural Engine]

4. Parallel Enrichment (TaskGroup — runs concurrently)
   ├─ Link metadata extraction     → pipelineContext.linkEnrichment
   └─ Cover image save             → pipelineContext.coverImagePath

5. Stage 1: SLM — Apple Intelligence (`performLLMAnalysis` via `ContextQuestionService`)
   ├─ Input: full PipelineContext (Vision tags, OCR text, location, link data, knowledge graph)
   ├─ @Generable `ContextAnalysis` structured output:
   │   ├─ `summary`             → 2-sentence activity summary
   │   ├─ `visualStatements`    → 2 evidence-based statements from primary data
   │   ├─ `locationStatements`  → 2 environmental/location context statements
   │   ├─ `purpose`             → user intent (e.g. "Researching camera gear")
   │   └─ `tags`                → 2 descriptive tags
   ├─ Concept extraction        → UserConcept auto-creation with weight tracking
   └─ All outputs aggregated into `pipelineContext.enrichmentContextString` for FastVLM
   [local OR edge]

6. Stage 2: FastVLM — Grounded Image Analysis (opt-in, `FastVLMEnrichmentService`)
   ├─ Input: raw image + Vision `visualTags` + SLM `enrichmentContextString` + OCR `transcription`
   ├─ Single-pass grounded prompt: Vision tags anchor what the model should see
   ├─ Local: FastVLM 0.5B (128 token cap, temperature 0.0)
   ├─ Edge:  FastVLM 3B+ (expanded context, higher quality)
   └─ `FastVLMAnalysis` structured output (same schema either path)

7. Session Assignment (`syncSession`)
   ├─ Priority 1: UI-provided `activeSessionID`
   ├─ Priority 2: Match existing session by time + location + topic proximity
   ├─ Priority 3: Create new session if no match within thresholds
   └─ Session summary generated/updated separately (batched after queue drains)

8. ESG / Commerce Enrichment (opt-in, edge node only)
   ├─ Product classification       → pipelineContext.productClassification (YOLO/barcode)
   ├─ ESG data retrieval           → pipelineContext.esgEnrichment (Climate TRACE, Open Food Facts)
   ├─ Pricing nowcast              → pipelineContext.priceTrajectory (DFM, 14-day projection)
   ├─ Financial context            → pipelineContext.financialSnapshot (FinanceKit + Plaid)
   ├─ Commerce routing             → pipelineContext.purchaseOptions (affiliate deep links)
   └─ Advisory decision            → RECOMMEND / REVIEW / DELAY / OVER_BUDGET

9. Persistence
   ├─ processingStatus = "ready"
   ├─ SwiftData save → CloudKit sync
   └─ Input record deleted (prevents re-queue loop)
```

---

## 6. User Interface

### 6.1 View Hierarchy

| View | Description |
|------|-------------|
| **ContentView** | Root navigation — sidebar + detail split view |
| **VisualIntelligenceView** | Camera interface — live preview, subject glow overlay, capture controls, detection results |
| **SidebarView** | Session-based navigation, collections, favorites, search, drag-and-drop |
| **ReferenceDetailView** | Full item detail — media, metadata, location, enrichments, siblings, editing |
| **SettingsView** | App configuration, library maintenance, Edge Node status, diagnostics |
| **ResultsOverlayView** | Detection results overlay on camera preview |
| **SiftedOverlayView** | Subject sifting glow/cutout overlay on camera preview |
| **ContextChipBar** | Horizontal scrolling context tag chips for capture review |
| **PipelineStatusView** | Real-time pipeline processing status display |
| **QueueProgressView** | Pipeline queue processing progress |
| **EditLocationView** | Unified location editing UI — works for individual items (`ProcessedItem`) and session-level bulk editing (`SessionMetadata`) via `LocationEditTarget` enum |
| **EditSessionLocationView** | Thin wrapper — delegates to `EditLocationView(session:)` |
| **PlaceSelectionMapView** | Full-screen map for place selection during location editing |
| **SessionLocationBar** | Inline session location display/edit bar |
| **ConceptListView** | Browse and manage UserConcept entries |
| **ConceptWeightingSection** | Concept weight display/editing within detail views |
| **LinkPreviewView** | Rich link preview rendering for URL items |
| **RichWebView** | WKWebView wrapper for full web page display |
| **AppleMusicReferenceView** | Apple Music item display with playback controls |
| **DiverAppAttributionView** | App attribution/branding display |
| **ReprocessingWizardView** | Guided reprocessing workflow |
| **ReprocessMetadataView** | Metadata review during reprocessing |
| **ShortcutGalleryView** | App Intents / Shortcuts gallery |
| **SharedWithYouView** | iMessage Shared with You integration |

**Ethical Commerce views** *(future — requires edge node)*:

| View | Platform | Description |
|------|----------|-------------|
| **ProductScoreOverlayView** | iOS/iPadOS | Camera overlay showing ESG data quality tier badge, carbon intensity, certifications |
| **NowcastChartView** | iOS/iPadOS | 14-day sparkline price trajectory with directional indicator |
| **CommerceActionView** | iOS/iPadOS | "Buy on [Platform]" CTA with ethical match indicator |
| **BudgetAlertView** | iOS/iPadOS | Financial context inline — budget remaining, category spend |
| **SpatialProductPanelView** | visionOS | RealityKit spatial panel anchored to detected product |


### 6.2 View Models

| ViewModel | Scope |
|-----------|-------|
| **VisualIntelligenceViewModel** (127KB) | Camera, detection, sifting, capture review state |
| **SidebarViewModel** (51KB) | Sidebar state, session management, drag-and-drop, library maintenance |
| **ReferenceDetailViewModel** | Item detail state, editing, enrichment display |
| **ProcessedItemViewModel** | Individual item actions and state |

---

## 7. System Integration

### 7.1 App Intents & Siri

6 registered App Intents, 5 exposed as Siri Shortcuts via `DiverShortcuts: AppShortcutsProvider`:

| Intent | Shortcut Title | Description |
|--------|---------------|-------------|
| **SaveLinkIntent** | "Save Link" | Save a URL to the library. Siri: *"Save to [app]"* |
| **ShareLinkIntent** | "Share Link" | Generate a wrapped link and share. Siri: *"Share with [app]"* |
| **SearchLinksIntent** | "Search & Deep Link" | Search library by keyword, browse recent. Siri: *"Search [app] for [query]"* |
| **OpenLinkIntent** | "Open Link" | Open a specific item by reference. Siri: *"Open [link] from [app]"* |
| **VisualIntelligenceIntent** | "Intelligence Scan" | OCR + QR extraction from screenshot/photo, wraps URL via `DiverLinkGenerator`, saves to queue. Siri: *"Scan screen with [app]"* |
| **OpenVisualIntelligenceIntent** | *(Action Button)* | Opens camera in Visual Intelligence mode. Not a Siri shortcut — bound to device Action Button via `openAppWhenRun`. |

### 7.2 Widgets

Home screen and Lock screen widgets via `VisualIntelligencePipelineWidget` target, providing at-a-glance access to recent captures and sessions.

### 7.3 Share Extension

Receives shared URLs and media from any app. Links are wrapped via `DiverLinkGenerator` (HMAC-signed) and queued for pipeline processing through `QueueStore` (file-based App Group queue for cross-process reliability).

### 7.4 Universal Links & Deep Linking

- Universal Links: `https://secretatomics.com/...`
- Custom scheme: `secretatomics://...`
- Apple App Site Association file for domain validation

### 7.5 Shared with You

`SharedWithYouManager` integrates with Apple's Shared with You framework to surface links shared via iMessage, with attribution in the detail view.

### 7.6 Distributed Actor Edge Node

The Mac/iPad edge node registers a Bonjour service for zero-config LAN discovery:

**Info.plist (edge node):**
```xml
<key>NSBonjourServices</key>
<array>
    <string>_visualintel._tcp</string>
</array>
```

**Info.plist (client — iOS/iPadOS/visionOS):**
```xml
<key>NSBonjourServices</key>
<array>
    <string>_visualintel._tcp</string>
</array>
<key>NSLocalNetworkUsageDescription</key>
<string>Connects to your Mac for faster ML processing</string>
```

**Discovery flow:**
1. Client starts `NWBrowser(for: .bonjour(type: "_visualintel._tcp", domain: nil))`
2. Edge node starts `NWListener` on the same Bonjour type
3. Client resolves `InferenceService` via `VisualIntelligenceActorSystem`
4. All subsequent `distributed func` calls are routed over TLS 1.3 `NWConnection`
5. If Bonjour discovery times out or connection drops → graceful fallback to on-device

---

## 8. Storage & Persistence

### 8.1 SwiftData + CloudKit

SwiftData syncs automatically to CloudKit via the `iCloud.com.secretatomics.knowmaps.Cache` container (declared in app entitlements). The `DiverDataStore` uses `VersionedSchema` + `SchemaMigrationPlan` for migration safety.

| Component | File | Responsibility |
|-----------|------|----------------|
| **DiverDataStore** | `Storage/DiverDataStore.swift` | SwiftData `ModelContainer` configuration with `DiverMigrationPlan` for schema versioning. Uses App Group container for cross-process access. |
| **DiverSchemaV1** | `Storage/DiverSchemaV1.swift` | V1 `VersionedSchema` — baseline snapshot of all 5 `@Model` classes |
| **DiverMigrationPlan** | `Storage/DiverMigrationPlan.swift` | `SchemaMigrationPlan` — registers schema versions and migration stages |
| **ReferencePayloadStore** | `Storage/ReferencePayloadStore.swift` | File-based raw payload storage (`Application Support/Payloads/`). Saves/loads/deletes payload data by ID. Supports App Group container for share extension cross-process access. |
| **StorageClient** | `Storage/StorageClient.swift` | Remote S3 storage client — generates presigned URLs for upload/download and lists job files via `HTTPClient` |
| **UnifiedDataManager** | `Storage/UnifiedDataManager.swift` | Unified data access layer |

**Data Deletion:** The "Delete Database" function in Settings performs a 4-step complete purge:
1. Clear `DiverQueueStore` (file-based processing queue)
2. Remove App Group directories (`Documents`, `Queue`, `SourceImages`, `Snapshots`) and orphaned files
3. Delete all SwiftData entities (7 model types: `ProcessedItem`, `LocalInput`, `UserConcept`, `SessionMetadata`, `SessionCollection`, `UserCachedRecord`, `RecommendationData`)
4. Direct `CKQuery` purge of CloudKit zone (`CD_ProcessedItem`, `CD_SessionMetadata`, `CD_UserConcept`, `CD_LocalInput`, `CD_SessionCollection`) to catch orphaned cloud records

### 8.2 File-Based Queue

`QueueStore` (in `DiverShared`) provides a crash-safe, file-based queue using App Groups for cross-process access (main app ↔ share extension). Ensures no captured link or media is lost, even under extension time limits.

### 8.3 Image Storage

- `rawPayload` — Original capture image data (SwiftData `@Attribute(.externalStorage)`)
- `depthPayload` — LiDAR/TrueDepth depth map data (SwiftData `@Attribute(.externalStorage)`)
- `siftedImageData` — Background-removed subject cutout with alpha channel
- `documentImageData` — Perspective-corrected document scan
- `thumbnailPaths` — File paths to aesthetics-scored session thumbnails

### 8.4 Edge Node Storage

The Mac/iPad edge node maintains local caches that never sync to CloudKit or leave the LAN:

| Store | Technology | Contents | TTL |
|-------|-----------|----------|-----|
| **ESG Cache** | SQLite | Climate TRACE, Open Food Facts, OpenESG results | 24h |
| **Price Time Series** | SQLite | World Bank, BLS PPI, FRED data points | Refreshed daily |
| **Financial Cache** | Keychain + encrypted file | Plaid OAuth2 tokens, transaction cache | Session-based |
| **Commerce Cache** | SQLite | Affiliate link mappings, platform configs | 7 days |
| **Model Cache** | File system | CoreML YOLO/DETR, MLX Swift 3B+ weights | Persistent until evicted |

---

## 9. Security

- **Link Integrity:** Shared URLs are wrapped with HMAC signatures via `DiverLinkGenerator` / `LinkWrapping`. Prevents URL tampering between share extension submission and pipeline ingestion.
- **Keychain:** Authentication tokens stored via `KeychainService`.
- **On-Device Processing:** All ML inference (Vision, Foundation Models, FastVLM) runs locally by default. No user data is sent to external servers for processing.
- **CloudKit:** End-to-end encrypted sync via Apple's CloudKit infrastructure.
- **Edge Transport Security:** Distributed actor calls between client and edge node use TLS 1.3 over `NWConnection`, scoped to the local network. No WAN exposure. Bonjour discovery is LAN-only.
- **Financial Data Isolation:** FinanceKit data stays on-device (Apple Wallet). Plaid data is cached only on the edge node and never forwarded to cloud services. No purchase history is stored unless the user explicitly opts in.
- **Commerce Privacy:** Affiliate links are generated on the edge node. No behavioral tracking or purchase analytics are collected.
- **Audit Logging:** Advisory decisions (ESG scoring, nowcast, recommendation) are logged locally on the edge node with timestamp, product ID, data sources, and recommendation — for user transparency, not analytics.

---

## 10. Platform Requirements

| Requirement | iOS / iPadOS Client | macOS Edge Node | visionOS Client *(future)* |
|-------------|--------------------|-----------------|-----------------------------|
| **Minimum OS** | iOS/iPadOS 26.0 | macOS 26.0 | visionOS 26.3 |
| **Minimum Device** | iPhone 16 / iPad (M-series) | Mac (M4+) | Apple Vision Pro |
| **Apple Intelligence** | Required | Required | Required |
| **FastVLM** | 0.5B (optional, ~500MB) | 3B+ (optional, ~2GB) | — |
| **YOLO/DETR** | — | CoreML model (optional) | — |
| **Key Frameworks** | Swift, SwiftUI, SwiftData, Vision, MapKit, Foundation Models, MLX Swift, AVFoundation, CoreLocation, Contacts, MusicKit, Distributed, Network, Charts, FinanceKit | Swift, Distributed, Network, CoreML, MLX Swift, Accelerate, Charts | Swift, SwiftUI, RealityKit, ARKit, Distributed, Network, Charts |
| **Key APIs** | Spotify, DuckDuckGo | Climate TRACE, Open Food Facts, OpenESG, World Bank, BLS, FRED, Plaid | — |
| **Financial** | FinanceKit (Apple Wallet) | Plaid (OAuth2 bank data) | — |
| **Entitlements** | Camera, Location, Contacts, Photo Library, App Groups, CloudKit, Shared with You, Local Network, FinanceKit | Local Network, App Sandbox | Camera, Local Network, Enterprise (optional) |

---

## 11. Development Conventions

### 11.1 Code Organization

- **Views:** `VisualIntelligencePipeline/View/`
- **View Models:** `DiverKit/Sources/DiverKit/ViewModel/`
- **Services:** `DiverKit/Sources/DiverKit/Services/`
- **Models:** `DiverKit/Sources/DiverKit/Models/`
- **API Schemas:** `DiverKit/Sources/DiverKit/Schemas/` (56 generated structures)
- **Storage:** `DiverKit/Sources/DiverKit/Storage/`

### 11.2 Naming Conventions

- Use `SessionMetadata` directly — the `DiverSession` typealias is deprecated
- Use `SessionCollection` directly — typealias for `DiverCollection` (SwiftData `@Model` class retains original name for schema compatibility)
- Use `ProcessedItem` for the primary enriched item model
- Service names follow `<Domain>Service` or `<Domain>EnrichmentService` pattern
- Distributed actor services follow `<Domain>Service` as `distributed actor` declarations

### 11.3 Critical Rules

1. **Never compromise data integrity** — No destructive schema changes without a tested migration plan
2. **Build stability is paramount** — Verify the project builds after any refactoring
3. **Main thread safety** — Keep pipeline work off `@MainActor`; use `@PipelineActor` or `Task.detached`. `LanguageModelSession`, Vision, and `IntelligenceProcessor` have no actor isolation and must not be called from `@MainActor` task closures.
4. **Task isolation (SE-0466)** — `Task { }` inside `@MainActor` types inherits main actor isolation. Always use `Task.detached(priority: .utility)` for ML/Vision/LLM work, hopping to `@MainActor` only for UI property updates via `await MainActor.run { }`.
5. **Background ModelContext** — Create via `ModelContext(container)` with `autosaveEnabled = false` for pipeline SwiftData access; never use `mainContext` from background tasks
6. **Error logging** — Use `do { try } catch { log }` instead of `try?` for all SwiftData saves
7. **Autorelease in loops** — Wrap image processing loops (`CGImage`, Vision results) in `autoreleasepool { }` to drain ObjC temporaries. Do not place `await` suspension points inside autoreleasepool blocks.
8. **AsyncStream factory** — Use `AsyncStream.makeStream(of:)` (SE-0388, Swift 5.9+) instead of closure-based initializer for progress reporting
9. **Distributed actor safety** — All types crossing the `distributed func` boundary must be `Codable & Sendable`. Use `Data` for image payloads, not `UIImage` or `CGImage`.

### 11.4 Build & Test

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

---

## 12. Relationship Semantics

| Relationship | Cardinality | Purpose |
|-------------|-------------|---------|
| `ProcessedItem.session` → `SessionMetadata` | Many-to-one | Session membership |
| `ProcessedItem.parentItem` ↔ `childItems` | One-to-many (self-referential) | Purpose-based grouping |
| `SessionMetadata.items` → `[ProcessedItem]` | One-to-many (cascade) | Items in a session |
| `SessionMetadata.parentCollection` → `SessionCollection` | Many-to-one | Collection membership |
| `SessionCollection.sessions` → `[SessionMetadata]` | One-to-many (nullify) | Sessions in a collection |
| `masterCaptureID` | String link (not a relationship) | Sibling captures from the same camera session |

---

## 13. Glossary

| Term | Definition |
|------|-----------|
| **Sifting** | Subject isolation from background using Vision framework person/object masks |
| **Pipeline** | The multi-stage enrichment process from raw capture to persisted, enriched item |
| **Session** | A time/location-grouped set of captures (`SessionMetadata`) |
| **Collection** | A user-curated or auto-imported grouping of sessions (`SessionCollection`) |
| **Context Tag / Purpose** | User-applied labels for intent tracking (e.g., "Gift ideas") |
| **PipelineContext** | Typed struct aggregating all enrichment data during processing |
| **Enrichment** | Any metadata added to a capture post-ingestion (location, web, music, AI analysis) |
| **Daily Focus** | AI-generated daily activity brief from `DailyContextService` |
| **FastVLM** | Apple's Fast Vision-Language Model (0.5B on-device, 3B+ on edge), run via MLX Swift |
| **masterCaptureID** | String linking sibling items captured simultaneously (photo + QR + document) |
| **Edge Node** | Local Mac or M-series iPad hosting distributed actors for ML offloading and data enrichment |
| **Data Quality Tier** | 1–5 rating adapted from PCAF: 1 = independently verified, 5 = sector-average estimate |
| **Nowcasting** | Statistical technique using mixed-frequency data to estimate near-real-time economic indicators |
| **Advisory Decision** | User-confirmed recommendation (RECOMMEND / REVIEW / DELAY / OVER_BUDGET). System assists, user acts. |
| **Distributed Actor** | Swift `distributed actor` — cross-device actor communication via `Distributed` framework (SE-0336) |
| **VisualIntelligenceActorSystem** | Custom `DistributedActorSystem` — Bonjour discovery + `NWConnection` TLS transport for ML offloading |
| **Procurement API** | `CommerceService` matching products to purchase options filtered by ethical policy + platform preferences |
| **FinanceKit** | Apple framework (iOS 17+) providing on-device access to Apple Wallet transaction data |
| **Affiliate Routing** | Deep-link generation to user's preferred commerce platforms with revenue-share tracking |

---

## 14. Ethical Commerce & Micro-Decisions — Implementation Roadmap

> The features described in §1.1 (value props 5–6), §2.2 (edge computing), §3.6 (commerce types), §4.7 (edge services), §5 (stage ⑧), §6.1 (commerce views), §7.6 (Bonjour), §8.4 (edge storage), and §9 (financial security) are all part of the Ethical Commerce initiative.
>
> For detailed implementation phases (Phase 0 PoC through Phase 3 VisionOS), data source assessment, PCAF data quality tier methodology, degraded-mode design, and procurement API architecture, see:
>
> **[Documentation/ethical_commerce_spec.md](Documentation/ethical_commerce_spec.md)**
