# Action Extension - Rich UI Implementation

This document describes the refactored Action Extension with rich UI and intent chaining capabilities.

## Overview

The Action Extension now provides a **rich SwiftUI interface** for saving and sharing links from any app via the iOS share sheet. It features smart tag suggestions, custom tagging, and seamless intent chaining.

**Location**: `Diver/ActionExtension/`

## Architecture

### Component Structure

```
ActionExtension/
├── ActionViewController.swift      # Main coordinator
├── Models/
│   └── LinkMetadata.swift         # Link preview data model
├── Services/
│   └── SmartTagGenerator.swift    # Domain & time-based tag suggestions
└── Views/
    └── LinkPreviewView.swift      # SwiftUI rich UI
```

### Flow Diagram

```
Share Sheet → ActionViewController
                ↓
       Extract URL from input
                ↓
       Generate smart tags
                ↓
     Show LinkPreviewView (SwiftUI)
                ↓
     User selects tags + action
                ↓
     ┌─────────┴──────────┐
     │                    │
  Save Only         Save & Share
     │                    │
     ↓                    ↓
Queue via          Queue + Wrap URL
DiverQueueStore           ↓
     │            Copy to clipboard
     ↓                    ↓
Show success      Open Messages app
     │                    │
     └─────────┬──────────┘
               ↓
         Dismiss extension
```

## Features

### 1. Rich Link Preview

**Component**: `LinkPreviewView.swift`

Displays a beautiful card with:
- Link title (from metadata or domain)
- Domain name
- Description (when available)
- Link icon

**Future Enhancement**: Use `LPMetadataProvider` to fetch rich metadata (title, description, image) from the URL.

### 2. Smart Tag Suggestions

**Component**: `SmartTagGenerator.swift`

Automatically suggests relevant tags based on:

#### Domain Patterns

| Domain | Suggested Tags |
|--------|---------------|
| youtube.com | video |
| github.com | code, dev |
| reddit.com | social |
| medium.com | articles |
| allrecipes.com | recipes, food |
| airbnb.com | travel |

**Total**: 20+ domain patterns

#### Time-Based Tags

| Condition | Tag |
|-----------|-----|
| Weekday 9am-5pm | work |
| Weekend | personal |
| Weekday outside work hours | personal |
| Evening/night (8pm-6am) | read-later |

#### Custom Tags

Users can add custom tags with:
- Automatic validation
- Lowercase conversion
- Space → hyphen replacement
- Special character removal
- 30 character limit

**Example**: "React Hooks" → "react-hooks"

### 3. Tag Selection UI

**Component**: `TagGrid` in `LinkPreviewView.swift`

Features:
- **Flow layout**: Tags wrap to multiple lines
- **Toggle selection**: Tap to add/remove
- **Visual feedback**: Selected tags highlighted in blue
- **Chip design**: Modern capsule shape with remove button
- **Custom tag input**: Text field for manual entry

### 4. Action Buttons

#### Save Only

```swift
SaveLinkIntent
  ↓
DiverItemDescriptor(url, title, categories: tags)
  ↓
DiverQueueStore.enqueue()
  ↓
Success message
```

**Use Case**: Quick save without sharing (when user wants to read later)

#### Save & Share

```swift
Step 1: SaveLinkIntent
  ↓
Queue item created
  ↓
Step 2: DiverLinkWrapper.wrap()
  ↓
Wrapped URL: diver.link/w/abc123...
  ↓
Step 3: Copy to clipboard
  ↓
Step 4: Open Messages app
  ↓
User shares wrapped link
```

**Use Case**: Save and immediately share to Messages (most common flow)

### 5. Intent Chaining

The extension chains multiple operations:

```swift
// Save & Share implementation
@MainActor
private func performSaveAndShare(url: URL, tags: [String]) async {
    // 1. Create descriptor with tags
    let descriptor = DiverItemDescriptor(
        id: DiverLinkWrapper.id(for: url),
        url: url.absoluteString,
        title: url.host ?? url.absoluteString,
        categories: tags  // User-selected tags
    )

    // 2. Enqueue for main app processing
    let queueItem = DiverQueueItem(
        action: "save",
        descriptor: descriptor,
        source: "action-extension"
    )
    try queueStore.enqueue(queueItem)

    // 3. Wrap URL for sharing
    let payload = DiverLinkPayload(url: url, title: nil)
    let wrappedURL = try DiverLinkWrapper.wrap(
        url: url,
        secret: secret,
        payload: payload,
        includePayload: true
    )

    // 4. Copy wrapped link to clipboard
    UIPasteboard.general.string = wrappedURL.absoluteString

    // 5. Open Messages app
    openMessages(with: wrappedURL.absoluteString)
}
```

