import SwiftUI
import DiverKit
import DiverShared

struct ReprocessMetadataView: View {
    let item: ProcessedItem
    @Environment(\.dismiss) private var dismiss
    
    @State private var sessionTitle: String = ""
    @State private var sessionSummary: String = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Session Metadata") {
                    if let image = itemImage {
                        #if os(iOS)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 200)
                            .listRowInsets(EdgeInsets())
                            .clipped()
                        #endif
                    }
                    
                    TextField("Session Title", text: $sessionTitle)
                    
                    if !sessionSummary.isEmpty {
                        Text(sessionSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Location Context") {
                    if let place = item.placeContext?.name {
                        LabeledContent("Place", value: place)
                    }
                    if let loc = item.location {
                        LabeledContent("Coordinates", value: loc)
                    }
                    LabeledContent("Session ID", value: item.sessionID ?? "None")
                }
                
                Section {
                    Button {
                        startReprocessing()
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Confirm & Reprocess")
                                .bold()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Reprocess Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                sessionTitle = item.title ?? "Untitled Session"
                sessionSummary = item.summary ?? ""
            }
        }
    }
    
    private var itemImage: UIImage? {
        if let data = item.rawPayload {
            return UIImage(data: data)
        }
        // Fallback: Try reading from URL if it was a file URL
        // Simplified for now, relying on payload
        return nil
    }
    
    private func startReprocessing() {
        guard let imageData = item.rawPayload else {
            // Need image data to reprocess visually
            return
        }
        
        isLoading = true
        
        // 1. Set Shared Context
        // Generate NEW session ID as requested ("save a new session with a new session id")
        let newSessionID = UUID().uuidString
        
        let context = ReprocessContext(
            imageData: imageData,
            sessionID: newSessionID,
            location: item.location,
            placeID: item.placeContext?.placeID,
            placeName: item.placeContext?.name
        )
        
        Task { @MainActor in
            Services.shared.pendingReprocessContext = context
            
            // 2. Dismiss this sheet
            dismiss()
            
            // 3. Trigger Visual Intelligence
            // Wait slightly for dismiss animation?
            try? await Task.sleep(nanoseconds: 300_000_000)
            NotificationCenter.default.post(name: .openVisualIntelligence, object: nil)
        }
    }
}
