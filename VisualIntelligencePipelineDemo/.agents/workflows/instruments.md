---
description: How to profile the Visual Intelligence pipeline with Instruments
---

# Instruments Profiling Workflow

## Prerequisites

1. Build the app first (use `/build` workflow)
2. Ensure an iOS Simulator is booted

## Steps

// turbo-all

1. Build a Debug configuration via the Xcode MCP bridge or CLI:
```bash
xcodebuild -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme VisualIntelligencePipeline \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build
```

2. Launch Instruments with the Time Profiler template:
```bash
xcrun xctrace record --template 'Time Profiler' \
  --device-name 'iPhone 17 Pro' \
  --launch -- VisualIntelligencePipeline
```

3. Perform the pipeline actions to profile (capture, import, reprocess)

4. Stop recording and open the trace:
```bash
open *.trace
```

## Pipeline-Specific Profiling Targets

| Area | What to Look For |
|------|-----------------|
| `LocalPipelineService.process()` | Main-thread hangs, background task scheduling |
| `IntelligenceProcessor` | SLM inference latency |
| `FastVLMEnrichmentService` | MLX model load and inference time |
| Vision pipeline (`executePipeline`) | OCR, sifting, aesthetics pass duration |
| `MetadataPipelineService` | Queue processing throughput |
| `createCGImage(from:)` | CGImage decode buffer accumulation |

## Notes

- Apple's hang threshold is 100ms on the main thread
- Use `autoreleasepool` around CGImage decode loops
- Check for `Task.isCancelled` guards between pipeline stages
