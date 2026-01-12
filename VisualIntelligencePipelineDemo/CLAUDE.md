# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Diver is a universal iOS/macOS application for saving and organizing links from various sources (TikTok, YouTube, Instagram, Safari, etc.) through Share Extensions. The project uses a modular Swift Package Manager architecture with SwiftUI, SwiftData, and CloudKit, integrating with a Know Maps backend for ML-powered search and recommendations.

**Platform Requirements:** iOS 18+, macOS 15+, visionOS 2+

## Essential Commands

### Building and Testing

```bash
# Build Visual Intelligence Pipeline
xcodebuild -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj -scheme VisualIntelligencePipeline -destination 'platform=iOS Simulator,name=iPhone 16' build

# Build Visual Intelligence Pipeline
xcodebuild -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj -scheme VisualIntelligencePipeline -destination 'platform=iOS Simulator,name=iPhone 16' build


# Run DiverKit tests
cd DiverKit
swift test

# Run DiverShared tests
cd DiverShared
swift test

# Run a single test
swift test --filter DiverSharedTests.LinkWrappingTests/testWrapURL
```

### Development Workflow

```bash
# Check git status (currently on UI branch)
git status

# Run tests before committing (TDD approach is emphasized in PLAN.md)
cd DiverShared && swift test && cd ../DiverKit && swift test && cd ../Diver
```

## Module Architecture

### Three-Layer Package Structure

1. **DiverShared** (Pure Swift, no dependencies)
   - Shared utilities for app + extensions
   - Key components: `DiverItemDescriptor`, `DiverQueueStore`, `DiverLinkWrapper`, `Validation`
   - App group configuration and keychain access groups
   - Location: `DiverShared/Sources/DiverShared/`

2. **DiverKit** (Core framework, depends on DiverShared)
   - Backend integration, auth, networking, services
   - Dependencies: LDSwiftEventSource (SSE), SpotifyAPI, DiverShared
   - Key components: API clients, `MetadataPipelineService`, `UnifiedDataManager`, `KeychainService`
   - Location: `DiverKit/Sources/DiverKit/`

3. **VisualIntelligencePipeline** (Main App Target)
   - Standalone app for developing and testing Visual Intelligence features
   - Includes: Camera, Sifting, Reprocessing, Location Editing
   - Location: `VisualIntelligencePipeline/`
4. **VisualIntelligencePipeline** (Demo App / Feature Application)
   - Standalone app for developing and testing Visual Intelligence features
   - Includes: Camera, Sifting, Reprocessing, Location Editing
   - Location: `VisualIntelligencePipeline/`

### Key Architectural Patterns

**Local-First Data Flow:**
```
Extension → DiverQueueStore (app group) → Main App → SwiftData + CloudKit
```

**Service Wiring:**
- `KnowMapsServiceContainer`: Consolidates ML, search, cache, analytics services
- `KnowMapsAdapter`: Maps Diver models to Know Maps `ItemMetadata`
- `MetadataPipelineService`: Converts queue items to `LocalInput` in `UnifiedDataManager`

**DiverLink Format (v1):**
```
https://diver.link/w/<id>?v=1&sig=<signature>&p=<payload>

- id: SHA256(url + salt), hex, 24 chars
- sig: HMAC(id + version + payload) using shared secret
- p: base64url-encoded JSON with original URL (optional)
```

Implementation: `DiverShared/Sources/DiverShared/LinkWrapping.swift`

**Queue-Based Extension → App Communication:**
- Extensions use `DiverQueueStore.enqueue()` to write `DiverQueueItem` as JSON files
- Main app processes queue via `DiverQueueProcessingService` on launch or background task
- Queue directory: `group.com.secretatomics.Diver/Queue/`
- Files named: `<timestamp>-<uuid>.json`, sorted by timestamp

**Visual Intelligence Services:**
- **LocalPipelineService**: Orchestrates ingestion, enrichment, and persistence for visual items.
- **LocationSearchAggregator**: Unified search service (`DiverKit`) that queries Foursquare and MapKit in parallel and merges results.
- **Reprocessing**: Items can be reprocessed silently. `LocalPipelineService.reprocessPipeline` handles this, ensuring that **existing item IDs are reused** to prevent duplicates in the database.

