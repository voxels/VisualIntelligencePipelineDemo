# Shortcuts and Widgets - Phase 4B

This document covers the implementation of Shortcuts, Widgets, and automation features in Diver (Phase 4B).

## Overview

Phase 4B extends the App Intents foundation (Phase 4) with:

1. **Widgets**: Home Screen, Lock Screen, and Interactive widgets for quick link access
2. **Shortcut Templates**: 5 pre-designed workflows for common tasks
3. **Shortcut Donation**: Automatic Siri Suggestions based on user behavior
4. **Shortcut Gallery**: In-app discovery and setup guide for shortcuts

## Widgets

### Home Screen Widgets

Three widget sizes displaying recent Diver links from SwiftData:

#### Small Widget (`systemSmall`)
- Displays single most recent link
- Shows title, host, and relative timestamp
- Tappable to open link
- Empty state for no links

**Location**: `DiverWidget/DiverHomeScreenWidget.swift:43-91`

#### Medium Widget (`systemMedium`)
- Shows 3 most recent links
- Header with link count
- Each link shows title and host
- Empty state with icon

**Location**: `DiverWidget/DiverHomeScreenWidget.swift:95-136`

#### Large Widget (`systemLarge`)
- Displays 5 most recent links
- Shows title, summary, host, and tags
- Header with total count
- Footer with last update time
- Empty state with instructions

**Location**: `DiverWidget/DiverHomeScreenWidget.swift:140-200`

### Lock Screen Widgets

Three Lock Screen widget styles for iOS 16+:

#### Circular (`accessoryCircular`)
- Shows total link count
- Link icon badge
- Simple numeric display

**Location**: `DiverWidget/DiverLockScreenWidget.swift:46-60`

#### Rectangular (`accessoryRectangular`)
- Shows 2 most recent link titles
- Numbered list (1, 2)
- Tappable to open first link

**Location**: `DiverWidget/DiverLockScreenWidget.swift:64-103`

#### Inline (`accessoryInline`)
- Single line with most recent link title
- Shows host if no title available
- Space-efficient for Lock Screen

**Location**: `DiverWidget/DiverLockScreenWidget.swift:107-121`

### Interactive Widgets

Button-driven widgets that execute App Intents directly:

#### Small Interactive Widget
- "Save from Clipboard" button
- Reads clipboard, validates URL, saves to library
- Uses `SaveFromClipboardIntent`

**Location**: `DiverWidget/DiverInteractiveWidget.swift:58-78`

#### Medium Interactive Widget
- Two buttons: "Save Clipboard" and "Open Recent"
- Save: Reads clipboard and saves link
- Open Recent: Opens most recent link in Safari
- Uses `SaveFromClipboardIntent` and `OpenRecentIntent`

**Location**: `DiverWidget/DiverInteractiveWidget.swift:82-123`

### Widget Data Pipeline

```
LinkTimelineProvider
  ↓
SearchLinksIntent (empty query = recent)
  ↓
LinkEntityQuery.suggestedEntities()
  ↓
Filter by status == .ready
  ↓
Sort by createdAt DESC
  ↓
LinkEntry with link array
  ↓
Widget views render
```

**Timeline Refresh**: Every 15 minutes
**Location**: `DiverWidget/Sources/LinkTimelineProvider.swift:38-45`

### Widget Configuration

**Bundle**: `DiverWidgetBundle.swift` declares all three widget types
**Entitlements**: Same app group as main app (`group.com.secretatomics.Diver`)
**SwiftData**: Read-only access to shared container

## Shortcut Templates

Five pre-designed workflow templates users can create manually:

### 1. Quick Share to Messages

**Difficulty**: Easy | **Time**: 2 minutes

**Purpose**: Share current page as wrapped Diver link to Messages

**Steps**:
1. Add `ShareLinkIntent` (URL from share sheet)
2. Add `Share` action → Messages destination
3. Test from Safari share sheet

**Use Cases**:
- Safari → Share → Shortcut → Messages
- Action Button quick share
- Clipboard URL sharing

**Location**: `Diver/Resources/Shortcuts/README.md:23-87`

### 2. Search and Share

**Difficulty**: Medium | **Time**: 3 minutes

**Purpose**: Search library and share wrapped link

**Steps**:
1. Add `SearchLinksIntent` (ask for query)
2. Get Details → Wrapped Link property
3. Add `Share` action

**Use Cases**:
- Voice: "Hey Siri, search and share"
- Find specific saved link
- Widget quick access

**Location**: `Diver/Resources/Shortcuts/README.md:89-158`

### 3. Save with Tags

**Difficulty**: Easy | **Time**: 3 minutes

