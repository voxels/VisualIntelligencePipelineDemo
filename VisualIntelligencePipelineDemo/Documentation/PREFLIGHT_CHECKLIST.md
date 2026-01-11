# Pre-Flight Checklist: Diver Operational Readiness

Before we write the first line of Phase 1C/Phase 2 code, these operational details should be confirmed to ensure App Store compliance and a premium user experience.

Status update (current): Phase 1A Action Extension baseline is implemented; Phase 0 integration testing remains pending.

## 1. Discovery & Review Efficiency
- **App Shortcuts**: Siri needs to "know" your intents exist without the user configuring them. 
- **Action**: We must implement `AppShortcutsProvider` with high-quality "App Shortcut Phrases" so they appear in the Shortcuts app immediately.
- **Review Strategy**: Prepare a screen recording for App Store reviewers showing the Action Button -> Save -> Siri query flow, as these are hard to test in sandbox.

## 2. The Feedback Loop (The "Black Box" Problem)
- **Problem**: With the "Defer and Process" pipeline, the user saves a URL but doesn't see the AI tags immediately.
- **Action**: Implement **Live Activities** or **Dynamic Island** support for the Metadata Pipeline.
- **UX**: Show a subtle "Diver is analyzing..." status in the Unified Feed for pending items.

## 3. Localization (Natural Language AGI)
- **Constraint**: Apple Intelligence (AGI Siri) requires your `AppIntent` parameters and `DisplayRepresentation` titles to be localized.
- **Action**: Use `LocalizedStringResource` for all user-facing strings in `DiverKit` so Siri can understand queries in multiple languages naturally.

## 4. Privacy & Compliance
- **Privacy Manifest**: iOS 17.4+ (and certainly iOS 26) requires a `PrivacyInfo.xcprivacy` file.
- **Action**: Document the use of "Required Reason" APIs (e.g., `File Timestamp` for SQLite sync and `Disk Space` for caching).
- **Transparency**: Ensure the "Shared with You" ingestion logic has a clear "opt-out" in the app's settings.

## 5. Background Data Budgeting
- **Efficiency**: Scraping 50 tabs shared from a group chat could consume significant data/battery.
- **Action**: Implement a "High Productivity Mode" toggle: only run the full AI pipeline on Wi-Fi or when the device is charging.

---
*Last Updated: 2025-12-18 by Antigravity*
