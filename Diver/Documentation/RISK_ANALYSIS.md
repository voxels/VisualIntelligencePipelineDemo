# Risk, Performance, and Safety Analysis: Diver Unified Architecture

This document provides a technical assessment of the proposed architecture, identifying potential bottlenecks and safety measures.

## 1. Integration Risks

### 🧩 Shared Framework Linking (DiverKit)
- **Risk**: Xcode linking errors when multiple targets (Main App, Share, iMessage, App Intent Extension) attempt to use the same SwiftData models.
- **Mitigation**: Ensure `DiverKit` is a dynamic framework (or a strictly defined static library) and that all targets share the same "App Group" identifier in their entitlements.

### 📇 Contacts Permissions in Action Extension (Removed)
- **Status**: Phase 1B was removed; no contacts-based extension flow is planned.

### 🧵 Multi-Process Concurrency (SwiftData)
- **Risk**: Corruption of the SQLite database when the Share Extension and Main App write simultaneously.
- **Mitigation**: Use `ModelContainer` with a specific App Group URL. SwiftData (via Core Data) handles file coordination, but we must use `@MainActor` or dedicated background `ModelContext`s to prevent deadlocks.
- **Safety**: Implement a "write-retry" logic or a "pending" queue if write locks are encountered.

### 🔗 Proprietary Link Security
- **Risk**: Maliciously crafted proprietary links could lead to SQL injection or data corruption during "unpacking."
- **Mitigation**: Use `JSONDecoder` with strict type validation. Never execute code found in a URL. Sanitize all incoming metadata before saving.

---

## 2. Performance Implications

### 🔋 Background Resource Limits
- **Risk**: The Share Extension has a strict ~120MB memory limit. If the `MetadataPipelineService` starts a heavy AI task, the extension will be killed.
- **Decision**: The Share Extension will only *enqueue* the task to the database. The Main App (via Background Tasks API) or the App Intent (which has more headroom) will perform the actual scraping/AI processing.

### 🏎️ Indexing Overhead
- **Risk**: Spotlight and Apple Intelligence (`IndexedEntity`) can slow down the device if thousands of items are saved at once.
- **Mitigation**: Use `indexed(for: )` with sensible batch sizes. Avoid indexing large binary blobs; index summaries and metadata only.

### 📱 iMessage Extension Memory
- **Risk**: iMessage extensions are notoriously memory-constrained. Loading a "Unified Feed" with rich previews might cause crashes.
- **Optimization**: Use "Lazy" loading in SwiftUI. Use low-resolution thumbnails for the iMessage feed.

---

## 3. Safety & Data Integrity

### ☁️ CloudKit Conflict Resolution
- **Risk**: Conflicts when the same record is edited on two devices (e.g., iPhone and iPad).
- **Mitigation**: SwiftData handles basic merging, but we should include a `version` or `lastModified` timestamp on `LocalInput` to handle edge cases manually in the `MetadataPipelineService`.

### 🤫 Privacy (Shared with You)
- **Decision**: We will respect `SWHighlightCenter` visibility settings. If a user deletes a message in iMessage, the "highlight" should disappear from our feed.
- **Implementation**: The "Auto-Ingestion" pipeline must periodically sync with `SWHighlightCenter` to prune dead links.

---

## 4. Testing Strategy

### ✅ Unit Testing (DiverKit)
- **Target**: `UnifiedDataManager` initialization.
- **Test**: Verify that saving in one `ModelContext` is visible in another (simulating multi-process).
- **Mocking**: Use an in-memory `ModelContainer` for local unit tests.

### 🧪 Pipeline Integration Tests
- **Target**: `MetadataPipelineService`.
- **Test**: Enqueue a mock URL and verify that the "AI Tagging" output is written back to the entity.

### 🖼️ UI & Extension Testing
- **iMessage**: Test the extension transition states (Compact vs. Expanded).
- **Share Sheet**: Test sharing from "Files" vs "Safari" vs "Photos" to ensure all `NSExtensionItem` types are handled.

---
*Last Updated: 2025-12-18 by Antigravity*
