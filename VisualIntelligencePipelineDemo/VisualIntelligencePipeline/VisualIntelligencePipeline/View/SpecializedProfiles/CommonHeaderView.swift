import SwiftUI
import DiverKit

public struct CommonHeaderView: View {
    let item: ProcessedItem
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    
    public init(item: ProcessedItem) {
        self.item = item
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // 1. Media Content (Video or Image)
            if item.mediaType == "video" {
                if let assetID = item.photosAssetIdentifier {
                    PhotosVideoPlayerView(assetIdentifier: assetID)
                        .frame(height: 300)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                        .padding(.bottom, 12)
                } else if let data = item.rawPayload {
                    DataVideoPlayer(data: data)
                        .frame(height: 300)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                        .padding(.bottom, 12)
                }
            } else {
                AsyncItemImageView(item: item)
            }
            
            // 2. Title Editor
            if isEditingTitle {
                TextField("Title", text: $editedTitle, onCommit: {
                    if !editedTitle.isEmpty {
                        item.title = editedTitle
                        Task { @MainActor in try? item.modelContext?.save() }
                    }
                    isEditingTitle = false
                })
                .font(.largeTitle)
                .fontWeight(.bold)
                .textFieldStyle(.roundedBorder)
                .onAppear {
                    editedTitle = item.title ?? "Untitled"
                }
            } else {
                Text(item.title ?? "Untitled")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)
                    .onLongPressGesture {
                        editedTitle = item.title ?? "Untitled"
                        isEditingTitle = true
                    }
            }
            
            // 3. Status Badges & LLM Summary Badge
            if let summary = item.summary {
                let parsed = parseSummaryModelBadge(from: summary)
                Text(parsed.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.top, 4)
                    
                if let badge = parsed.badge {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text(badge)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 2)
                }
            }
            
            HStack {
                StatusBadge(status: item.status)
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }
    
    /// Parses `[Model: ModelName]` from the end of the summary.
    private func parseSummaryModelBadge(from summary: String) -> (text: String, badge: String?) {
        let pattern = #"^\s*(.*?)\s*\[Model:\s*(.*?)\]\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return (summary, nil)
        }
        
        let nsString = summary as NSString
        let results = regex.matches(in: summary, range: NSRange(location: 0, length: nsString.length))
        
        if let match = results.first, match.numberOfRanges == 3 {
             let cleanedText = nsString.substring(with: match.range(at: 1))
             let modelBadge = nsString.substring(with: match.range(at: 2))
             return (cleanedText, modelBadge)
        }
        
        return (summary, nil)
    }
}
