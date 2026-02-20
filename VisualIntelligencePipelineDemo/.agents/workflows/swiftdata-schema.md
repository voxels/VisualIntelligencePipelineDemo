---
description: Safely modify SwiftData schema with CloudKit compatibility
---

# SwiftData Schema Change Workflow

Follow this procedure for ANY change to `@Model` classes. CloudKit sync requires lightweight-only migrations.

## 1. Determine change type

| Change | Lightweight? | Safe with CloudKit? |
|---|---|---|
| Add optional property with default | ✅ Yes | ✅ Yes |
| Add non-optional property with default | ✅ Yes | ✅ Yes |
| Remove property | ✅ Yes | ⚠️ Data loss on older clients |
| Rename property | ❌ No | ❌ Breaks sync |
| Change property type | ❌ No | ❌ Breaks sync |
| Add relationship | ✅ Yes | ✅ Yes |
| Rename entity | ❌ No | ❌ Breaks sync |

> **STOP** if your change is not lightweight. You must find an alternative approach
> (e.g., add new property + deprecate old one, never rename).

## 2. Update VersionedSchema

```swift
// In your schema versioning file:
enum DiverSchemaVN: VersionedSchema {
    static var versionIdentifier = Schema.Version(N, 0, 0)
    static var models: [any PersistentModel.Type] {
        DiverDataStore.coreTypes
    }
}
```

Add a new migration stage to your `SchemaMigrationPlan`:

```swift
static let migrateVPrevToVN = MigrationStage.lightweight(
    fromVersion: DiverSchemaVPrev.self,
    toVersion: DiverSchemaVN.self
)
```

## 3. Check Data storage rules

For any new `Data` or `Data?` property:

- **> 1KB** (images, depth maps, payloads) → Add `@Attribute(.externalStorage)`
- **< 1KB** (JSON context blobs) → Inline is fine
- **> 10KB JSON** → Migrate to `.externalStorage` or file-path reference

```swift
// ✅ Correct for large binary data
@Attribute(.externalStorage)
public var rawPayload: Data?

// ✅ Fine for small JSON context
public var weatherContextData: Data?  // ~500 bytes typical
```

## 4. Test the migration

```bash
# Build clean
xcodebuild -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme VisualIntelligencePipeline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  clean build

# Run tests to verify schema
xcodebuild test -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme DiverTests_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## 5. Verify CloudKit compatibility

- Open CloudKit Console (https://icloud.developer.apple.com)
- Check that the schema change appears in Development environment
- Deploy to Production only after thorough device testing

## 6. Update documentation

Follow `/pre-commit` workflow — schema changes always require GEMINI.md and changelog updates.
