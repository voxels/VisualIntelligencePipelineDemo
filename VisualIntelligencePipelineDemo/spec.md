# Visual Intelligence Pipeline — Project Specification

> **Version:** 1.0  
> **Last Updated:** 2026-02-17  
> **Platform:** iOS 26.0+  
> **Bundle ID:** `com.secretatomics.VisualIntelligencePipeline`

---

## 1. Product Vision

Visual Intelligence Pipeline transforms the iPhone camera into an intelligence layer for everyday life. Point your camera at anything — a product, a sign, a document, a landmark — and the app instantly identifies it, enriches it with contextual metadata, and organizes it into a searchable personal knowledge base.

Beyond the camera, it serves as a universal hub for saving and organizing links shared from Safari, TikTok, YouTube, iMessage, and any app with a share sheet.

### 1.1 Core Value Propositions

1. **Capture → Enrich → Understand** — A single tap triggers a multi-stage pipeline that sifts subjects from backgrounds, enriches captures with location/web/music/document context, and generates AI summaries.
2. **Local-First Intelligence** — All ML inference runs on-device: Apple Vision framework, Apple Intelligence (Foundation Models), and FastVLM 0.5B via MLX Swift. No data leaves the device for processing.
3. **Universal Link Organization** — Links from any source are wrapped in tamper-proof HMAC-signed URLs, processed through the same enrichment pipeline, and surfaced alongside visual captures.
4. **Cross-Device Sync** — SwiftData + CloudKit provides seamless, automatic sync across all devices.

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
| **VisualIntelligencePipeline** | App entry point, UI layer, App Intents | 25 SwiftUI views, 7 app services, 14 App Intent definitions |
| **DiverKit** | Business logic, ML pipelines, persistence | 37 services, 4 view models, 14 models, 56 API schemas, storage layer |
| **DiverShared** | Cross-target shared types | `AppGroupConfig`, `QueueStore`, `LinkWrapping`, `IntelligenceCapability`, `ContextSnapshot` |

### 2.2 Concurrency Model

| Context | Mechanism | Usage |
|---------|-----------|-------|
| Pipeline processing | `@PipelineActor` (custom global actor) | `LocalPipelineService`, heavy enrichment tasks |
| Heavy computation | `Task.detached(priority: .utility)` | ML inference, image analysis, metadata extraction |
| Background SwiftData | `ModelContext(container)` with `autosaveEnabled = false` | All pipeline/enrichment SwiftData access |
| UI updates | `@MainActor` | View models, published properties |

> **Critical Rule:** Never use `Task { }` in SwiftUI handlers (`onAppear`, `onChange`, `onReceive`) for pipeline work — it inherits `@MainActor`. Always use `Task.detached(priority: .utility)` with explicit capture lists.

### 2.3 Data Flow

The pipeline is **sequential** — each stage feeds its output into `PipelineContext`, which accumulates typed fields for downstream consumers.

```
┌──────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│  Camera /     │    │  MetadataPipeline │    │  LocalPipeline      │
│  Share Sheet  │───▶│  Service          │───▶│  Service            │
│  / Import     │    │  (Queue → Input)  │    │  (Orchestrator)     │
└──────────────┘    └──────────────────┘    └─────────────────────┘
                                                      │
                                                      ▼
                                              ┌───────────────┐
                                         ①    │  Location      │  Pinned → EXIF → GPS
                                              │  Resolution    │  → Session fallback
                                              │  + Geocoding   │  → MapKit geocode
                                              └──────┬────────┘
                                                     ▼
                                              ┌───────────────┐
                                         ②    │  Vision        │  OCR, QR, visual tags,
                                              │  Framework     │  sifting, aesthetics,
                                              │  (6 requests)  │  document detection
                                              └──────┬────────┘
                                                     ▼
                                    ┌────────────────┼────────────────┐
                               ③    ▼                                 ▼     (parallel)
                            ┌──────────┐                        ┌──────────┐
                            │ Link     │                        │ Cover    │
                            │ Metadata │                        │ Image    │
                            └────┬─────┘                        └────┬─────┘
                                 └───────────────┬───────────────────┘
                                                 ▼
                                          ┌───────────────┐
                                     ④    │  SLM           │  @Generable structured
                                          │  (Foundation   │  extraction: summary,
                                          │   Models)      │  intent, tags
                                          └──────┬────────┘
                                                 ▼
                                          ┌───────────────┐
                                     ⑤    │  FastVLM       │  Multimodal synthesis
                                          │  (MLX Swift)   │  using image + full
                                          │  (opt-in)      │  PipelineContext
                                          └──────┬────────┘
                                                 ▼
                                          ┌───────────────┐
                                     ⑥    │  Session       │  Cluster, merge,
                                          │  Assignment    │  generate summary
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

Provides two serialization outputs:
- `asContextString` — Full context for SystemLanguageModel
- `enrichmentContextString` — Priority-ordered, truncated context for FastVLM

---

## 4. Pipeline Services

### 4.1 Core Orchestration

| Service | File | Responsibility |
|---------|------|----------------|
| **LocalPipelineService** | `LocalPipelineService.swift` (135KB) | Master orchestrator — ingestion, enrichment coordination, persistence, session management, reprocessing, library maintenance |
| **MetadataPipelineService** | `MetadataPipelineService.swift` (47KB) | Converts queue items → `LocalInput`, dispatches metadata extraction tasks via `Task.detached` |
| **PipelineContext** | `PipelineContext.swift` | Typed context struct aggregated across enrichment stages |
| **PipelineActor** | `PipelineActor.swift` | Custom `@globalActor` for pipeline isolation |

### 4.2 ML & Intelligence

| Service | Responsibility |
|---------|---------------|
| **IntelligenceProcessor** | Runs 6 Vision requests in a single `executePipeline` pass (OCR, QR, semantic classification, document detection, subject sifting, aesthetics scoring). Also drives on-device LLM (SystemLanguageModel) for concept extraction and summarization. |
| **FastVLMEnrichmentService** | Apple FastVLM 0.5B via MLX Swift. Single-pass grounded analysis: image + Vision tags + enrichment context → structured output. Prefers sifted (subject-only) image. ~500MB on-demand download, memory-pressure eviction. |
| **ContextQuestionService** | Apple Foundation Models (`LanguageModelSession`) structured generation via `@Generable` macro. Produces summaries, evidence statements, intent identification, tags. |
| **FoundationModelsIntentClassifier** | LLM-based intent classification for incoming items. |
| **AestheticsScoringService** | Wraps `VNCalculateImageAestheticsScoresRequest`. Also bundled into `IntelligenceProcessor.executePipeline`; standalone usage for video frame selection and import scoring. |

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

### 4.7 Library Maintenance Pipeline

Triggered from **Settings > Rebuild Library**, the 6-step `maintainLibrary` process:

1. **Recover stuck items** — Reset `processing` → `queued` for stalled items, re-create `LocalInput` records so they can be re-processed
2. **Assign orphaned items** — Match inbox items (nil sessionID) to nearest session by `createdAt` within a 30-minute window and by location proximity
3. **Regenerate missing sessions** — Create sessions for items with no session record
4. **Consolidate fragmented sessions** — Merge sessions within 5s/50m proximity
5. **Reconcile relationships** — Fix broken SwiftData relationships
6. **Regenerate summaries** — Rebuild all session summaries (newest-first)

---

## 5. Enrichment Pipeline Flow

When a capture or link enters the system, it proceeds through these stages **sequentially**. Each stage populates fields on a shared `PipelineContext` struct, which downstream stages read.

```
1. Ingestion
   └─ Camera capture / Share Sheet / Photo import / URL deep link
   └─ Item inserted with `processingStatus = "processing"`
   └─ Item saved to SwiftData immediately for live UI updates

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

