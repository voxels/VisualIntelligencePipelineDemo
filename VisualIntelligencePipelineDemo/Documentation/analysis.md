# Visual Intelligence Pipeline — v1.2 Analysis

**Date:** 2026-02-23
**Revision:** Post-edge infrastructure + commerce intelligence + reprocessing unification
**Development period:** 43 days (Jan 11 – Feb 23, 2026)

---

## Summary Statistics

| Metric | Value |
|--------|-------|
| Total Swift files | 431 |
| Total lines of code | ~72,900 |
| DiverKit lines | ~44,800 |
| App target lines | ~24,300 |
| DiverShared lines | ~2,300 |
| Test files | 41 |
| Test lines | ~6,200 |
| Contributors | 1 |

### Module Breakdown

| Module | Files | Lines | Purpose |
|--------|-------|-------|---------|
| **DiverKit** | ~270 | 44,800 | Core logic — services, models, view models, storage, edge infrastructure, commerce |
| **App Target** | ~120 | 24,300 | UI views (62), AppIntents, ActionExtension, app-level services |
| **DiverShared** | ~16 | 2,300 | Pure Swift shared data models and utilities |
| **Tests** | 41 | 6,200 | Unit + integration tests for DiverKit and app target |
| **EdgeDaemon** | ~15 | ~1,200 | macOS menu bar ML inference node (Bonjour-advertised) |
| **SpatialCommerce** | ~10 | ~800 | visionOS spatial commerce viewer |

### DiverKit Service Breakdown

| Category | Count |
|----------|-------|
| Services (total files) | 67 |
| Protocols | 18 |
| Models | 21 |
| View Models | 6 |
| Storage | 5 |

---

## Largest Files

| File | Lines | Concern |
|------|-------|---------|
| `LocalPipelineService.swift` | 3,656 | Pipeline orchestration, enrichment, persistence, reprocessing, session management |
| `VisualIntelligenceViewModel.swift` | 3,198 | Camera, detection, sifting, capture review, import, spatial commerce |
| `SidebarViewModel.swift` | 1,517 | Sidebar state, session management, library maintenance, reprocessSession |
| `MetadataPipelineService.swift` | 1,223 | Queue processing, processItemByID, processQueuedOrphanItems, freshness guard |
| `ReferenceDetailView.swift` | 1,413 | Unified item detail view routing to 6 domain-specific profile views |
| `EdgeDaemonService.swift` | 811 | Bonjour TLS server, distributed actor dispatch, CLaRa/FastVLM/Vision routing |

> [!NOTE]
> `LocalPipelineService` grew from 3,041 → 3,656 lines since v1.1 (+615 lines) due to commerce intelligence, CLaRa edge routing, and reprocessing unification. `ReferenceDetailView` shrank from 2,496 → 1,413 lines (–1,083 lines) due to profile view extraction.

---

## Architecture Assessment

### Strengths

**Clean Modular Boundaries**
The three-layer package architecture (`DiverShared` → `DiverKit` → `App`) enforces clear dependency direction. `DiverShared` has zero dependencies and contains only pure Swift types. `DiverKit` encapsulates all business logic. The app target is a thin shell focused on UI wiring and system integration.

**Unified Reprocessing Path**
All reprocessing entry points (`processItemImmediately`, `reprocessPipeline`, `reprocessSession`, `processQueuedOrphanItems`) converge on `processItemByID` — a single canonical function with its own private `ModelContext`. This eliminates the ~200 lines of duplicated pipeline logic that previously existed in `processItemImmediately`. Every enrichment step runs identically regardless of entry point.

**Lifecycle-Safe Reprocessing**
`reprocessPipeline` uses a 3-phase durable design: Phase 1 marks all items `.queued` and saves to SwiftData (crash-safe checkpoint), Phase 2 processes sequentially via `processItemByID`, Phase 3 regenerates session summaries. If the app is killed during Phase 2, the next foreground resume picks up remaining `.queued` items via `processQueuedOrphanItems`.

**Multi-Device Safety**
`processItemByID` has a freshness guard: re-fetches the item's status before starting. If already `.ready` or `.processing` (synced from another device via CloudKit), it skips processing. `force: true` bypasses this for explicit user-initiated reprocessing ("Process Now"). Prevents redundant work across devices without device ownership stamps or distributed coordination.

**Edge-First Intelligence Routing**
The EdgeDaemon (macOS menu bar app) is Bonjour-advertised as `_visualintel._tcp` and provides 4 distributed actors: `EdgeContextActor` (CLaRa 7B), `EdgeInferenceActor` (FastVLM 1.5B + Vision), `EdgeCommerceActor` (platform ranking), `EdgeAgenticSearchActor` (RAG). `CapabilityRouter` performs runtime hardware detection (RAM/TOPS) and routes tasks accordingly. Edge CLaRa (7B) supersedes local SLM + FastVLM when available.

