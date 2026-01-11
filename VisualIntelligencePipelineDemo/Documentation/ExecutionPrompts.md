# Diver Execution Prompts & Recovery Notes

Use these prompts if a phase fails or needs to be re-run. They follow the revised plan order (Phase 0.5 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8) and include mitigation checkpoints.

Status update (current): Phase 0.5 added to fix blocking test issues; Phase 2 baseline implemented (tests blocked); Phase 3 planning in progress.

## Phase 0.5: Critical Fixes (NEW - Run First)
- Prompt: "Add `init(queueStore:)` initializer to ActionViewController for dependency injection. Keep existing init methods but allow queueStore to be injected for testing."
- Prompt: "Update AppGroupConfigTests.testDefaultIdentifiers() to expect the Team ID prefix in keychain access group: `23264QUM9A.com.secretatomics.Diver.shared`"
- Prompt: "Run `cd DiverShared && swift test` and `cd DiverKit && swift test` to verify all tests pass."

## Phase 1: DiverKit Preparation
- Prompt: "Define ProcessingStatus enum (queued, processing, ready, failed, archived) in DiverKit/Sources/DiverKit/Models/"
- Prompt: "Add fields to ProcessedItem: status (ProcessingStatus), source (String?), updatedAt (Date), referenceCount (Int), lastProcessedAt (Date?), wrappedLink (String?), payloadRef (String?). Add migration defaults."
- Prompt: "Add fixture loader utilities for reference payloads from Diver/DiverTests/Fixtures/pipeline_logs.json"
- Prompt: "Add os_log infrastructure with subsystem 'com.secretatomics.Diver' and categories: pipeline, queue, storage"

## Phase 2: Action Extension Tests + Safety
- Prompt: "Add Action Extension tests for queue enqueue, wrapped-link creation, and validation failures. Ensure missing keychain secret shows a safe error state and does not enqueue."
- Prompt: "Add tests for MessagesLaunchStore integration and diver://open-messages deep link handling."
- Prompt: "Add a manual smoke test checklist for extension performance limits (no heavy processing, no network dependencies)."

## Phase 3: Data Model + SwiftData + UI Recovery
- Prompt: "Extend ProcessedItem with status/source/updatedAt/referenceCount/lastProcessedAt/wrappedLink/payloadRef. Add ProcessingStatus enum and migration defaults, then write migration tests." 
- Prompt: "Create ReferenceEntity model and ReferencePayloadStore (compressed file storage). Add tests for payload read/write + reference creation from fixtures."
- Prompt: "Introduce DiverDataStore as the only ModelContainer entry point. Inject contexts into KnowMapsServiceContainer, MetadataPipelineService, and LocalPipelineService. Add tests for single-store wiring."
- Prompt: "Build split navigation with Shared shelf placeholder, processing list, and processed list. Add status badges, empty/error states, and swipe actions (re-process/delete/share)." 
- Prompt: "Add dedupe by URL hash during ingest, retry strategy for failed items, and retention/purge policy for payload files." 
- Prompt: "Add processing-failed UI state with retry action and queue drain on app launch/foreground." 
- Prompt: "Add share-from-app actions: copy wrapped link, share sheet, open original source, wrapped-link deep link handling."

## Phase 4: App Intents + Action Button
- Prompt: "Define AppEntity/EntityQuery for stored content and add Save/Share/Preprocess intents with snippet previews. Add intent execution + entity query tests." 
- Prompt: "Implement BGTaskScheduler queue drain (app refresh) and verify with a background task smoke test." 

## Phase 5: Shared with You
- Prompt: "Add Shared with You entitlement checks, a shelf empty state, and opt-out toggle in Settings. Validate highlight ingestion and pruning logic." 

## Phase 6: Foursquare Enrichment
- Prompt: "Add endpoint expansion (My Place, photos, tips, reviews). Normalize into local models with throttling and retries. Add contract + golden tests." 

## Phase 7: Know-Maps Ranking + RL Loop
- Prompt: "Wire embedding and ranking feedback loop with deterministic tests. Ensure ranking updates don’t block UI and can be replayed from stored events." 

## Phase 8: Final Integration Test Gate
- Prompt: "Run the final integration test: verify CoreML assets load, CloudKit keys resolve, and a live Foursquare query returns data. If any fail, add a startup diagnostics view and gate features behind a health check." 
- Prompt: "Add a one-shot integration test that asserts app-group SwiftData access, KnowMaps cache access, and OpenAI/Segment config are not required when keys are missing."

## Mitigation Checkpoints
- Before Phase 3 migrations: confirm CloudKit keys + Foursquare + CoreML health.
- After Phase 3 data model changes: run migration tests + payload store tests; verify no data loss on upgrade.
- After SwiftData consolidation: verify single entry point and app-group access.
- After Phase 3 UI wiring: run UI smoke test for lists + detail states.
- After Phase 4 intents: run intent execution tests on a clean install.
- After Phase 5 Shared with You: verify validation, opt-out, and empty shelf behavior.
