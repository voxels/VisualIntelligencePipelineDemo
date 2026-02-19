# Ethical Commerce & Micro-Decisions — Technical Specification

> **Draft:** 0.2  
> **Date:** 2026-02-19  
> **Status:** Pre-implementation research spec  
> **Parent:** [spec.md](../spec.md) §14  
> **Client Platforms:** iOS 26.0+, iPadOS 26.0+, visionOS 26.3+  
> **Edge Node Platforms:** macOS 26.0+ (M-series), iPadOS 26.0+ (M-series)

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

### 3.1 Product Identification & Scoring Overlay

When the user views a physical product (via camera on iPhone/iPad or spatial tracking on Vision Pro), the system identifies it and overlays available sustainability data.

| Stage | Device | Technology | Latency Target |
|-------|--------|-----------|---------------|
| Object detection & bounding box | Client | ARKit / AVFoundation | <50ms |
| Barcode/QR scan | Client | ARKit / Vision framework | <100ms |
| Product classification | Edge node (or client fallback) | CoreML YOLO/DETR on Neural Engine | <200ms |
| Entity resolution (barcode → product ID) | Edge node | Local SQLite lookup + API fallback | <100ms |
| ESG data retrieval | Edge node | HTTPS API call (cached) | <500ms (cached: <10ms) |

**Overlay Output** (spatial panel on Vision Pro, card overlay on iOS/iPadOS):
- **Data Quality Tier** (1–5, see §3.5 for PCAF explanation)
- **Carbon intensity** (company-level, kg CO₂e per revenue unit)
- **Certification badges** (if available: Carbon Trust, TÜV, EPD)
- **Confidence indicator** showing data source and freshness
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

### 3.3 Advisory Decisions (User-Initiated, System-Assisted)

> [!IMPORTANT]
> The system surfaces recommendations and a commerce CTA. The user always confirms any action. No purchases are executed without explicit user tap.

**Policy Configuration** (local JSON, stored per-user on edge node):
```json
{
    "maxCarbonIntensity": 50.0,
    "minDataQualityTier": 3,
    "inflationTolerance": 5.0,
    "preferredCertifications": ["Carbon Trust", "EPD"],
    "preferredPlatforms": ["amazon", "thrive_market", "ebay"],
    "monthlyBudgetLimit": 500.0
}
```

**Advisory Outputs:**

| Output | Meaning | Display |
|--------|---------|---------|
| `RECOMMEND` | Meets all policy criteria | Green shield + "Buy" CTA |
| `REVIEW` | Partial match or data gaps | Yellow shield + "Review recommended" |
| `DELAY` | Nowcast indicates unfavorable pricing | Orange clock + "Price trending down — consider waiting" |
| `OVER_BUDGET` | Exceeds monthly spending threshold | Red indicator + "Budget alert: $X remaining this month" |

**Implementation:** On-device LLM (MLX Swift, ~3B) on edge node with structured generation. Input: product classification + ESG data + nowcast + financial context. Output: advisory enum + natural-language explanation.

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

## 5. Implementation Phases

### Phase 0: Pure-Swift Proof of Concept (iOS/macOS)

> **Goal:** Validate detection → enrichment → overlay on existing hardware before investing in distributed actors or visionOS.

| Step | Deliverable |
|------|-------------|
| 1 | Convert YOLO model to CoreML via `coremltools`. Run on iPhone/Mac Neural Engine. Measure inference latency. |
| 2 | Integrate **Open Food Facts** free API — barcode scan → product data + Eco-Score. |
| 3 | Integrate **Climate TRACE** API — map product category to emissions data by sector. |
| 4 | SwiftUI overlay on AVFoundation camera feed rendering a score card with ESG data. |
| 5 | Measure end-to-end latency: camera frame → YOLO → enrichment → overlay. Target: <500ms. |

**Exit criteria:** <500ms end-to-end with real data from at least one ESG source. If >1s, reevaluate model size before proceeding.

### Phase 1: Distributed Actor Edge Node

| Step | Deliverable |
|------|-------------|
| 1 | `VisualIntelligenceActorSystem` conforming to `DistributedActorSystem` — Bonjour + `NWConnection` (reference: TicTacFish `SampleLocalNetworkActorSystem`). |
| 2 | `distributed actor InferenceService` — CoreML YOLO on Mac NE + existing pipeline Vision analysis offloading. |
| 3 | `distributed actor NowcastingService` — DFM via Accelerate framework. |
| 4 | macOS daemon registering Bonjour service + hosting distributed actors. |
| 5 | iOS/iPadOS client discovering + resolving actors, sending frames, receiving results. |
| 6 | Fallback path: client detects no edge node → runs on-device (existing behavior). |

### Phase 2: Data Enrichment & Commerce

| Step | Deliverable |
|------|-------------|
| 1 | `ESGEnrichmentService` — Climate TRACE + Open Food Facts + OpenESG. Local cache, 24h TTL. |
| 2 | `PricingDataService` — World Bank + BLS + FRED. SQLite time-series on edge node. |
| 3 | `NowcastingEngine` — DFM in Swift via Accelerate (LAPACK wrappers). 14-day projections. |
| 4 | `CommerceService` — Product-to-affiliate-link routing. Platform ranking by user preference + ethical policy. |
| 5 | FinanceKit integration — on-device `FinancialSnapshot` from Apple Wallet. |
| 6 | Plaid integration — OAuth2 flow, bank data cached on edge node. |
| 7 | All services conform to protocols with mock implementations for testing. |

### Phase 3: visionOS Client & AR HUD

| Step | Deliverable |
|------|-------------|
| 1 | visionOS app target with ARKit (object + barcode tracking). |
| 2 | `VisualIntelligenceActorSystem` client — resolve Mac edge node via Bonjour. |
| 3 | RealityKit spatial UI:<br>— Data quality tier badge (color-coded per §3.6)<br>— 14-day price sparkline<br>— Advisory pill ("Recommended" / "Review" / "Consider waiting")<br>— "Buy on [Platform]" CTA |
| 4 | Spatial anchoring — panels attached to detected product coordinates. |
| 5 | Enterprise entitlements for higher-frequency object tracking if needed. |

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
