# UI Branch UI + Model Baseline

## Scope snapshot
This document captures the **UI branch** UI surface and model layer so it can be compared against `main`. It focuses on views, view controllers, and model/service classes used by the app and extensions.

## App entry points and targets
- **App entry**: `Diver/Diver/DiverApp.swift` (SwiftUI app for iOS). Uses SwiftData, DiverShared, DiverKit, BackgroundTasks, and KnowMaps services.
- **Action Extension**: `Diver/ActionExtension/ActionViewController.swift` (UIKit) handles shared URLs, wraps Diver links, enqueues queue items, and shows a status view.

## View inventory (UI branch)
### App UI
- `Diver/Diver/View/ContentView.swift`
  - SwiftUI list showing `ProcessedItem` entries when available; falls back to `LocalInput` when processed items are empty.
  - Minimal UI: navigation stack + list rows + empty state.

### Extension UI
- `Diver/ActionExtension/ActionViewController.swift`
  - UIKit view controller with in-code status layout (stack view + labels + optional action button).
  - Uses `MessagesLaunchStore` (DiverShared) to attempt an SMS launch, and falls back gracefully.

## View models
- No dedicated view models in UI branch app UI. Extension logic is embedded in `ActionViewController`.

## App models (UI branch)
- `Diver/Diver/Model/Schema/Item.swift`
  - SwiftData `@Model` representing a locally stored item (id/url/title/description/styleTags/categories/location/price/createdAt).
  - Provides `descriptor` mapping to `DiverItemDescriptor`.

## DiverKit models used by UI branch
- `DiverKit/Sources/DiverKit/Models/LocalInput.swift`
- `DiverKit/Sources/DiverKit/Models/ProcessedItem.swift`

## Services and data pipeline
- `DiverKit/Sources/DiverKit/Storage/UnifiedDataManager.swift`
  - SwiftData container initialization; used by `DiverApp`.
- `DiverKit/Sources/DiverKit/Services/MetadataPipelineService.swift`
  - Processes the queue and refreshes `ProcessedItem` records.
- `DiverKit/Sources/DiverKit/Services/LocalPipelineService.swift`
  - Builds `ProcessedItem` from `LocalInput` and `DiverItemDescriptor`.

## KnowMaps integration (UI branch)
- `Diver/Diver/Services/KnowMapsServiceContainer.swift`
  - CloudKit-backed cache + model controller wiring.
  - Owns `KnowMapsCacheStore` and a `DiverQueueProcessingService` for pipeline integration.
- `Diver/Diver/Services/KnowMapsCacheStore.swift`
  - Persists `UserCachedRecord` via KnowMaps `CloudCacheService`.
- `Diver/Diver/Services/KnowMapsAdapter.swift`
  - Maps `Item` / `DiverItemDescriptor` into KnowMaps `ItemMetadata` and cache payloads.
- `Diver/Diver/Services/DiverQueueProcessingService.swift`
  - Drains Diver queue and writes into KnowMaps cache.

## Summary for comparison
- UI branch is **minimal** UI: a single list view (`ContentView`) plus the Action extension controller.
- Most logic is in services + models (SwiftData + DiverKit + KnowMaps) rather than view models.