**Commerce Intelligence (7 Engines)**
Products scored via barcode or classification across 7 simultaneous strategies: ESG (Ethics), Brand Fit, Value, Durability, Social Proof, Health Fit, Total Cost. `RankingPolicy` protocol with 3 presets (`EthicalPolicy`, `PriceFocusedPolicy`, `SpeedFocusedPolicy`). Open product data cascade: Food Facts → Beauty Facts → Pet Food Facts → Products Facts → UPC Item DB. All free/open databases, no paid APIs.

**Bundled Vision Pass**
7 Vision requests (OCR, QR, semantic classification, document segmentation, sifting, aesthetics scoring, saliency) execute in a single `handler.perform()` call via `IntelligenceProcessor.executePipeline`. Eliminates redundant image decoding.

**Two-Phase Pipeline**
Phase 1 (capture-time, ~1-2s): Vision + Location + Web enrichment. Returns with `.captured` status. Phase 2 (background): CLaRa/SLM, FastVLM, Commerce, Concepts. `captureOnly` parameter controls the gate. Background sweep picks up `.captured` items via `enrichCapturedItems()`.

**Robust Edge Transport**
`NWTransportLayer` uses TLS 1.3 with `ConnectionSerializer` actor for ordering. Self-healing: framing errors cancel the connection so the next request creates a fresh TCP connection, preventing cascading failures. Length-prefixed framing with per-request timeout.

### Areas for Improvement

**God Objects**
`LocalPipelineService` (3,656 lines) handles pipeline orchestration, enrichment, persistence, session management, reprocessing, CLaRa integration, FastVLM routing, and commerce scoring. `VisualIntelligenceViewModel` (3,198 lines) manages camera, sifting, capture review, photo import, QR detection, and spatial commerce. Both are prime decomposition candidates.

**Test Coverage**
41 test files with ~6,200 lines represent ~8.5% of the codebase by line count — improved from 3% in v1.1 but still disproportionate for a production pipeline. Key gaps:

| Area | Test Status |
|------|-------------|
| `LocalPipelineService` (3,656 lines) | 1 integration test file |
| `VisualIntelligenceViewModel` (3,198 lines) | 5 tests (init, capture, reset, recording, peel) |
| `EdgeDaemonService` (811 lines) | No tests |
| Edge actor dispatch | No tests |
| Commerce scoring pipeline (7 engines) | No integration tests |
| Reprocessing lifecycle (3-phase) | No tests |
| Multi-device freshness guard | No tests |

**CloudKit Sync Timing**
The freshness guard in `processItemByID` is best-effort — it depends on CloudKit sync propagating a status change before a second device starts processing the same item. In practice, CloudKit latency is 5-30s; concurrent reprocessing across devices within that window is uncommon but possible. The result is redundant work (not data corruption) since both devices produce equivalent output.

---

## Feature Completeness at v1.2

| Feature | Status | Key Files |
|---------|--------|-----------|
| Camera & Subject Sifting | ✅ Complete | `VisualIntelligenceView`, `VisualIntelligenceViewModel`, `CameraManager` |
| Vision Analysis (OCR, QR, Semantic, Document, Aesthetics, Saliency) | ✅ Complete | `IntelligenceProcessor` — 7 requests, single pass |
| Location Enrichment (MapKit + Contacts) | ✅ Complete | `ReverseGeocodingService`, `ContactService` |
| Location Editing (MapKit + Foursquare) | ✅ Complete | `LocationSearchAggregator`, `EditLocationView` |
| Document Detection & Saving | ✅ Complete | `DocumentManager` |
| Apple Music / Spotify | ✅ Complete | `AppleMusicEnrichmentService`, `SpotifyService` |
| Web / QR URL Enrichment | ✅ Complete | `LinkEnrichmentService` (http/https only — custom schemes skipped) |
| On-Device LLM (summaries, concepts, tags) | ✅ Complete | `IntelligenceProcessor`, `SystemLanguageModel` |
| FastVLM multimodal analysis | ✅ Complete | `FastVLMEnrichmentService` (Edge 1.5B → Local 0.5B fallback) |
| CLaRa 7B edge summarization | ✅ Complete | `EdgeContextActor`, `EdgeDaemon` |
| Edge Vision + FastVLM offload | ✅ Complete | `EdgeInferenceActor` |
| Person identity (PhotoKit) | ✅ Complete | `PHPerson`, `PersonVector` database |
| Session Clustering | ✅ Complete | `SessionClusteringService` |
| Daily Focus Briefs | ✅ Complete | `DailyContextService` |
| Commerce Intelligence (7 engines) | ✅ Complete | `Services/Scoring/`, `ESGEnrichmentService`, `ProductRecommendationService` |
| Open product database cascade | ✅ Complete | Food/Beauty/Pet/Products Facts → UPC Item DB |
| Ethical platform ranking | ✅ Complete | `AffiliateRoutingService`, `EthicalPolicy`, `PriceFocusedPolicy`, `SpeedFocusedPolicy` |
| Price nowcasting | ✅ Complete | `NowcastingEngine` (Dynamic Factor Model via Accelerate vDSP) |
| Government data (CPSC, FDA, EPA, Energy Star) | ✅ Complete | `GovernmentDataService` |
| Preference learning | ✅ Complete | `PreferenceLearner` — ownership history → strategy weights |
| Score history charting | ✅ Complete | `ScoreHistoryChartView`, `NowcastChartView` (Swift Charts) |
| visionOS Spatial Commerce | ✅ Complete | `SpatialCommerce/` — AR product detection + score overlay |
| Reprocessing (unified path) | ✅ Complete | `processItemByID`, `reprocessPipeline` (lifecycle-safe), `reprocessSession` |
| Multi-device safety | ✅ Complete | Freshness guard in `processItemByID` |
| Photo Library Import | ✅ Complete | `PhotoLibraryImportService`, `PhotosAssetLoader` |
| Sidebar / Collections / Drag-Drop | ✅ Complete | `SidebarView` (7 child views), `SidebarViewModel` |
| Share Sheet Extension | ✅ Complete | `ActionExtension/` |
| App Intents | ✅ Complete | `AppIntents/` |
| Widgets | ✅ Complete | `VisualIntelligencePipelineWidget/` |
| Agentic Chat (CLaRa RAG) | ✅ Complete | `AgenticChatView`, `EdgeAgenticSearchActor` |
| 3D Splat generation (ML-Sharp) | ⚙️ In Progress | `MLSharpService` — edge Python interop, on-demand via profile button |
| Library Maintenance (Rebuild Library) | ✅ Complete | `maintainLibrary` — 6-step repair pipeline |