**Purpose**: Save clipboard URL with chosen tags

**Steps**:
1. Get Clipboard
2. Choose from List (tags: work, personal, vacation, etc.)
3. Add `SaveLinkIntent` with URL and tags

**Use Cases**:
- Copy URL → Run shortcut → Choose tags
- Organize by category
- Quick save from any app

**Location**: `Diver/Resources/Shortcuts/README.md:160-228`

### 4. Open Recent Link

**Difficulty**: Easy | **Time**: 2 minutes

**Purpose**: Open most recently saved link

**Steps**:
1. Add `SearchLinksIntent` (empty query, limit 1)
2. Get Details → URL property
3. Add `Open URLs` action

**Use Cases**:
- Voice: "Hey Siri, open recent link"
- Action Button quick access
- Widget tap action

**Location**: `Diver/Resources/Shortcuts/README.md:230-292`

### 5. Find by Tag

**Difficulty**: Medium | **Time**: 3 minutes

**Purpose**: Search by tag and open selected link

**Steps**:
1. Choose from List (tag list)
2. Add `SearchLinksIntent` with tags parameter
3. Choose from results
4. Get URL and open

**Use Cases**:
- Voice: "Hey Siri, find vacation links"
- Browse by category
- Filter library by topic

**Location**: `Diver/Resources/Shortcuts/README.md:294-365`

### Template Files

- **README.md**: Step-by-step instructions with screenshots guidance
  `Diver/Resources/Shortcuts/README.md`

- **shortcuts-manifest.json**: Machine-readable definitions for parsing
  `Diver/Resources/Shortcuts/shortcuts-manifest.json`

## Shortcut Discovery & Automatic Donation

App Intents provide **automatic donation** to Siri Suggestions when users perform shortcuts. No manual donation service is required.

### How It Works

**App Intents donate automatically** when:
1. User runs an intent via Shortcuts app
2. User invokes an intent via Siri voice command
3. User executes an intent from a widget button
4. User performs an intent through the share sheet

```
User performs ShareLinkIntent
  ↓
iOS automatically records the interaction
  ↓
Siri learns the pattern
  ↓
Shortcut appears in Siri Suggestions
  ↓
Shortcut becomes available in Spotlight Search
```

### Discovery Mechanisms

**1. AppShortcutsProvider (Primary)**

Our shortcuts are registered in `AppShortcutsProvider.swift` with phrases that make them discoverable:

```swift
static var appShortcuts: [AppShortcut] {
    AppShortcut(
        intent: ShareLinkIntent(),
        phrases: [
            "Share with \(.applicationName)",
            "Share link to \(.applicationName)",
            "Create \(.applicationName) link"
        ]
    )
}
```

**Location**: `Diver/AppIntents/AppShortcutsProvider.swift`

**What This Enables**:
- 🔍 **Spotlight Search**: Type "Share with Diver" → shortcut appears
- 🎙️ **Siri**: Say "Hey Siri, share with Diver" → executes immediately
- ⚡ **Shortcuts App**: Shortcuts appear in app with suggested phrases
- 💡 **Siri Suggestions**: iOS learns when to suggest based on usage

**2. Automatic Usage Learning**

iOS learns patterns automatically:
- User shares 5 links from Safari on weekday mornings → Siri suggests "Share with Diver" every weekday morning
- User searches links every Friday afternoon → Siri suggests "Search Diver links" on Fridays
- User opens recent link after lunch → Lock Screen suggests "Open recent link"

**No code required** - iOS handles this automatically based on actual usage.

**3. Widget Intent Discovery**

Interactive widget buttons automatically donate:
- Tap "Save from Clipboard" widget button → SaveLinkIntent donated
- Tap "Open Recent" widget button → OpenRecentIntent donated

These build up usage patterns for Siri Suggestions.

### Verifying Donation

**Check Siri & Search Settings**:
1. Settings → Siri & Search → Diver
2. Look for "Shortcuts from Diver" section
3. Registered shortcuts should appear with suggested phrases

**Check Shortcuts App**:
1. Open Shortcuts app
2. Tap "+" → Search for "Diver"
3. All 5 intents should be listed with icons

**Check Spotlight**:
1. Swipe down on Home Screen
2. Type shortcut phrase (e.g., "Share with Diver")
3. Shortcut should appear in results

### Limitations vs Legacy SiriKit

**What App Intents DON'T Support**:
- ❌ Manual donation after arbitrary thresholds (e.g., "donate after 3 shares")
- ❌ Programmatic control over Siri Suggestion timing
- ❌ Custom donation identifiers or grouping
- ❌ Pre-populating suggested shortcuts before first use

