import SwiftUI
import SwiftData
import DiverKit
import DiverShared

struct ReprocessMetadataView: View {
    let item: ProcessedItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
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
                    .disabled(item.rawPayload == nil || isJSON(item.rawPayload) || isLoading)
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
        if let data = item.rawPayload, !isJSON(data) {
            return UIImage(data: data)
        }
        return nil
    }
    
    private func isJSON(_ data: Data?) -> Bool {
        guard let data = data, !data.isEmpty else { return false }
        let first = data[0]
        return first == 0x7B || first == 0x5B // '{' or '['
    }
    
    private func startReprocessing() {
        guard let imageData = item.rawPayload, !isJSON(imageData) else { return }
        
        isLoading = true
        
        // 0. Reset Purposes/Intent to force fresh generation
        item.purposes = []
        item.questions = []
        try? modelContext.save()
        
        // 1. Set Shared Context - Preserve Session ID if possible to maintain continuity
        let sessionID = item.sessionID ?? UUID().uuidString
        
        let context = ReprocessContext(
            imageData: imageData,
            sessionID: sessionID,
            location: item.location,
            placeID: item.placeContext?.placeID,
            placeName: item.placeContext?.name
        )
        
        Task { @MainActor in
            print("🔄 [ReprocessMetadataView] Setting pending context. Image Size: \(context.imageData.count) bytes")
            Services.shared.pendingReprocessContext = context
            
            // 2. Dismiss this sheet
            dismiss()
            
            // 3. Trigger Visual Intelligence
            try? await Task.sleep(nanoseconds: 300_000_000)
            NotificationCenter.default.post(name: .openVisualIntelligence, object: nil)
        }
    }
}
