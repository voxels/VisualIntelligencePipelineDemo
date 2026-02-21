# Visual Intelligence Pipeline — Visual Intelligence for Your Everyday Life

**Visual Intelligence Pipeline** is a multi-platform application that transforms the way you capture, organize, and understand the world around you. It combines real-time camera intelligence, rich contextual enrichment, AI-powered semantic understanding, and **ethical commerce intelligence** into a single, elegant experience. It also serves as a universal hub for saving and organizing links shared from Safari, TikTok, YouTube, and any app with a share sheet.

## 🎯 Core Concept

Point your camera at anything — a product on a shelf, a restaurant sign, a document, a landmark — and Visual Intelligence Pipeline instantly identifies it, enriches it with contextual metadata, scores it across ethical and economic dimensions, and organizes it into an intelligent, searchable library. An optional M-series Mac edge node on your home network accelerates processing with larger ML models.

---

## ✨ Key Features

### Intelligent Sifting

Uses Apple's Vision framework (`VNGenerateForegroundInstanceMaskRequest`) to automatically detect and isolate subjects in captures. Subjects are "sifted" out from the background, producing clean cutouts with proper alpha channels — ready for sharing or further analysis. A real-time glow overlay highlights detected subjects during the camera preview.

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

### Commerce Intelligence

Products detected via barcode or visual classification are automatically scored across **7 strategies simultaneously**:

| Engine | What It Scores | Data Sources |
|--------|----------------|--------------|
| **Ethics** | Carbon intensity, certifications, Eco-Score, product safety, nutrition, packaging, privacy, EPA compliance, energy efficiency (10 sub-dimensions) | Open *Facts (4 databases), Climate TRACE, gov APIs |
| **Brand Fit** | Brand match, category familiarity, preference strength | UserConcept knowledge graph |
| **Value** | Price trend direction, forecast confidence, price positioning | World Bank, BLS PPI, FRED |
| **Durability** | Category longevity, brand durability, repairability, material quality | iFixit, EU repairability framework |
| **Social Proof** | Reddit sentiment, expert reviews, complaint/recall history, demand signals | Reddit API, CPSC, FDA |
| **Health Fit** | Nutritional alignment, allergen safety, dietary compliance, NOVA processing | HealthKit, Open Food Facts |
| **Total Cost** | Energy cost, consumables, subscriptions, replacement cycle, resale value | Energy Star, category-aware estimation |

- **Score History** — Swift Charts visualize how product scores, prices, and your preference profile evolve over time via `ScoreSnapshot` time-series.
- **Preference Learning** — `PreferenceLearner` derives per-strategy weights from your owned product history. Sharing products with friends gets 1.5× endorsement weight.
- **"I Own This" / "I Want This"** — Track products across ownership states: **owned** (confirmed purchase), **wishlisted** (want but haven't bought), **considering** (CTA tapped, evaluating), or **returned**. All states feed the preference model — wishlisted products signal intent, owned products confirm taste.
- **SLM Advisory** — On-device Apple Intelligence generates Buy Now / Wait / Neutral timing recommendations using enriched product context.
- **Free/Open Data Only** — No paid APIs. All data from ODbL/CC0 databases, gov APIs, and free tiers.

### Edge Computing (Home Network ML Offloading)

Any device on your home network can offload ML inference to a more powerful M-series Mac or iPad via **Swift Distributed Actors** over Bonjour (`_visualintel._tcp`, TLS 1.3). The edge node hosts larger models (FastVLM 3B+), runs nowcasting projections, and handles ESG/commerce data enrichment — while your iPhone stays responsive. Transparent fallback to on-device when no edge node is reachable.

A standalone **macOS Edge Daemon** (menu-bar app) provides a dashboard showing connected clients, model status, inference throughput, and data cache health.

### Intelligent Session Management

Captures are automatically grouped by location and time into cohesive **sessions** via `SessionClusteringService`. Multiple captures at the same MapKit landmark merge into a single session history. Sessions support bulk location editing, context resumption, and reprocessing. Session summaries aggregate all item metadata for deeply contextual AI-generated summaries.

### Library Maintenance

A built-in **Rebuild Library** tool (Settings > Rebuild Library) repairs orphaned items, recovers stuck processing states, consolidates fragmented sessions, reconciles relationships, and regenerates all session summaries — with live progress status.

### Universal Link Organization

Save links from Safari, YouTube, TikTok, or any app via the Share Sheet extension. Links are wrapped in a proprietary format (HMAC-signed, tamper-proof URLs via `DiverLinkWrapper`) and processed through the enrichment pipeline. Supports Universal Links and custom scheme links for deep linking and Shared with You integration.

### Context Tags, Daily Focus & Agentic Chat

Add custom context tags to captures. A **Daily Focus** summary aggregates the day's activity into an AI-generated brief. You can also converse directly with your visual memory via an integrated **Agentic Chat** interface powered by the FastVLM/SLM system and CLaRa.

### Siri, Shortcuts & Widgets

Fully integrated with Apple's system — 6 App Intents, pre-built shortcut templates, and Home & Lock screen widgets.

---

## 🏗️ Architecture Highlights

- **Modular Swift Packages** — `DiverKit` (ML & pipeline orchestration, 62 services, 18 protocols), `DiverShared` (data models & utilities), and the main app target.
- **Local-First with Sync** — SwiftData persistence backed by CloudKit for seamless cross-device access.
- **On-Device ML** — Apple Vision (6 request types per pass), FastVLM via MLX Swift, Apple Intelligence via Foundation Models.
- **Edge Computing** — Swift Distributed Actors over Bonjour for transparent ML offloading to M-series Macs.
- **Commerce Intelligence** — 7 scoring strategies, Open *Facts cascade, preference learning, score snapshots.
- **Queue-Based Reliability** — File-based queue ensures no capture or link is ever lost.
- **Protocol-Based DI** — 18 service protocols (`IntelligenceProcessing`, `ContextProcessing`, `AestheticsScoring`, `FastVLMAnalyzing`, `ProductScoringStrategy`, `ProductRecommending`, `ESGEnriching`, etc) enable mock injection for testing.

---

## 📱 Platform & Requirements

| Platform | Minimum Version | Role |
|----------|----------------|------|
| **iOS** | 26.0+ | Primary client — camera, capture, full UI |
| **iPadOS** | 26.0+ | Client + optional edge node (M-series) |
| **macOS** | 26.0+ | Edge node daemon (menu-bar app) |
| **visionOS** | 26.3+ | Spatial UI, ARKit object tracking |

- **Apple Intelligence:** Required for on-device LLM features (summaries, tags, purposes, commerce advisory)
- **FastVLM:** Optional, requires ~500MB download and sufficient device memory
- **Edge Node:** Optional, M-series Mac or iPad on local network
- **Built with:** Swift, SwiftUI, SwiftData, Vision, MapKit, Foundation Models, MLX Swift, Swift Charts, Distributed Actors, Network framework

---

Visual Intelligence Pipeline isn't just another bookmarking app or camera tool — it's an **intelligence layer** for your physical and digital world, turning fleeting moments and scattered links into a structured, searchable, and deeply enriched personal knowledge base.
