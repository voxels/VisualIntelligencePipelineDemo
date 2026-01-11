# Visual Intelligence Camera Feature - Implementation Plan

**Status**: Planning
**Last Updated**: 2025-12-24

---

## Executive Summary

Create a camera-based Visual Intelligence feature for the Action Button that:
1. Opens camera viewfinder
2. Detects QR codes (immediate URL capture)
3. Runs CoreML segmentation/classification on camera view
4. Extracts semantic meaning from scene
5. Generates contextual Diver links

---

## Table of Contents

1. [User Experience Flow](#user-experience-flow)
2. [Architecture Overview](#architecture-overview)
3. [Analysis Pipeline](#analysis-pipeline)
4. [CoreML Model Options](#coreml-model-options)
5. [Content-to-URL Mapping](#content-to-url-mapping)
6. [UI/UX Design](#uiux-design)
7. [Implementation Phases](#implementation-phases)
8. [Open Questions](#open-questions)
9. [Risks & Mitigations](#risks--mitigations)

---

## User Experience Flow

### Primary Flow: Action Button Press

```
User presses Action Button
         ↓
┌─────────────────────────────────────┐
│     CAMERA VIEWFINDER OPENS         │
│                                     │
│   ┌───────────────────────────┐    │
│   │                           │    │
│   │      Camera Preview       │    │
│   │                           │    │
│   │    [Scanning overlay]     │    │
│   │                           │    │
│   └───────────────────────────┘    │
│                                     │
│   Status: "Looking for content..."  │
│                                     │
│   [Cancel]              [Capture]   │
└─────────────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│     CONTENT DETECTED                │
│                                     │
│   🔗 QR Code Found                  │
│   https://example.com/page          │
│                                     │
│   OR                                │
│                                     │
│   🌿 Plant Identified               │
│   "Monstera Deliciosa"              │
│   Confidence: 94%                   │
│                                     │
│   [Create Diver Link]   [Retry]     │
└─────────────────────────────────────┘
         ↓
Diver link created → Copy to clipboard → Open Messages (optional)
```

### Detection Priority

| Priority | Content Type | Action |
|----------|-------------|--------|
| 1 | QR Code with URL | Direct URL capture |
| 2 | Barcode (UPC/EAN) | Product search URL |
| 3 | Visible URL text | OCR → Extract URL |
| 4 | Document | OCR → Text search URL |
| 5 | Object/Scene | Classification → Semantic search URL |

---

## Architecture Overview

### Component Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                     ACTION BUTTON                            │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                  CAMERA VIEW (SwiftUI)                       │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              AVCaptureSession                          │ │
│  │                    │                                   │ │
│  │         CVPixelBuffer (30 fps)                         │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│              ANALYSIS COORDINATOR                            │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ QR/Barcode  │  │    OCR      │  │  CoreML Semantic    │  │
│  │  Detector   │  │   Engine    │  │     Analyzer        │  │
│  │  (Vision)   │  │  (Vision)   │  │  (Segmentation +    │  │
│  │             │  │             │  │   Classification)   │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│         │                │                    │              │
│         └────────────────┼────────────────────┘              │
│                          ▼                                   │
│              ┌─────────────────────┐                        │
│              │  Result Aggregator  │                        │
│              └─────────────────────┘                        │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│              DIVER LINK GENERATOR                            │
│                                                              │
│  Input: DetectedContent (type, payload, confidence)         │
│  Output: URL (direct or search-based)                       │
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  QR Code URL    → Direct wrap                           ││
│  │  Barcode        → Product search URL                    ││
│  │  Text URL       → Direct wrap                           ││
│  │  Document text  → Text search URL                       ││
│  │  Object label   → Contextual search URL                 ││
│  └─────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│              DiverLinkWrapper.wrap()                         │
│                                                              │
│  Creates: diver.link/w/abc123...                            │
│  Saves to: DiverQueueStore                                  │
│  Copies to: Clipboard                                       │
│  Opens: Messages (if configured)                            │
└──────────────────────────────────────────────────────────────┘
```

### Data Flow

```swift
// Frame captured from camera
CVPixelBuffer
    ↓
// Parallel analysis
┌─────────────────────────────────────────┐
│ VNDetectBarcodesRequest  → [Barcode]    │
│ VNRecognizeTextRequest   → [Text]       │
│ VNCoreMLRequest          → [Objects]    │
└─────────────────────────────────────────┘
    ↓
// Aggregated result
CameraAnalysisResult {
    barcodes: [DetectedBarcode]
    text: [DetectedText]
    objects: [DetectedObject]
    timestamp: Date
}
    ↓
// Best content selection
DetectedContent {
    type: .qrCode | .barcode | .url | .object | ...
    payload: URL | String | Classification
    confidence: Float
    boundingBox: CGRect?
}
    ↓
// URL generation
URL (direct or search-based)
    ↓
// Diver link creation
DiverLink (wrapped, saved, shared)
```

---

## Analysis Pipeline

### Layer 1: QR/Barcode Detection (Highest Priority)

**Framework**: Vision (VNDetectBarcodesRequest)

**Supported Symbologies**:
- QR Code
- EAN-8, EAN-13
- UPC-E
- Code 128, Code 39
- ITF-14
- Data Matrix

**Output**:
```swift
struct DetectedBarcode {
    let symbology: VNBarcodeSymbology
    let payload: String
    let boundingBox: CGRect
    let confidence: Float
}
```

**URL Generation**:
- QR with URL → Direct use
- QR with text → Google search
- UPC/EAN → Product search (Google Shopping or Amazon)

---

### Layer 2: Text Recognition (OCR)

**Framework**: Vision (VNRecognizeTextRequest)

**Configuration**:
```swift
request.recognitionLevel = .accurate  // vs .fast
request.usesLanguageCorrection = true
request.recognitionLanguages = ["en-US"]  // or auto-detect
```

**Processing**:
1. Extract all recognized text
2. Run NSDataDetector for URLs
3. If URL found → Direct use
4. If document-like text → Text search
5. If short text → Entity search

**Output**:
```swift
struct DetectedText {
    let string: String
    let confidence: Float
    let boundingBox: CGRect
    let isURL: Bool
    let extractedURL: URL?
}
```

---

### Layer 3: Semantic Analysis (CoreML)

**Goal**: Understand WHAT is in the camera view and create meaningful search queries.

#### Option A: Image Classification Only

**Models**:
- MobileNetV2 (bundled with iOS, via VNClassifyImageRequest)
- EfficientNet (custom bundle, ~20MB)
- ResNet50 (custom bundle, ~100MB)

**Output**: Top-N class labels with confidence

**Pros**:
- Simple to implement
- Small model size
- Fast inference

**Cons**:
- Limited to 1000 ImageNet classes
- No spatial understanding
- Can't distinguish multiple objects

#### Option B: Object Detection

**Models**:
- YOLOv8 (custom bundle, ~25MB)
- MobileNet-SSD (custom bundle, ~20MB)
- Vision's built-in (iOS 17+)

**Output**: Bounding boxes + class labels

**Pros**:
- Can detect multiple objects
- Spatial awareness
- Can highlight detected object in UI

**Cons**:
- Larger models
- More complex integration
- Limited to trained classes

#### Option C: Semantic Segmentation

**Models**:
- DeepLabV3 (Apple's bundled version)
- BiSeNet (custom, ~15MB)
- Custom trained model

**Output**: Per-pixel class labels

**Pros**:
- Full scene understanding
- Can identify dominant content
- Works well for nature/outdoor scenes

**Cons**:
- More expensive computation
- Post-processing needed
- May be overkill for link generation

#### Option D: Vision-Language Model (Advanced)

**Models**:
- CLIP (OpenAI, ~150MB)
- BLIP (Salesforce, ~200MB)
- Apple's on-device ML (iOS 18+?)

**Output**: Free-form text description

**Pros**:
- Natural language understanding
- Can describe anything
- Most flexible

**Cons**:
- Large model size
- Slower inference
- May require server-side

---

### Recommended Approach: Hybrid Pipeline

```
Frame Input
     ↓
┌────┴────┐
│ Stage 1 │ → QR/Barcode (Vision, always runs)
└────┬────┘
     ↓ (if no barcode)
┌────┴────┐
│ Stage 2 │ → OCR Text (Vision, always runs)
└────┬────┘
     ↓ (if no URL in text)
┌────┴────┐
│ Stage 3 │ → Classification (CoreML, runs if needed)
└────┬────┘
     ↓
Result Aggregation
```

**Stage 3 Model Selection**:

| Use Case | Recommended Model | Size | Speed |
|----------|------------------|------|-------|
| MVP/Quick ship | VNClassifyImageRequest | 0 (built-in) | Fast |
| Better accuracy | MobileNetV2/V3 | ~15MB | Fast |
| Object detection | YOLOv8-nano | ~6MB | Fast |
| Best quality | EfficientNet-B0 | ~20MB | Medium |

---

## CoreML Model Options

### Built-in (No Bundle Required)

#### VNClassifyImageRequest (iOS 17+)
```swift
let request = VNClassifyImageRequest()
// Returns VNClassificationObservation with identifier + confidence
```

**Pros**: Zero bundle size, Apple-maintained
**Cons**: iOS 17+ only, limited classes

#### VNGenerateImageFeaturePrintRequest
```swift
// Generates feature vector for similarity comparison
```

**Use case**: Compare against known reference images

---

### Bundled Models (Requires Download/Bundle)

#### MobileNetV2 (Apple's Core ML Model Zoo)
- **Size**: 14MB
- **Classes**: 1000 (ImageNet)
- **Speed**: ~10ms on iPhone 15
- **Download**: [Apple ML Models](https://developer.apple.com/machine-learning/models/)

#### YOLOv8-nano
- **Size**: 6MB
- **Classes**: 80 (COCO)
- **Speed**: ~15ms on iPhone 15
- **Output**: Bounding boxes + labels
- **Download**: [Ultralytics](https://docs.ultralytics.com/modes/export/#coreml)

#### DeepLabV3 (Segmentation)
- **Size**: 8MB (MobileNet backbone)
- **Classes**: 21 (Pascal VOC)
- **Speed**: ~30ms on iPhone 15
- **Download**: [Apple ML Models](https://developer.apple.com/machine-learning/models/)

---

### Custom Model Training (Future)

If built-in models don't meet needs:

1. **Create ML** (Apple's tool)
   - Train image classifier with custom categories
   - Export directly to CoreML format

2. **Transfer Learning**
   - Fine-tune MobileNet/EfficientNet on custom data
   - Categories: Products, Plants, Animals, Food, Landmarks, Art

3. **Cloud API Fallback**
   - Google Cloud Vision API
   - AWS Rekognition
   - OpenAI Vision API
   - Use when on-device fails or for advanced features

---

## Content-to-URL Mapping

### Direct URL Sources

| Source | URL Generation |
|--------|---------------|
| QR Code with URL | Use directly |
| Text with URL (OCR) | Use directly |
| QR Code with text | `google.com/search?q={text}` |

### Search-Based URLs

| Content Type | Search URL Template |
|-------------|---------------------|
| Barcode (UPC) | `google.com/search?tbm=shop&q={barcode}` |
| Product | `google.com/search?tbm=shop&q={label}` |
| Plant | `google.com/search?q={label}+plant+identification` |
| Animal | `google.com/search?q={label}+species` |
| Food | `google.com/search?q={label}+recipe` |
| Landmark | `google.com/search?q={label}+landmark` |
| Artwork | `google.com/search?q={label}+artwork` |
| Document text | `google.com/search?q="{extracted_text}"` |
| Generic | `google.com/search?q={label}` |

### Specialized Search Providers

| Content | Alternative URL |
|---------|----------------|
| Barcode | `amazon.com/s?k={barcode}` |
| Plant | `inaturalist.org/taxa/search?q={label}` |
| Artwork | `artstor.org/search/{label}` |
| Landmark | `maps.google.com/search/{label}` |
| Food | `allrecipes.com/search?q={label}` |

**Configuration**: User could choose preferred providers in settings.

---

## UI/UX Design

### Camera View (Minimal)

```
┌─────────────────────────────────────┐
│ ← Cancel                    ⚙️      │  ← Navigation bar
├─────────────────────────────────────┤
│                                     │
│                                     │
│         ┌─────────────┐             │
│         │             │             │  ← Viewfinder
│         │   Camera    │             │     (with scanning overlay)
│         │   Preview   │             │
│         │             │             │
│         └─────────────┘             │
│                                     │
│                                     │
├─────────────────────────────────────┤
│  🔍 Scanning for content...         │  ← Status
│                                     │
│  ○ QR Codes  ○ Text  ○ Objects      │  ← Mode indicators
│                                     │
│         ┌─────────────┐             │
│         │  📷 Capture │             │  ← Manual capture button
│         └─────────────┘             │
└─────────────────────────────────────┘
```

### Detection Overlay

When content is detected, show overlay on camera:

```
┌─────────────────────────────────────┐
│                                     │
│      ┌─────────────────────┐        │
│      │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│        │  ← Highlighted region
│      │▓▓▓ QR CODE HERE ▓▓▓▓│        │
│      │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│        │
│      └─────────────────────┘        │
│                                     │
├─────────────────────────────────────┤
│  ✅ QR Code Detected                │
│  https://example.com/page           │
│                                     │
│  [Create Diver Link]                │
└─────────────────────────────────────┘
```

### Result Confirmation

After detection, show confirmation:

```
┌─────────────────────────────────────┐
│                                     │
│        ┌─────────────────┐          │
│        │   [Thumbnail]   │          │
│        │   of captured   │          │
│        │     content     │          │
│        └─────────────────┘          │
│                                     │
│  🔗 QR Code                         │
│  ─────────────────────────          │
│  https://example.com/article/123    │
│                                     │
│  OR                                 │
│                                     │
│  🌿 Plant Identified                │
│  ─────────────────────────          │
│  Monstera Deliciosa                 │
│  Confidence: 94%                    │
│  Search: "monstera deliciosa care"  │
│                                     │
├─────────────────────────────────────┤
│                                     │
│  [Create Diver Link]   [Retry]      │
│                                     │
│  ☑️ Open Messages after creating    │
│                                     │
└─────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: Camera Foundation (MVP)

**Goal**: QR code scanning + direct URL capture

**Components**:
- [ ] AVCaptureSession setup
- [ ] Camera preview view (SwiftUI)
- [ ] VNDetectBarcodesRequest integration
- [ ] QR URL extraction
- [ ] Diver link creation flow
- [ ] Basic UI (viewfinder + capture button)

**Deliverable**: Working QR scanner that creates Diver links

**Estimated Effort**: 1-2 days

---

### Phase 2: Text Recognition

**Goal**: OCR for visible URLs and document text

**Components**:
- [ ] VNRecognizeTextRequest integration
- [ ] URL detection in recognized text
- [ ] Document vs. single-line text classification
- [ ] Text-based search URL generation
- [ ] UI updates for text detection

**Deliverable**: Can capture URLs from business cards, screenshots, documents

**Estimated Effort**: 1 day

---

### Phase 3: Semantic Classification

**Goal**: Understand objects/scenes and generate contextual searches

**Components**:
- [ ] CoreML model integration (start with VNClassifyImageRequest)
- [ ] Object label extraction
- [ ] Content type classification (product, plant, food, etc.)
- [ ] Contextual search URL generation
- [ ] UI for showing classification results
- [ ] Confidence threshold tuning

**Deliverable**: Can identify products, plants, food, etc. and create relevant search links

**Estimated Effort**: 2-3 days

---

### Phase 4: Enhanced Models (Optional)

**Goal**: Better accuracy with custom/larger models

**Components**:
- [ ] Evaluate alternative models (YOLOv8, EfficientNet)
- [ ] Bundle selected model with app
- [ ] Object detection with bounding boxes
- [ ] Multi-object handling
- [ ] Performance optimization

**Deliverable**: More accurate, faster detection

**Estimated Effort**: 2-3 days

---

### Phase 5: Polish & Edge Cases

**Goal**: Production-ready feature

**Components**:
- [ ] Low-light handling
- [ ] Blurry image detection
- [ ] Multiple content type handling (QR + text in same frame)
- [ ] Haptic feedback on detection
- [ ] Accessibility (VoiceOver)
- [ ] Error states and recovery
- [ ] Settings (preferred search providers, auto-share)

**Deliverable**: Polished, reliable feature

**Estimated Effort**: 2-3 days

---

## Open Questions

### 1. Model Selection

**Question**: Which CoreML model should we use for Phase 3?

**Options**:
- A) VNClassifyImageRequest (built-in, iOS 17+)
- B) MobileNetV2 (bundled, 14MB, works on iOS 14+)
- C) YOLOv8-nano (bundled, 6MB, object detection)
- D) Custom trained model (future)

**Recommendation**: Start with (A) for MVP, add (B) as fallback for older iOS.

---

### 2. Search Provider

**Question**: What search engine should be used for semantic searches?

**Options**:
- A) Google (most comprehensive)
- B) DuckDuckGo (privacy-focused)
- C) User's default browser search
- D) Specialized per content type (Amazon for products, etc.)

**Recommendation**: Start with (A), add settings for (D) later.

---

### 3. Auto-Capture vs Manual

**Question**: Should we auto-capture when confident, or require user tap?

**Options**:
- A) Auto-capture at high confidence (>90%)
- B) Always require manual capture
- C) Configurable in settings

