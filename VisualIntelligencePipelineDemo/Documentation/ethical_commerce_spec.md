# Ethical Commerce & Micro-Decisions — Technical Specification

> **Draft:** 0.3  
> **Date:** 2026-02-19  
> **Status:** In-progress (single PR delivery)  
> **Parent:** [spec.md](../spec.md) §14  
> **Client Platforms:** iOS 26.3+, iPadOS 26.3+, visionOS 26.3+  
> **Edge Node Platforms:** macOS 26.3+ (M-series), iPadOS 26.3+ (M-series)

---

## 1. Problem Statement

Users lack real-time, contextual data when making purchase decisions about physical products. Sustainability certifications, inflation trajectories, and supply-chain trust data exist in scattered, inaccessible databases. This spec defines an AR/camera overlay system that surfaces this data at the point of decision — anchored to the physical product a user is looking at — and provides a commerce path with ethical filtering, affiliate routing, and personal financial awareness.

The system uses an M-series Mac (or iPad) as a local ML edge node, connected to client devices (iPhone, iPad, Vision Pro) via Swift distributed actors over the home network. When no edge node is available, clients fall back to on-device inference.

---

## 2. Architecture

### 2.1 Universal ML Offloading

> [!IMPORTANT]
> This architecture applies to **all** intelligence work in the pipeline — both the existing capture/enrichment features (§1–13 of `spec.md`) and the Ethical Commerce features described here. Any device on the home network can offload ML inference to a more powerful device when one is available.

**Discovery:** Bonjour (`NWBrowser` / `NWListener`) discovers available edge nodes on the local network. The client selects the highest-capability node based on advertised Neural Engine TOPS.

**Fallback:** When no edge node is reachable, the client runs inference locally using its own Neural Engine (existing behavior).

### 2.2 Compute Split Rationale

| Device | Chip | Neural Engine | Role |
|--------|------|--------------|------|
| **Mac edge node** | M4+ | 16-core, **38 TOPS** | Heavy ML inference (YOLO, nowcasting, LLM reasoning, FastVLM) |
| **iPad edge node** | M5+ | TBD (expected 40+ TOPS) | Same as Mac when available; also a client |
| **Vision Pro** | M2 + R1 | M2: ~15.8 TOPS; R1: sensor fusion (12ms) | ARKit tracking, HUD rendering, lightweight on-device classification |
| **iPhone** | A18+ | 16-core NE | Client — on-device inference when no edge node available |

**Why offload:**
- M4's 38 TOPS Neural Engine has ~2.4× the throughput of the M2/A18, with no competition from OS-level spatial tracking or foreground UI
- Mac has access to larger memory (up to 128GB unified on M4 Max) for hosting larger LLM models via MLX Swift
- iPhone/iPad foreground apps compete for NE time with system intelligence features; offloading preserves battery and responsiveness
- The existing FastVLM 0.5B pipeline on iPhone can transparently hand off to a 3B+ model running on the Mac

### 2.3 System Topology

```
┌──────────────────────┐
│  iPhone / iPad       │           ┌────────────────────────────┐
│  (iOS/iPadOS Client) │◀────────▶│  Mac / iPad Edge Node      │
├──────────────────────┤  Bonjour  │  (macOS/iPadOS Service)    │
│  Camera / ARKit      │  + NW    ├────────────────────────────┤
│  Lightweight CoreML  │  Framework│  distributed actor:        │
│  Distributed Actor   │  (LAN)   │    InferenceService        │
│    Client (resolver) │           │    NowcastingService       │
└──────────────────────┘           │    EnrichmentService       │
                                   │    CommerceService         │
┌──────────────────────┐           │                            │
│  Apple Vision Pro    │◀────────▶│  CoreML YOLO/DETR (NE)     │
│  (visionOS Client)   │  Bonjour  │  MLX Swift LLM (~3B)       │
├──────────────────────┤           │  Nowcasting Engine (Swift) │
│  ARKit Object Track  │           └────────────┬───────────────┘
│  RealityKit HUD      │                        │ HTTPS
│  Barcode Detection   │           ┌────────────▼───────────────┐
└──────────────────────┘           │  External APIs             │
                                   │  (ESG, Pricing, Commerce,  │
                                   │   Plaid, FinanceKit)       │
                                   └────────────────────────────┘
```

### 2.4 Transport: Swift Distributed Actors