## Critical Configuration

### Entitlements (Shared Across Targets)

- **App Group:** `group.com.secretatomics.Diver`
- **Keychain Access Group:** `com.secretatomics.Diver.shared`
- **CloudKit Containers:**
  - `iCloud.com.secretatomics.knowmaps.Cache` (user cache)
  - `iCloud.com.secretatomics.knowmaps.Keys` (secret storage)

These are defined in `DiverShared/Sources/DiverShared/AppGroupConfig.swift` and must match across all targets.

### Storage Locations

- **SwiftData (Main App):** `group.com.secretatomics.Diver/Diver.sqlite`
- **Queue Directory:** `group.com.secretatomics.Diver/Queue/`
- **Keychain:** Uses app group + keychain access group for shared secrets (DiverLink encryption key)

## Know Maps Integration

**Important:** The `knowmaps` framework is an app-only dependency. DO NOT reference it from DiverKit or DiverShared, and DO NOT import Know Maps UI code into Diver.

**What to Use from Know Maps:**
- Models: `ItemMetadata`, `UserCachedRecord`, `RecommendationData`
- Services: `DefaultModelController`, `CloudCacheManager`, `DefaultPlaceSearchService`
- ML: `MiniLMEmbeddingClient`, `DefaultAdvancedRecommenderService`, `HybridRecommenderModel`
- Auth: `AppleAuthenticationService` (canonical auth stack)

**What NOT to Use:**
- SwiftUI views or components
- UI-specific utilities

**Adapter Pattern:**
`KnowMapsAdapter` in the Diver app target maps local `Item` models to Know Maps `ItemMetadata`. The ID is SHA256(url), and all fields must be populated to avoid ML/recommender regressions.

## Testing Strategy

### Test-First Approach (Per PLAN.md)

All phases require tests before implementation. Test structure:

```
DiverShared/Tests/DiverSharedTests/     # Queue, link wrapping, validation
DiverKit/Tests/DiverKitTests/           # Networking, services, auth
Diver/DiverTests/                       # App logic, adapters, integration
Diver/DiverUITests/                     # UI tests
```

### Test Utilities

- **Fixtures:** `DiverShared/Fixtures/` for test data
- **CloudKit Test Support:** `CloudKitTestSupport.swift` for CloudKit operations
- **Golden Tests:** For mapping output validation (adapter changes)
- **Contract Tests:** For external service endpoints (Foursquare, backend API)

### Running Specific Tests

```bash
# Single test class
swift test --filter LinkWrappingTests

# Single test method
swift test --filter QueueStoreTests/testEnqueueCreatesFile

# All tests in a module
cd DiverShared && swift test
```

## Development Phases (From PLAN.md)

**Current Status:** Phase 0 complete, Phase 1 in progress

### Phase 0: Foundation ✅
- SwiftData + CloudKit unified persistence
- Know Maps integration (models + services only, no UI)
- DiverQueueStore for extension ↔ app IPC
- KnowMapsAdapter bridging
- Background task scheduling
- Entitlements configured

### Phase 1: Action Extension (IN PROGRESS)
- URL wrapping into DiverLink format
- Queue-based persistence via app group
- Share sheet integration (including Messages)
- **Files:** `Diver/ActionExtension/ActionViewController.swift`
- **Tests Required:** URL wrapping, queue operations, extension flow

### Phase 2: Shared with You
- `SWHighlightCenter` integration for link ingestion
- Shelf view in main app
- Conversation removal tracking

### Phase 3A: Foursquare Enrichment
- Fetch My Place, photos, tips, reviews
- Contract tests for endpoints
- Golden tests for normalization

### Phase 3B: Know Maps RL Ranking
- Embedding-based scoring
- Feedback signal recording
- Advanced recommender integration

