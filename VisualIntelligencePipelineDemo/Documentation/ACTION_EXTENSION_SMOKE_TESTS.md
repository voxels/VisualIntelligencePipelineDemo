# Action Extension Manual Smoke Tests

Use this checklist before releasing new builds. The Action Extension has strict memory and time limits, so testing in real conditions is critical.

## Prerequisites

- [ ] Device running iOS 18+ (physical device or simulator)
- [ ] Diver app installed with valid provisioning
- [ ] Action Extension entitlements configured (app group, keychain access group)
- [ ] Main app launched at least once (to generate keychain secret)

## Test Environment Setup

### 1. Verify Keychain Secret
- [ ] Launch main app
- [ ] Check console for "Generated DiverLink secret" or "DiverLink secret exists"
- [ ] If missing, delete app and reinstall

### 2. Verify App Group Access
- [ ] Launch Action Extension from Safari share sheet
- [ ] Check console for "✅ App group accessible"
- [ ] If ❌ appears, check entitlements in Xcode

## Functional Tests

### Test 1: Valid URL from Safari
**Steps:**
1. Open Safari
2. Navigate to https://example.com
3. Tap Share button
4. Select "Diver" action
5. Wait for processing

**Expected:**
- [ ] Extension opens without crash
- [ ] "Saving to Diver" status appears
- [ ] Wrapped link copied to clipboard (check via paste)
- [ ] "Open Messages" button appears
- [ ] Extension completes without error
- [ ] URL appears in main app's queue (check queue directory or next app launch)

### Test 2: Invalid URL Handling
**Steps:**
1. Create a text file with "not-a-url" content
2. Share to Diver from Files app
3. Observe behavior

**Expected:**
- [ ] Extension shows error: "Unable to Save"
- [ ] No queue item created
- [ ] No crash

### Test 3: Missing Keychain Secret (Simulate)
**Manual simulation** (requires code change for testing):
- Temporarily comment out keychain retrieval success path
- Share a valid URL
- Observe error handling

**Expected:**
- [ ] Error shown: "DiverLink secret not found in Keychain"
- [ ] No queue item created
- [ ] No crash

### Test 4: Messages Integration
**Steps:**
1. Share a URL from Safari to Diver
2. Tap "Open Messages" button
3. Select a contact
4. Check message compose field

**Expected:**
- [ ] Messages app opens
- [ ] Wrapped link (https://secretatomics.com/w/...) pre-filled in message
- [ ] Link has correct format (v=1, sig=..., p=...)

### Test 5: Multiple URL Shares (Rapid Fire)
**Steps:**
1. Share URL #1 from Safari
2. Immediately return to Safari (don't wait for completion)
3. Share URL #2
4. Share URL #3
5. Wait 30 seconds

**Expected:**
- [ ] All 3 URLs enqueued (check queue directory)
- [ ] No crashes
- [ ] No queue corruption (files parseable as JSON)

### Test 6: Memory Pressure Handling
**Steps:**
1. Open multiple heavy apps (Photos, Maps, YouTube)
2. Share a URL from Safari to Diver while apps are in background

**Expected:**
- [ ] Extension completes successfully
- [ ] No memory-related crash (check device logs)
- [ ] Queue item created

## Performance Tests

### Test 7: Extension Launch Time
**Steps:**
1. Share URL from Safari
2. Measure time from tap to "Saving" screen

**Expected:**
- [ ] Extension UI appears < 500ms
- [ ] No visible lag or freeze

### Test 8: Processing Time
**Steps:**
1. Share URL from Safari
2. Measure time from "Saving" to "Copied" status

**Expected:**
- [ ] Total time < 2 seconds for simple URL
- [ ] No watchdog timeout (iOS terminates extensions after 30s)

## Edge Cases

### Test 9: Long URLs
**Steps:**
1. Share a URL with 2000+ character query string
2. Verify extension handles it

**Expected:**
- [ ] No crash
- [ ] URL enqueued (may be truncated per wrapping logic)

### Test 10: Special Characters in URLs
**Steps:**
1. Share URL with emoji, unicode, or special characters
2. Example: `https://example.com/page?q=hello%20world&emoji=🎉`

**Expected:**
- [ ] Correct encoding/decoding
- [ ] Wrapped link valid
- [ ] Original URL preserved in payload

### Test 11: App Group Permissions
**Steps:**
1. Remove app group entitlement temporarily
2. Rebuild extension
3. Try to share a URL

**Expected:**
- [ ] Error in console: "❌ ERROR: Cannot access app group"
- [ ] No crash
- [ ] User sees error UI

### Test 12: Concurrent Extension Invocations
**Steps:**
1. Open two Safari tabs
2. Share from tab 1 to Diver
3. While processing, switch to tab 2 and share to Diver again

**Expected:**
- [ ] Both shares complete independently
- [ ] No queue file conflicts
- [ ] Both URLs enqueued with unique IDs

## Regression Checks

### After Code Changes
- [ ] Re-run Tests 1-6 (core functionality)
- [ ] Check queue directory for file format consistency
- [ ] Verify wrapped links can be unwrapped (test in main app or DiverShared tests)

### Before Release
- [ ] All smoke tests pass
- [ ] No console errors during normal flow
- [ ] Extension memory usage < 50MB (check Instruments)
- [ ] No background assertions in device logs

## Known Issues & Limitations

### Current Limitations
- Extension can only process one URL at a time per invocation
- Heavy ML/search operations deferred to main app (by design)
- Extension cannot display rich UI (intentional for performance)

### iOS-Specific Behaviors
- iOS may terminate extension if it takes > 30s (watchdog)
- Low memory conditions may force extension termination
- Background app refresh affects queue processing timing

## Debugging Tips

### Console Logs
- Filter by "Diver" or "ActionExtension"
- Look for "✅" (success) or "❌" (error) emoji markers
- Check for "DiverLink secret" and "App group" status

### Queue Directory Inspection
- Path: `group.com.secretatomics.Diver/Queue/`
- Files named: `<timestamp>-<uuid>.json`
- Verify JSON is valid and contains expected fields

### Device Logs
- Use Console.app (macOS) to view device logs
- Filter by process: "ActionExtension"
- Look for memory warnings or crash reports

## Test Results Template

```
Date: ____________________
Tester: __________________
Device: __________________
iOS Version: _____________
Build: ___________________

Test 1: Valid URL from Safari          [ PASS / FAIL ]
Test 2: Invalid URL Handling            [ PASS / FAIL ]
Test 3: Missing Keychain Secret         [ PASS / FAIL ]
Test 4: Messages Integration            [ PASS / FAIL ]
Test 5: Multiple URL Shares             [ PASS / FAIL ]
Test 6: Memory Pressure Handling        [ PASS / FAIL ]
Test 7: Extension Launch Time           [ PASS / FAIL ]
Test 8: Processing Time                 [ PASS / FAIL ]
Test 9: Long URLs                       [ PASS / FAIL ]
Test 10: Special Characters in URLs     [ PASS / FAIL ]
Test 11: App Group Permissions          [ PASS / FAIL ]
Test 12: Concurrent Extension Invocations [ PASS / FAIL ]

Notes:
_________________________________________________
_________________________________________________
_________________________________________________
```