**Why This Is Better**:
- ✅ No code to maintain or debug
- ✅ iOS learns actual usage patterns (not artificial thresholds)
- ✅ Privacy-preserving (all learning happens on-device)
- ✅ No risk of spam suggestions for unused features
- ✅ Consistent behavior across all apps

## Shortcut Gallery

In-app discovery and setup guide for shortcuts.

### Features

1. **Template Cards**: Visual cards for each of 5 shortcuts
2. **Difficulty Badges**: Easy, Medium, Advanced indicators
3. **Step-by-Step Instructions**: Numbered steps with icons
4. **Use Cases**: Real-world examples for each shortcut
5. **Customization Ideas**: Ways to extend each shortcut
6. **Deep Link**: "Open Shortcuts App" button

**Location**: `Diver/Diver/Views/ShortcutGalleryView.swift`

### UI Components

#### Gallery View
- Scrollable list of shortcut cards
- Header with description
- Advanced workflows section
- Tips section

**Location**: `ShortcutGalleryView.swift:33-120`

#### Shortcut Card
- Icon with color badge
- Name and difficulty
- Estimated time
- Short description
- Tap to view details

**Location**: `ShortcutGalleryView.swift:125-166`

#### Detail View
- Large icon
- Full description
- Numbered step-by-step guide
- "Open Shortcuts App" button
- Use cases list
- Customization suggestions

**Location**: `ShortcutGalleryView.swift:170-300`

### Presenting Gallery

From main app:

```swift
@State private var showShortcutGallery = false

Button("Shortcuts Gallery") {
    showShortcutGallery = true
}
.sheet(isPresented: $showShortcutGallery) {
    ShortcutGalleryView()
}
```

## Testing

### Widget Tests

**File**: `DiverTests/Widgets/DiverWidgetTests.swift`

**Coverage**:
- Timeline provider placeholder, snapshot, timeline generation
- Widget configuration for all three widget types
- View rendering for all widget sizes
- Lock Screen widget views
- Interactive widget intents
- Error handling for invalid clipboard data

**Total Tests**: 15

### Running Widget Tests

```bash
# Run all widget tests
xcodebuild test -scheme DiverWidget -destination 'platform=iOS Simulator,name=iPhone 16'

# Run specific test class
swift test --filter DiverWidgetTests

# Run specific test
swift test --filter DiverWidgetTests/testLinkTimelineProvider_Timeline_RefreshesEvery15Minutes
```

### Manual Widget Testing

1. **Add Widgets to Home Screen**:
   - Long press Home Screen → "+" button → Search "Diver"
   - Add Small, Medium, and Large widgets
   - Verify recent links display correctly

2. **Lock Screen Widgets**:
   - Lock Screen → Long press → Customize
   - Add Diver widgets (Circular, Rectangular, Inline)
   - Verify link counts and recent links

3. **Interactive Widget**:
   - Add Interactive Widget to Home Screen
   - Copy URL to clipboard
   - Tap "Save" button → Verify link saved
   - Tap "Open Recent" → Verify link opens

4. **Timeline Refresh**:
   - Save new link in main app
   - Wait up to 15 minutes or force refresh
   - Verify widget updates with new link

## Integration Points

### With App Intents (Phase 4)

Widgets use the same intents as Shortcuts:

- `SearchLinksIntent`: Fetch recent/search links for display
- `SaveLinkIntent`: Interactive widget save button
- `ShareLinkIntent`: Potentially used in future widget buttons

**Why This Matters**: Single source of truth for data access, consistent behavior across widgets, shortcuts, and Siri.

### With SwiftData

Widgets read from shared SwiftData container:

```swift
// In LinkTimelineProvider
let entities = try await LinkEntityQuery().suggestedEntities()
    .filter { $0.status == .ready }
    .sorted { $0.createdAt > $1.createdAt }
```

**App Group**: `group.com.secretatomics.Diver`
**Container**: Same ModelContainer as main app

### With Automatic Shortcut Donation

App Intents donate automatically when performed - no manual integration required:

```
User performs intent (via Siri, Shortcuts, Widget, Share Sheet)
  ↓
iOS automatically records the interaction
  ↓
AppShortcutsProvider makes shortcuts discoverable
  ↓
iOS learns usage patterns over time
```

Shortcuts appear in:
- **Siri Suggestions**: Based on learned usage patterns
- **Spotlight Search**: Search by phrase from AppShortcutsProvider
- **Shortcuts App**: All intents listed under "Apps" → "Diver"
- **Lock Screen**: Siri Suggestions widget shows frequently used shortcuts
- **Share Sheet**: ShareLinkIntent appears in share sheet after first use

