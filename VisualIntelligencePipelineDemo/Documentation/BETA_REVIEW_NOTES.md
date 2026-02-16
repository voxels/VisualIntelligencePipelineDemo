# Visual Intelligence Pipeline — Beta Review Notes

**Version:** 1.1 (Build 2)
**Date:** February 16, 2026
**Platform:** iOS 26.0+
**Requires:** Device with Apple Intelligence support

---

## Welcome, Beta Tester!

Thank you for testing **Visual Intelligence Pipeline** — an app that uses your camera, on-device AI, and real-world context to capture, enrich, and organize visual information and links into a searchable personal knowledge base.

This is the **first public beta**. Your feedback is critical to shaping the final release. Please report any crashes, UI issues, or unexpected behavior through TestFlight's built-in feedback tool (screenshot → Share → TestFlight).

---

## What to Test

### 1. Camera Capture & Sifting

- Open the app and tap the camera shutter.
- Point at objects, signs, products, or documents.
- Observe if subjects are correctly detected and "sifted" (isolated from background).
- Try tapping detected subjects — they should highlight and produce clean cutouts.
- Try capturing documents — they should be automatically perspective-corrected.

**What to look for:**
- Does the camera launch quickly and reliably?
- Are detected subjects accurate?
- Do cutouts have clean edges?
- Does document detection trigger when expected?

### 2. Location & Enrichment

- Grant location permission when prompted.
- After a capture, check the **location bar** below the preview — it should show a nearby venue or landmark.
- Try **pinning** a location (tap the pin icon) and take multiple captures — all should stay associated with that location.
- Long-press a location pill to **rename** a place.
- Try editing the location via the map view.

**What to look for:**
- Is the detected location accurate?
- Does pinning persist across captures?
- Does renaming update everywhere?
- Are Foursquare/MapKit results relevant?

### 3. Session Management

- Take several captures at the same location — they should automatically group into one **session**.
- Open the sidebar and verify sessions are organized by location and time.
- Tap a session to view all its captures and the AI-generated summary.
- Try "Add to Context" to resume a previous session.

**What to look for:**
- Are captures correctly grouped?
- Are session summaries accurate and relevant?
- Does resuming a session restore previous context?

### 4. AI & Context Tags

- After a capture, check the **context chip bar** for AI-suggested tags.
- Tap a suggested tag to add it, or add a custom context tag (e.g., "Gift for Mom").
- Verify that context tags persist with the saved capture.
- Check the **Daily Focus** summary from the sidebar for accuracy.

**What to look for:**
- Are AI suggestions relevant to the capture?
- Do custom tags save correctly?
- Is the Daily Focus summary coherent and up-to-date?

### 5. Photo & Video Import

- Use the import button to bring in photos or videos from your library.
- Verify that imported media goes through detection and enrichment.
- For videos, check that the best frame is selected and location is extracted from metadata.

**What to look for:**
- Does import complete without errors?
- Is the correct orientation preserved?
- Are videos processed with a reasonable frame selection?

### 6. Link Saving (Share Extension)

- From Safari or another app, use the **Share Sheet** to save a link to Visual Intelligence Pipeline.
- Verify the link appears in your library with extracted metadata (title, description, thumbnail).
- Try sharing links from YouTube, TikTok, and other apps.

**What to look for:**
- Does the share extension appear reliably?
- Is metadata extraction accurate?
- Do links appear in the library promptly?

### 7. QR Code Enrichment

- Capture an image containing a QR code.
- Verify the QR URL is detected and enriched with web metadata (title, description).
- Check that the enrichment data appears in the item's detail view.

**What to look for:**
- Is the QR code detected automatically?
- Does the URL get web enrichment (not just the raw URL)?
- Is metadata displayed in the detail card?

### 8. Reprocessing

- From the sidebar, long-press a saved item and select **Reprocess**.
- Verify that metadata is updated without creating a duplicate entry.
- Check that location and context tags are preserved.

**What to look for:**
- Does reprocessing complete without errors?
- Is the original item updated in place (no duplicates)?
- Are existing edits (location, tags) preserved?

### 9. Search

- Use the search bar in the sidebar.
- Try searching by keyword, location name, or concept.
- Verify results are relevant and returned promptly.

**What to look for:**
- Are search results accurate?
- Does semantic/vector search surface relevant items even with non-exact terms?
- Is search performance acceptable (< 1 second)?

---

## Known Issues

| Issue | Severity | Notes |
|-------|----------|-------|
| Apple Intelligence features require iOS 26 with a supported device | Expected | On unsupported devices, AI summaries and concept tagging will be unavailable. |
| First capture may take a few seconds to initialize the camera pipeline | Low | Subsequent captures are faster. |
| Weather context may be unavailable without location permission | Low | Grant "While Using" location access for full enrichment. |
| FastVLM model download (~500MB) required for multimodal analysis | Expected | Optional feature, app works fully without it. |

---

## Out of Scope for v1.0

The following features are **not included** in this beta and should not be tested:

- Proximity sharing (GroupActivities / "bump" sharing)
- Foursquare deep enrichment (expanded venue details, photos, tips)
- Advanced recommendation ranking (vector ranking + reinforcement learning)
- macOS / visionOS builds (iOS only for this beta)

---

## Feedback Guidelines

When reporting issues, please include:

1. **What you did** — Step-by-step actions leading to the issue.
2. **What you expected** — The behavior you anticipated.
3. **What happened** — The actual result, including any error messages.
4. **Screenshot or screen recording** — Use TestFlight's built-in tools.
5. **Device & OS version** — e.g., iPhone 16 Pro, iOS 26.0 beta 1.

### Priority Areas for Feedback

We are especially interested in feedback on:

- **Camera reliability** — Does it launch, focus, and capture consistently?
- **Location accuracy** — Are places correctly identified?
- **AI quality** — Are summaries, tags, and suggestions useful?
- **Performance** — Does the UI feel responsive during and after capture?
- **Crashes** — Any crashes will be automatically reported via TestFlight.

---

## Thank You

Your testing helps us build a better product. We read every piece of feedback and prioritize fixes based on beta tester reports. Thank you for your time and attention!

— The Visual Intelligence Pipeline Team