Communication uses the `Distributed` framework (iOS 16+ / macOS 13+, SE-0336, SE-0344).

**Transport implementation:** Custom `DistributedActorSystem` conformance using:
- **Discovery:** `NWBrowser` / `NWListener` (Network framework) with Bonjour service type `_visualintel._tcp`
- **Serialization:** `Codable`-based envelope encoding (TicTacFish `WebSocketActorSystem` pattern)
- **Connection:** `NWConnection` (TLS 1.3, LAN-only)

**Key protocol surface:**

```swift
import Distributed

distributed actor InferenceService {
    typealias ActorSystem = VisualIntelligenceActorSystem

    /// Classify a product from a camera frame crop.
    distributed func classify(
        frameData: Data,
        boundingBox: CGRect
    ) async throws -> ProductClassification

    /// Run existing pipeline Vision analysis on edge node.
    distributed func analyzeVisual(
        imageData: Data
    ) async throws -> VisionAnalysisResult

    /// Run FastVLM / LLM analysis on edge node (larger model than on-device).
    distributed func analyzeLLM(
        imageData: Data,
        context: PipelineContext
    ) async throws -> LLMAnalysisResult

    /// Run nowcasting model on cached price series.
    distributed func nowcast(
        commodityID: String
    ) async throws -> PriceTrajectory

    /// Query ESG data for a resolved product entity.
    distributed func enrichESG(
        productID: String
    ) async throws -> ESGEnrichment?
}
```

**Bonjour registration** (`Info.plist` on edge node):
```xml
<key>NSBonjourServices</key>
<array>
    <string>_visualintel._tcp</string>
</array>
```

---

## 3. Features

### 3.1 Product Identification & Multi-Strategy Scoring Overlay

When the user views a physical product (via camera on iPhone/iPad or spatial tracking on Vision Pro), the system identifies it and overlays scores from **all active scoring strategies simultaneously**.

| Stage | Device | Technology | Latency Target |
|-------|--------|-----------|---------------|
| Object detection & bounding box | Client | ARKit / AVFoundation | <50ms |
| Barcode/QR scan | Client | ARKit / Vision framework | <100ms |
| Product classification | Edge node (or client fallback) | CoreML YOLO/DETR on Neural Engine | <200ms |
| Entity resolution (barcode → product ID) | Edge node | Local SQLite lookup + API fallback | <100ms |
| Multi-strategy scoring | Edge node or client | `[ProductScoringStrategy]` array | <500ms total |
| ESG data retrieval | Edge node | HTTPS API call (cached) | <500ms (cached: <10ms) |

**Scoring Strategies (all active simultaneously):**

| Strategy | Protocol | Dimensions | Source |
|----------|----------|-----------|--------|
| **ESG** | `ESGScoringStrategy` | Carbon intensity, data quality, certifications, Eco-Score | Open Food Facts, Climate TRACE |
| **Brand Fit** | `BrandAlignmentStrategy` | Direct match, category familiarity, preference strength | `UserConcept` knowledge graph |
| **Value** | `ValueScoringStrategy` | Price trend, forecast confidence, price position | Price APIs, nowcasting |
| **Durability** | `DurabilityScoringStrategy` | Category longevity, brand durability, repairability, material quality | Category heuristics, EU framework |

Each item carries an array of `ProductScore` — one per strategy. The overlay renders **all scores** with per-dimension breakdowns.

**Overlay Output** (spatial panel on Vision Pro, card overlay on iOS/iPadOS):
- **Per-strategy scores** with dimension bars (composite badge per strategy)
- **Timing recommendation** — Buy now / Wait / Neutral (based on economic trends, independent of ethical scores)
- **Data Quality Tier** (1–5, see §3.5 for PCAF explanation)
- **Score summary** — SLM-generated natural language synthesis of all strategy scores
- **"Buy" CTA** linking to preferred commerce platform (see §3.4)

### 3.2 Pricing Nowcast Overlay

> [!NOTE]
> Nowcasting uses mixed-frequency econometric models to estimate near-real-time economic indicators before official statistics are published.

| Aspect | Specification |
|--------|--------------|
| **Data inputs** | Public commodity price APIs (World Bank, FRED, BLS PPI), refreshed daily |
| **Model** | Dynamic Factor Model (DFM) in Swift using Accelerate framework (BLAS/LAPACK) |
| **Inference location** | Mac/iPad edge node (CPU-bound matrix operations via Accelerate) |
| **Output** | 14-day price trajectory estimate with confidence interval |
| **Display** | Sparkline chart + directional indicator ("Trending ↑ 3.2% over 14 days") |