---

## Code Quality — v1.2 Audit Results

### Improvements Since v1.1

| Category | Change |
|----------|--------|
| Reprocessing code duplication | Eliminated: `processItemImmediately` collapsed from ~200 lines → 10-line wrapper |
| Reprocessing lifecycle safety | Added: `reprocessPipeline` durably queues before processing (crash-safe) |
| Session summary regeneration | Fixed: `reprocessPipeline` and `reprocessSession` now regenerate summaries |
| Multi-device race | Mitigated: freshness guard skips `.ready`/`.processing` items in `processItemByID` |
| Edge FastVLM empty payload | Fixed: iOS guards `!imageData.isEmpty` before calling `runVLM` |
| EdgeDaemon log noise | Fixed: expected nil imageData downgraded from `⚠️ print` to debug log |
| EdgeDaemon CloudKit warning | Fixed: `APIKeyService` skips `CKContainer` init in EdgeDaemon process |
| URL scheme guard | Fixed: link enrichment only runs on `http://`/`https://` URLs |
| Queue self-cancellation | Fixed: `processQueuedOrphanItems` uses `processItemByID` not `processItemImmediately` |

### Positive Patterns (Carried Forward)

- **Async/await throughout** — No completion-handler callback nesting. All services use structured concurrency.
- **Protocol-based DI** — 18 protocols across `DiverKit/Sources/DiverKit/Protocols/` and service files. Pipeline services accept protocol-typed dependencies enabling mock injection for testing.
- **SwiftData + CloudKit** — Local-first persistence with sync, managed through `DiverDataStore`. VersionedSchema V1/V2 migration plan in place.
- **Typed errors** — Domain-specific error types (`DiverLinkError`, `EdgeInferenceError`, etc.) rather than raw `Error`.
- **`@unchecked Sendable` audit** — All production `@unchecked Sendable` types documented with `/// Safety:` comments.
- **`@PipelineActor` isolation** — Long-running pipeline work isolated from `@MainActor`. Never spawning N concurrent Tasks in for-loops over SwiftData models.
- **Background `ModelContext`** — All pipeline/enrichment code creates `ModelContext(container)` with `autosaveEnabled = false`. Never uses `mainContext` from background tasks.

### Remaining Concerns

- **God objects** — `LocalPipelineService` (3,656 lines) and `VisualIntelligenceViewModel` (3,198 lines) combine too many responsibilities. Prime candidates for decomposition into focused sub-services/sub-view-models.
- **Test depth** — 41 test files but edge actors, commerce engines, and the 3-phase reprocessing lifecycle have no test coverage. The freshness guard logic is also untested.
- **CloudKit sync window** — Multi-device reprocessing is mitigated (not eliminated) by the freshness guard. True prevention would require distributed coordination beyond SwiftData/CloudKit's last-writer-wins model.

---

## Recommendations for v1.3

1. **Decompose `LocalPipelineService`** — Extract reprocessing orchestration into `ReprocessingCoordinator`, enrichment composition into `EnrichmentOrchestrator`, and session management into `SessionSyncService`. Target ~1,000 lines each.
2. **Decompose `VisualIntelligenceViewModel`** — Extract camera management into `CameraViewModel`, sifting into `SiftingViewModel`, capture review into `CaptureReviewViewModel`.
3. **Edge actor test harness** — Add integration tests for `EdgeContextActor`, `EdgeInferenceActor`, `EdgeCommerceActor` with mock transport.
4. **Commerce integration tests** — Test the full 7-engine scoring pipeline end-to-end with fixture products.
5. **Reprocessing lifecycle tests** — Test the 3-phase `reprocessPipeline` against simulated app kills (Phase 1 checkpoint, Phase 2 resume via `processQueuedOrphanItems`).
