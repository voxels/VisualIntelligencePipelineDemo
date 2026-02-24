import SwiftUI
import DiverKit
import DiverShared

public struct WebLinkProfileView: View {
    let item: ProcessedItem
    @StateObject private var viewModel = ReferenceDetailViewModel()
    
    public init(item: ProcessedItem) {
        self.item = item
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let web = item.webContext {
                 WebInfoView(context: web, url: item.resolvedWebURL)
                    .padding(.horizontal)
                 
                 if let json = web.structuredData {
                     StructuredDataView(jsonString: json)
                        .padding(.horizontal)
                 }
            } else if let url = item.resolvedWebURL {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Web Preview")
                        .font(.title3)
                        .bold()
                    RichWebView(url: url) { title in
                        if !title.isEmpty && title != item.title {
                            viewModel.updateTitle(title, for: item)
                        }
                    }
                        .frame(height: 300)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    
                    Button {
                        viewModel.refreshLinkMetadata(item: item)
                    } label: {
                        Label("Refresh Preview", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(normalize(color: .secondarySystemGroupedBackground)))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
}

// MARK: - Web Info
struct WebInfoView: View {
    let context: WebContext
    let url: URL?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Web Preview")
                    .font(.title3)
                    .bold()
                Spacer()
                if let url = url {
                    Link(destination: url) {
                        Image(systemName: "safari")
                            .font(.body)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
            }
            
            if let snapshotPath = context.snapshotURL {
                AsyncImage(url: URL(fileURLWithPath: snapshotPath)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200)
                            .cornerRadius(12)
                            .clipped()
                    }
                }
            }

            if let url = url {
                RichWebView(url: url)
                    .frame(height: 300)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            } else {
                GroupBox {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "safari")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(context.siteName ?? "Website")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            if let time = context.readingTimeMinutes {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                    Text("\(time) min read")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                }
                .groupBoxStyle(.automatic)
            }
        }
        .padding()
        .background(Color(normalize(color: .secondarySystemGroupedBackground)))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Structured Data View
struct StructuredDataView: View {
    let jsonString: String
    
    var body: some View {
        if let data = parseJSON(), !data.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Structured Data")
                    .font(.title3)
                    .bold()
                
                ForEach(data.indices, id: \.self) { index in
                    let item = data[index]
                    VStack(alignment: .leading, spacing: 8) {
                        if let type = item["@type"] as? String {
                            Text(type)
                                .font(.headline)
                                .foregroundStyle(.blue)
                        }
                        
                        // Limit display to simple string values to avoid clutter
                        ForEach(item.keys.sorted().filter { $0 != "@type" && $0 != "@context" }, id: \.self) { key in
                            if let value = item[key] as? String {
                                HStack(alignment: .top) {
                                    Text(formatKey(key))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .leading)
                                    Text(value)
                                        .font(.caption)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                    .padding()
                    .glass(cornerRadius: 12)
                }
            }
            .padding()
            .background(Color(normalize(color: .secondarySystemGroupedBackground)))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }
    
    private func formatKey(_ key: String) -> String {
        return key.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).capitalized
    }
    
    private func parseJSON() -> [[String: Any]]? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return [object]
        }
        return nil
    }
}
