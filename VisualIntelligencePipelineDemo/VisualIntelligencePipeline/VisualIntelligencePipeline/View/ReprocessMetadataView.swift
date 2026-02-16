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
    @State private var loadedImageData: Data? = nil
    @State private var isLoadingImage = false
    
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
                        } else if isLoadingImage {
                            HStack {
                                ProgressView()
                                Text("Loading from Photos...")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        } else if effectiveImageData == nil {
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
                    .disabled(effectiveImageData == nil || isLoading || isLoadingImage)
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
                
                // Load from Photos if:
                // 1. No rawPayload at all, OR
                // 2. rawPayload contains video data but item is a photo (Live Photo case)
                let needsPhotosLoad: Bool = {
                    if item.rawPayload == nil { return true }
                    if let data = item.rawPayload, item.mediaType != "video" {
                        // Check for video bytes (ftyp/moov header)
                        guard data.count >= 12 else { return false }
                        let header = data.prefix(12).map { String(format: "%02hhx", $0) }.joined()
                        return header.contains("66747970") || header.contains("6d6f6f76")
                    }
                    return false
                }()
                
                if needsPhotosLoad, let assetId = item.photosAssetIdentifier {
                    isLoadingImage = true
                    Task {
                        let data = await PhotosAssetLoader.shared.loadImageData(identifier: assetId)
                        await MainActor.run {
                            loadedImageData = data
                            isLoadingImage = false
                        }
                    }
                }
            }
        }
    }
    
    /// Effective image data: rawPayload or loaded from Photos.
    /// CRITICAL: For Live Photos, rawPayload may contain MOV video data.
    /// If the item is a photo but rawPayload has video bytes, skip it and use Photos.
    private var effectiveImageData: Data? {
        if let data = item.rawPayload, !isJSON(data) {
            // Guard: If item is a photo but payload starts with ftyp (video),
            // it's a Live Photo's video component — skip and load still from Photos.
            let isPhotoType = item.mediaType != "video"
            if isPhotoType && isVideoData(data) {
                return loadedImageData
            }
            return data
        }
        return loadedImageData
    }
    
    private var itemImage: UIImage? {
        if let data = effectiveImageData {
            return UIImage(data: data)
        }
        return nil
    }
    
    private func isVideoData(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        let header = data.prefix(12).map { String(format: "%02hhx", $0) }.joined()
        return header.contains("66747970") || header.contains("6d6f6f76") // ftyp or moov
    }
    
    private func isJSON(_ data: Data?) -> Bool {
        guard let data = data, !data.isEmpty else { return false }
        let first = data[0]
        return first == 0x7B || first == 0x5B // '{' or '['
    }
    
    private func startReprocessing() {
        guard let imageData = effectiveImageData else { return }
        
        isLoading = true
        
        // 0. Reset Purposes/Intent to force fresh generation
        item.purposes = []
        item.questions = []
        Task { @MainActor in try? modelContext.save() }
        
        // 1. Set Shared Context - Preserve Session ID if possible to maintain continuity
        let sessionID = item.sessionID ?? UUID().uuidString
        
        let context = ReprocessContext(
            imageData: imageData,
            sessionID: sessionID,
            sessionTitle: sessionTitle.isEmpty ? nil : sessionTitle,
            location: item.location,
            placeID: item.placeContext?.placeID,
            placeName: item.placeContext?.name,
            mediaType: item.mediaType
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
