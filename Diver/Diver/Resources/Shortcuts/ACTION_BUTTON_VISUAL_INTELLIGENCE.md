# Action Button: Visual Intelligence Screen Capture

**For iPhone 15 Pro / 16 Pro and later**

## What This Does

Press the **Action Button** to:
1. 📸 Take a screenshot
2. 🔍 Scan for URLs using Vision OCR
3. 🔗 Create a Diver wrapped link
4. 💬 Open Messages to share

**Perfect for**: Capturing links from:
- Photos of business cards with URLs
- Screenshots of web pages
- QR codes on screen
- Text messages with links
- Social media posts

---

## How to Set Up

### Step 1: Create the Shortcut

1. **Open Shortcuts app**
2. **Tap "+" to create new shortcut**
3. **Name it**: "Diver Screen Capture"
4. **Add these actions in order**:

#### Action 1: Take Screenshot
- Search for **"Take Screenshot"**
- Add it to your shortcut
- This captures whatever is currently on screen

#### Action 2: Visual Intelligence Intent
- Search for **"Diver"** in apps
- Select **"Scan Screen"** (VisualIntelligenceIntent)
- Configure:
  - **Screenshot**: Select "Screenshot" from Action 1
  - **Include QR Codes**: ✅ ON (to scan QR codes too)
  - **Auto-Share**: ✅ ON (to auto-open Messages)

#### Action 3 (Optional): Show Result
- Search for **"Show Result"**
- Add it to see the wrapped link before sharing
- Or skip this for fastest workflow

### Step 2: Assign to Action Button

1. **Open Settings** → **Action Button**
2. **Swipe until you see "Shortcut"**
3. **Tap "Choose"**
4. **Select "Diver Screen Capture"**
5. **Done!**

---

## How to Use

### Example 1: Capture Link from Instagram Story

1. **Open Instagram** and view a story with a link
2. **Press Action Button** (physical button on side)
3. **Screenshot taken automatically**
4. **Diver scans for URL** using OCR
5. **Messages opens** with wrapped link ready to paste
6. **Paste and send** to friend

Result: Friend receives `diver.link/w/abc123...` that opens to the original Instagram link

### Example 2: Save Business Card URL

1. **Take photo** of business card with printed URL
2. **Open Photos** and view the image
3. **Press Action Button**
4. **Screenshot taken** (captures the photo on screen)
5. **Diver extracts URL** from business card text
6. **Link saved** to your Diver library with tags: ["visual-intelligence", "screenshot"]

### Example 3: Capture QR Code

1. **See QR code** on website or in app
2. **Press Action Button**
3. **Diver scans QR code** and extracts URL
4. **Messages opens** with wrapped link
5. **Share immediately**

---

## What Gets Detected

### Text Recognition (OCR)

