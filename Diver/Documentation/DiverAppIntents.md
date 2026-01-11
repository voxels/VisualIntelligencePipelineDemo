# Diver App Intents

This document describes the App Intents supported by Diver, their usage, sample phrases, and integration guidelines.

---

## Supported Intents

### 1. Save Link to Diver
- **Intent:** `SaveLinkIntent`
- **Description:** Save a URL (with optional title and tags) to your Diver library for processing.
- **Parameters:**
  - `URL` (required) - The web address to save
  - `Title` (optional) - Custom title for the link
  - `Tags` (optional) - Tags for categorization (e.g., "swift", "ios", "development")
- **Behavior:**
  - Validates URL before saving
  - Queues link for background processing
  - Does NOT wrap the URL (saves original)
  - Confirmation dialog includes tags if provided
- **Sample phrases:**
  - "Save to Diver"
  - "Save link in Diver"
  - "Add to Diver"
- **Shortcuts Use Case:** Save from Safari share sheet with custom tags

---

### 2. Share Diver Link (from Current Page)
- **Intent:** `ShareLinkIntent`
- **Description:** Wrap the current page as a Diver link, save to library, and get shareable wrapped URL.
- **Parameters:**
  - `URL` (required) - The current page URL (from share sheet)
  - `Title` (optional) - Custom title for the wrapped link
- **Behavior:**
  - Wraps URL into format: `https://secretatomics.com/w/<id>?v=1&sig=<signature>&p=<payload>`
  - Saves wrapped link to library (queued for processing)
  - Returns wrapped URL string (can be shared via Shortcuts actions)
  - Requires keychain secret for link encryption
- **Sample phrases:**
  - "Share with Diver"
  - "Share link to Diver"
  - "Create Diver link"
- **Shortcuts Use Case:**
  1. Safari → Share → Run ShareLinkIntent → Get wrapped URL
  2. Use Shortcuts "Share" action to send wrapped URL to Messages/Mail
  3. Link is saved to your library automatically

---

### 3. Search Diver Links (and Browse Recent)
- **Intent:** `SearchLinksIntent`
- **Description:** Search your library by keyword OR browse recent links. Returns single link (first match).
- **Parameters:**
  - `Query` (optional, default: "") - Search term (empty = browse recent links)
  - `Tags` (optional) - Filter results by tags (AND logic - requires ALL tags)
  - `Limit` (optional, default: 10) - Maximum results to consider
- **Behavior:**
  - **Empty query:** Returns most recent `.ready` link sorted by creation date
  - **With query:** Searches title, URL, and summary fields
  - Tag filtering requires ALL specified tags (not OR)
  - Returns single `LinkEntity` (first match only)
  - Throws error if no results found
- **Sample phrases:**
  - "Search Diver"
  - "Search Diver for [query]"
  - "Show my recent Diver links"
  - "Get recent links from Diver"
- **Shortcuts Use Case:**
  - Search for "swift" → Get top result → Share wrapped link
  - Empty search → Get most recent link → Open in browser

---

### 4. Open Diver Link
- **Intent:** `OpenLinkIntent`
- **Description:** Open a saved Diver link's **original URL** in the default browser.
- **Parameters:**
  - `Link` (required) - The LinkEntity to open
- **Behavior:**
  - Opens the original URL (not the wrapped link)
  - Cross-platform: Safari on iOS, default browser on macOS
  - Sets `openAppWhenRun = true` for app context
- **Sample phrases:**
  - "Open [link] from Diver"
  - "Show Diver link"
- **Shortcuts Use Case:** Search for link → Open in browser

---

## How to Use

- Open the Shortcuts app and search for "Diver" to find all registered intents.
- Use Siri to invoke supported phrases, or add shortcuts to your Home Screen or widgets.
- Each intent supports rich preview and confirmation dialogs.
- Share links directly from Shortcuts or Siri using the Share intent.

---

## Chaining Intents (Advanced Workflows)

App Intents can be **chained together** in Shortcuts to create powerful workflows. Here are some examples:

### Example 1: Save and Share in One Step
```
1. Run ShareLinkIntent (URL from share sheet)
   → Returns wrapped URL string
2. Share (wrapped URL)
   → Opens Messages/Mail to share
```
**Use Case:** Safari → Share → Diver → Auto-opens Messages with wrapped link

---

### Example 2: Search and Share from Library
```
1. Run SearchLinksIntent (query: "vacation")
   → Returns first matching LinkEntity
2. Get wrapped link from result
   → Extract wrappedLink property
3. Share (wrapped link)
   → Share to Messages/Mail
```
**Use Case:** "Search Diver for vacation and share to Messages"

---

### Example 3: Browse Recent and Open
```
1. Run SearchLinksIntent (empty query)
   → Returns most recent link
2. Run OpenLinkIntent (result from step 1)
   → Opens in browser
```
**Use Case:** "Show my most recent Diver link" → Opens automatically

---

### Example 4: Save with Tags, Then Search
```
1. Run SaveLinkIntent (URL, tags: ["swift", "tutorial"])
   → Saves to library
2. Wait 5 seconds (for processing)
3. Run SearchLinksIntent (tags: ["swift"])
   → Returns the saved link
4. Show result notification
```
**Use Case:** Automated tagging and verification workflow

---

### Example 5: Widget with Recent Links
Create a **Widget** that displays recent links:
```
1. Run SearchLinksIntent (empty query, limit: 5)
   → Returns first recent link
2. Display title and URL in widget
3. Tap widget → Run OpenLinkIntent
```
**Use Case:** Home screen widget showing your most recent Diver link

---

### Shortcuts Tips
- **Chaining:** Output from one intent can be input to another
- **Properties:** LinkEntity has `title`, `url`, `wrappedLink`, `tags`, `summary`
- **Loops:** Use "Repeat" actions to process multiple results
- **Conditionals:** Check if `wrappedLink` exists before sharing
- **Variables:** Store LinkEntity in variables for reuse

---

## Troubleshooting

- **Intents not appearing in Shortcuts:** Make sure the app has launched at least once after installation.
- **Siri does not recognize phrases:** Try alternate phrases, or check for app/OS updates.
- **Background processing not working:** Check system permissions for background refresh and notifications.
- **Chaining fails:** Check that previous intent returns the correct type (e.g., LinkEntity vs String)
- **Missing wrapped link:** ShareLinkIntent generates wrapped links; SaveLinkIntent does not

---

## Advanced

- All intents support localization and can be integrated with custom workflows.
- For developers: see source files in `Diver/Diver/AppIntents/` for implementation details.
- LinkEntity conforms to `AppEntity` and `Transferable` for maximum interoperability
- Intents use SwiftData for persistence and can be queried by ID, search string, or suggestions

---