### 3.3 Advisory Decisions & Timing Recommendations

> [!IMPORTANT]
> The system surfaces recommendations and a commerce CTA. The user always confirms any action. No purchases are executed without explicit user tap.

Advisory decisions have **two independent axes**:
1. **Strategy scores** — Per-engine recommendation (ESG, brand, value, durability) based on product characteristics
2. **Timing recommendation** — Buy now / Wait / Neutral based on short-term economic trends (nowcasting), independent of strategy scores

**Timing Outputs (economic trend-based):**

| Output | Trigger | Display |
|--------|---------|---------|
| `BUY_NOW` | Prices trending up, high confidence | Green clock + "Prices rising — buy now" |
| `WAIT` | Prices trending down, high confidence | Orange clock + "Price trending down — consider waiting" |
| `NEUTRAL` | Stable prices or low confidence | Gray indicator + "Prices stable" |

**Strategy Score Summaries:**

Each scoring engine produces an independent `ProductScore` with an `overallScore` (0.0–1.0). The SLM (`@Generable ProductInsight`) synthesizes all strategy scores into a natural-language summary:

```swift
@Generable(description: "Per-strategy score summary")
struct ProductInsight {
    @Guide(description: "Score summary per strategy engine")
    var scoreSummaries: [StrategyScoreSummary]
    
    @Guide(description: "Overall product assessment")
    var overallAssessment: String
    
    @Guide(description: "Key differentiators")
    var keyDifferentiators: [String]
    
    @Guide(description: "Brand reputation insight if known")
    var brandInsight: String?
}

@Generable(description: "Single strategy score summary")
struct StrategyScoreSummary {
    @Guide(description: "Strategy name: esg, brand, value, or durability")
    var strategyName: String
    
    @Guide(description: "Human-readable assessment of this score")
    var assessment: String

    @Guide(description: "Score as percentage string")
    var scorePercent: String
}
```

**Implementation:** On-device SLM (`SystemLanguageModel`) with structured `@Generable` output. Input: multi-strategy `commerceContextString`. Output: per-strategy summaries + timing signal + explanation.

### 3.4 Commerce Path & Procurement

The system provides a CTA to purchase products through the user's preferred platforms, filtered by ethical criteria.

**Commerce Routing:**

| Component | Description |
|-----------|-------------|
| **Platform Preferences** | User configures ranked list of preferred vendors (Amazon, eBay, Thrive Market, direct brand sites, etc.) |
| **Ethical Filtering** | Procurement API filters vendor options by user's ESG policy (carbon threshold, certification requirements) |
| **Deep Link Routing** | Product match → affiliate deep link to preferred platform's product page |
| **Affiliate Integration** | Revenue share via affiliate programs (Amazon Associates, CJ Affiliate, ShareASale, etc.) |
| **CTA Display** | "Buy on [Platform]" button anchored to product overlay. Tapping opens the platform's native app or Safari. |

**Procurement API (`distributed actor CommerceService`):**
```swift
distributed actor CommerceService {
    typealias ActorSystem = VisualIntelligenceActorSystem

    /// Find purchase options filtered by user's ethical and platform preferences.
    distributed func findPurchaseOptions(
        productID: String,
        userPolicy: EthicalPolicy,
        financialContext: FinancialSnapshot?
    ) async throws -> [PurchaseOption]

    /// Generate affiliate deep link for the selected option.
    distributed func generateAffiliateLink(
        option: PurchaseOption
    ) async throws -> URL
}

struct PurchaseOption: Codable, Sendable {
    let platform: String           // "amazon", "ebay", etc.
    let price: Decimal
    let currency: String
    let carbonScore: Float?        // If available for this vendor
    let certifications: [String]
    let affiliateURL: URL
    let ethicalMatch: EthicalMatch // .full, .partial, .none
}
```

### 3.5 Personal Financial Integration

The system connects to the user's financial data to validate spending, track budget adherence, and plan purchases.

**Data Sources:**