Diver uses Apple's Vision framework to recognize:
- ✅ **Printed URLs**: `https://example.com/article`
- ✅ **Short URLs**: `bit.ly/abc123`
- ✅ **www URLs**: `www.example.com` (auto-adds https://)
- ✅ **Broken URLs**: `https://example. com` (removes spaces)
- ✅ **Multi-line URLs**: URLs split across lines

### QR Code Detection

- ✅ **Standard QR codes** containing URLs
- ✅ **Wi-Fi QR codes** (if they contain a URL)
- ✅ **Multiple QR codes** (uses first one found)

### What Doesn't Work

- ❌ Handwritten URLs (OCR not accurate enough)
- ❌ Heavily stylized fonts
- ❌ URLs in images with low contrast
- ❌ Blurry screenshots

**Tip**: For best results, make sure the URL is clearly visible and in focus before taking the screenshot.

---

## Advanced Configuration

### Disable Auto-Share (Manual Messages)

If you don't want Messages to auto-open:

1. Edit your shortcut
2. Find "Scan Screen" action
3. Turn **OFF** "Auto-Share"
4. Now it will just copy the link to clipboard
5. You manually open Messages and paste

### Add Notification

To see what URL was found:

1. After "Scan Screen" action
2. Add **"Show Notification"**
3. Set notification text to: "Scan Screen"
4. Now you'll see a notification with the found URL

### Save to Specific Collection

To automatically tag with custom tags:

1. You'll need to use a different intent flow
2. After "Scan Screen", extract the URL
3. Use "Save Link" intent with your custom tags
4. More complex but gives you tag control

---

## Troubleshooting

### "No URLs found in the screenshot"

**Causes**:
- Screenshot doesn't contain any text URLs
- URL is handwritten or in stylized font
- Text is too small or blurry

**Fixes**:
- Zoom in on the URL before taking screenshot
- Make sure URL is clearly visible
- Try capturing just the URL area, not the whole screen

### "Could not read the screenshot image"

**Causes**:
- Screenshot failed to save
- Permission issue with Photos access

**Fixes**:
- Check Settings → Diver → Photos (should be "Read and Write")
- Try taking manual screenshot first, then run shortcut on it

### Multiple URLs Found, Wrong One Used

**Current Behavior**: If multiple URLs detected, Diver uses the first one found

**Workaround** (until picker is added):
- Crop screenshot to show only the URL you want
- Or manually delete other URLs from the screenshot before scanning

**Future Enhancement**: We'll add a picker to let you choose which URL to save

### QR Codes Not Detected

**Causes**:
- QR code is too small in screenshot
- QR code is damaged or partially obscured
- QR code doesn't contain a URL (contains plain text)

**Fixes**:
- Zoom in on QR code before screenshot
- Make sure entire QR code is visible and in focus
- Turn on "Include QR Codes" in intent settings

---

## How It Works Technically

### Behind the Scenes

```
Press Action Button
  ↓
Take Screenshot → screenshot.png
  ↓
Vision Framework
  ↓
┌──────────────┬─────────────────┐
│     OCR      │   QR Detection  │
│ (Text Recog) │   (Barcode)     │
└──────────────┴─────────────────┘
  ↓                    ↓
Recognized Text    QR Payload
  ↓                    ↓
NSDataDetector    URL Validation
  ↓                    ↓
  └────────┬───────────┘
           ↓
     URL Extraction
           ↓
  https://example.com/article
           ↓
  DiverLinkWrapper.wrap()
           ↓
  diver.link/w/abc123...
           ↓
    Copy to Clipboard
           ↓
  Save to Diver Queue
           ↓
   Open Messages App
```

### Privacy

- ✅ **On-device processing**: All OCR happens on your iPhone using Apple's Vision framework
- ✅ **No screenshots uploaded**: Screenshots are processed locally and deleted immediately
- ✅ **No external API calls**: URL extraction uses iOS built-in data detectors
- ✅ **Your data stays private**: Only the final wrapped link is created

---

## Comparison: Visual Intelligence vs Manual Share

| Method | Visual Intelligence | Manual Share |
|--------|-------------------|--------------|
| **Speed** | 1 button press | Tap share → Select Diver → Tags → Save |
| **Use Case** | URLs in screenshots, photos, QR codes | URLs in Safari, apps with share sheet |
| **Accuracy** | Depends on OCR quality | 100% accurate |
| **Tags** | Auto-tagged: "visual-intelligence", "screenshot" | Custom tags via rich UI |
| **Best For** | Quick capture, QR codes, printed URLs | Curated saves with organization |

**Recommendation**: Use both!
- **Visual Intelligence**: Quick capture of anything on screen
- **Manual Share**: Organized saving with custom tags

---

## Future Enhancements

### Planned Improvements

1. **URL Picker**: When multiple URLs found, show picker to choose which one
2. **Smart Cropping**: Auto-crop to URL region before OCR for better accuracy
3. **History**: View recently scanned URLs in case you need to go back
4. **Batch Mode**: Scan multiple screenshots at once
5. **Context Detection**: Suggest tags based on what app the screenshot came from
6. **OCR Confidence**: Show confidence level and allow retry if low

### Experimental Features

- **Live Text Integration**: Use iOS 15+ Live Text API for even better accuracy
- **Continuous Capture**: Hold Action Button to scan rapidly (multiple screenshots)
- **Smart Highlighting**: Highlight detected URLs on screen before capturing

---

## See Also

- **Documentation/ACTION_EXTENSION.md**: Rich UI share extension
- **Documentation/SHORTCUTS_AND_WIDGETS.md**: All shortcuts and widgets
- **Diver/Resources/Shortcuts/README.md**: Other shortcut templates

---

## Feedback

Found a URL that didn't get detected? Send us:
1. The screenshot (with URL visible)
2. What URL should have been detected
3. Any error messages

We'll improve the OCR patterns to catch it next time!