## User Experience

### Typical Flow

1. **User finds interesting article in Safari**
2. **Taps Share button** → "Diver" in share sheet
3. **Extension opens** with rich preview:
   - Shows article title and domain
   - Suggests tags: ["articles", "work"] (if weekday during business hours)
4. **User adds custom tag**: "swift" → becomes "swift"
5. **User taps "Save & Share"**
6. **Extension**:
   - Saves link to Diver queue with tags ["articles", "work", "swift"]
   - Wraps URL into `diver.link/w/abc123...`
   - Copies wrapped link to clipboard
   - Opens Messages app
7. **User in Messages**:
   - Wrapped link pre-filled in clipboard
   - Pastes and sends to friend
8. **Friend receives**: `diver.link/w/abc123...`
9. **Friend taps link**: Resolves to original article

### Alternative Flow: Save Only

1-4. (Same as above)
5. **User taps "Save to Diver"**
6. **Extension**:
   - Saves link to queue
   - Shows success message
   - Dismisses
7. **User returns to Safari** to continue browsing

## Implementation Details

### SwiftUI in UIKit Extension

The extension uses `UIHostingController` to present SwiftUI views:

```swift
let previewView = LinkPreviewView(...)
let hostingController = UIHostingController(rootView: previewView)
hostingController.modalPresentationStyle = .formSheet
present(hostingController, animated: true)
```

**Why**: Extensions support UIKit view controllers, so we wrap SwiftUI views in hosting controllers.

### Flow Layout for Tags

Custom SwiftUI `Layout` protocol implementation that wraps tags to multiple lines:

```swift
struct FlowLayout: Layout {
    func sizeThatFits(...) -> CGSize {
        // Calculate total size needed for wrapping
    }

    func placeSubviews(...) {
        // Position subviews in rows
    }
}
```

**Behavior**:
- Tags flow left-to-right
- Wrap to next line when exceeding container width
- Automatic spacing between tags

### Error Handling

**URL Extraction Failures**:
- Invalid URL format → "The provided URL is not valid"
- No URL in share item → "No URL was found"
- Network errors → Ignored (uses placeholder metadata)

**Intent Execution Failures**:
- Queue store not initialized → "Extension not properly initialized"
- Keychain secret missing → "DiverLink secret not found"
- Wrapping failures → "Failed to save and share: [error]"

**Recovery**: All errors show alert with "Done" button that dismisses extension.

## Integration Points

### With DiverQueueStore

Extension writes `DiverQueueItem` to app group storage:

```swift
DiverQueueItem(
    action: "save",
    descriptor: DiverItemDescriptor(
        id: "abc123...",
        url: "https://example.com",
        title: "Example Domain",
        categories: ["articles", "work"]
    ),
    source: "action-extension"
)
```

**App Group**: `group.com.secretatomics.Diver`
**Queue Directory**: `group.com.secretatomics.Diver/Queue/`

**Main app processes queue** via `DiverQueueProcessingService` on:
- App launch
- Background task execution
- Manual refresh

### With DiverLinkWrapper

Extension wraps URLs using keychain secret:

```swift
let secret = keychainService.retrieveString(key: "diver-link-secret")
let wrappedURL = DiverLinkWrapper.wrap(
    url: originalURL,
    secret: secret,
    payload: DiverLinkPayload(url: originalURL),
    includePayload: true
)
```

**Keychain**: `23264QUM9A.com.secretatomics.Diver.shared`

### With Messages App

Extension copies wrapped link and opens Messages:

```swift
UIPasteboard.general.string = wrappedLink
extensionContext?.open(URL(string: "sms:")!)
```

**Fallback**: If Messages fails to open, shows success message: "Link copied! Open Messages to share."

## Future Enhancements

### 1. LPMetadataProvider Integration

Fetch rich metadata from URLs:

```swift
import LinkPresentation

let provider = LPMetadataProvider()
provider.startFetchingMetadata(for: url) { metadata, error in
    let linkMetadata = LinkMetadata(
        url: url,
        title: metadata?.title,
        description: metadata?.summary,
        imageURL: metadata?.imageProvider?.url
    )
    showLinkPreview(with: linkMetadata)
}
```

**Benefits**:
- Show actual article titles
- Display hero images
- Show descriptions from Open Graph tags

