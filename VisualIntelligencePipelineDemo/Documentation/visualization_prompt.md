# Visual Intelligence Pipeline — Video Visualization Prompts

> For use with Google DeepMind Genie 3 (interactive 3D world model, 24fps/720p)  
> or Veo 3 / Veo 3.1 (cinematic video generation, 4K)  
> Generated: 2026-02-19

---

## Prompt 1: The Complete User Journey (Genie 3 — Interactive World)

```
A photorealistic first-person view through the world as seen by someone using an
iPhone. The person is walking through a premium grocery store with warm overhead
lighting and wooden shelving. They raise their iPhone and point it at a bottle of
olive oil on the shelf.

The phone screen comes alive: a glowing translucent HUD overlay appears on the
camera feed. The olive oil bottle is outlined with a soft cyan glow as the Vision
framework detects it. A thin progress ring spins briefly near the top of the
screen (the pipeline processing).

Then overlays materialize smoothly:

1. TOP LEFT: A small shield badge fades in showing "Tier 1 ✓" in green with
   "Carbon Trust Verified" beneath it in 10pt text. The badge has a subtle
   frosted glass backdrop.

2. TOP RIGHT: A Swift Charts sparkline chart slides in — a graceful blue line
   showing 14 days of price history, with a faint teal area fill showing
   confidence interval. A small "↓2.3%" label in green indicates a downward
   price trend.

3. BOTTOM: A card rises from the bottom edge with rounded corners and
   glassmorphic blur. It shows:
   - The product name "Olio Verde Extra Virgin — 500ml"
   - A row of certification badges (organic leaf, fair trade hands, carbon
     neutral circle)
   - Carbon intensity: "0.4 kg CO₂e/unit" with a thin horizontal bar chart
   - A prominent "Buy on Thrive Market — $14.99" button in brand green, with
     a small green shield showing "Full Ethical Match"
   - Below it in smaller text: "$312 of $500 monthly grocery budget remaining"

The entire interface feels premium, with smooth 60fps animations, depth-of-field
blur on the store background, and subtle parallax on the HUD elements as the
phone tilts slightly.

The camera slowly pans right to reveal a MacBook sitting open on a kitchen
counter in the background — its menu bar shows a small blue pulsing dot (the
Edge Node daemon), confirming the ML processing is being handled remotely.
```

---

## Prompt 2: The Edge Node Dashboard (Veo 3 — Cinematic)

```
Cinematic slow dolly shot across a modern home office desk at golden hour, warm
light streaming through floor-to-ceiling windows. A Mac Studio sits on the desk,
its power light glowing white.

Cut to the Mac's screen: a clean SwiftUI menu bar app is visible in the top
right, showing a green dot and "2 devices · 411 inferences today". The user
clicks it and a dashboard window opens with a smooth spring animation.

The dashboard has a dark sidebar with four icons: Connections, Models, Data, Logs.

CONNECTIONS TAB (active): Shows two connected devices — "iPhone 16 Pro" and
"iPad Pro M5" — each with a real-time Swift Charts line graph showing inference
requests per second over the last 5 minutes. The iPhone line pulses with
activity. Device names are in SF Pro, stats in SF Mono.

The user clicks MODELS TAB: Four model cards appear in a 2x2 grid. Each card
shows model name, file size, and a status pill. "FastVLM 3B" shows a blue
progress bar at 67% with "Downloading..." beneath. "SAM 2.1" shows a green
"Active" pill with a circular gauge showing Neural Engine utilization at 34%.

Cut to the user's hand picking up an iPhone from the desk. The camera app opens
and points at a houseplant. Instantly, the Mac's dashboard Connections tab shows
the iPhone's inference line spike upward — a visual confirmation of the
distributed actor system routing ML work to the more powerful machine.
```

---

## Prompt 3: The Capture-to-Insight Pipeline (Veo 3 — Product Demo)

```
Top-down view of a person's hands holding an iPhone over a restaurant receipt on
a wooden table, evening ambient lighting with warm bokeh in the background.

They tap the capture button — a satisfying haptic ripple animation emanates from
the button. The screen shows the pipeline in action:

Step 1 (0.2s): OCR text appears character by character overlaid on the receipt
image, each line highlighting in sequence — restaurant name, items, prices, tax,
total.

Step 2 (0.5s): The receipt image smoothly perspective-corrects itself, the
corners snapping to perfect right angles with a subtle spring animation.

Step 3 (1.0s): A tasteful summary card slides up from the bottom:
"Dinner at Oleander — $78.42 · 2 guests · Mediterranean"
Three concept tags materialize as capsule pills: "dining out", "date night",
"Mediterranean cuisine"

Step 4 (1.5s): The item smoothly slides into the sidebar, joining a session
titled "Saturday Evening Downtown" that already contains 3 other captures. A
small Swift Charts bar graph embedded in the session row shows spending by
category for that session.

The camera pulls back to reveal the full app: sidebar on the left showing
organized sessions with thumbnail mosaics, detail view on the right showing the
enriched receipt with location pin, AI summary, and related captures from the
same outing linked by masterCaptureID.
```

---

## Prompt 4: Vision Pro Spatial Commerce (Genie 3 — Future Feature)

```
First-person view through Apple Vision Pro in a well-lit retail store. The
wearer's hands are visible at the bottom of the frame.

They look at a running shoe on a display shelf. ARKit detects the shoe and a
translucent spatial panel materializes next to it, anchored in 3D space. The
panel has a frosted glass appearance with rounded corners, floating 30cm to the
right of the shoe.

The panel contains:
- Product name and brand at top in SF Pro bold
- A circular data quality gauge showing Tier 2 (yellow) with "Company reported,
  not independently verified" in small text
- A 3D-rendered molecular structure icon representing carbon footprint
- Carbon intensity: "2.1 kg CO₂e/pair" with comparison: "34% lower than
  category average"
- A Swift Charts area chart showing 30-day price movement
- Three certification badges floating as small 3D pills
- An advisory recommendation: "REVIEW — Price 8% above 30-day average"
- A "Buy on Nike.com — $142" spatial button that glows when the user's hand
  approaches it

As the wearer turns their head slightly, the panel tracks smoothly, maintaining
its position relative to the shoe. When they look at a different shoe, the panel
gracefully dissolves and a new one materializes for the second product.

The environment has natural depth — shelves recede realistically into the
background with proper occlusion, and the spatial panels cast subtle shadows on
the real shelf surface.
```

---

## Usage Notes

- **Genie 3** prompts (1, 4) describe interactive, navigable environments. The user would be able to move through the space and trigger events via text commands.
- **Veo 3** prompts (2, 3) describe fixed cinematic sequences. Output is a video clip, not interactive.
- All prompts reference specific UI elements from `spec.md` v2.0: data quality tiers, Swift Charts sparklines, advisory decisions, distributed actor edge node, ESG badges, and affiliate CTAs.
- For Genie 3, you can add follow-up commands like *"Now walk to the next aisle and point at a cereal box"* to extend the interactive session.