**Recommendation**: (C) with default to auto-capture for QR codes, manual for everything else.

---

### 4. Multiple Detections

**Question**: What if camera sees QR code AND recognizable object?

**Options**:
- A) Prioritize QR code (direct URL always wins)
- B) Show picker for user to choose
- C) Create multiple Diver links

**Recommendation**: (A) for MVP, consider (B) for future.

---

### 5. Offline Behavior

**Question**: Should semantic search work offline?

**Options**:
- A) Require network (search URLs need internet anyway)
- B) Cache common searches
- C) Save for later processing

**Recommendation**: (A) for MVP - if no network, still create Diver link to search URL (user can open when online).

---

## Risks & Mitigations

### Risk 1: CoreML Model Accuracy

**Risk**: Built-in classification not accurate enough for useful searches

**Mitigation**:
- Start with QR/text (high accuracy)
- Add classification as "experimental" feature
- Allow user to edit search query before creating link
- Consider cloud API fallback for complex cases

---

### Risk 2: Performance on Older Devices

**Risk**: Real-time analysis too slow on older iPhones

**Mitigation**:
- Throttle analysis to 5-10 FPS
- Use smaller models
- Skip classification on older devices, only do QR/text
- Show loading indicator during analysis

---

### Risk 3: Battery Drain