| Source | Framework | Coverage | Privacy |
|--------|-----------|----------|---------|
| **FinanceKit** | Apple (iOS 17+) | Apple Card, Apple Cash, Wallet transactions | Fully on-device, no data egress |
| **Plaid** | Third-party API | Bank accounts, credit cards, investment accounts (~12,000 institutions) | OAuth2, user-authorized, data on edge node only |

**Financial Context (`FinancialSnapshot`):**
```swift
struct FinancialSnapshot: Codable, Sendable {
    let monthlySpendToDate: Decimal
    let monthlyBudgetRemaining: Decimal?
    let recentTransactions: [RecentTransaction]  // Last 30 days, same category
    let averageCategorySpend: Decimal?           // Historical average for this product category
}
```

**Usage in Advisory Engine:**
- Budget check: "You've spent $380 of your $500 monthly budget. This item is $89."
- Category awareness: "You typically spend $45/month on coffee. This would bring you to $67."
- Purchase planning: "Based on your payday cycle, consider waiting 3 days."

**FinanceKit integration** reads Apple Wallet data on-device via `FinanceStore`. No financial data is sent to external services. Plaid data is fetched to the edge node and cached locally with user-authorized OAuth2 tokens. Financial data never leaves the local network.

### 3.6 Data Quality Tiers (PCAF-Adapted)

The **Partnership for Carbon Accounting Financials (PCAF)** defines a 5-tier data quality scoring system originally designed for financial institutions to rate the quality of emissions data in their loan and investment portfolios. This spec adapts that framework to rate the quality of ESG data available for consumer products:

| Tier | PCAF Original Meaning | Our Adaptation | HUD Display |
|------|----------------------|----------------|-------------|
| **1** | Audited emissions from the company | Product-specific, independently verified carbon data (e.g., Carbon Trust certified) | Green shield: "Verified" |
| **2** | Company-reported, unaudited | Company-level emissions, self-reported to CDP/MSCI | Blue shield: "Reported" |
| **3** | Estimated using physical activity data | Estimated from industry-sector averages + company revenue | Yellow shield: "Estimated" |
| **4** | Estimated using economic activity data | Extrapolated from broad economic sector data | Orange shield: "Extrapolated" |
| **5** | Estimated using sector averages | No company-specific data; generic sector estimate only | Gray shield: "Sector Average" |

**Lower tier = higher quality.** Tier 1 data is rare (<5,000 certified products globally). The system defaults to displaying Tier 3–5 data for most products, with an explicit label indicating the estimation method. The HUD never conflates estimated data with verified data.

### 3.7 Scoring Strategy Catalog

Each strategy implements `ProductScoringStrategy` and runs independently. Items carry scores from **all** active strategies simultaneously. Strategies are grouped by domain — each uses free APIs to liberate data that platforms currently hold hostage.

#### Phase 0 (Implemented)

| # | Strategy | API Source | What It Scores | Data Freedom |
|---|----------|-----------|----------------|--------------|
| 1 | **ESG** | Open Food Facts, Climate TRACE | Carbon intensity, certifications, Eco-Score | Unlocks sustainability data locked in corporate CSR reports |
| 2 | **Brand Fit** | UserConcept knowledge graph | Brand match, category familiarity, preference strength | Your brand preferences belong to you, not Amazon/Google |
| 3 | **Value** | World Bank Commodities, BLS PPI, FRED | Price trend, forecast confidence, price position | Free economic data vs paywalled price trackers |
| 4 | **Durability** | Category heuristics, EU repairability framework | Longevity, repairability, material quality | Durability data platforms hide to drive repeat purchases |

#### Phase 1a (Free API Strategies)

**Consumer Protection & Safety:**

| # | Strategy | API Source (Free) | What It Scores |
|---|----------|-------------------|----------------|
| 5 | **Product Safety** | CPSC Recalls API, FDA openFDA | Active recalls, adverse event reports, safety alerts |
| 6 | **Chemical Safety** | EWG Skin Deep, ECHA REACH | Ingredient toxicity, carcinogen presence, endocrine disruptors |
| 7 | **Food Safety** | FDA FSMA, USDA FSIS | Inspection history, import alerts, pathogen risk |
| 8 | **Allergen Risk** | Open Food Facts ingredients | Allergen cross-contamination, undeclared allergens |

**Nutrition & Health:**

