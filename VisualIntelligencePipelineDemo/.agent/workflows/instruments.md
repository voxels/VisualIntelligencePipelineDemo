---
description: How to profile the Visual Intelligence pipeline with Instruments
---

# Instruments Analysis Workflow

This workflow covers profiling the Visual Intelligence app with Xcode Instruments to identify performance bottlenecks, memory issues, and main-thread hangs.

## Prerequisites

- Physical iOS device (Instruments GPU/Metal profiling requires hardware)
- Xcode 26+ with Instruments
- At least 5-10 test images in Photos library for batch processing

## 1. Build for Profiling

// turbo
```bash
xcodebuild -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme VisualIntelligencePipeline \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  build
```

Then in Xcode: **Product → Profile** (⌘I) to launch Instruments.

## 2. Time Profiler — Pipeline Latency

**Goal:** Identify which pipeline stage takes the longest.

1. Select **Time Profiler** template
2. Connect your iOS device and select the app
3. Start recording
4. In the app:
   - Capture 3 photos in quick succession
   - Wait for pipeline to complete (watch sidebar for "Processing...")
   - Import 5+ photos from library (batch processing)
5. Stop recording
6. **Analyze:**
   - Filter to `LocalPipelineService.process` in the call tree
   - Look for functions taking >100ms:
     - `analyzeVisualContent` (Vision framework)
     - `performLLMAnalysis` (SLM inference)
     - `FastVLMEnrichmentService.analyze` (MLX model)
     - `reverseGeocode` (MapKit network)
     - `enrich(url:)` (web scraping)
   - Check for unexpected main-thread work
   - Document top-5 hotspots with percentages

## 3. Allocations — Memory Pressure

**Goal:** Verify autorelease pools and caches prevent memory accumulation.

1. Select **Allocations** template
2. Start recording
3. In the app:
   - Import 10+ photos from library (triggers batch pipeline)
   - Watch the "All Heap & Anonymous VM" graph
4. Stop recording
5. **Analyze:**
   - Filter to `CGImage` allocations — should see create/release pairs (not accumulation)
   - Search for `CGImageSource` — verify `autoreleasepool` prevents buffer accumulation
   - Check `NSCache` entries — should stay under `countLimit=10`
   - Look for growth patterns:
     - ✅ Sawtooth pattern = good (allocate, process, release)
     - ❌ Staircase pattern = bad (leaking or accumulating)
   - Filter to `PlaceContext` — verify reverse geocoding cache entries are bounded

## 4. Leaks — Memory Leak Detection

**Goal:** Verify no retain cycles in pipeline/enrichment services.

1. Select **Leaks** template
2. Start recording
3. In the app:
   - Process 5 captures
   - Navigate to sidebar, open detail views
   - Background the app (press Home)
   - Return to the app
   - Process 5 more captures
4. Stop recording
5. **Analyze:**
   - Check for leaked `LocalPipelineService` instances (should be deallocated after processing)
   - Check for leaked `Task` captures (closures holding references)
   - Look for `MetadataPipelineService` leaks during cancellation
   - Verify `CGImageWrapper` doesn't leak when NSCache evicts

## 5. Hangs — Main Thread Responsiveness

**Goal:** Verify no main-thread blocks >100ms (Apple's threshold).

1. Select **App Hang Detection** (or **Thread State Trace**) template
2. Start recording
3. In the app:
   - Rapidly scroll the sidebar while pipeline is processing
   - Open/close detail views during processing
   - Tap capture button and immediately scroll sidebar
   - Trigger "Rebuild Library" from Settings
4. Stop recording
5. **Analyze:**
   - Look for hangs >100ms (red markers)
   - Check if hangs correlate with:
     - `modelContext.save()` calls
     - `Services.shared` access from background
     - SwiftData fetch in `.onAppear`
   - Verify `Task.detached` is keeping heavy work off main thread

## 6. Record Results

After each profiling session, document findings:

```markdown
## Instruments Results — [Date]

### Time Profiler
| Stage | Avg Duration | % of Total |
|-------|-------------|-----------|
| Vision Analysis | Xms | X% |
| SLM Inference | Xms | X% |
| FastVLM | Xms | X% |
| Reverse Geocoding | Xms | X% |
| Link Enrichment | Xms | X% |

### Allocations
- Peak heap: X MB
- CGImage peak: X instances
- Cache hit rate: X%

### Leaks
- Leaked objects: X (list types)

### Hangs
- Hangs >100ms: X
- Longest hang: Xms (cause: ...)
```

Save results to `Documentation/instruments_analysis.md`.

## 7. Run Performance Tests

After profiling, run the XCTest performance baselines to establish regression detection:

// turbo
```bash
xcodebuild test -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme DiverTests_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:DiverKitTests/PipelinePerformanceTests
```

Review baselines in Test Navigator → Set Baseline for each `measure {}` test.
