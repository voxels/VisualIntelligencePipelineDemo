# Visual Intelligence Pipeline — Visual Intelligence for Your Everyday Life

**Visual Intelligence Pipeline** is a universal iOS and macOS application that transforms the way you capture, organize, and understand the world around you. It combines real-time camera intelligence, rich contextual enrichment, and AI-powered semantic understanding into a single, elegant experience.

## 🎯 Core Concept

Point your camera at anything — a product on a shelf, a restaurant sign, a document, a landmark — and Visual Intelligence Pipeline instantly identifies it, enriches it with contextual metadata, and organizes it into an intelligent, searchable library. It also serves as a universal hub for saving and organizing links shared from Safari, TikTok, YouTube, and any app with a share sheet.

---

## ✨ Key Features

### Contextual Enrichment Pipeline

Every capture is automatically enriched with layers of real-world context:

- **Location** — Foursquare venues and Apple MapKit landmarks/addresses via a unified `LocationSearchAggregator`, with user-pinnable location persistence.
- **Weather** — Current environmental conditions via WeatherKit, embedded directly into the capture's context.
- **Web Intelligence** — Metadata extraction for related links, DuckDuckGo enrichments, and rich link previews.
- **Aesthetics Scoring** — Quality scores for images and video frames so you always keep the best shots.
- **Document Detection** — Automatic perspective correction and saving of detected documents.
- **Apple Music & Spotify** — Recognition and linking of music-related captures.

### AI-Powered Semantic Understanding

Visual Intelligence Pipeline uses Apple Intelligence (`SystemLanguageModel`) for on-device context generation — including summaries, purpose identification, and intelligent concept tagging. LLM prompts are enriched with weather, location tips, OCR/transcription text, and structured web data for deeply contextual results.

### Intelligent Session Management

Captures are automatically grouped by location and time into cohesive **sessions**. Multiple captures at the same Foursquare venue or MapKit landmark merge into a single session history, providing a holistic, AI-generated summary of each visit. Sessions support bulk location editing, context resumption, and reprocessing.

### Universal Link Organization

Beyond the camera, Visual Intelligence Pipeline is a central repository for any shared content. Save links from Safari, YouTube, TikTok, or any app via the Share Sheet extension. Links are wrapped in a proprietary format (HMAC-signed, tamper-proof URLs) and processed through the enrichment pipeline for automatic metadata extraction.

### Context Tags & Daily Focus

Add custom context tags (e.g., "Gift for Mom," "Home renovation ideas") to captures. A **Daily Focus** summary aggregates the day's activity into an AI-generated brief, keeping you oriented on what matters.

### Siri, Shortcuts & Widgets

Fully integrated with Apple's system:

- **5 App Intents** — Save, Share, Search, Get Recent, and Open links via Siri voice commands.
- **Shortcuts** — Pre-built shortcut templates for automation workflows.
- **Widgets** — Home screen and Lock screen widgets for at-a-glance access to your library.

---

## 🏗️ Architecture Highlights

- **Modular Swift Packages** — `DiverKit` (ML & pipeline orchestration), `DiverShared` (data models & utilities), and the main app target.
- **Local-First with Sync** — SwiftData persistence backed by CloudKit for seamless cross-device access.
- **On-Device ML** — CoreML models (MiniLM embeddings, intent classification, taxonomy tagging) for semantic search, hybrid recommendation, and vector-based ranking — all running locally.
- **Queue-Based Reliability** — A file-based queue ensures no shared link or capture is ever lost, even under extension time limits or interruptions.

---

## 📱 Platform & Requirements

- **Platforms:** iOS 26+, macOS 26+, visionOS 26+
- **Apple Intelligence:** Required for on-device LLM features
- **Built with:** Swift, SwiftUI, SwiftData, Vision, MapKit, WeatherKit, CoreML

---

Visual Intelligence Pipeline isn't just another bookmarking app or camera tool — it's an **intelligence layer** for your physical and digital world, turning fleeting moments and scattered links into a structured, searchable, and deeply enriched personal knowledge base.
