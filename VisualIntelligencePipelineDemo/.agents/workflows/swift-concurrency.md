---
description: Swift concurrency patterns and rules for the Visual Intelligence pipeline
---

# Swift Concurrency Workflow

Reference this workflow when writing or reviewing async code in this project.

## Decision Tree

### 1. Where is this code running?

- **SwiftUI handler** (`onAppear`, `onChange`, `onReceive`, `task`, button action)?
  → Use `Task.detached(priority: .utility)` — `Task {}` inherits `@MainActor`
- **Service/pipeline code** (not UI)?
  → Use `async/await` naturally, ensure no `@MainActor` inheritance
- **ViewModel** (`@Observable`)?
  → UI property updates: `await MainActor.run { }`. Heavy work: `Task.detached`

### 2. Does it touch SwiftData?

- **Reading from UI** → `@Query` or `FetchDescriptor` on `mainContext` is fine
- **Reading from background** → Create `ModelContext(container)` with `autosaveEnabled = false`
- **Writing from background** → Same private `ModelContext`, call `try context.save()` explicitly
- **Reprocessing an item** → Use `processItemByID(id:)` (creates private context per call)
- **Never** use `dataStore.mainContext` or `manager.mainContext` from `Task.detached`

### 3. Does it do heavy work (ML, Vision, IO)?

// turbo-all

- Always `Task.detached(priority: .utility)` with `[weak self]` capture list
- Check `Task.isCancelled` between pipeline stages
- Wrap CGImage decode in `autoreleasepool { }`
- Use `await MainActor.run { }` only for the final UI property update

## Patterns

### ✅ Correct: Pipeline work from SwiftUI
```swift
Button("Reprocess") {
    let itemID = item.id
    Task.detached(priority: .utility) {
        await pipelineService.processItemByID(itemID)
    }
}
```

### ❌ Wrong: Task {} in SwiftUI
```swift
Button("Reprocess") {
    Task {
        // Inherits @MainActor — blocks UI!
        await pipelineService.processItemByID(item.id)
    }
}
```

### ✅ Correct: Background SwiftData access
```swift
Task.detached(priority: .utility) {
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let descriptor = FetchDescriptor<ProcessedItem>(
        predicate: #Predicate { $0.sessionID == sessionID }
    )
    let items = try context.fetch(descriptor)
    // ... process items ...
    try context.save()
}
```

### ❌ Wrong: Shared context from background
```swift
Task.detached {
    // dataStore.mainContext is @MainActor — crash or corruption
    let items = try dataStore.mainContext.fetch(descriptor)
}
```

### ✅ Correct: Sequential batch processing
```swift
// Collect IDs first, then process sequentially
let ids = items.map(\.id)
Task.detached(priority: .utility) {
    for id in ids {
        guard !Task.isCancelled else { break }
        await pipelineService.processItemByID(id)
    }
}
```

### ❌ Wrong: N concurrent tasks mutating SwiftData
```swift
for item in items {
    Task { // N concurrent tasks = context corruption
        await pipelineService.processItemByID(item.id)
    }
}
```

## Key Types

| Type | Isolation | Safe from background? |
|---|---|---|
| `LanguageModelSession` | None (`final class`) | ✅ Any thread |
| `IntelligenceProcessor` | None (`Sendable`) | ✅ Any thread, but don't call from `@MainActor` tasks |
| `FastVLMEnrichmentService` | None | ✅ Runs at `.utility` priority internally |
| `Vision` requests (iOS 18+) | None | ✅ Native async |
| `ModelContext` | Not Sendable | ⚠️ Create per-task, don't share |
| `DiverDataStore.mainContext` | `@MainActor` | ❌ Never from `Task.detached` |

## Checklist

Before merging async code, verify:

- [ ] No `Task { }` in SwiftUI handlers for pipeline work
- [ ] Background SwiftData uses private `ModelContext(container)`
- [ ] No N concurrent for-loop Tasks mutating models
- [ ] `Task.isCancelled` checked between pipeline stages
- [ ] CGImage decode wrapped in `autoreleasepool`
- [ ] UI updates use `await MainActor.run { }`
- [ ] `processItemByID` used (not `processItemImmediately`) from UI/ViewModel code
