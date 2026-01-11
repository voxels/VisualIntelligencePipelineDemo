# KnowMaps Importer – Dry Run & Recovery Notes

Use these steps if you need to validate the KnowMaps → Diver importer or recover from a failed run.

## 1. Prepare the environment
1. Launch Diver once to ensure:
   - Shared App Group container exists (`group.com.secretatomics.diver.shared`).
   - KnowMaps cache has been refreshed (run the app’s startup flow).
2. Confirm the importer is idle:
   - `KnowMapsImporter.shared.isImporting` is `false`.
   - `StoreHealthMonitor.shared.captureSnapshot(label: "PreDryRun")` captures baseline counts.

## 2. Dry-run ingestion
Use the temporary limit override to ingest a small batch:
```swift
Task { @MainActor in
    await KnowMapsImporter.shared.importCachedPlaces(using: cacheManager, limit: 5)
}
```
Verify:
- Toast appears (“KnowMaps Imports”).
- `StoreHealthMonitor` logs a “PostImport” snapshot with increased `LocalInput` count.
- SwiftData inspector shows new `LocalInput` rows with `fsqID`.

## 3. Recovery / reset
- If you need to re-run, remove the persisted ID cache:
  ```swift
  UserDefaults.standard.removeObject(forKey: "com.secretatomics.diver.importedKnowMapsIDs")
  ```
- Optionally delete newly created rows (e.g., via a SwiftData migrator) before re-importing.
- Capture snapshots after each run to confirm counts match expectations.
