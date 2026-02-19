---
description: Run unit tests for Visual Intelligence
---

# Test Workflow

## Test Targets

| Scheme | Target | Contents |
|--------|--------|----------|
| `DiverTests_iOS` | DiverKit SPM tests | Service protocols, pipeline, enrichment, VM tests |
| `VisualIntelligencePipeline` | App test bundle | Integration, share intent, adapter tests |
| `DiverShared` | SharedLib SPM tests | Pure Swift model/utility tests |

## Bridge-First Tests (Preferred)

When Xcode is running with the project open:

// turbo-all

1. Use the Xcode MCP bridge `test` tool to run the target scheme's tests
2. Read structured test results (pass/fail per test, diagnostics with file/line)
3. If failures found, fix and re-run only the failing tests via the bridge

## CLI Fallback

If Xcode is not running or the bridge is unavailable:

1. Run DiverShared package tests (pure Swift, no UIKit):
```bash
cd DiverShared && swift test
```

2. Run DiverKit unit tests (requires iOS Simulator):
```bash
xcodebuild test -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme DiverTests_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

3. Run app-level unit tests:
```bash
xcodebuild test -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme VisualIntelligencePipeline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

4. Run a single test method:
```bash
swift test --filter DiverSharedTests.LinkWrappingTests/testWrapURL
```

## Notes

- `swift test` does **not** work for DiverKit — it compiles for macOS which lacks UIKit
- Always use `xcodebuild test` with an iOS Simulator destination for DiverKit
- Bridge tests return structured pass/fail results; CLI tests require parsing terminal output
