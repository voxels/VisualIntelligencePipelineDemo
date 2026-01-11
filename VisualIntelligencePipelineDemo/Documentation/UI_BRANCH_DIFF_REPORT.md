# Main vs UI Branch — Views + Models Comparison

## View surface changes
- **Main branch** is UI‑heavy: onboarding/auth/paywall flows, chat UI, main workspace, account settings, menu bar, and multiple components in `Diver/Views/**` (see `Documentation/MAIN_BRANCH_UI_BASELINE.md`).
- **UI branch** collapses UI to a single list view in `Diver/Diver/View/ContentView.swift` and removes the rest of the `Diver/Views/**` hierarchy.
- **Share/Action UI** shifts:
  - Main branch uses `DiverShareExtension/ShareViewController.swift` + `DiverMacOsShareExtension/ShareViewController.swift` with SwiftUI wrappers (`IOSShareView`, `ShareExtensionView`).
  - UI branch removes those share extensions and introduces `Diver/ActionExtension/ActionViewController.swift` for a dedicated Action extension UI.

## Model changes
- **Main branch app models** (SwiftUI + document flow):
  - `Diver/Models/AccountSetting.swift`, `Diver/Models/MarkdownDocument.swift`, `Diver/Models/DocumentViewModel.swift`, `Diver/Models/JobProgress.swift`, `Diver/Models/SSEEvent.swift`, `Diver/Models/TypeAliases.swift`.
  - Heavy dependency on `Api` types (`InputRead`, `MessageRead`, `ItemRead`, etc.) used across chat and workspace views.
- **UI branch app models** (SwiftData + pipeline):
  - Adds `Diver/Diver/Model/Schema/Item.swift` (SwiftData `@Model`, diver link descriptor mapping).
  - UI lists `DiverKit` models: `ProcessedItem` and `LocalInput` (`DiverKit/Sources/DiverKit/Models/*`).
  - No document or chat models in app target.

## Service / pipeline differences
- **Main branch** services focus on authentication, SSE stream, and UI workflow:
  - `Diver/Services/AuthManager.swift`, `SSEStreamService.swift`, `SpotifyService.swift`, `AppRouter.swift`, `MenuBarManager.swift`.
- **UI branch** services focus on queue processing + KnowMaps cache:
  - `Diver/Diver/Services/KnowMapsServiceContainer.swift`, `KnowMapsCacheStore.swift`, `KnowMapsAdapter.swift`, `DiverQueueProcessingService.swift`.
  - Uses `DiverKit` services: `UnifiedDataManager`, `MetadataPipelineService`, `LocalPipelineService`.

## Extension changes
- **Main branch** includes both iOS + macOS share extensions in `DiverShareExtension/` and `DiverMacOsShareExtension/`.
- **UI branch** removes those and adds a dedicated **Action extension** in `Diver/ActionExtension/` with queue + Diver link wrapping.

## Dependency shifts
- **Main branch** relies on `Api` module, `MarkdownUI`, and UI‑specific services.
- **UI branch** relies on `DiverKit`, `DiverShared`, `SwiftData`, and KnowMaps (`knowmaps`) for pipeline and cache behavior.

## Functional implications for UI comparison
- UI branch is built around **pipeline ingestion** (queue → `ProcessedItem`) and **minimal list UI**, while main branch is built around **interactive UI flows** (chat, auth, workspace, paywall).
- Any UI features (auth/chat/menus) from main branch are **absent** in UI branch and would need to be reintroduced or re-scoped if parity is required.