6. Stage 2: FastVLM — Grounded Image Analysis (opt-in, `FastVLMEnrichmentService`)
   ├─ Input: raw image + Vision `visualTags` + SLM `enrichmentContextString` (summary, statements, purpose, tags) + OCR `transcription`
   ├─ Single-pass grounded prompt: Vision tags anchor what the model should see
   ├─ `FastVLMAnalysis` structured output:
   │   ├─ `imageDescription`    → multimodal description of image content
   │   ├─ `contextSummary`      → synthesized summary (may override SLM summary)
   │   ├─ `suggestedTitle`      → title (applied only if item has none)
   │   ├─ `suggestedPurpose`    → intent (appended to item purposes)
   │   ├─ `suggestedTags`       → tags (logged, not applied to UI)
   │   └─ `statements`          → evidence statements (logged, not applied to UI)
   └─ Constrained: 128 token cap, temperature 0.0

7. Session Assignment (`syncSession`)
   ├─ Priority 1: UI-provided `activeSessionID` (user explicitly in an active session context)
   ├─ Priority 2: Match existing session by time proximity + location proximity + topic similarity
   ├─ Priority 3: Create new session if no match within thresholds
   └─ Session summary generated/updated separately (batched after queue drains)

8. Persistence
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
| **SettingsView** | App configuration, library maintenance, diagnostics |
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

---

## 9. Security

- **Link Integrity:** Shared URLs are wrapped with HMAC signatures via `DiverLinkGenerator` / `LinkWrapping`. Prevents URL tampering between share extension submission and pipeline ingestion.
- **Keychain:** Authentication tokens stored via `KeychainService`.
- **On-Device Processing:** All ML inference (Vision, Foundation Models, FastVLM) runs locally. No user data is sent to external servers for processing.
- **CloudKit:** End-to-end encrypted sync via Apple's CloudKit infrastructure.

---

## 10. Platform Requirements

| Requirement | Value |
|-------------|-------|
| **Minimum Device** | iPhone 16 (A18 chip required for Apple Intelligence and on-device LLM) |
| **Minimum iOS** | 26.0 |
| **Apple Intelligence** | Required for on-device LLM features (summaries, tags, intent classification) |
| **FastVLM** | Optional — ~500MB on-demand download, auto-evicted under memory pressure |
| **Frameworks** | Swift, SwiftUI, SwiftData, Vision, MapKit, Foundation Models, MLX Swift, AVFoundation, CoreLocation, Contacts, MusicKit |
| **APIs** | Spotify (music matching), DuckDuckGo (link enrichment) |
| **Entitlements** | Camera, Location, Contacts, Photo Library, App Groups, CloudKit, Shared with You | 

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

### 11.3 Critical Rules

1. **Never compromise data integrity** — No destructive schema changes without a tested migration plan
2. **Build stability is paramount** — Verify the project builds after any refactoring
3. **Main thread safety** — Keep pipeline work off `@MainActor`; use `@PipelineActor` or `Task.detached`
4. **Background ModelContext** — Create via `ModelContext(container)` with `autosaveEnabled = false` for pipeline SwiftData access; never use `mainContext` from background tasks
5. **Error logging** — Use `do { try } catch { log }` instead of `try?` for all SwiftData saves

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
| **FastVLM** | Apple's Fast Vision-Language Model (0.5B), run locally via MLX Swift |
| **masterCaptureID** | String linking sibling items captured simultaneously (photo + QR + document) |