| # | Strategy | API Source (Free) | What It Scores |
|---|----------|-------------------|----------------|
| 9 | **Nutrition Quality** | Open Food Facts (Nutri-Score) | Sugar, sodium, fiber, protein density per 100g |
| 10 | **Ingredient Transparency** | Open Food Facts ingredients | Additive count, E-number classification, ultra-processing |
| 11 | **HealthKit Alignment** | Apple HealthKit (on-device) | Matches product nutrients against user's dietary goals |
| 12 | **Glycemic Impact** | Open Food Facts + GI databases | Predicted blood sugar impact from carb/fiber ratio |

**Environmental & Ethical:**

| # | Strategy | API Source (Free) | What It Scores |
|---|----------|-------------------|----------------|
| 13 | **Water Footprint** | Water Footprint Network open data | Liters of water per unit across supply chain |
| 14 | **Deforestation Risk** | Global Forest Watch API | Supply chain deforestation links by commodity/region |
| 15 | **Labor Rights** | KnowTheChain, US DoL ILAB | Forced labor indicators, supply chain transparency |
| 16 | **Animal Welfare** | Open Food Facts labels, Certified Humane | Animal testing, cage-free, cruelty-free certifications |
| 17 | **Packaging Waste** | Open Food Facts packaging | Recyclability, plastic content, packaging-to-product ratio |
| 18 | **Country of Origin** | UN Comtrade, Open Food Facts | Supply chain transparency, manufacturing origin |

**Financial & Commerce:**

| # | Strategy | API Source (Free) | What It Scores |
|---|----------|-------------------|----------------|
| 19 | **Historical Price** | CamelCamelCamel (scrape), Keepa (free tier) | Price vs historical average, sale detection |
| 20 | **Cross-Platform Price** | Open pricing APIs, web scraping | Same product price comparison across platforms |
| 21 | **Shrinkflation** | Open Food Facts weight history | Package size reductions with unchanged pricing |
| 22 | **Subscription Trap** | App Store API, receipt analysis | Hidden recurring charges, free trial conversion rates |
| 23 | **Warranty Value** | Manufacturer warranty databases | Warranty duration, claim process ratings |

**Social & Reviews (User-Owned Data):**

| # | Strategy | API Source (Free) | What It Scores |
|---|----------|-------------------|----------------|
| 24 | **Reddit Sentiment** | Reddit API (free tier) | Product subreddit sentiment, common complaints, praise themes |
| 25 | **Repair Community** | iFixit API, Reddit r/repair | Repairability guides available, community repair success rate |
| 26 | **Expert Reviews** | Wirecutter RSS, RTINGS open data | Professional recommendation status, test methodology quality |
| 27 | **Recall History** | CPSC API, NHTSA API | Previous recalls on this brand/product line |

**Media & Entertainment:**

| # | Strategy | API Source (Free) | What It Scores |
|---|----------|-------------------|----------------|
| 28 | **Content Rating** | TMDB, OMDB | Age appropriateness, content warnings |
| 29 | **Music Ethics** | MusicBrainz, Spotify Web API | Artist royalty transparency, label practices |
| 30 | **Book Sourcing** | Open Library, ISBNdb | Publisher practices, author compensation model |

**Privacy & Digital Rights:**

| # | Strategy | API Source (Free) | What It Scores |
|---|----------|-------------------|----------------|
| 31 | **Data Privacy** | ToS;DR API, Mozilla Privacy Not Included | Data collection practices, tracking, sharing policies |
| 32 | **IoT Security** | Mozilla IoT guide, CVE databases | Connected device security posture, update frequency |
| 33 | **Right to Repair** | iFixit scores, EU repairability index | Self-repair difficulty, parts availability, tool requirements |

**Government & Regulatory:**

| # | Strategy | API Source (Free) | What It Scores |
|---|----------|-------------------|----------------|
| 34 | **EPA Compliance** | EPA ECHO, TRI | Manufacturer environmental violations, toxic releases |
| 35 | **Import Safety** | CBP CROSS rulings, FDA Import Alerts | Import detention history, compliance violations |
| 36 | **Energy Efficiency** | Energy Star API | Energy consumption relative to category standard |
| 37 | **FTC Enforcement** | FTC Cases API | Deceptive marketing history, consent decrees |

**Location & Context-Aware:**

| # | Strategy | API Source (Free) | What It Scores |
|---|----------|-------------------|----------------|
| 38 | **Local Alternative** | Yelp Fusion (free), Google Places | Locally-sourced or locally-made alternatives available |
| 39 | **Seasonal Alignment** | USDA crop calendars | Produce in/out of season for user's location |
| 40 | **Carbon Miles** | OpenRouteService + origin data | Transportation emissions from origin to user's location |

