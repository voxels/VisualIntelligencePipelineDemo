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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        
                        Text(item.sessionID ?? "No Session ID")
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                
                Section {
                    Button {
                        startReprocessing()
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else if item.rawPayload == nil {
                            Text("Original Image Missing")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Confirm & Reprocess")
                                .bold()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(item.rawPayload == nil || isLoading)
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
        return nil
    }
    
    private func startReprocessing() {
        guard let imageData = item.rawPayload else { return }
        
        isLoading = true
        
        // 1. Set Shared Context - New Session
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
            try? await Task.sleep(nanoseconds: 300_000_000)
            NotificationCenter.default.post(name: .openVisualIntelligence, object: nil)
        }
    }
}
