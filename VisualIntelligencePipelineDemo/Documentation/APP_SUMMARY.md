# Visual Intelligence Pipeline — Visual Intelligence for Your Everyday Life

**Visual Intelligence Pipeline** is a universal iOS application that transforms the way you capture, organize, and understand the world around you. It combines real-time camera intelligence, rich contextual enrichment, and AI-powered semantic understanding into a single, elegant experience. It also serves as a universal hub for saving and organizing links shared from Safari, TikTok, YouTube, and any app with a share sheet.

## 🎯 Core Concept

Point your camera at anything — a product on a shelf, a restaurant sign, a document, a landmark — and Visual Intelligence Pipeline instantly identifies it, enriches it with contextual metadata, and organizes it into an intelligent, searchable library.

---

## ✨ Key Features

### Intelligent Sifting

Uses Apple's Vision framework (`VNGeneratePersonInstanceMaskRequest`) to automatically detect and isolate subjects in captures. Subjects are "sifted" out from the background, producing clean cutouts with proper alpha channels — ready for sharing or further analysis. A real-time glow overlay highlights detected subjects during the camera preview.

### Deep Contextual Enrichment

Every capture is automatically enriched with layers of real-world context:

- **Location** — Apple MapKit reverse geocoding with contact detection ("Home", friend's addresses). Foursquare venue search available in the location editing UI for manual place selection.
- **Web Intelligence** — Metadata extraction for web URLs and QR codes, with rich link previews.
- **Aesthetics Scoring** — Image quality scores bundled into the Vision analysis pass via `VNCalculateImageAestheticsScoresRequest`, plus brightness, contrast, and sharpness analysis.
- **Document Detection** — Automatic perspective correction via `VNDetectDocumentSegmentationRequest` and saving of detected documents as separate child items.
- **Music Recognition** — Apple Music and Spotify identification for music-related captures.

### AI-Powered Semantic Understanding

#### Apple Intelligence (SystemLanguageModel)
`ContextQuestionService` uses Apple's Foundation Models framework (`LanguageModelSession`) for on-device structured generation. Produces summaries, evidence-based statements, user intent identification, and descriptive tags. Supports context chaining for large inputs and structured output via the `@Generable` macro. Requires iOS 26.0+.

#### FastVLM (Opt-In)
`FastVLMEnrichmentService` runs Apple's FastVLM 0.5B model (~500MB) locally via MLX Swift for multimodal image understanding. Performs two-pass analysis: image description and context synthesis. Model is downloaded on-demand and managed with automatic memory pressure eviction.

### Intelligent Session Management

Captures are automatically grouped by location and time into cohesive **sessions** via `SessionClusteringService`. Multiple captures at the same MapKit landmark merge into a single session history, providing a holistic, AI-generated summary of each visit. Session summaries aggregate all item metadata — transcription, themes, tags, categories, location, web/document/QR context, FastVLM analysis, product metadata, and more. Sessions support bulk location editing, context resumption, and reprocessing.

### Library Maintenance

A built-in **Rebuild Library** tool (Settings > Rebuild Library) repairs orphaned items, recovers stuck processing states, consolidates fragmented sessions, reconciles relationships, and regenerates all session summaries — with live progress status.

### Universal Link Organization

Save links from Safari, YouTube, TikTok, or any app via the Share Sheet extension. Links are wrapped in a proprietary format (HMAC-signed, tamper-proof URLs via `DiverLinkWrapper`) and processed through the enrichment pipeline for automatic metadata extraction. Supports Universal Links (`https://secretatomics.com/...`) and custom scheme links (`secretatomics://...`) for deep linking and Shared with You integration.

### Context Tags & Daily Focus

Add custom context tags (e.g., "Gift for Mom," "Home renovation ideas") to captures. A **Daily Focus** summary aggregates the day's activity into an AI-generated brief, keeping you oriented on what matters.

### Shared with You

Links shared via iMessage automatically surface in the app through Apple's Shared with You framework. `SharedWithYouManager` tracks highlights and provides attribution in the detail view.

### Siri, Shortcuts & Widgets

Fully integrated with Apple's system:

- **5 App Intents** — Save, Share, Search, Get Recent, and Open links via Siri voice commands.
- **Shortcuts** — Pre-built shortcut templates for automation workflows.
- **Widgets** — Home screen and Lock screen widgets for at-a-glance access to your library.

---

## 🏗️ Architecture Highlights

- **Modular Swift Packages** — `DiverKit` (ML & pipeline orchestration, 36 services, 4 service protocols), `DiverShared` (data models & utilities), and the main app target.
- **Local-First with Sync** — SwiftData persistence backed by CloudKit for seamless cross-device access.
- **On-Device ML** — All inference runs locally: Apple Vision framework (6 request types in a single pass), FastVLM 0.5B via MLX Swift, and Apple Intelligence via Foundation Models.
- **Queue-Based Reliability** — A file-based queue ensures no shared link or capture is ever lost, even under extension time limits or interruptions.
- **Structured Context Pipeline** — `PipelineContext` aggregates typed fields from each enrichment service (Vision, location, web, knowledge graph) so that downstream ML consumers read structured data rather than parsing text.
- **Protocol-Based DI** — Core ML services (`IntelligenceProcessing`, `ContextProcessing`, `AestheticsScoring`, `FastVLMAnalyzing`) are abstracted behind `Sendable` protocols, enabling mock injection for unit testing.

---

## 📱 Platform & Requirements

- **Platforms:** iOS 26+
- **Apple Intelligence:** Required for on-device LLM features (summaries, tags, purposes)
- **FastVLM:** Optional, requires ~500MB download and sufficient device memory
- **Built with:** Swift, SwiftUI, SwiftData, Vision, MapKit, Foundation Models, MLX Swift

---

Visual Intelligence Pipeline isn't just another bookmarking app or camera tool — it's an **intelligence layer** for your physical and digital world, turning fleeting moments and scattered links into a structured, searchable, and deeply enriched personal knowledge base.