> [!NOTE]
> Each strategy degrades gracefully when its API is unavailable. The overlay shows "Data unavailable" for that dimension rather than fabricating scores. Strategies can be enabled/disabled per user preference.

### 3.8 Ownership & Purchase Tracking

Users build a personal product collection by scanning tags/barcodes of items they own. This creates an **ownership relationship** that:
- Feeds brand affinity back into the knowledge graph (auto-creates `UserConcept` with `"Brand:"` prefix)
- Closes the RAG feedback loop (did recommendations lead to purchases?)
- Syncs across devices via SwiftData + CloudKit

**Ownership Model (`OwnedProduct` — SwiftData `@Model`):**

| Field | Type | Purpose |
|-------|------|---------|
| `productID` | String | Links to `ProductClassification.productID` or barcode |
| `productName` | String | Human-readable name |
| `brand` | String? | Auto-creates `UserConcept` when set |
| `barcode` | String? | For re-lookup and enrichment |
| `status` | `OwnershipStatus` | `.owned`, `.considering`, `.returned`, `.wishlisted` |
| `source` | `OutcomeSource` | `.tagScan`, `.ctaTap`, `.financeKit`, `.manual` |
| `scoringStrategyIDs` | [String] | Which strategies were active when recommended |
| `recommendedScore` | Double? | Composite score at recommendation time |
| `captureItemID` | String? | Links back to originating `ProcessedItem` |

**Acquisition Flows:**
1. **Tag scan** → Camera captures barcode → pipeline creates `OwnedProduct` with `.tagScan` source
2. **CTA tap** → User taps "Buy" in overlay → creates with `.considering` status → confirmed later
3. **FinanceKit match** → Transaction matches pending `.considering` item → upgrades to `.owned`
4. **Manual** → User marks existing `ProcessedItem` as "I own this"

---

## 4. Data Source Assessment

> [!WARNING]
> Product-level ESG data with Scope 1/2/3 granularity is not widely available. The system handles "no data" as the **default**, not the exception.

### 4.1 Available Data Sources (Real, Free or Low-Cost)

| Source | Type | Granularity | Coverage | Cost | API |
|--------|------|------------|----------|------|-----|
| **Climate TRACE** | Emissions | Country + source-level, annual | Global, ~80,000 sources | Free | REST (beta) |
| **Open Food Facts** | Product ESG | Product-level (food) | ~3M food products | Free | REST |
| **OpenESG** | ESG scoring | Company + product | Growing; self-reported | Free | REST |
| **Open Sustainability Index** | Corporate ESG | Company-level | Global companies | Free | REST |
| **ESG Enterprise** | ESG risk | Company-level | ~5,000 companies | Free tier | REST |
| **World Bank Commodities** | Pricing | Commodity class | ~60 commodities | Free | REST |
| **BLS Producer Price Index** | Pricing | US industry sector | US industries | Free | REST |
| **FRED (Federal Reserve)** | Economic | Macro indicators | US economy | Free | REST |

**Phase 0 recommendation:** Start with **Open Food Facts** (largest free product database with sustainability data) + **Climate TRACE** (emissions by sector/source) + **World Bank Commodities** (pricing). All three have free REST APIs with no authentication or minimal API key requirements.

### 4.2 Degraded Mode Design

| Condition | Behavior |
|-----------|----------|
| No product match | "Product not recognized" — offer manual barcode scan |
| Product matched, no ESG data | Show product name + "No sustainability data available" + "Buy" CTA still available |
| ESG data available, stale (>90 days) | Show data with staleness badge: "Last updated: [date]" |
| Nowcast model has insufficient data | Hide sparkline, show "Insufficient pricing data" |
| Edge node unreachable | Client runs on-device inference (existing pipeline); ESG/nowcast features unavailable |
| Financial data not connected | Advisory engine omits budget checks; all other features work normally |

**The system never displays fabricated or interpolated scores.** If verified data doesn't exist, the overlay explicitly says so.

---

## 5. Implementation

> [!IMPORTANT]
> All features ship in a **single PR**. No phased releases — the full scoring pipeline, distributed actors, commerce path, and UI overlay are delivered together.

### Core Pipeline (Stage ⑦ in `LocalPipelineService`)