**Trade-off**: Adds network latency (~1-3 seconds)

### 2. Collection Management

Pre-defined tag groups:

```swift
struct Collection {
    let name: String
    let tags: [String]
    let icon: String
}

let collections = [
    Collection(name: "Vacation Planning", tags: ["vacation", "travel"], icon: "airplane"),
    Collection(name: "Recipe Ideas", tags: ["recipes", "food"], icon: "fork.knife")
]
```

**UI**: Show collection picker with icons, select to auto-apply tags.

### 3. Share Destination Picker

Instead of always opening Messages, let user choose:

```swift
enum ShareDestination {
    case messages
    case mail
    case clipboard
    case slack  // If installed
}
```

**UI**: After "Save & Share", show destination picker with app icons.

### 4. Quick Actions Menu

Long-press on extension icon in share sheet:

- Save with default tags (bypasses UI)
- Save and copy link (skip Messages)
- Add to specific collection

**Requires**: iOS 15+ share sheet quick actions

## Testing

### Manual Testing Checklist

**Basic Functionality**:
- [ ] Extension appears in share sheet
- [ ] URL extracted from Safari share
- [ ] URL extracted from text selection
- [ ] Smart tags suggested correctly
- [ ] Custom tag validation works
- [ ] Tags can be selected/deselected

**Save Flow**:
- [ ] "Save to Diver" creates queue item
- [ ] Queue item has correct URL and tags
- [ ] Success message displayed
- [ ] Extension dismisses after save

**Save & Share Flow**:
- [ ] Link wrapped correctly
- [ ] Wrapped link copied to clipboard
- [ ] Messages app opens
- [ ] Wrapped link can be pasted
- [ ] Original URL resolves from wrapped link

**Error Handling**:
- [ ] Invalid URL shows error
- [ ] Missing keychain secret shows error
- [ ] App group unavailable shows error

### Unit Tests

**File**: `DiverTests/ActionExtension/SmartTagGeneratorTests.swift`

```swift
func testDomainTags_YouTube_ReturnsVideoTag() {
    let tags = SmartTagGenerator.generateTags(
        for: URL(string: "https://youtube.com/watch?v=abc")!
    )
    XCTAssertTrue(tags.contains("video"))
}

func testTimeTags_Weekday9AM_ReturnsWorkTag() {
    // Mock date to weekday 9am
    let tags = SmartTagGenerator.timeTags()
    XCTAssertTrue(tags.contains("work"))
}

func testCustomTagValidation_ConvertsToLowercase() {
    let validated = SmartTagGenerator.validateTag("React Hooks")
    XCTAssertEqual(validated, "react-hooks")
}
```

### UI Tests

**File**: `DiverUITests/ActionExtensionUITests.swift`

```swift
func testExtension_ShareFromSafari_ShowsPreview() {
    // Open Safari
    // Navigate to URL
    // Tap Share
    // Select Diver
    // Verify preview appears
    // Verify tags suggested
}
```

## Troubleshooting

### Extension Not Appearing in Share Sheet

**Cause**: Extension activation rules don't match content type

**Fix**: Check `Info.plist` for activation rules:

```xml
<key>NSExtensionActivationSupportsWebPageWithMaxCount</key>
<integer>1</integer>
<key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
<integer>1</integer>
```

### Queue Items Not Processed

**Cause**: App group entitlements mismatch

**Debug**:
```bash
plutil -p Diver/ActionExtension/ActionExtension.entitlements | grep application-groups
# Should show: "group.com.secretatomics.Diver"

ls ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Shared/AppGroup/*/Queue/
# Should show queue items
```

### Wrapped Links Not Working

**Cause**: Keychain secret mismatch between app and extension

**Fix**: Both must use same keychain access group:
- `23264QUM9A.com.secretatomics.Diver.shared`

**Verify**:
```swift
print(keychainService.retrieveString(key: "diver-link-secret"))
// Should print same value in app and extension
```

## References

- **PLAN.md**: Phase 2 (Action Extension)
- **SHORTCUTS_AND_WIDGETS.md**: Intent chaining examples
- **DiverShared/LinkWrapping.swift**: DiverLink format
- **DiverShared/QueueStore.swift**: Queue architecture
- **Apple Docs**: [Share Extension](https://developer.apple.com/documentation/uikit/view_controllers/providing_a_share_extension), [UIHostingController](https://developer.apple.com/documentation/swiftui/uihostingcontroller)
