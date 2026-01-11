# Plan: Visual Intelligence Proximity Sharing

## Objective
Enable users to share their current "Visual Intelligence" context (recognized objects, metadata, overlay state) with another user by simply bringing their devices close together. This leverages Apple's proximity-based sharing features (SharePlay/AirDrop) to establish a connection (often referred to by users as an "AirPlay connection" in the context of device bumping).

## 1. Data Model: Visual Intelligence Context
We will create a new `VisualIntelligenceContext` struct in `DiverShared`. usage of the existing `ContextSnapshot` where applicable.

*   **Struct**: `VisualIntelligenceContext` (extends or composes `ContextSnapshot`)
    *   `id`: UUID
    *   `description`: String (Summary of what is being viewed)
    *   `contextSnapshot`: `ContextSnapshot` (Existing model: Weather, Activity, Place)
    *   `visualItems`: `[VisualIntelligenceItem]` (Recognized objects, bounding boxes, text)
    *   `deepLink`: `URL` (Diver-link to the specific context)
    *   `timestamp`: Date

## 2. Technology Stack
*   **GroupActivities (SharePlay)**: The primary mechanism for "bringing devices close" to share an app experience.
*   **GroupSessionMessenger**: For sending the context data in real-time once connected.
*   **SystemCoordinator**: To handle the spatial/proximity triggers (handled by iOS for SharePlay).

## 3. Implementation Steps

### Phase 1: Define the Activity
Create a `GroupActivity` that represents the shared visual intelligence session.

```swift
import GroupActivities

struct VisualIntelligenceSharingActivity: GroupActivity {
    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = "Share Visual Intelligence"
        metadata.subtitle = "Sharing context with nearby device"
        metadata.type = .generic
        return metadata
    }
}
```

### Phase 2: Session Management
In `VisualIntelligenceViewModel` or a new `DiverKit` service `VisualIntelligenceSharingService`:

1.  **Activation**:
    *   Listen for `VisualIntelligenceSharingActivity.sessions()`.
    *   When a session is received (initiated via proximity/AirDrop), join it.
2.  **Data Transmission**:
    *   Create a `GroupSessionMessenger`.
    *   Serialize the current context (`VisualIntelligenceContext`).
    *   Send it via the messenger.

### Phase 3: UI Integration
*   **Proximity Trigger**: iOS handles the "bump" to start SharePlay if the activity is prepared or active. 
    *   We will call `VisualIntelligenceSharingActivity().prepareForActivation()` when the user is actively viewing a subject in the Visual Intelligence view (e.g., when `VisualIntelligenceViewModel.hasSubject` is true).

### Phase 4: Receiver Experience
*   When a context is received via the messenger:
    *   Parse the `VisualIntelligenceContext`.
    *   Update the `VisualIntelligenceView` to show a "Shared Context" banner or overlay.
    *   Allow saving the context to the Diver library as a `ProcessedItem`.

## 4. Execution Plan (Tomorrow)
1.  **09:00 - 10:00**: Define `VisualIntelligenceContext` struct in `DiverShared` and `VisualIntelligenceSharingActivity`.
2.  **10:00 - 12:00**: Implement `VisualIntelligenceSharingService` in `DiverKit` to handle `GroupSession` and `GroupSessionMessenger`.
3.  **13:00 - 15:00**: Integrate into `VisualIntelligenceViewModel`.
    *   Call `.prepareForActivation()` when analysis is complete.
    *   Observe `sessions` and handle incoming data.
4.  **15:00 - 16:00**: Integrate Receiver UI in `VisualIntelligenceView` to display shared items.
5.  **16:00 - 17:00**: Quality Assurance and Testing (verify "bump" gesture triggers session).