**Risk**: Camera + CoreML drains battery quickly

**Mitigation**:
- Auto-timeout camera after 30 seconds
- Only run classification every few frames
- Stop analysis when app backgrounded
- Show battery warning for extended use

---

### Risk 4: Privacy Concerns

**Risk**: Users uncomfortable with camera analyzing everything

**Mitigation**:
- Clear indication when camera is active
- All processing on-device
- No images saved (unless user explicitly captures)
- Clear privacy policy

---

### Risk 5: Action Button Availability

**Risk**: Action Button only on iPhone 15 Pro+

**Mitigation**:
- Also expose as regular app feature
- Add to Shortcuts for other devices
- Consider Control Center shortcut (iOS 18)

---

## Success Criteria

### MVP (Phase 1-2)
- [ ] QR codes captured with <500ms latency
- [ ] URLs extracted from text with >90% accuracy
- [ ] Diver links created and shared successfully
- [ ] Works on iPhone 12 and newer

### Full Feature (Phase 3-5)
- [ ] Object classification with >70% accuracy
- [ ] Context-appropriate search URLs generated
- [ ] <1 second from capture to link creation
- [ ] User satisfaction with search results
- [ ] <5% battery drain for typical session (30 seconds)

---

## Next Steps

1. **Review this plan** - Does the approach make sense?
2. **Decide on model** - Which CoreML option for Phase 3?
3. **Confirm UX** - Is the proposed UI acceptable?
4. **Prioritize phases** - Skip any? Reorder?
5. **Begin Phase 1** - Camera + QR scanning MVP

