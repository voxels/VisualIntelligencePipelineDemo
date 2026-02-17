import SwiftUI
import DiverKit

/// Thin wrapper — delegates to the unified `EditLocationView(session:)`.
/// Kept for backward compatibility at existing call sites.
struct EditSessionLocationView: View {
    @Bindable var session: SessionMetadata
    
    var body: some View {
        EditLocationView(session: session)
    }
}