### Phase 4: App Intents
- `AppEntity` + `EntityQuery` conformance
- Intents: SaveContentIntent, ShareContentIntent, PreprocessContentIntent
- Siri shortcuts and Action button support

## Key Implementation Files

### Authentication & Security
- `DiverKit/Sources/DiverKit/Authentication/KeychainService.swift` - Generic secure storage
- `DiverShared/Sources/DiverShared/LinkWrapping.swift` - DiverLink format (wrap/parse/verify)
- `DiverShared/Sources/DiverShared/Validation.swift` - URL validation utilities

### Data & Persistence
- `DiverKit/Sources/DiverKit/Storage/UnifiedDataManager.swift` - SwiftData orchestration
- `DiverShared/Sources/DiverShared/QueueStore.swift` - File-based queue for extension IPC
- `DiverShared/Sources/DiverShared/DiverItemDescriptor.swift` - Link metadata struct

### Services & Integration
- `DiverKit/Sources/DiverKit/Services/MetadataPipelineService.swift` - Queue → LocalInput conversion
- `Diver/Diver/Services/KnowMapsServiceContainer.swift` - Service dependency injection
- `Diver/Diver/Services/KnowMapsAdapter.swift` - Diver → Know Maps model mapping
- `Diver/Diver/Services/DiverQueueProcessingService.swift` - Queue drain + cache storage

### Networking
- `DiverKit/Sources/DiverKit/Core/HTTPClient.swift` - Low-level request/response
- `DiverKit/Sources/DiverKit/Core/ApiClient.swift` - Domain-specific API clients
- `DiverKit/Sources/DiverKit/Services/SSEStreamService.swift` - Job log streaming

## Common Patterns & Best Practices

### Dependency Injection
Services accept dependencies via constructor:
```swift
MetadataPipelineService(queueStore: queueStore, modelContext: context)
KnowMapsServiceContainer(configuration: config, analyticsService: analytics)
```

### Error Handling
- Use typed errors (e.g., `DiverLinkError`, `APIErrorResponse`)
- Fallback strategies: in-memory SwiftData if CloudKit unavailable
- Safe-mode paths for extensions (lightweight, no heavy ML)

### URL Validation Before Wrapping
Always validate URLs before wrapping to prevent share sheet rejection:
```swift
// Use Validation.isValidURL() from DiverShared
guard Validation.isValidURL(string) else { /* skip */ }
```

### Extension Constraints
- Memory and time limits require deferred processing
- Heavy ML/search operations MUST run in main app, not extensions
- Extensions should only enqueue to `DiverQueueStore` and exit quickly

### App Group Access
Use `AppGroupConfig` for all shared storage paths:
```swift
let queueDir = try AppGroupConfig.queueDirectory()
let store = try DiverQueueStore(directoryURL: queueDir)
```

## Known Risks & Mitigations

### CloudKit Key Provisioning (HIGH)
- Foursquare + OpenAI keys stored in CloudKit are hard dependencies
- **Mitigation:** Add startup health check, gate features when missing, include in Phase 0 integration test

### Extension Memory Limits (HIGH)
- Action Extension must stay lightweight
- **Mitigation:** Defer all heavy work to main app via queue, use background tasks for processing

### Schema Drift (MEDIUM)
- Local-first mapping must preserve all `ItemMetadata` fields
- **Mitigation:** Version adapter mapping, add golden tests, validate required fields on save

### CoreML Resource Bundling (MEDIUM)
- MiniLM embeddings + vocab.txt + taxonomy JSON required
- **Mitigation:** Assert bundle presence at launch, add resource smoke test

## Additional Resources

- **Implementation Plan:** `PLAN.md` - Detailed phase breakdown, risk assessment, prompt hand-offs
- **Architecture Strategy:** `IMPROVED_STRATEGY.md` - Architecture decisions
- **Multi-Agent Notes:** `GEMINI.md` - Orchestration guidance

## Git Workflow

- **Current Branch:** `UI` (development)
- **Main Branch:** `main` (use for PRs)
- **Commit Style:** See recent commits for format (e.g., "phase 0", "fixing test data")