---

## Appendix: Code Snippets

### A. Basic Camera Setup

```swift
import AVFoundation

class CameraService: NSObject, ObservableObject {
    let captureSession = AVCaptureSession()

    func setup() throws {
        captureSession.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.unavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        captureSession.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: analysisQueue)
        captureSession.addOutput(output)
    }
}
```

### B. QR Detection

```swift
import Vision

func detectQRCodes(in pixelBuffer: CVPixelBuffer) {
    let request = VNDetectBarcodesRequest { request, error in
        guard let results = request.results as? [VNBarcodeObservation] else { return }

        for barcode in results where barcode.symbology == .qr {
            if let payload = barcode.payloadStringValue,
               let url = URL(string: payload) {
                // Found QR code with URL
                self.handleDetectedURL(url)
            }
        }
    }

    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
    try? handler.perform([request])
}
```

### C. CoreML Classification

```swift
import CoreML
import Vision

func classifyImage(_ pixelBuffer: CVPixelBuffer) {
    // Using built-in classifier (iOS 17+)
    let request = VNClassifyImageRequest { request, error in
        guard let results = request.results as? [VNClassificationObservation] else { return }

        if let top = results.first, top.confidence > 0.7 {
            let label = top.identifier
            let searchURL = self.createSearchURL(for: label)
            self.handleDetectedContent(label: label, url: searchURL)
        }
    }

    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
    try? handler.perform([request])
}
```

---

**End of Plan Document**
