# Summary of Strategy & Decisions: Diver Unified Architecture

This document summarizes the technical and architectural decisions made for the Diver iOS 26 integration.

## 1. Vision & Core Objectives
- **Unified Flow**: Ingest content from any entry point (Action Button, Siri, Share Sheet) and pipe it through a background metadata service.
- **Diver Metadata Pipeline**: Automated processing (AI tagging, scraping) for every saved or shared item.
- **Unified Feed**: A single view for personal saves and Shared with You content.
- **Collaborative Search**: An iMessage extension that allows users to search the Diver engine and share results instantly.

---

## 2. Key Architectural Decisions

### 📦 Shared Framework (DiverKit) & Pipeline
- **Decision**: All data models (`LocalInput`) and storage logic (`UnifiedDataManager`) reside in DiverKit.
- **Decision**: Implement a `MetadataPipelineService` in DiverKit to handle background tasks for both personal and shared content.
- **Rationale**: Ensures the same processing logic applies whether you save a link yourself or a friend shares it with you.

### 💾 SwiftData + App Groups
- **Decision**: Use SwiftData with a custom `ModelContainer` pointing to `group.com.secretatomics.diver.shared`.
- **Decision**: Enable `iCloudSync: true` for seamless private database synchronization via CloudKit.
- **Requirement**: Target A13 Bionic and newer (iOS 26 minimum spec).

### 🧠 App Intents & Assistant Schemas
- **Decision**: Implement `@AssistantEntity` and `@AssistantIntent` macros.
- **Selection**: Map `LocalInput` to the `.browser.bookmark` or `.journal.entry` schemas to allow Siri's LLM to process data semantically.
- **Interactivity**: Use `requestConfirmation` and `SnippetIntents` to provide a "Liquid Glass" preview before destructive or saving actions.

### 👁️ Visual Intelligence
- **Decision**: Conforms to `IntentValueQuery`.
- **Logic**: Use the `SemanticContentDescriptor` to perform searches based on camera pixel data and high-level scene labels.

---

## 3. Design & UX Decisions

### 💎 Liquid Glass Aesthetic
- **Decision**: Interactive snippets and Control Center widgets must adopt reflective, multilayered glass materials.
- **Platform**: Multi-platform support (Vision Pro, Mac, iOS).

### 🤝 Social Integration (Unified Feed)
- **Decision**: Implement a "Unified Feed" using `SWHighlightCenter` and SwiftData.
- **Decision**: **Auto-Ingestion Pipeline**: Automatically add "Shared with You" highlights to the local SQLite database and kick off the metadata pipeline.
- **Decision**: iMessage App Extension with a search bar and unified feed of shared-in-conversation content (future phase).
- **Link Format**: Use a proprietary universal link format to encapsulate/reference local metadata during sharing.

---

## 4. Implementation Logic (Revised Order)
- **Phase 0.5**: Critical Fixes (test infrastructure, DI, keychain format) ← NEW
- **Phase 1**: DiverKit preparation (ProcessingStatus enum, model additions, fixtures, migration tests, os_log).
- **Phase 2**: Action Extension tests + keychain fallback handling.
- **Phase 3**: Data model consolidation, SwiftData single entry point (`DiverDataStore`), split navigation UI.
- **Phase 4**: App Intents + Action button entry points (includes BGTaskScheduler hookup).
- **Phase 5**: Shared with You ingestion + shelf.
- **Phase 6**: Foursquare enrichment expansion.
- **Phase 7**: Know-Maps ranking + RL loop.
- **Phase 8**: Final integration test gate.

## 5. Failure Recovery Prompts
- Use `Documentation/ExecutionPrompts.md` for per-phase recovery steps.
- Apply mitigation checkpoints at Phase 0.5 (all tests pass), Phase 3 migrations, SwiftData consolidation, UI wiring, Phase 4 intents, and Phase 5 ingestion.

---
## Status Update (2025-12-23)
- Action Extension baseline is implemented (wraps Diver links, writes to queue, provides share sheet, Messages integration).
- **Phase 0.5 added** to fix blocking test issues:
  - ActionViewController needs `init(queueStore:)` for DI
  - AppGroupConfigTests expects wrong keychain format (missing Team ID prefix)
- Phase 1 planning complete (DiverKit prep).
- Phase 2 tests blocked by Phase 0.5; Phase 3 planning in progress.
- Revised execution order: Phase 0.5 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 → Phase 7 → Phase 8.
- iMessage App Extension remains a future phase.

*Last Updated: 2025-12-23 by Claude Code Audit*
