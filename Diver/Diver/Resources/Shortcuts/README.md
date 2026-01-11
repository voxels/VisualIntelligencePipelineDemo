# Diver Shortcut Templates

This directory contains templates and guides for creating powerful Diver shortcuts. Since Apple doesn't allow programmatic creation of multi-step shortcuts, these guides will help you create them manually in the Shortcuts app.

## Quick Start

1. Open the **Shortcuts app** on your device
2. Tap **+** to create a new shortcut
3. Follow the step-by-step guide for your desired workflow below
4. Name the shortcut and add it to your Home Screen

---

## Template 1: Quick Share to Messages

**What it does:** Share the current page as a wrapped Diver link directly to Messages

**Steps to create:**
1. Add action: **Share Diver Link** (from Diver app)
   - Set URL: **Shortcut Input** (or ask each time)
   - Title: Ask Each Time
2. Add action: **Share**
   - Share: **Shortcut Result** (the wrapped link from step 1)
   - Destination: **Messages**
3. Name: "Quick Share to Messages"
4. Icon: Message bubble, Blue color

**Usage:**
- Safari → Share → Quick Share to Messages
- Action Button → Select this shortcut
- Home Screen icon → Tap to share from clipboard

**Customization:**
- Change destination to Mail, Slack, etc.
- Add a note before sharing
- Save to specific conversation

---

## Template 2: Search and Share

**What it does:** Search your Diver library and share the wrapped link

**Steps to create:**
1. Add action: **Search Diver Links** (from Diver app)
   - Query: Ask Each Time
   - Limit: 1
2. Add action: **Get Details of Shortcut Result**
   - Get: **wrappedLink** property
3. Add action: **Share**
   - Share: **Details** (wrapped link from step 2)
4. Name: "Search and Share"
5. Icon: Magnifying glass, Purple color

**Usage:**
- "Hey Siri, search and share"
- Prompts for search query
- Returns first match and opens share sheet

**Customization:**
- Add tag filtering
- Increase limit to show multiple results
- Copy to clipboard instead of sharing

---

## Template 3: Save with Tags

**What it does:** Save a link with predefined tags for organization

**Steps to create:**
1. Add action: **Get Clipboard**
2. Add action: **Save Link to Diver** (from Diver app)
   - URL: **Clipboard**
   - Title: Ask Each Time (or use default)
   - Tags: **Choose from List**
     - Add options: work, personal, vacation, recipes, articles, videos
3. Name: "Save with Tags"
4. Icon: Bookmark, Orange color

**Usage:**
- Copy URL → Run shortcut → Choose tags
- Works with URLs from any source
- Tags help organize your library

**Customization:**
- Change predefined tag list
- Add multiple tag selection
- Set default tags for different contexts

---

## Template 4: Open Recent Link

**What it does:** Opens your most recently saved link in Safari

**Steps to create:**
1. Add action: **Search Diver Links** (from Diver app)
   - Query: **(leave empty for recent)**
   - Limit: 1
2. Add action: **Get Details of Shortcut Result**
   - Get: **url** property
3. Add action: **Open URLs**
   - URLs: **Details** (original URL from step 2)
4. Name: "Open Recent Link"
5. Icon: Arrow right, Green color

**Usage:**
- "Hey Siri, open recent link"
- Action Button quick access
- Widget tap action

**Customization:**
- Change limit to show menu of recent links
- Filter by specific tags
- Open in specific browser app

---

## Template 5: Find by Tag

**What it does:** Search links by tag and display results

**Steps to create:**
1. Add action: **Search Diver Links** (from Diver app)
   - Query: **(leave empty)**
   - Tags: Ask Each Time
   - Limit: 10
2. Add action: **Choose from List**
   - Choose from: **Shortcut Result**
3. Add action: **Open URLs**
   - URLs: **Chosen Item**
4. Name: "Find by Tag"
5. Icon: Tag, Yellow color

**Usage:**
- "Hey Siri, find by tag"
- Prompts for tag name
- Shows menu of matching links
- Tap to open

**Customization:**
- Add predefined tag list
- Change result limit
- Add preview of link details

---

## Advanced Workflows

### Workflow 6: Save and Process
Saves a link and waits for processing to complete, then shows a notification.

**Steps:**
1. Save Link to Diver (URL from Shortcut Input)
2. Wait 10 seconds
3. Search Diver Links (query: URL from step 1)
4. Show Notification (processing complete)

---

### Workflow 7: Batch Share
Share multiple links from your library at once.

**Steps:**
1. Search Diver Links (tags: Ask Each Time, limit: 20)
2. Choose from List (allow multiple selection)
3. Get wrappedLink property from each
4. Combine Text (join with newlines)
5. Share (combined wrapped links)

---

### Workflow 8: Widget Integration
Create a menu-driven shortcut for widgets.

**Steps:**
1. Choose from Menu
   - Recent: Search Diver Links (empty query) → Open
   - Save: Get Clipboard → Save Link to Diver
   - Search: Ask for input → Search Diver Links → Open
2. Show Result

---

## Tips

**Sharing Shortcuts:**
- After creating, tap (...) → Share → Copy iCloud Link
- Share link with others to import
- Store in iCloud Drive for backup

**Widget Integration:**
- Add shortcut to Home Screen as widget
- Configure widget parameters
- Long-press for quick access menu

**Automation:**
- Use Personal Automation triggers
- Time-based (save clipboard at 9 AM daily)
- Location-based (save when arriving at work)
- App-based (auto-save when leaving Safari)

**Debugging:**
- Add "Show Alert" actions to debug
- Check variable values with "Show Result"
- Test each step individually

---

## Need Help?

- **Documentation:** See `Documentation/DiverAppIntents.md` for intent details
- **GitHub:** Open an issue for shortcut templates
- **Community:** Share your custom workflows!

---

## Future: Downloadable Templates

We're working on providing pre-built `.shortcut` files you can download and import directly. Check for updates in future app versions!
