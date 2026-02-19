---
description: Build the Visual Intelligence project for iOS Simulator
---

# Build Workflow

## Bridge-First Build (Preferred)

When Xcode is running with the project open:

// turbo-all

1. Use the Xcode MCP bridge `build` tool to build the `VisualIntelligencePipeline` scheme
2. Read structured build diagnostics from the bridge response (file, line, column, severity)
3. If errors found, fix them and rebuild via the bridge

## CLI Fallback

If Xcode is not running or the bridge is unavailable:

1. Build for iOS Simulator:
```bash
xcodebuild -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme VisualIntelligencePipeline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

2. If the scheme is not found, list available schemes:
```bash
xcodebuild -list -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj
```

## Notes

- The primary scheme is `VisualIntelligencePipeline`
- DiverKit and DiverShared are SPM packages resolved by the project
- Bridge builds return structured diagnostics; CLI builds require parsing terminal output