## Architecture Decisions

### Why Timeline Refresh Every 15 Minutes?

**Trade-off**: Balance freshness vs battery impact

- Users save links infrequently (few per day)
- Real-time updates not critical for link library
- 15 minutes is Apple's recommended minimum for most widgets
- Background tasks can force widget refresh when new link saved

**Alternative**: Use `BGTaskScheduler` to refresh widget immediately after link save (not yet implemented).

### Why Manual Shortcut Creation?

**Constraint**: Apple provides NO API for programmatic multi-step shortcut creation

**Options Considered**:
1. ❌ Programmatic creation: Not possible with current APIs
2. ❌ Importable `.shortcut` files: Requires signed URL scheme (rejected by App Review)
3. ✅ Template instructions: User creates manually (chosen approach)
4. ✅ AppShortcutsProvider: Makes intents discoverable (implemented)

**Chosen Approach**: Template guide + AppShortcutsProvider for best user experience within API constraints.

### Why Automatic Donation Instead of Manual?

**App Intents use a different paradigm than legacy SiriKit**:

**Old Way (SiriKit - Deprecated)**:
- App manually calls `INInteraction.donate()` after arbitrary thresholds
- Developer controls when/how shortcuts appear
- Requires tracking usage counts in UserDefaults
- Can spam users with irrelevant suggestions

**New Way (App Intents - Modern)**:
- iOS automatically records intent usage
- System learns patterns (time, location, frequency)
- Privacy-preserving (all learning on-device)
- Only suggests shortcuts users actually use
- No code to maintain

**Why This Is Better**:
- More accurate suggestions based on real patterns
- No arbitrary thresholds to tune
- Respects user privacy
- Eliminates donation bugs and edge cases

## Future Enhancements (Phase 9)

See `PLAN.md` Phase 9 for experimental features:

- **Live Activities**: Real-time link processing status
- **Control Center Widget**: Quick save button in Control Center
- **Dynamic Island**: Processing progress for wrapped links

These are low priority due to:
- iOS 18+ only
- Complex lifecycle management
- Limited use case for link saving app

## Troubleshooting

### Widget Not Updating

**Symptoms**: Widget shows old data or placeholder

**Causes**:
1. App group entitlements mismatch
2. SwiftData container not accessible
3. Timeline not refreshing

**Fixes**:
```bash
# Verify entitlements
plutil -p Diver/Diver.entitlements | grep -A 2 "com.apple.security.application-groups"
plutil -p DiverWidget/DiverWidget.entitlements | grep -A 2 "com.apple.security.application-groups"

# Should both show: "group.com.secretatomics.Diver"

# Force widget refresh
# Delete widget from Home Screen, reinstall
```

### Shortcuts Not Appearing in Siri/Spotlight

**Symptoms**: Siri doesn't recognize phrases, Spotlight doesn't show shortcuts

**Causes**:
1. AppShortcutsProvider not registered correctly
2. Siri & Search disabled in Settings → Siri & Search → Diver
3. Shortcuts need to be used at least once to appear in suggestions
4. iOS learning requires time (suggestions appear after usage patterns emerge)

**Debug**:
```bash
# Check if shortcuts are registered
# Open Shortcuts app → tap "+" → search "Diver"
# All 5 intents should appear

# Check Settings
# Settings → Siri & Search → Diver
# Verify "Learn from this App" is ON
# Verify "Show Siri Suggestions" is ON

# Force registration
# Delete app, reinstall, wait 24 hours for iOS to reindex
```

**Quick Fix**:
- Use each intent once via Shortcuts app
- Wait 24-48 hours for Siri to learn patterns
- Shortcuts will appear in Spotlight immediately after first use
- Siri Suggestions require established usage patterns

### Interactive Widget Button Not Working

**Symptoms**: Tapping button does nothing

**Causes**:
1. Intent not registered in `AppShortcutsProvider`
2. App group access failure
3. Invalid URL in clipboard (for SaveFromClipboard)

**Fixes**:
- Verify intent is in `AppShortcutsProvider.swift`
- Check console for app group errors
- Test with valid URL in clipboard

## References

- **PLAN.md**: Phase 4B implementation plan
- **DiverAppIntents.md**: App Intents documentation (Phase 4)
- **Shortcuts/README.md**: Step-by-step template guides
- **Shortcuts/shortcuts-manifest.json**: Machine-readable shortcut definitions
- **Apple Docs**: [WidgetKit](https://developer.apple.com/documentation/widgetkit), [App Intents](https://developer.apple.com/documentation/appintents), [SiriKit](https://developer.apple.com/documentation/sirikit)