| Step | Deliverable |
|------|-------------|
| 1 | `CommerceTypes.swift` (DiverShared) — 11 `Codable & Sendable` types |
| 2 | `ProductScoringStrategy` protocol — pluggable scoring with 4 implementations |
| 3 | `ESGScoringStrategy`, `BrandAlignmentStrategy`, `ValueScoringStrategy`, `DurabilityScoringStrategy` |
| 4 | `ESGEnrichmentService` — Open Food Facts + Climate TRACE, 24h cache |
| 5 | `ProductRecommendationService` — multi-strategy composite scoring + SLM advisory |
| 6 | `@Generable` types — `AdvisorySignalOutput` (timing) + `ProductInsight` (score summaries) |
| 7 | `PipelineContext` commerce fields + `commerceContextString` |
| 8 | `ProcessedItem.commerceContextData` blob with computed accessor |
| 9 | Stage ⑦ hooks in both pipeline paths (update + new-item) |
| 10 | `ProductScoreOverlayView` — strategy-agnostic card with per-strategy dimension bars |

### Distributed Actors & Edge Node

| Step | Deliverable |
|------|-------------|
| 1 | `VisualIntelligenceActorSystem` — Bonjour + `NWConnection` (TLS 1.3, LAN-only) |
| 2 | `distributed actor InferenceService` — YOLO on Mac NE + pipeline offloading |
| 3 | `distributed actor NowcastingService` — DFM via Accelerate |
| 4 | macOS daemon + Bonjour registration |
| 5 | Client discovery + fallback |

### Data Enrichment & Commerce

| Step | Deliverable |
|------|-------------|
| 1 | `PricingDataService` — World Bank + BLS + FRED, SQLite cache |
| 2 | `NowcastingEngine` — DFM in Swift via Accelerate |
| 3 | `CommerceService` — affiliate routing filtered by ethical policy |
| 4 | FinanceKit integration (deferred to post-MVP if needed) |

### visionOS Client & AR HUD

| Step | Deliverable |
|------|-------------|
| 1 | visionOS app target with ARKit object + barcode tracking |
| 2 | RealityKit spatial UI — per-strategy score panels, timing pill, "Buy" CTA |
| 3 | Spatial anchoring to detected product coordinates |

---

## 6. Security & Privacy

| Requirement | Implementation |
|-------------|---------------|
| **Transport** | `NWConnection` TLS 1.3 over LAN. Distributed actor calls encrypted. |
| **LAN-only** | Bonjour scoped to local network. No WAN exposure. |
| **No raw data egress** | Camera frames: client → edge node (encrypted LAN) → never forwarded to cloud. |
| **Financial data isolation** | FinanceKit: on-device only. Plaid: edge node only, never crosses network boundary. |
| **Audit logging** | Advisory decisions logged locally: product ID, data sources, recommendation, timestamp. SOC 2-aligned. |
| **Data lineage** | Each data point tagged with source, retrieval timestamp, data quality tier. |
| **Commerce privacy** | Affiliate links generated on edge node. No purchase history stored unless user opts in. |

---

## 7. Glossary

| Term | Definition |
|------|-----------|
| **Edge Node** | Local Mac or M-series iPad hosting distributed actors for ML inference and data enrichment |
| **Data Quality Tier** | 1–5 rating adapted from PCAF: 1 = independently verified, 5 = sector-average estimate (see §3.6) |
| **Nowcasting** | Statistical technique using mixed-frequency data to estimate near-real-time economic indicators |
| **DFM** | Dynamic Factor Model — econometric model extracting common factors from mixed-frequency time series |
| **Advisory Decision** | User-confirmed recommendation (RECOMMEND / REVIEW / DELAY / OVER_BUDGET). System assists, user acts. |
| **Distributed Actor** | Swift `distributed actor` — cross-device actor communication via `Distributed` framework (SE-0336) |
| **VisualIntelligenceActorSystem** | Custom `DistributedActorSystem` — Bonjour discovery + `NWConnection` transport for all ML offloading |
| **Procurement API** | `CommerceService` that matches products to purchase options filtered by ethical policy + user platform preferences |
| **FinanceKit** | Apple framework (iOS 17+) providing on-device access to Apple Wallet transaction data |
| **Affiliate Routing** | Deep-link generation to user's preferred commerce platform with revenue-share tracking |
