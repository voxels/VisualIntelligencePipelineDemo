# Visual Intelligence Pipeline

**Visual Intelligence Pipeline** transforms the way you capture, organize, and understand the world around you. It combines real-time camera intelligence, rich contextual enrichment, and AI-powered semantic understanding into a single, elegant iOS experience. It also serves as a universal hub for saving and organizing links shared from Safari, TikTok, YouTube, and any app with a share sheet.

Point your camera at anything — a product on a shelf, a restaurant sign, a document, a landmark — and Visual Intelligence instantly identifies it, enriches it with contextual metadata, and organizes it into an intelligent, searchable library.

## Core Features

### Intelligent Sifting
Uses Apple's Vision framework to automatically detect and isolate subjects in your captures. Subjects are "sifted" out from the background, producing clean cutouts with proper alpha channels — ready for sharing or further analysis.

### Deep Contextual Enrichment
Every capture is automatically enriched with layers of real-world context:
- **Location** — Foursquare venues and Apple MapKit landmarks via a unified `LocationSearchAggregator`, with user-pinnable location persistence.
- **Weather** — Current environmental conditions via WeatherKit.
- **Web Intelligence** — DuckDuckGo enrichments, link metadata extraction, and rich link previews.
- **Aesthetics Scoring** — Quality scores for images and video frames.
- **Document Detection** — Automatic perspective correction and saving of detected documents.
- **Music Recognition** — Apple Music and Spotify identification for music-related captures.

### AI-Powered Understanding
On-device Apple Intelligence (`SystemLanguageModel`) generates summaries, identifies purposes, and suggests intelligent concept tags. LLM prompts are enriched with weather, location, OCR text, and structured web data for deeply contextual results — all processed locally for maximum privacy.

### Smart Sessions
Captures are automatically grouped by location and time into cohesive **sessions** with AI-generated summaries. Multiple captures at the same venue merge into a single session history. Sessions support bulk location editing, context resumption, and reprocessing.

### Context Tags & Daily Focus
Add custom context tags (e.g., "Gift for Mom," "Home renovation ideas") to any capture. A **Daily Focus** summary aggregates the day's activity into an AI-generated brief.

### Universal Link Organization
Save links from Safari, YouTube, TikTok, or any app via the Share Sheet extension. Links are wrapped in a proprietary format (HMAC-signed, tamper-proof URLs) and processed through the enrichment pipeline for automatic metadata extraction.

### Siri, Shortcuts & Widgets
Fully integrated with Apple's system — 5 App Intents (Save, Share, Search, Get Recent, Open), pre-built shortcut templates, and Home & Lock screen widgets.

## Architecture

The project is modularized using Swift Package Manager:

| Module | Purpose |
|--------|---------|
| `VisualIntelligencePipeline/` | Main application target and UI |
| `DiverKit/` | Core logic — ML pipeline, services, view models, models, storage |
| `DiverShared/` | Pure Swift shared data models and utilities |
| `LocalPackages/YahooSearch` | Local package for web search enrichment |

**Key Technologies:** Swift, SwiftUI, SwiftData + CloudKit, Vision, CoreML, MapKit, WeatherKit, Apple Intelligence

## Getting Started

1. Open `VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj` in Xcode.
2. Select the `VisualIntelligencePipeline` scheme.
3. Run on an iOS Simulator or Device (iOS 26.0+ required for Apple Intelligence).

## Testing

```bash
# Build for iOS Simulator
xcodebuild -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj \
  -scheme VisualIntelligencePipeline \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run DiverKit package tests
cd DiverKit && swift test

# Run DiverShared package tests
cd DiverShared && swift test
```

## Documentation

- [App Summary](VisualIntelligencePipelineDemo/Documentation/APP_SUMMARY.md)
- [Beta Review Notes](VisualIntelligencePipelineDemo/Documentation/BETA_REVIEW_NOTES.md)
- [Changelog](VisualIntelligencePipelineDemo/changelog.md)

## Copyright

2026 Secret Atomics