---
description: Add a new service to DiverKit with protocol, mock, and documentation
---

# Add Service Workflow

Follow this when adding a new service to `DiverKit`.

## 1. Define the protocol (if needed)

Create in `DiverKit/Sources/DiverKit/Protocols/`:

```swift
// ServiceProtocols.swift or a new file
public protocol MyServiceProtocol: Sendable {
    func doWork() async throws -> Result
}
```

Rules:
- Protocol must be `Sendable`
- Use `async throws` for any I/O or network work
- Keep protocols small and focused

## 2. Create the service

Create in `DiverKit/Sources/DiverKit/Services/` (or appropriate subdirectory):

```
Services/
├── Commerce/     # Commerce/scoring services
├── Edge/         # Edge computing/distributed actors
├── Scoring/      # ProductScoringStrategy implementations
└── *.swift       # Core services (pipeline, camera, location, etc.)
```

Rules:
- Mark as `public final class` or `public actor`
- Conform to your protocol
- Use `Task.detached(priority: .utility)` for heavy work
- Create `ModelContext(container)` for SwiftData access (never use shared context)
- Follow `/swift-concurrency` workflow for async patterns

## 3. Create a test mock

Create in `DiverKit/Tests/DiverKitTests/Mocks/`:

```swift
final class MockMyService: MyServiceProtocol, @unchecked Sendable {
    var doWorkCallCount = 0
    var doWorkResult: Result = .default

    func doWork() async throws -> Result {
        doWorkCallCount += 1
        return doWorkResult
    }
}
```

## 4. Write tests

Create in `DiverKit/Tests/DiverKitTests/`:

- Test the service's core logic using the mock for dependencies
- Test error paths
- Run tests: `/test`

## 5. Wire into the app (if needed)

- Add to `VisualIntelligencePipelineApp.init()` if it needs app-lifetime scope
- Or inject via protocol parameter into the consuming service/ViewModel
- Prefer protocol-based DI over concrete types

## 6. Update documentation

// turbo-all

```bash
# Get updated service count
find DiverKit/Sources/DiverKit/Services -name '*.swift' | wc -l
```

Update in GEMINI.md:
- Add to **Key Files** → **Core Services** section
- Update service count in Commerce/Edge/Scoring sections if applicable
- Add to relevant protocol listing if new protocol was created

Then follow `/pre-commit` for remaining docs.
