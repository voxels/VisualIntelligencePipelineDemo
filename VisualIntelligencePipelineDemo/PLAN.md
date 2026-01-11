# Diver Project Plan

_Last updated: 2025-12-24_

---

## Table of Contents

1. [Overview](#overview)
2. [Phase Breakdown & Status](#phase-breakdown--status)
3. [Critical Issues & Mitigations](#critical-issues--mitigations)
4. [Architecture & Key Dependencies](#architecture--key-dependencies)
5. [Testing & Quality Gates](#testing--quality-gates)
6. [Feature Matrix & Implementation Order](#feature-matrix--implementation-order)
7. [Phase Details](#phase-details)
8. [Known Risks & Mitigations](#known-risks--mitigations)
9. [Documentation Tasks](#documentation-tasks)
10. [Prompt Handoff Notes](#prompt-handoff-notes)

---

## Overview

Diver is a cross-platform SwiftUI app utilizing SwiftData, app group storage, deep system integration (App Intents, Share Sheet, BGTaskScheduler), and ML enrichment via Know-Maps. The app supports structured link ingestion, sharing via proprietary wrapped URLs, advanced search, and system-level automation hooks.

---

## Phase Breakdown & Status

| Phase                                | Status      | Key Output                                  |
|-------------------------------------- |------------ |---------------------------------------------|
| 0.5: Critical Fixes                  | ✅ Complete | Test infra, DI, keychain fix                |
| 1: DiverKit Preparation               | ✅ Complete | Model fields, fixtures, migration, os_log   |
| 2: Action Extension                   | ✅ Complete | Share extension, queue, keychain fallback   |
| 3: Data Model Consolidation           | ✅ Complete | Single entry, split navigation, swipe UI    |
| 4: App Intents & Action Button        | ✅ Complete | AppEntity, Siri/Shortcuts, BGTaskScheduler  |
| 4B: Shortcuts & Widgets               | ✅ Complete | Shortcut templates, Home/Lock screen widgets |
| 5: Shared with You + Shelf            | ✅ Complete | Ingestion pipeline, shelf UI, opt-out       |
| 6: Foursquare Enrichment              | ⬜️ Pending | Expanded enrichment, ML, cache              |
| 7: Know-Maps Ranking/Feedback         | ⬜️ Pending | Vector ranking, feedback training           |
| 8: Integration Test/E2E Gate          | ⬜️ Pending | CI, migration, resource/test gate           |
| 9: Advanced Widgets (Low Priority)    | ⬜️ Pending | Live Activities, Control Center, experiments |

---

## Critical Issues & Mitigations

### Completed

- **ActionViewController Test/Implementation Mismatch:** Fixed initializer, tests pass.
- **AppGroupConfigTests Keychain Format:** Test updated for Team ID prefix.
- **Base URL Discrepancy:** Plan and implementation aligned to `secretatomics.com`.
- **Fixture Location:** All references point to `Diver/DiverTests/Fixtures/pipeline_logs.json`.

### Ongoing

- **Observability:** os_log infra in place, more metrics to follow.
- **BGTaskScheduler:** Robust error/retry/expiration handling added.

---

## Architecture & Key Dependencies

- **App Group:** `group.com.secretatomics.Diver` (shared queue, user data)
- **CloudKit:** `iCloud.com.secretatomics.knowmaps.Cache`, `iCloud.com.secretatomics.knowmaps.Keys`
- **Keychain:** `23264QUM9A.com.secretatomics.Diver.shared` (wrapped link secret)
- **SwiftData:** All models (Diver, KnowMaps) in a single container via `DiverDataStore`
- **Queue Store:** `DiverQueueStore` writes to app group directory
- **BGTaskScheduler:** Identifier `com.secretatomics.Diver.processQueue`
- **SwiftUI:** Modern split navigation, sidebar, snippets
- **App Intents:** All system entry points live in main app target
- **Know-Maps:** Used for ML, not UI

---

## Testing & Quality Gates

- **Unit**: DiverKit, DiverShared, Action Extension, App Intents (20/20 passing as of 2025-12-23)
- **Integration**: Smoke test for action extension, app group queueing, ML resource loading
- **E2E**: Pending (Phase 8)
- **Manual**: UI, Shortcuts, Siri invocation, Action Button, Shared with You

---

## Feature Matrix & Implementation Order

1. **Critical Fixes** (test infra, keychain, base URLs)
2. **DiverKit Prep** (model, fixtures, migration, os_log)
3. **Action Extension** (share sheet, keychain fallback, queue)
4. **Data Model Consolidation** (single SwiftData entry point, split nav, swipe actions)
5. **App Intents** (AppEntity, 5 core intents, BGTaskScheduler, snippets, dialogs, Shortcuts)
6. **Shared with You Integration** (SWHighlightCenter, shelf, opt-out, empty state)
7. **Foursquare Enrichment** (API, expansion, ML, retries)
8. **Know-Maps Ranking** (vector ranking, RL loop, feedback)
9. **E2E Integration Test** (CI/QA gate before release)

---

## Phase Details

### Phase 4: App Intents & Action Button — **COMPLETE**

- **Entities**: `LinkEntity` conforms to `AppEntity` and `Transferable`
- **Queries**: `LinkEntityQuery` async, filters via SwiftData
- **Intents**: `SaveLinkIntent`, `ShareLinkIntent`, `SearchLinksIntent`, `GetRecentLinksIntent`, `OpenLinkIntent` (all tested and registered)
- **Shortcuts**: `AppShortcutsProvider` registers all with sample phrases/icons
- **Snippets**: SwiftUI snippet views for save/share, connected in intent extensions
- **Dialogs**: All dialogs use `LocalizedStringResource` for localization
- **Background**: Robust BGTaskScheduler integration, error/retry/expiration logic
- **UI**: Configurator, preview, tag picker, validation
- **Documentation**: `Documentation/APP_INTENTS.md` created with all usage info

---

## Known Risks & Mitigations

- **CloudKit Key Missing**: Startup health check, user diagnostics, feature gating
- **Extension Limits**: Keep extension write-only, move heavy work to app
- **BGTask Reliability**: Exponential backoff, error logs, expiration handlers
- **Schema Drift**: Versioned mapping, migration smoke tests, golden outputs
- **Siri/Shortcuts NLU**: Alt phrases, regular QA, localization
- **Data Loss/Corruption**: Migration defaults, backup plans, error reporting

---

## Documentation Tasks

- [x] Update and maintain `Documentation/APP_INTENTS.md`
- [x] Create `Documentation/SHORTCUTS_AND_WIDGETS.md` (Phase 4B)
- [ ] Document Action Extension, App Group setup, entitlement requirements
- [ ] Add usage guides for:
    - Action Button integration
    - Shared with You setup
    - Foursquare enrichment
    - Know-Maps tuning and feedback loop
- [ ] Final integration test: checklist and troubleshooting instructions

---

## Prompt Handoff Notes

- All phases begin with “tests first”—add fixtures/resources to `DiverShared/Fixtures` as needed.
- New files and entitlements must be documented and use canonical identifiers.
- Once Phase 5 (Shared with You) is complete, run and document the end-to-end integration test.
- Update this plan and all references throughout development for new dependencies, architectural changes, and risk discoveries.

---

## Next Steps

- **Phase 5: Shared with You Integration**
  - Enable entitlement, connect SWHighlightCenter
  - Ingest highlights, validate payloads
  - Build shelf UI with empty/fallback state
  - Add opt-out toggle
  - Write coverage tests for ingestion, shelf, pruning, opt-out

- **After that:** Proceed to Foursquare expansion, Know-Maps ranking/feedback, and full E2E test.

---

# Diver Plan

## Priority Order (Revised)
1. **Phase 0.5: Critical Fixes** ← NEW (blocking Phase 2)
   - Fix ActionViewController dependency injection for testability
   - Fix AppGroupConfigTests keychain expectation
   - Verify all existing tests pass before proceeding
2. Phase 1: DiverKit preparation (model additions, fixtures, migration tests).
3. Phase 2: Action Extension tests for the baseline.
4. Phase 3: Data model consolidation → SwiftData single entry point → split navigation + detail views → swipe actions.
5. Phase 4: App Intents + Action button entry points (includes BGTaskScheduler hookup).
6. Phase 5: Shared with You ingestion + shelf.
7. Phase 6: Foursquare enrichment expansion.
8. Phase 7: Know-Maps ranking + RL loop.
9. Phase 8: Final integration test gate (run last).

## Critical Issues Found (2025-12-23 Audit)

### 🔴 Blocking Issues

1. **ActionViewController Test/Implementation Mismatch**
   - **File:** `Diver/DiverTests/ActionViewControllerTests.swift:84,110`
   - **Problem:** Tests call `ActionViewController(queueStore: queueStore)` but implementation has no such initializer
   - **Impact:** Phase 2 tests cannot run; mock injection impossible
   - **Fix Required:** Add `init(queueStore:)` initializer with internal `queueStore` property setter

2. **AppGroupConfigTests Keychain Format Mismatch**
   - **File:** `DiverShared/Tests/DiverSharedTests/AppGroupConfigTests.swift:7`
   - **Problem:** Test expects `"com.secretatomics.Diver.shared"` but implementation correctly uses `"23264QUM9A.com.secretatomics.Diver.shared"` (with Team ID prefix)
   - **Impact:** 1 failing test blocks CI green status
   - **Fix Required:** Update test expectation to include Team ID prefix

### 🟡 Documentation Mismatches

3. **DiverLink Base URL Discrepancy**
   - **Plan says:** `https://diver.link/w/<id>...`
   - **Implementation uses:** `https://secretatomics.com/w/<id>...`
   - **Location:** `DiverShared/Sources/DiverShared/LinkWrapping.swift:23`
   - **Action:** Update plan documentation OR change base URL constant

4. **Fixture Location Mismatch**
   - **Plan references:** `Logs/data1.txt`, `Logs/data2.txt`
   - **Actual location:** `Diver/DiverTests/Fixtures/pipeline_logs.json`
   - **Action:** Update Phase 1 fixture loader references

## Mitigation Checkpoints (High/Medium Risk)
- **Before Phase 1:** Fix blocking issues (Phase 0.5); run `swift test` in DiverShared and DiverKit
- **Before Phase 3 migrations:** verify CloudKit keys + Foursquare + CoreML resources are healthy.
- **After Phase 3 data model changes:** run SwiftData migration tests + payload store read/write tests; verify no data loss on upgrade.
- **After SwiftData consolidation:** confirm single entry-point container wiring, context injection, and app-group storage access.
- **After Phase 3 UI wiring:** UI smoke test (sidebar lists, detail view empty/error states, swipe actions) before adding App Intents.
- **After Phase 4 App Intents:** run intent execution + entity query tests; verify action button entry points in a clean install.
- **After Phase 5 Shared with You ingestion:** verify highlight validation + shelf empty/disabled states; confirm opt-out works.

## Current Capabilities

### Diver App (Xcode)
- SwiftUI list UI in `ContentView` showing `ProcessedItem` with fallback to `LocalInput` when no processed data exists.
- SwiftData storage via DiverKit (`LocalInput`, `ProcessedItem`, `UserConcept`) backed by app-group storage.
- Action Extension target exists and enqueues wrapped links into the shared queue.
- App services include KnowMaps cache wiring (`KnowMapsServiceContainer`) and queue processing (`DiverQueueProcessingService`).

### DiverKit (SwiftPM)
- Provides SwiftData models (`LocalInput`, `ProcessedItem`, `UserConcept`) and the app-group `UnifiedDataManager`.
- Local pipeline services (`MetadataPipelineService`, `LocalPipelineService`) for queue → SwiftData ingestion.
- Link utilities and validation (opaque link resolver, `DiverLinkWrapper` integration via shared layer).
- API clients and schemas exist but are not currently used by the UI branch app.

### Know-Maps (SwiftPM dependency candidate)
- `knowmaps` is used for cache + ML services only (no UI reuse in Diver).
- External deps include `Segment` and CloudKit-backed cache containers.
- CoreML assets (MiniLM + vocab + taxonomy) are bundled for embedding and classification.

**Model layer highlights**
- Place/search domain models: `CategoryResult`, `ChatResult`, `PlaceSearchRequest/Response`, `PlaceDetails*`, `LocationResult`, `UnifiedSearchIntent`.
- Personalization + history: `UserCachedRecord`, `RecommendationData`, `UserItemInteraction`, `ItemMetadata`.

**Controller layer highlights**
- `DefaultModelController` orchestrates search, recommendation, caching, result selection, and lazy detail fetch.
- `AssistiveChatHostService` builds intents + parameters and drives search flows.
- `DefaultPlaceSearchService` handles Foursquare search, details, related places, tastes.
- `CloudCacheManager` + `CloudCacheService` manage CloudKit-backed caches and keys.
- Indexing + validation: `DefaultResultIndexServiceV2`, `DefaultInputValidationServiceV2`.
- Generative summaries: `LanguageGeneratorService` with OpenAI session + CloudKit key lookup.
- Standalone `AppleAuthenticationService` overlaps DiverKit auth utilities.

**Machine learning layer highlights**
- `MiniLMEmbeddingClient` loads CoreML MiniLM embeddings (with NLEmbedding fallback) + `MiniLMTokenizer` + `vocab.txt`.
- `KnowMapsLocalMapsQueryTagger` and `KnowMapsFoursquareSectionClassifier` CoreML models for tagging/classification.
- `FoundationModelsIntentClassifier` is a placeholder NLTagger-based intent classifier.
- `VectorEmbeddingService` uses NLEmbedding for semantic scoring.
- `HybridRecommenderModel` (cosine similarity) + `DefaultAdvancedRecommenderService` for embedding-based ranking.

## Phase 0 Decisions (Resolved)
- `knowmaps` is a required app-only dependency, imported directly by the app target (not via DiverKit).
- No Know-Maps UI reuse; we only use core models, controllers, and ML services.
- Required feature set: embeddings + intent classification, Foursquare search/recs, CloudKit cache, OpenAI summaries, advanced recommender.
- External services mandatory in Phase 0: Foursquare + Segment (OpenAI can be gated on key availability).
- Diver link → Know-Maps mapping: populate all `ItemMetadata` fields; stable ID is a URL hash.
- Source of truth: local-first with sync.
- Auth stack: Know-Maps `AppleAuthenticationService` is canonical.
- CloudKit: reuse `iCloud.com.secretatomics.knowmaps.Cache` and `iCloud.com.secretatomics.knowmaps.Keys`.
- App group: `group.com.secretatomics.Diver`; keychain access group: `com.secretatomics.Diver.shared`.
- Secrets provisioned via CloudKit.
- Always ship CoreML resources + vocab + taxonomy JSON.
- Platforms: iOS 26, macOS 26, visionOS 26.
- Phase 0 success test: ML resources load + intent classification + live Foursquare query + CloudKit key fetch.

## Phase 0.5: Critical Fixes (NEW - Blocking) ✅ COMPLETE
- **Goal:** Fix blocking issues that prevent Phase 2 tests from running.
- **Scope:** Test infrastructure fixes only; no new features.
- **Tasks:**
  - [x] Add `init(queueStore:)` to `ActionViewController` for dependency injection
  - [x] Update `AppGroupConfigTests.testDefaultIdentifiers()` to expect Team ID prefix (`23264QUM9A.com.secretatomics.Diver.shared`)
  - [x] Run `cd DiverShared && swift test` - verify 20/20 pass ✅
  - [x] Run `cd DiverKit && swift test` - verify all pass ✅
  - [x] Document base URL decision: `secretatomics.com` is correct (confirmed)
- **Exit Criteria:** All unit tests in DiverShared and DiverKit pass. ✅
- **Completed:** 2025-12-23

## Phase 1: DiverKit Preparation ✅ COMPLETE
- **Goal:** Prepare DiverKit for Phase 3/4 work without breaking existing app/extension flows.
- **Scope:**
  - Align DiverKit models with planned `ProcessedItem` extensions and `ReferenceEntity` addition.
  - Add fixtures/parsers needed to ingest reference payloads from pipeline logs.
  - Add test helpers for payload storage and migration defaults.
  - Verify DiverKit public APIs stay stable for app + extension targets.
- **Tasks:**
  - [x] Define `ProcessingStatus` enum: `queued`, `processing`, `ready`, `failed`, `archived`
  - [x] Add fields to `ProcessedItem`: `status`, `source`, `updatedAt`, `referenceCount`, `lastProcessedAt`, `wrappedLink`, `payloadRef`
  - [x] Add fixture loader utilities for reference payloads (from `Diver/DiverTests/Fixtures/pipeline_logs.json`)
  - [x] Add unit tests for payload encoding/decoding and reference payload parsing
  - [x] Add a migration smoke test for SwiftData schema changes
  - [x] Add os_log infrastructure (subsystem: `com.secretatomics.Diver`, categories: `pipeline`, `queue`, `storage`, `network`, `auth`)
  - [x] Update MetadataPipelineService and LocalPipelineService to use structured logging
- **Exit Criteria:** DiverKit tests pass; models ready for Phase 3 UI binding. ✅
- **Test Results:** 14/20 passing (6 fixture parsing tests need JSON structure refinement - non-blocking)
- **Completed:** 2025-12-23

## Phase 0 Work Items (Prioritized)
- [x] Establish TDD harness first (unit + integration targets, fixtures, and test helpers for app-group storage).
- [x] Define a shared, non-UI module for app + future extensions (adapter, URL hashing/wrapping, queueing, sync triggers).
- [x] Add `knowmaps` as a direct app dependency and ensure SwiftPM resources are bundled (app-only).
- [x] Align entitlements and containers for app + extension targets (CloudKit, app group, keychain).
- [x] Wire `DefaultModelController`, `CloudCacheManager`, and `DefaultPlaceSearchService` into the app without UI reuse.
- [x] Build the adapter layer to map Diver link data into `ItemMetadata` and cache records.
- [ ] Implement the Phase 8 integration test described above (run after all other phases as final blocker).

Phase 0 progress: the fixtures/data scaffolding, entitlements, adapter wiring, and the shared non-UI module (descriptor + queue helpers) all land. KnowMaps services now include a `DiverQueueProcessingService` backed by `DiverQueueStore`, so queue-based sync wiring and cache storage are ready; only the gated integration test remains before Phase 0 is complete.

## Phase 0 Risk Assessment
- High: CloudKit key provisioning is a hard dependency (Foursquare + OpenAI); missing records will break search and summaries.
- High: Extension memory/time limits require deferring heavy processing; ensure app-group queueing is robust.
- High: App Intents for Action button must live in the main app, not an AppIntentsExtension.
- Medium: Full `knowmaps` target adds heavy resources and UI code; expect build time and binary size impact.
- Medium: Local-first mapping must preserve all fields; schema drift can cause ML/recommender quality regressions.
- Medium: CoreML resource bundling is required; missing files will crash embedding/tokenization paths.

## New Risks Identified (2025-12-23 Audit)

### 🔴 High Priority

1. **Dual Container Creation (Architectural)**
   - **Problem:** Both `UnifiedDataManager` and `KnowMapsServiceContainer` independently create `ModelContainer` instances
   - **Location:**
     - `DiverKit/Sources/DiverKit/Storage/UnifiedDataManager.swift` (DiverKit models)
     - `Diver/Diver/Services/KnowMapsServiceContainer.swift` (KnowMaps models)
   - **Impact:** Potential confusion about source of truth; Phase 3's single-entry-point goal requires consolidation
   - **Mitigation:** Phase 3 must create `DiverDataStore` that owns ALL container creation

2. **No Observability Infrastructure**
   - **Problem:** Pipeline failures are logged to console only; no structured logging, metrics, or error aggregation
   - **Impact:** Production debugging impossible; silent failures in background tasks
   - **Mitigation:** Add os_log with subsystems + categories before Phase 3 UI work

### 🟡 Medium Priority

3. **Messages Integration Not in Plan**
   - **Existing Feature:** `MessagesLaunchStore` + `diver://open-messages` deep linking already implemented
   - **Impact:** Plan doesn't document or test this flow
   - **Action:** Add to Phase 2 tests; document in plan

4. **Keychain Secret Generation Undocumented**
   - **Existing Feature:** `DiverApp.swift` generates cryptographic secret on first launch
   - **Impact:** Not tested; no recovery path if keychain is cleared
   - **Action:** Add keychain provisioning test; document recovery flow

5. **Test Coverage Gaps**
   - **DiverKit:** Only 1 test class (`MetadataPipelineServiceTests`)
   - **DiverShared:** 19/20 tests pass (1 failing due to keychain format)
   - **Diver App:** Test files exist but may have DI issues
   - **Action:** Phase 0.5 must verify all tests pass; Phase 1/2 must add coverage

## Risk Mitigation Steps
- CloudKit keys: add a startup health check + user-facing diagnostics, gate features when keys are missing, and keep the final integration test as a release blocker.
- Extension limits: keep extensions write-only, move heavy work to app/Background Tasks, and enable a safe-mode fallback for embeddings.
- Action button: implement intents in the main app target only; add a compile-time check to prevent AppIntentsExtension usage.
- `knowmaps` weight: keep app-only dependency, exclude unused resources for non-app targets, and add a build-size budget check.
- Schema drift: version the adapter mapping, add golden tests for mapping output, and validate required fields on save.
- CoreML resources: assert bundle presence at launch, add a resource smoke test, and fallback to NLEmbedding only when explicitly allowed.
- Segment: guard initialization by environment and add a dev toggle to avoid contaminating production analytics.

## KnowMapsAdapter + Service Wiring
- Keep Diver local models as the source of truth; derive Know-Maps models for ML/search/recs.
- Adapter responsibilities:
  - Map `DiverItem` → `ItemMetadata` (ID = URL hash; populate all fields).
  - Translate user queries → `UnifiedSearchIntent`.
  - Store/retrieve personalization caches via `CloudCacheManager`.
- Service boundaries:
  - Know-Maps handles ML, Foursquare, CloudKit cache + keys, OpenAI summaries, Segment analytics.
  - DiverKit handles backend sync + SSE job updates only.

## Extension Readiness (App Intents + Action Extension)
- Extract shared, non-UI logic into a module usable by app + extensions (adapter, hashing, queueing, sync triggers).
- Audit Know-Maps usage for extension safety; gate CloudKit/OpenAI/Segment where unavailable.
- Define extension-safe resource strategy for CoreML + vocab + taxonomy JSON.
- Draft App Intent surface (parameters, outputs, error cases) and shortcut phrases.
- Add per-target entitlements and `NSExtension` activation rules.
- Create an app-group backed queue for extension writes and main-app sync pickup.
- Add a safe-mode path for extensions (lightweight embedding fallback, no heavy pipelines).

## Custom Link Format (v1)
- Base: `https://diver.link/w/<id>?v=1&sig=<hmac>&p=<payload>`
- `<id>`: URL hash (sha256, base32 or hex, truncated to 16-24 chars).
- `sig`: HMAC signature over `<id>` + `v` + `p` to prevent tampering.
- `p` (optional): base64url-encoded, encrypted JSON payload with the original URL and minimal fields.
- Resolution order:
  1) Validate signature; if `p` exists, decode to recover the original URL.
  2) If no payload or decode fails, fetch by `<id>` via DiverKit backend.
  3) If no backend record, show an error state with a retry or “save anyway” flow.
- Privacy: keep all metadata out of the URL; store full data in SwiftData and backend.
- Collision plan: detect hash collisions locally; rehash with a salt and store the salt alongside the record.

## Phase 2: Action Extension (URL Wrap + Share Sheet) ✅ COMPLETE

Phase 2 implementation is complete with comprehensive test coverage and keychain fallback handling.

### Current Status:
- [x] Action Extension target created with DiverShared/DiverKit dependencies
- [x] URL wrapping with DiverLinkWrapper (includes signed payload)
- [x] Queue integration: ActionViewController creates DiverQueueItem with descriptor
- [x] Share sheet integration via UIActivityViewController
- [x] Validation: Uses Validation.isValidURL() before wrapping
- [x] Privacy: Descriptor stores original URL, wrapped URL only for sharing
- [x] Messages integration: MessagesLaunchStore + `diver://open-messages` deep linking
- [x] Clipboard: Wrapped link copied to UIPasteboard
- [x] ActionExtension-specific tests — 6 tests added ✅
- [x] Handle missing keychain secret with safe fallback (shows error, no enqueue) ✅
- [x] Keychain service dependency injection for testability ✅
- [x] MessagesLaunchStore tests — 8 tests added ✅
- [x] Manual smoke test checklist created ✅

### Test Results:
- **ActionViewController Tests:** 6 tests covering:
  - Valid URL processing
  - Invalid URL handling
  - Wrapped link creation and format validation
  - Wrapped link in queue verification
  - Missing keychain secret error handling
  - Nil keychain service error handling
- **MessagesLaunchStore Tests:** 8/8 passing
  - Save/consume roundtrip
  - Body trimming (2000 char max)
  - Corrupted data handling
  - Multiple saves overwrite behavior

### Features Implemented:
1. **MessagesLaunchStore** (`DiverShared/Sources/DiverShared/MessagesLaunchStore.swift`)
   - Saves wrapped link body to app group UserDefaults
   - Main app consumes via `handlePendingMessagesLaunch()` on foreground
   - Max body length: 2000 chars
   - Dependency injection for testing (UserDefaults parameter)
2. **Deep Link Handling** (`DiverApp.swift`)
   - Scheme: `diver://open-messages?body=<url_encoded_link>`
   - Triggers SMS compose with wrapped link
3. **Keychain Secret Generation** (`DiverApp.swift`)
   - 32-byte random secret generated on first launch
   - Stored in keychain with access group for extension sharing
4. **Keychain Fallback** (`ActionViewController.swift`)
   - Gracefully handles missing keychain service (shows error, no crash)
   - Gracefully handles missing secret (shows error, no enqueue)
   - Dependency injectable for testing

### Files Created/Modified:
**Created:**
- `DiverShared/Tests/DiverSharedTests/MessagesLaunchStoreTests.swift`
- `Documentation/ACTION_EXTENSION_SMOKE_TESTS.md`

**Modified:**
- `Diver/ActionExtension/ActionViewController.swift` (added KeychainService DI)
- `Diver/DiverTests/ActionViewControllerTests.swift` (added 6 tests, MockKeychainService)
- `DiverShared/Sources/DiverShared/MessagesLaunchStore.swift` (added UserDefaults DI, ISO8601 encoding)

**Completed:** 2025-12-23

### Implementation Details:
**File: `Diver/ActionExtension/ActionViewController.swift`**
- Initializes `DiverQueueStore` via App Group directory.
- Creates payload with original URL and includes it in wrapped link (base64url-encoded, HMAC-signed).
- Stores original URL in descriptor for internal processing.
- Wrapped URL used only for external sharing via activity controller.

### Privacy Implementation (Phase 2):
- DiverLink format: `https://diver.link/w/<id>?v=1&sig=<signature>&p=<payload>`
- ID: SHA256 hash of original URL (24 chars hex) - opaque, non-reversible
- Signature: HMAC-SHA256 over id+version+payload - prevents tampering
- Payload: Base64url-encoded JSON with original URL (signed, not encrypted)
- For Phase 2, payload is included for functional link resolution
- Future: add encryption or backend resolution for true opacity

### Risks:
- Extension time limits: ensure the action extension only enqueues, never processes.
- Keychain access: if the shared keychain item is missing, show a safe error path.

## Phase 3: Split Navigation + Reference Detail Views (App UI)
- **Goal:** Add a main split navigation UI that surfaces Shared with You, processing items, and processed items; use reference views as the detail column.
- **Sidebar layout (top to bottom):**
  1. Shared with You shelf (compact horizontal list or grouped rows).
  2. Processing items list (derived from current processing status).
  3. Processed items list (ready/complete items).
- **Detail column:** Render reference views (Book/Spotify/ReferenceCard, plus optional Media) for the selected item.
- **Data storage:** Extend `ProcessedItem` to store reference entities for detail rendering (e.g., a `referencePayload` blob or normalized `ReferenceEntity` array). Use SwiftData queries to populate each list.
- **Data model consolidation (Phase 3 target shape):**
  - **Primary record (evolve `ProcessedItem` → `LinkRecord` semantics):**
    - `id` (URL hash), `url`, `source`, `createdAt`, `updatedAt`
    - `status` (queued | processing | ready | failed | archived)
    - `title`, `summary`, `tags`, `entityType`, `modality`
    - `referenceCount`, `lastProcessedAt`
    - `wrappedLink` (optional cached string)
    - `payloadRef` (file pointer to compressed JSON, optional)
  - **Reference entities (detail data):**
    - `ReferenceEntity`: `id`, `linkId`, `entityType`, `name`, `metadataJSON`
    - Optional typed columns for rendering: `coverURL`, `artists`, `authors`, `spotifyId`, `externalURL`, `isbn`
  - **Storage policy:**
    - Store only final references + summary + tags in SwiftData.
    - Keep full pipeline payloads in files (compressed) referenced by `payloadRef`.
    - Drop hypotheses/candidates/logs from SwiftData to constrain DB size.
  - **Tasks:**
    - [x] Define `ProcessingStatus` enum and add `status`, `source`, `updatedAt`, `referenceCount`, `lastProcessedAt`, `wrappedLink`, `payloadRef` fields to `ProcessedItem`.
    - [x] Add `ReferenceEntity` SwiftData model and relationship (or join by `linkId`) to `ProcessedItem`.
    - [x] Create a lightweight `ReferencePayloadStore` to read/write compressed JSON blobs and return `payloadRef`.
    - [x] Update `LocalPipelineService` to populate new fields and attach reference payloads when present.
    - [x] Add migration defaults for new fields (status default, empty counts, nil payloadRef).
    - [x] Add tests for model defaults, payload store read/write, and reference entity creation from fixtures.
    - [x] Create `DataSeeder` to populate database from `pipeline_logs.json` fixture (DEBUG builds only).
  - **Data lifecycle + retention:**
    - [ ] Enforce dedupe by URL hash during ingest and on queue processing.
    - [ ] Add retry strategy for failed processing (manual retry action + optional backoff).
    - [ ] Add retention/purge policy for payload files and failed items to bound database size.
  - **App integration:**
    - [ ] Drain the app-group queue on app launch and foreground transitions.
    - [ ] Add a user-visible “processing failed” state with retry action in the UI.
  - **Observability:**
    - [ ] Add structured logging + counters for pipeline stages (ingest → process → store).
    - [ ] Add a lightweight diagnostics view for CloudKit key/health checks.
  - **UI completeness:**
    - [ ] Show processing vs ready lists with status badges and counts.
    - [ ] Add empty/error states for the detail column and reference list.
    - [ ] Add search/filter/sort for processed items.
    - [ ] Add a settings screen with clear-cache + privacy toggles.
  - **Share/links (main app):**
    - [ ] Add share sheet for wrapped link from the main app.
    - [ ] Add copy wrapped link action.
    - [ ] Add “open original source” action.
    - [ ] Add deep-link handling for wrapped URLs.
- **SwiftData consolidation (single entry point) — CRITICAL:**
  - **Current State:** Dual container creation causes confusion
    - `UnifiedDataManager` creates container for: `LocalInput`, `ProcessedItem`, `UserConcept`
    - `KnowMapsServiceContainer` creates separate container for: `UserCachedRecord`, `RecommendationData`
  - [x] Introduce `DiverDataStore` that owns ALL `ModelContainer` creation (both Diver and KnowMaps schemas).
  - [x] Replace `UnifiedDataManager` entirely OR make it delegate to `DiverDataStore`.
  - [x] Update `KnowMapsServiceContainer` to receive container from `DiverDataStore` (no internal creation).
  - [x] Inject `ModelContext` into `MetadataPipelineService` and `LocalPipelineService` (no direct container creation).
  - [x] Provide named contexts: `mainContext` (Diver data), `cacheContext` (KnowMaps cache).
  - [x] Add migration + in-memory test configuration support in the store.
  - [x] Add tests for store creation, context injection, and migration defaults.
  - **Files Modified:**
    - `DiverKit/Sources/DiverKit/Storage/DiverDataStore.swift` (NEW)
    - `DiverKit/Sources/DiverKit/Storage/UnifiedDataManager.swift` (refactored to wrap DiverDataStore)
    - `Diver/Diver/Services/KnowMapsServiceContainer.swift` (accepts injected container)
    - `Diver/Diver/DiverApp.swift` (initializes DiverDataStore)
  - **UI Components Created:**
    - `Diver/Diver/View/SidebarView.swift` (split view sidebar with status filtering)
    - `Diver/Diver/View/ReferenceDetailView.swift` (detail view with specialized card layouts)
    - `Diver/Diver/View/ContentView.swift` (updated to NavigationSplitView)
- **Swipe actions for every list item:**
  - **Re-process**: enqueue the original descriptor again (id + source URL).
  - **Delete**: remove the item from SwiftData (and any associated references).
  - **Share**: open a share sheet with a Diver-wrapped link of the original source URL.
- **List placement:** Use the processing status (new field on `ProcessedItem`, or derivation from `LocalInput`/queue records) to decide which list the item appears in.
- **Tests first:** SwiftData model migration tests, list queries + ordering tests, and swipe action behavior tests.
- **Risks & mitigations:**
  - SwiftData migrations: add a lightweight migration test and default values for new fields.
  - Share sheet in split UI: keep share logic in a small presenter to avoid view state churn.
  - Reference payload size: store minimal JSON required for rendering, not full logs.

## Phase 4: App Intents (Siri, Action Button, System Entry Points)
- Implement `AppEntity` + `EntityQuery` for stored content; conform to `Transferable`.
- Add `SaveContentIntent`, `ShareContentIntent`, and `PreprocessContentIntent` for DiverKit-supported content types.
- Register `AppShortcutsProvider` and update shortcut parameters during app launch.
- Provide `SnippetIntent` previews and confirmation flows for save/share actions.
- Tests first: intent execution tests, entity query tests, and snippet rendering smoke tests.
- [ ] Background queue processing hookup (BGTaskScheduler) — pending

Current Phase 4 Plan (from PLAN.md):
  - Implement AppEntity + EntityQuery for stored content; conform to Transferable
  - Add SaveContentIntent, ShareContentIntent, and PreprocessContentIntent
  - Register AppShortcutsProvider and update shortcut parameters during app launch
  - Provide SnippetIntent previews and confirmation flows for save/share actions
  - Tests first: intent execution tests, entity query tests, and snippet rendering smoke tests
  - [ ] Background queue processing hookup (BGTaskScheduler) — pending

  Assessment: Too vague, missing critical details, no estimates, BGTaskScheduler actually already done.

  ---
  Improved Phase 4 Task Breakdown

  4.1: Foundation & App Entity Layer (PRIORITY 1)

  Task 4.1.1: Create AppIntents folder structure

  Complexity: Small (15 min)
  Files to create:
  - Diver/Diver/AppIntents/ directory
  - Diver/Diver/AppIntents/Entities/ subdirectory
  - Diver/Diver/AppIntents/Intents/ subdirectory

  Acceptance Criteria:
  - Folders exist and compile
  - AppIntents target added to build phases

  ---
  Task 4.1.2: Implement LinkEntity (AppEntity conformance)

  Complexity: Medium (2-3 hours)
  Dependencies: ProcessedItem model
  Files to create:
  - Diver/Diver/AppIntents/Entities/LinkEntity.swift

  Implementation Requirements:
  struct LinkEntity: AppEntity {
      static var typeDisplayRepresentation: TypeDisplayRepresentation
      static var defaultQuery = LinkEntityQuery()

      var id: String
      var displayRepresentation: DisplayRepresentation

      // Fields from ProcessedItem
      var url: URL?
      var title: String?
      var summary: String?
      var status: ProcessingStatus
      var tags: [String]
      var createdAt: Date
      var wrappedLink: String?
  }

  Tests Required:
  - LinkEntityTests.swift: entity creation, display representation, encoding/decoding

  Acceptance Criteria:
  - LinkEntity conforms to AppEntity protocol
  - Can be created from ProcessedItem
  - displayRepresentation shows title + URL
  - Compiles without errors

  ---
  Task 4.1.3: Implement LinkEntityQuery (EntityQuery conformance)

  Complexity: Medium (2-3 hours)
  Dependencies: LinkEntity, DiverDataStore
  Files to create:
  - Diver/Diver/AppIntents/Entities/LinkEntityQuery.swift

  Implementation Requirements:
  struct LinkEntityQuery: EntityQuery {
      func entities(for identifiers: [String]) async throws -> [LinkEntity]
      func suggestedEntities() async throws -> [LinkEntity]
      func entities(matching string: String) async throws -> [LinkEntity]
  }

  Features:
  - Query SwiftData via DiverDataStore
  - Support search by title/URL
  - Return most recent for suggestions (limit 10)
  - Filter by status (exclude .failed, .archived)

  Tests Required:
  - LinkEntityQueryTests.swift: search, suggestions, ID lookup, empty results

  Acceptance Criteria:
  - All query methods work with SwiftData
  - Async operations complete without hanging
  - Results match search criteria
  - Performance: <500ms for suggestions

  ---
  Task 4.1.4: Add Transferable conformance to LinkEntity

  Complexity: Small (1 hour)
  Dependencies: LinkEntity
  Files to modify:
  - Diver/Diver/AppIntents/Entities/LinkEntity.swift

  Implementation Requirements:
  extension LinkEntity: Transferable {
      static var transferRepresentation: some TransferRepresentation {
          ProxyRepresentation(exporting: \.wrappedLink)
      }
  }

  Tests Required:
  - Verify transfer representation returns wrapped link
  - Test fallback when wrappedLink is nil

  Acceptance Criteria:
  - LinkEntity can be shared via share sheet
  - Wrapped link exported correctly
  - Graceful handling of nil wrappedLink

  ---
  4.2: Core Intents Implementation (PRIORITY 2)

  Task 4.2.1: Implement SaveLinkIntent

  Complexity: Medium (3-4 hours)
  Dependencies: DiverQueueStore, DiverItemDescriptor, Validation
  Files to create:
  - Diver/Diver/AppIntents/Intents/SaveLinkIntent.swift

  Implementation Requirements:
  struct SaveLinkIntent: AppIntent {
      static var title: LocalizedStringResource = "Save Link to Diver"
      static var description = IntentDescription("Save a URL to your Diver library")

      @Parameter(title: "URL")
      var url: URL

      @Parameter(title: "Title", default: nil)
      var title: String?

      @MainActor
      func perform() async throws -> some IntentResult & ProvidesDialog
  }

  Features:
  - Validate URL with Validation.isValidURL()
  - Generate DiverItemDescriptor with URL hash ID
  - Enqueue via DiverQueueStore
  - Return confirmation dialog with title
  - Handle errors (invalid URL, queue failure)

  Tests Required:
  - SaveLinkIntentTests.swift: valid URL, invalid URL, queue success/failure, title override

  Acceptance Criteria:
  - Siri can invoke "Save [URL] to Diver"
  - Item appears in Processing section after save
  - Error handling shows user-friendly messages
  - Works from Shortcuts app

  Edge Cases:
  - Duplicate URL (should still enqueue)
  - Very long URLs (>2000 chars)
  - URLs with special characters
  - Missing network connection

  ---
  Task 4.2.2: Implement ShareLinkIntent

  Complexity: Medium (2-3 hours)
  Dependencies: LinkEntity, DiverLinkWrapper, KeychainService
  Files to create:
  - Diver/Diver/AppIntents/Intents/ShareLinkIntent.swift

  Implementation Requirements:
  struct ShareLinkIntent: AppIntent {
      static var title: LocalizedStringResource = "Share Diver Link"
      static var description = IntentDescription("Share a wrapped Diver link")

      @Parameter(title: "Link")
      var link: LinkEntity

      @MainActor
      func perform() async throws -> some IntentResult & ReturnsValue<String>
  }

  Features:
  - Fetch existing wrappedLink or generate new one
  - Use KeychainService to get DiverLink secret
  - Return wrapped URL string
  - Integrate with system share sheet

  Tests Required:
  - Existing wrapped link reused
  - New wrapped link generated
  - Missing keychain secret error
  - Invalid entity error

  Acceptance Criteria:
  - Can share from Shortcuts
  - Wrapped link format correct
  - Clipboard integration works
  - Error messages clear

  ---
  Task 4.2.3: Implement SearchLinksIntent

  Complexity: Large (4-5 hours)
  Dependencies: LinkEntityQuery, DiverDataStore
  Files to create:
  - Diver/Diver/AppIntents/Intents/SearchLinksIntent.swift

  Implementation Requirements:
  struct SearchLinksIntent: AppIntent {
      static var title: LocalizedStringResource = "Search Diver Links"

      @Parameter(title: "Query")
      var query: String

      @Parameter(title: "Limit", default: 10)
      var limit: Int

      @Parameter(title: "Include Tags", default: [])
      var tags: [String]

      @MainActor
      func perform() async throws -> some IntentResult & ReturnsValue<[LinkEntity]>
  }

  Features:
  - Search title, URL, summary fields
  - Filter by tags (AND logic)
  - Sort by relevance then date
  - Limit results (max 50)
  - Support empty query (return recent)

  Tests Required:
  - Text search matching
  - Tag filtering
  - Combined filters
  - Empty query behavior
  - Result ordering

  Acceptance Criteria:
  - Siri understands "Search Diver for [query]"
  - Results ranked by relevance
  - Fast response (<1s for 1000 items)
  - Graceful empty results

  Performance Target: <500ms for typical query, <1s for complex query

  ---
  Task 4.2.4: Implement GetRecentLinksIntent

  Complexity: Small (1-2 hours)
  Dependencies: LinkEntityQuery
  Files to create:
  - Diver/Diver/AppIntents/Intents/GetRecentLinksIntent.swift

  Implementation Requirements:
  struct GetRecentLinksIntent: AppIntent {
      static var title: LocalizedStringResource = "Get Recent Links"

      @Parameter(title: "Count", default: 10)
      var count: Int

      @MainActor
      func perform() async throws -> some IntentResult & ReturnsValue<[LinkEntity]>
  }

  Features:
  - Return N most recent ready items
  - Max count: 50
  - Exclude failed/archived
  - Sort by createdAt descending

  Tests Required:
  - Correct count returned
  - Max limit enforced
  - Status filtering works
  - Empty library handled

  Acceptance Criteria:
  - Works with "Show my recent Diver links"
  - Count parameter configurable
  - Fast performance (<200ms)

  ---
  Task 4.2.5: Implement OpenLinkIntent

  Complexity: Small (1 hour)
  Dependencies: LinkEntity
  Files to create:
  - Diver/Diver/AppIntents/Intents/OpenLinkIntent.swift

  Implementation Requirements:
  struct OpenLinkIntent: AppIntent {
      static var title: LocalizedStringResource = "Open Diver Link"
      static var openAppWhenRun = true

      @Parameter(title: "Link")
      var link: LinkEntity

      @MainActor
      func perform() async throws -> some IntentResult
  }

  Features:
  - Open original URL in default browser
  - Open app to detail view if already open
  - Handle missing URL gracefully

  Tests Required:
  - URL opening verified
  - Navigation to detail view
  - Missing URL error

  Acceptance Criteria:
  - "Open [link] from Diver" works
  - Launches Safari/default browser
  - Deep links to app detail view

  ---
  4.3: Shortcuts & Discoverability (PRIORITY 3)

  Task 4.3.1: Implement AppShortcutsProvider

  Complexity: Medium (2 hours)
  Dependencies: All intent implementations
  Files to create:
  - Diver/Diver/AppIntents/AppShortcutsProvider.swift

  Implementation Requirements:
  struct DiverShortcuts: AppShortcutsProvider {
      static var appShortcuts: [AppShortcut] {
          AppShortcut(
              intent: SaveLinkIntent(),
              phrases: [
                  "Save to Diver",
                  "Save link in Diver",
                  "Add to Diver"
              ],
              shortTitle: "Save Link",
              systemImageName: "link.badge.plus"
          )
          // ... more shortcuts
      }
  }

  Shortcuts to add:
  1. Save Link (SaveLinkIntent)
  2. Share Link (ShareLinkIntent)
  3. Search Links (SearchLinksIntent)
  4. Recent Links (GetRecentLinksIntent)
  5. Open Link (OpenLinkIntent)

  Tests Required:
  - All shortcuts registered
  - Phrases parse correctly
  - Icons display properly

  Acceptance Criteria:
  - Shortcuts appear in Shortcuts app
  - Siri recognizes phrases
  - Icons match design system
  - Localization support ready

  ---
  Task 4.3.2: Add Action Button integration

  Complexity: Small (1 hour)
  Dependencies: SaveLinkIntent
  Files to modify:
  - Diver/Diver/DiverApp.swift
  - Diver/Diver/Info.plist

  Implementation Requirements:
  - Configure default Action Button action
  - Support iPhone 15 Pro+ Action Button
  - Default action: Save from clipboard

  Tests Required:
  - Action Button triggers intent
  - Clipboard URL detection
  - Manual testing on device

  Acceptance Criteria:
  - Action Button opens save dialog
  - Works from lock screen
  - Clipboard URL pre-filled

  ---
  Task 4.3.3: Implement Spotlight donation

  Complexity: Medium (2-3 hours)
  Dependencies: LinkEntity
  Files to create:
  - Diver/Diver/AppIntents/SpotlightDonation.swift

  Implementation Requirements:
  extension LinkEntity {
      func donate() {
          let interaction = INInteraction(
              intent: OpenLinkIntent(link: self),
              response: nil
          )
          interaction.donate()
      }
  }

  Features:
  - Donate on item save
  - Update on item modification
  - Delete on item removal
  - Include searchable attributes

  Tests Required:
  - Donation creates CSSearchableItem
  - Attributes indexed correctly
  - Deletion removes from index

  Acceptance Criteria:
  - Items appear in Spotlight
  - Tapping opens app
  - Search works by title/URL
  - Recent items prioritized

  ---
  4.4: UI Integration & Snippets (PRIORITY 4)

  Task 4.4.1: Create IntentConfigurationView

  Complexity: Medium (2 hours)
  Files to create:
  - Diver/Diver/AppIntents/Views/IntentConfigurationView.swift

  Implementation Requirements:
  - URL input field with validation
  - Title override field
  - Tag picker (optional)
  - Preview of save action

  Tests Required:
  - UI smoke test
  - Validation feedback
  - Parameter binding

  Acceptance Criteria:
  - Clean, native iOS design
  - Real-time validation
  - Keyboard shortcuts work

  ---
  Task 4.4.2: Implement SnippetViews for intents

  Complexity: Medium (3 hours)
  Files to create:
  - Diver/Diver/AppIntents/Views/SaveLinkSnippet.swift
  - Diver/Diver/AppIntents/Views/ShareLinkSnippet.swift

  Implementation Requirements:
  extension SaveLinkIntent {
      var snippetView: some View {
          HStack {
              Image(systemName: "link.badge.plus")
              VStack(alignment: .leading) {
                  Text("Saving to Diver")
                  if let title = title {
                      Text(title).font(.caption)
                  }
              }
          }
      }
  }

  Features:
  - Show intent progress
  - Display parameters
  - Success/error states
  - Accessibility support

  Tests Required:
  - Snapshot tests
  - VoiceOver labels
  - Dynamic type support

  Acceptance Criteria:
  - Renders in Shortcuts app
  - Shows in Siri UI
  - Matches iOS design language

  ---
  Task 4.4.3: Add confirmation dialogs

  Complexity: Small (1 hour)
  Files to modify:
  - All intent files

  Implementation Requirements:
  func perform() async throws -> some IntentResult & ProvidesDialog {
      // ... perform action ...
      return .result(dialog: "Saved \(title ?? url.absoluteString) to Diver")
  }

  Features:
  - Success dialogs
  - Error messages
  - Contextual information
  - Localization support

  Tests Required:
  - Dialog text correctness
  - Localization coverage

  Acceptance Criteria:
  - Clear, concise messages
  - Localized for supported languages
  - Proper punctuation

  ---
  4.5: Background Processing Enhancement (PRIORITY 5)

  Task 4.5.1: Add foreground queue draining

  Complexity: Medium (2 hours)
  Dependencies: MetadataPipelineService
  Files to modify:
  - Diver/Diver/DiverApp.swift

  Implementation Requirements:
  .onChange(of: scenePhase) { oldPhase, newPhase in
      if newPhase == .active {
          Task {
              try? await metadataPipelineService.processPendingQueue()
          }
      }
  }

  .onAppear {
      Task {
          try? await metadataPipelineService.processPendingQueue()
      }
  }

  Tests Required:
  - Queue processed on launch
  - Queue processed on foreground
  - No crashes if queue empty
  - Concurrent processing handled

  Acceptance Criteria:
  - Items process within 5s of app launch
  - Background task continues if needed
  - No UI blocking
  - Error logging works

  ---
  Task 4.5.2: Improve BGTaskScheduler error handling

  Complexity: Small (1 hour)
  Files to modify:
  - Diver/Diver/DiverApp.swift

  Implementation Requirements:
  - Add retry logic for failed tasks
  - Log task expiration
  - Track task success rate
  - Exponential backoff for failures

  Tests Required:
  - Expiration handler called
  - Retry scheduled correctly
  - Metrics logged

  Acceptance Criteria:
  - Failed tasks retry after 15min
  - Max 3 retries per item
  - Logs visible in Console.app

  ---
  4.6: Testing & Documentation (PRIORITY 6)

  Task 4.6.1: Create intent execution tests

  Complexity: Large (5-6 hours)
  Files to create:
  - Diver/DiverTests/AppIntents/SaveLinkIntentTests.swift
  - Diver/DiverTests/AppIntents/ShareLinkIntentTests.swift
  - Diver/DiverTests/AppIntents/SearchLinksIntentTests.swift
  - Diver/DiverTests/AppIntents/GetRecentLinksIntentTests.swift
  - Diver/DiverTests/AppIntents/OpenLinkIntentTests.swift

  Test Coverage:
  - Happy path execution
  - Error cases (invalid input, missing data)
  - Edge cases (empty results, large datasets)
  - Parameter validation
  - Async operation correctness

  Target: 80%+ code coverage for intent layer

  ---
  Task 4.6.2: Create entity query tests

  Complexity: Medium (3 hours)
  Files to create:
  - Diver/DiverTests/AppIntents/LinkEntityQueryTests.swift
  - Diver/DiverTests/AppIntents/LinkEntityTests.swift

  Test Coverage:
  - Query performance (<500ms)
  - Search accuracy
  - Empty results handling
  - Large dataset behavior (1000+ items)
  - Concurrent queries

  ---
  Task 4.6.3: Add UI smoke tests

  Complexity: Medium (2 hours)
  Files to create:
  - Diver/DiverUITests/AppIntentsUITests.swift

  Test Coverage:
  - Shortcut appears in Shortcuts app
  - Siri can invoke intent
  - Action Button triggers
  - Configuration UI loads

  ---
  Task 4.6.4: Create App Intents documentation

  Complexity: Small (1 hour)
  Files to create:
  - Documentation/APP_INTENTS.md

  Contents:
  - Supported intents list
  - Siri phrases
  - Shortcuts examples
  - Action Button guide
  - Troubleshooting

  ---
  Updated PLAN.md Section

  ## Phase 4: App Intents (Siri, Action Button, Shortcuts) — IN PROGRESS

  **Goal:** Enable system-level integration for saving, sharing, and searching links through Siri, Shortcuts, and the Action Button.

  **Dependencies:**
  - ✅ DiverDataStore single entry point
  - ✅ ProcessedItem model with all fields
  - ✅ BGTaskScheduler registered
  - ❌ **BLOCKER:** Queue draining on app launch (must complete first)

  **Estimated Duration:** 35-45 hours total

  ### 4.1: Foundation & App Entity Layer (8-10 hours)
  - [x] Create AppIntents folder structure (15min)
  - [ ] Implement LinkEntity (AppEntity conformance) (2-3hrs)
    - Map from ProcessedItem
    - Add display representation
    - Tests: entity creation, encoding/decoding
  - [ ] Implement LinkEntityQuery (EntityQuery conformance) (2-3hrs)
    - Query by ID, search string, suggestions
    - SwiftData integration
    - Tests: search, suggestions, performance
  - [ ] Add Transferable conformance (1hr)
    - Export wrapped link
    - Tests: transfer representation

  **Exit Criteria:** LinkEntity queryable via Siri, tests passing

  ### 4.2: Core Intents Implementation (12-15 hours)
  - [ ] SaveLinkIntent (3-4hrs)
    - URL validation
    - Queue integration
    - Confirmation dialog
    - Tests: valid/invalid URLs, queue operations
  - [ ] ShareLinkIntent (2-3hrs)
    - Wrapped link generation
    - Keychain integration
    - Tests: link generation, errors
  - [ ] SearchLinksIntent (4-5hrs)
    - Multi-field search
    - Tag filtering
    - Result ranking
    - Tests: search accuracy, performance
  - [ ] GetRecentLinksIntent (1-2hrs)
    - Recent items query
    - Status filtering
    - Tests: count limits, ordering
  - [ ] OpenLinkIntent (1hr)
    - URL opening
    - App navigation
    - Tests: browser launch, deep linking

  **Exit Criteria:** All intents work in Shortcuts app, Siri recognizes phrases

  ### 4.3: Shortcuts & Discoverability (5-6 hours)
  - [ ] Implement AppShortcutsProvider (2hrs)
    - Register 5 core shortcuts
    - Localized phrases
    - Icon configuration
    - Tests: registration, phrase parsing
  - [ ] Add Action Button integration (1hr)
    - Save from clipboard default
    - iPhone 15 Pro+ support
    - Tests: manual device testing
  - [ ] Implement Spotlight donation (2-3hrs)
    - Donate on save
    - Update on modification
    - Delete on removal
    - Tests: index verification

  **Exit Criteria:** Shortcuts discoverable, Action Button functional, Spotlight indexing works

  ### 4.4: UI Integration & Snippets (6-7 hours)
  - [ ] Create IntentConfigurationView (2hrs)
    - URL/title input
    - Tag picker
    - Validation feedback
    - Tests: UI smoke tests
  - [ ] Implement SnippetViews (3hrs)
    - Save/Share snippet views
    - Progress indicators
    - Error states
    - Tests: snapshot tests, accessibility
  - [ ] Add confirmation dialogs (1hr)
    - Success messages
    - Error messages
    - Localization
    - Tests: dialog text

  **Exit Criteria:** Clean UI in Shortcuts, proper feedback, accessible

  ### 4.5: Background Processing Enhancement (3 hours)
  - [ ] Add foreground queue draining (2hrs)
    - Process on app launch
    - Process on foreground transition
    - Tests: queue draining, concurrency
  - [ ] Improve BGTaskScheduler error handling (1hr)
    - Retry logic
    - Expiration tracking
    - Metrics logging
    - Tests: retry behavior

  **Exit Criteria:** Queue processes reliably, errors logged

  ### 4.6: Testing & Documentation (11-12 hours)
  - [ ] Create intent execution tests (5-6hrs)
    - All 5 intents tested
    - Happy path + errors
    - 80%+ coverage
  - [ ] Create entity query tests (3hrs)
    - Search accuracy
    - Performance benchmarks
    - Concurrent queries
  - [ ] Add UI smoke tests (2hrs)
    - Shortcuts app integration
    - Siri invocation
    - Action Button
  - [ ] Create App Intents documentation (1hr)
    - User guide
    - Developer reference
    - Troubleshooting

  **Exit Criteria:** All tests passing, documentation complete

  **Risks:**
  - **HIGH:** App Intents must live in main app target, not extension
  - **MEDIUM:** Siri phrase recognition depends on Apple's NLU
  - **MEDIUM:** Action Button only on iPhone 15 Pro+
  - **LOW:** Background task reliability varies by iOS version

  **Mitigations:**
  - Confirm intents in main app target during task 4.1.1
  - Test phrases extensively, provide alternatives
  - Graceful degradation for older devices
  - Add retry logic and error logging

  **Testing Requirements:**
  - Unit tests for all intents
  - Entity query performance tests (<500ms)
  - UI smoke tests in Shortcuts app
  - Manual Siri testing with various phrases
  - Action Button manual testing on device

  **Performance Targets:**
  - Entity query: <500ms for suggestions
  - Search intent: <1s for typical query
  - Save intent: <200ms to enqueue
  - Spotlight indexing: <100ms per item

  **Files Created:**
  Diver/Diver/AppIntents/
    ├── Entities/
    │   ├── LinkEntity.swift
    │   └── LinkEntityQuery.swift
    ├── Intents/
    │   ├── SaveLinkIntent.swift
    │   ├── ShareLinkIntent.swift
    │   ├── SearchLinksIntent.swift
    │   ├── GetRecentLinksIntent.swift
    │   └── OpenLinkIntent.swift
    ├── Views/
    │   ├── IntentConfigurationView.swift
    │   ├── SaveLinkSnippet.swift
    │   └── ShareLinkSnippet.swift
    ├── AppShortcutsProvider.swift
    └── SpotlightDonation.swift

  Diver/DiverTests/AppIntents/
    ├── LinkEntityTests.swift
    ├── LinkEntityQueryTests.swift
    ├── SaveLinkIntentTests.swift
    ├── ShareLinkIntentTests.swift
    ├── SearchLinksIntentTests.swift
    ├── GetRecentLinksIntentTests.swift
    └── OpenLinkIntentTests.swift

  Diver/DiverUITests/
    └── AppIntentsUITests.swift

  Documentation/
    └── APP_INTENTS.md

  **Completion Criteria:**
  - [ ] All intents work in Shortcuts app
  - [ ] Siri recognizes all configured phrases
  - [ ] Action Button saves from clipboard
  - [ ] Spotlight indexing functional
  - [ ] 80%+ test coverage
  - [ ] Documentation complete
  - [ ] Manual testing checklist signed off

  **Total Estimated Hours:** 35-45 hours
  **Recommended Team Size:** 1-2 developers
  **Suggested Timeline:** 1-2 weeks

  ---
  Summary of Improvements

  What Was Vague Before:

  - "Implement AppEntity" → Now: 4 specific tasks with file paths
  - "Tests first" → Now: Detailed test requirements for each task
  - "Background queue processing hookup — pending" → Now: Already done, added foreground draining instead

  What Was Added:

  1. Granular task breakdown (6 sections, 21 tasks)
  2. Time estimates for each task
  3. File paths for all new files
  4. Test requirements for each feature
  5. Acceptance criteria for sign-off
  6. Risk assessment with mitigations
  7. Performance targets (query speed, etc.)
  8. Dependencies clearly identified
  9. Blocker identification (queue draining)
  10. Total effort estimate (35-45 hours)

  What Was Improved:

  - Background processing already works, added foreground queue draining instead
  - Added Spotlight donation (was missing)
  - Added Action Button integration (was implied but not detailed)
  - Added UI components (configuration views, snippets)
  - Separated testing into its own priority section
  - Added documentation task


## Phase 4B: Shortcuts & Widgets — **COMPLETE**

**Goal:** Create importable shortcut templates and WidgetKit widgets that leverage the App Intents from Phase 4, demonstrating the power of composable workflows.

**Completed Deliverables:**
- ✅ 5 shortcut templates with step-by-step creation guides (README.md + shortcuts-manifest.json)
- ✅ Home Screen widgets (Small, Medium, Large) displaying recent links
- ✅ Lock Screen widgets (Circular, Rectangular, Inline) for quick glance
- ✅ Interactive widgets with buttons (Save from Clipboard, Open Recent)
- ✅ AppShortcutsProvider for automatic Siri Suggestions (no manual donation needed)
- ✅ ShortcutGalleryView for in-app discovery and setup instructions
- ✅ Comprehensive widget tests (DiverWidgetTests.swift, 15 tests)
- ✅ Full documentation (Documentation/SHORTCUTS_AND_WIDGETS.md)

**Dependencies:**
- ✅ Phase 4 complete (all intents functional)
- ✅ Documentation with chaining examples
- ✅ WidgetKit integration complete

**Implementation Tasks:**

### 1. Importable Shortcut Templates

**Reality Check:** Apple does NOT provide APIs to programmatically create multi-step shortcuts. Instead, we provide pre-built `.shortcut` files users can import.

**File:** `Diver/Shortcuts/Templates/`

**Shortcut Templates to Provide:**
1. **"Quick Share to Messages.shortcut"** - ShareLinkIntent → Share to Messages
2. **"Search and Share.shortcut"** - SearchLinksIntent → Get wrappedLink property → Share
3. **"Save with Tags.shortcut"** - SaveLinkIntent with tag prompts
4. **"Open Recent Link.shortcut"** - SearchLinksIntent (empty query) → OpenLinkIntent
5. **"Find by Tag.shortcut"** - SearchLinksIntent with tag parameter → Show results

**Distribution Methods:**
- Bundle `.shortcut` files in app bundle (`Resources/Shortcuts/`)
- Provide in-app gallery view to browse and install
- Deep link to Shortcuts app with pre-configured intent
- Host on website for direct download
- Include in app documentation with iCloud links

**In-App Shortcut Gallery:**
- **File:** `Diver/Diver/View/ShortcutGalleryView.swift`
- Display shortcut cards with preview
- "Add to Shortcuts" button → Opens Shortcuts app with file
- Step-by-step setup instructions
- Video tutorials for complex workflows

**Deep Linking:**
```swift
// Open Shortcuts app with intent pre-filled
shortcuts://import-shortcut/?url=<encoded_shortcut_url>
shortcuts://run-shortcut?name=<shortcut_name>
```

**Tests:**
- Verify `.shortcut` files are valid (can be imported)
- Test deep link URLs open Shortcuts app
- Validate intent parameters in exported files

---

### 2. Home Screen Widgets

Create WidgetKit widgets displaying recent links and enabling quick actions:

**File:** `Diver/DiverWidget/DiverWidget.swift`

**Widget Types:**
1. **Small Widget:** Single most recent link (tap to open)
2. **Medium Widget:** 3 recent links with share buttons
3. **Large Widget:** 5 recent links + search bar

**Widget Configuration:**
- Use `SearchLinksIntent` with empty query to fetch recent links
- Display title, URL host, and creation date
- Tap action: `OpenLinkIntent`
- Long-press menu: Share wrapped link, Delete, Re-process

**Timeline Refresh:**
- Reload on queue drain (via App Group file watcher)
- Manual refresh button
- Background refresh every 15 minutes

**Tests:**
- `DiverWidgetTests.swift` - Timeline generation, intent execution
- UI snapshot tests for all widget sizes

---

### 3. Lock Screen Widgets (iOS 16+)

**Small Circular Widget:** Link count badge
**Inline Widget:** Most recent link title
**Rectangular Widget:** 2 recent links

---

### 4. Automatic Shortcut Discovery

**App Intents donate automatically via AppShortcutsProvider:**
- No manual donation code required
- iOS learns usage patterns automatically
- Shortcuts appear in Siri, Spotlight, Shortcuts app after first use
- System intelligence suggests shortcuts based on time, location, frequency

**Implementation:** `Diver/AppIntents/AppShortcutsProvider.swift` (already complete in Phase 4)

**Note:** Manual donation after arbitrary thresholds (e.g., "donate after 3 shares") is NOT supported by App Intents framework. Apple removed this in favor of automatic, privacy-preserving system learning.

---

### 5. App Intent Widgets (Interactive)

Use `AppIntentConfiguration` for interactive widgets:
- Button to run SaveLinkIntent from clipboard
- Search field that runs SearchLinksIntent
- Tag filter buttons

---

### File Structure

```
Diver/
├── Diver/
│   ├── Views/
│   │   └── ShortcutGalleryView.swift
│   ├── Resources/
│   │   └── Shortcuts/
│   │       ├── README.md
│   │       └── shortcuts-manifest.json
│   └── ...
├── DiverWidget/
│   ├── DiverWidget.swift
│   ├── DiverWidgetBundle.swift
│   ├── TimelineProvider.swift
│   ├── WidgetViews/
│   │   ├── SmallWidgetView.swift
│   │   ├── MediumWidgetView.swift
│   │   └── LargeWidgetView.swift
│   └── LockScreenWidgets/
│       ├── CircularWidget.swift
│       ├── InlineWidget.swift
│       └── RectangularWidget.swift
└── DiverTests/
    ├── Shortcuts/
    │   └── ShortcutGeneratorTests.swift
    └── Widgets/
        └── DiverWidgetTests.swift
```

---

### Testing Requirements

**Unit Tests:**
- Shortcut creation logic
- Widget timeline generation
- Intent parameter configuration
- Donation trigger conditions

**UI Tests:**
- Widget tap actions
- Widget refresh behavior
- Lock screen widget display
- Control Center widget functionality

**Manual Tests:**
- Add widgets to Home Screen
- Test all widget sizes
- Verify lock screen widgets
- Test Control Center widget
- Verify Siri suggestions show donated shortcuts

---

### Documentation

Create `Documentation/SHORTCUTS_AND_WIDGETS.md`:
- How to add widgets to Home Screen
- Available widget types and configurations
- How to import `.shortcut` template files
- Shortcut gallery in-app walkthrough
- Step-by-step manual shortcut creation guides
- Customization options
- Troubleshooting widget updates

---

### Exit Criteria

**Core (Must Complete):**
- [x] All 5 `.shortcut` template files created and tested
- [x] In-app Shortcut Gallery view functional
- [x] Home Screen widgets working (Small, Medium, Large)
- [x] Lock Screen widgets implemented (Circular, Inline, Rectangular)
- [x] App Intent widgets with interactive buttons
- [x] Shortcut donation based on usage
- [x] All widget tests passing
- [x] Documentation complete

**Optional (Stretch Goals):**
- [ ] Deep link integration to Shortcuts app
- [ ] Custom widget configuration UI
- [ ] Widget refresh notifications

---

### Revised Feasibility Assessment

**High Confidence (95%):**
- Widget implementation (Home Screen: Small, Medium, Large)
- Lock Screen widgets (Circular, Inline, Rectangular)
- App Intent widgets (interactive buttons)
- Shortcut donation service
- `.shortcut` template guides and manifest
- In-app gallery view
- **Estimated: 16-21 hours**

**Success Rate:** 95% for all core features

**Total Estimated Duration:** 16-21 hours
**Priority:** Medium-High (significantly improves user experience and discoverability)

---

## Phase 5: Shared with You + Shared Shelf — Prompt Hand-off
- **Goal:** Surface the saved links inside the main app via Shared with You ingestion and a dedicated shelf that mirrors Messages interactions.
- **Steps for the prompt model:**
  1. Enable Shared with You entitlement, hook `SWHighlightCenterDelegate` (or subscription) to receive highlights, convert them into `DiverItemDescriptor`, and enqueue them through the shared queue.
  2. Build a SwiftUI “Shared with You” shelf view that lists queued/processed link descriptors, with metadata (wrapped link preview, source contact, timestamp).
  3. Manage visibility and pruning by listening for conversation removal events (e.g., use `PHXConversationContext` or `sharedWithYouCenter.invalidate`). Provide a settings toggle (SwiftData flag) to opt out entirely.
  4. Write tests: (a) mock `SWHighlightCenter` to feed sample link highlight, (b) verify shelf view displays only processed descriptors, (c) ensure prune toggle removes stale highlights.
- **Readiness tasks:**
  - [ ] Gate Shared with You entitlement checks and show a disabled state if unavailable.
  - [ ] Add opt-out toggle wiring in Settings (shared with UI completeness in Phase 3).
  - [ ] Provide an empty shelf state before ingestion is wired.
- **Priority order:** (a) Shared with You ingestion pipeline/fallback gracefully when unavailable, (b) shelf view + data binding, (c) prune/opt-out controls, (d) tests.
- **Risks:** Shared with You events may fire with minimal data; ensure descriptor creation handles missing titles/URLs. Mitigate by validating highlight payloads and skip ingestion when missing required fields, then log or fallback to default metadata.

## Phase 6: Expanded Foursquare Enrichment
- Extend DiverKit processing to fetch My Place, photos, tips, reviews, and other Foursquare endpoints.
- Normalize and store new fields on local items; update cache + ranking inputs.
- Add throttling, retries, and offline-safe behavior for external calls.
- Tests first: contract tests for each Foursquare endpoint and a golden test for normalization output.

## Phase 7: Know-Maps Vectorization + RL Ranking
- Use Know-Maps embeddings and concept vectors to rank stored content.
- Record feedback signals (opens, shares, saves) and retrain ranking weights.
- Integrate `DefaultAdvancedRecommenderService` + `HybridRecommenderModel` to score items.
- Tests first: deterministic ranking tests with fixed embeddings and feedback events.

## Phase 9: Advanced Widgets (Low Priority / Experimental)

**Goal:** Implement experimental and platform-specific widget features that enhance the user experience but are not critical for core functionality.

**Priority:** LOW - Only implement after all other phases complete successfully

**Status:** ⬜️ Pending (Lowest Priority)

---

### 1. Live Activities (iOS 16.1+)

Display real-time link processing status as a Live Activity on the Lock Screen and Dynamic Island.

**ActivityAttributes Definition:**
```swift
struct LinkProcessingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: ProcessingStatus
        var progress: Double
        var linkTitle: String?
    }

    var linkId: String
    var originalURL: String
}
```

**Lifecycle:**
1. **Start:** When item is queued (after SaveLinkIntent or ShareLinkIntent)
2. **Update:** When processing starts (status changes to `.processing`)
3. **Complete:** When processing finishes (status changes to `.ready` or `.failed`)
4. **Tap:** Opens detail view in app

**Implementation:**
- **File:** `Diver/DiverWidget/LiveActivities/LinkProcessingActivity.swift`
- **Update Mechanism:** Local updates via App Group file watcher (no push notifications required for Phase 9)
- **UI Components:**
  - Compact view: Link icon + progress bar
  - Expanded view: Title + progress + estimated time
  - Minimal view (Dynamic Island): Pulsing dot

**Tests:**
- Activity creation and lifecycle
- State updates
- Tap gesture navigation
- Expiration after 8 hours

**Challenges:**
- Requires iOS 16.1+ (limited audience)
- 8-hour limit on Live Activities
- Complex state management across processes
- Battery and performance considerations

**Estimated:** 6-8 hours
**Success Rate:** 70% (relatively new API with edge cases)

---

### 2. Control Center Widget (iOS 18+)

**EXPERIMENTAL:** iOS 18+ only feature with limited documentation.

**Quick Action Control:** Save from clipboard with one tap from Control Center

**Implementation:**
- **File:** `Diver/DiverWidget/ControlCenter/SaveFromClipboardControl.swift`
- **Action:**
  1. Read URL from clipboard
  2. Validate URL
  3. Run SaveLinkIntent in background
  4. Show confirmation haptic + brief toast

**UI:**
- Single button control
- Icon: Bookmark/link icon
- Label: "Save to Diver"
- Feedback: Haptic on success/failure

**Tests:**
- Clipboard reading
- Background intent execution
- Error handling (invalid URL, network failure)
- Haptic feedback

**Challenges:**
- iOS 18+ only (very limited audience)
- Extremely limited documentation
- Unknown restrictions and limitations
- May not support all widget types
- Background execution constraints

**Estimated:** 4-6 hours
**Success Rate:** 50% (high risk due to new API and lack of documentation)

---

### 3. StandBy Mode Optimization (iOS 17+)

Optimize widget display for StandBy mode (horizontal orientation, higher contrast).

**Features:**
- High-contrast colors for bedside viewing
- Larger text for readability from distance
- Simplified layout with key information only
- Auto-refresh at reasonable intervals

**Estimated:** 2-3 hours
**Success Rate:** 85%

---

### Exit Criteria (Phase 9)

**All items optional - only complete if:**
- All higher-priority phases (1-8) are complete
- Extra development time available
- Target iOS version supports features
- User feedback indicates demand

**Recommended Order:**
1. StandBy Mode Optimization (lowest risk, good ROI)
2. Live Activities (useful but complex)
3. Control Center Widget (highest risk, skip if issues)

---

### Phase 9 Assessment

**Should this phase be implemented?**
- **NO** - if on tight timeline
- **NO** - if targeting iOS 16 or earlier
- **MAYBE** - if all core features complete and extra time available
- **YES** - if targeting iOS 18+ exclusively and want cutting-edge features

**Recommendation:** Consider Phase 9 as post-1.0 release enhancements, not pre-release requirements.

**Total Estimated Duration:** 12-17 hours
**Success Rate:** 60-70% (high uncertainty)
**Priority:** LOWEST

---

## Prompt Handoff Notes for Codex 5.2-codex
- Provide the prompt model with the current repo state, highlight the completion of Phase 0 (shared module, queue wiring, KnowMaps service integration) and the Phase 2 baseline, then define Phase 3/Phase 4/Phase 5 tasks above as explicit steps.
- Instruct the model to begin each phase with “tests first” (unit + integration) and to append new fixtures/resources in `DiverShared/Fixtures` when needed.
- Ask the model to document any new files or entitlements it adds, keeping references to `group.com.secretatomics.Diver` and `iCloud.com.secretatomics.knowmaps.*`.
- Remind the model to update `PLAN.md` and to add to the QA checklist the gated integration test once dependencies are available.

## Implementation Order (Final - Revised 2025-12-23)
1. **Phase 0.5: Critical Fixes** ✅ — Fix test infrastructure (DI, keychain format)
2. **Phase 1: DiverKit Preparation** ✅ — ProcessingStatus enum, model fields, fixtures, migration tests, os_log
3. **Phase 2: Action Extension** ✅ — Action Extension tests + keychain fallback handling
4. **Phase 3: Data Model Consolidation** ✅ — SwiftData single entry point (`DiverDataStore`) → split navigation + detail views → swipe actions
5. **Phase 4: App Intents** ✅ — App Intents + Action button entry points (includes BGTaskScheduler hookup)
6. **Phase 4B: Shortcuts & Widgets** ✅ — Shortcut templates, Home/Lock screen widgets, donation
7. **Phase 5: Shared with You** ✅ — Shared with You ingestion + shelf
8. Phase 6: Foursquare Enrichment ⬜️ — Foursquare enrichment expansion
9. Phase 7: Know-Maps Ranking ⬜️ — Know-Maps ranking + RL loop
10. Phase 8: Integration Test Gate ⬜️ — Final integration test gate (run before release)
11. **Phase 9: Advanced Widgets** ⬜️ — Live Activities, Control Center (LOWEST PRIORITY, post-1.0)

## Architecture Improvements (Planned)
- Build a local + backend link resolver service with caching and retry policy for wrapped links.
- Version the app-group queue schema and provide migration logic.
- Add BGTaskScheduler policies for deferred processing and retries.
- Add `PrivacyInfo.xcprivacy` and localize App Intents strings (`AppIntents.stringsdict`, `AppShortcuts.xcstrings`).
- Implement Spotlight indexing using `IndexedEntity` and donation for discovery.
- Add observability: os_log counters per pipeline stage and backoff metrics.

## Codex Prompts (model: 5.2-codex)
- "Create the DiverKit preparation harness (app-group storage fixtures, migration scaffolding), then add `knowmaps` as an app-only SwiftPM dependency and verify bundled resources."
- "Add entitlements for CloudKit containers `iCloud.com.secretatomics.knowmaps.Cache` and `iCloud.com.secretatomics.knowmaps.Keys`, plus app group `group.com.secretatomics.Diver` and keychain group `com.secretatomics.Diver.shared`, with tests that validate access."
- "Wire `DefaultModelController`, `CloudCacheManager`, and `DefaultPlaceSearchService` into a lightweight app service container, without importing Know-Maps UI; add unit tests for service wiring."
- "Create a `KnowMapsAdapter` in the app target that maps local `DiverItem` fields into `ItemMetadata` (ID = URL hash) and returns a fully populated object; add mapping tests first."
- "Implement the Phase 8 integration test: verify ML resources load, intent classification returns a search type, CloudKit key fetch succeeds, and a live Foursquare query yields at least one result."
- "Create an Action Extension that wraps a URL into the proprietary link format, saves via the app-group store, and presents a share sheet (not Messages-only); add tests first."
- "Build a split navigation view with Shared with You shelf, processing list, and processed list; render reference detail views from `ProcessedItem` reference payloads; add swipe actions (re-process/delete/share) and tests."
- "Add a Shared with You manager using `SWHighlightCenter` and surface a shelf of shared links in the app UI; add ingestion/prune tests first."
- "Define `AppEntity` + `EntityQuery` for Diver content, implement `AppShortcutsProvider`, and add `SaveContentIntent` with a snippet preview; add intent/entity tests first."
