import SwiftUI

/// Snippet view for SaveLinkIntent shown in Siri/Shortcuts UI.
struct SaveLinkSnippet: View {
    let url: String
    let title: String?
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "link.badge.plus")
                    .foregroundColor(.blue)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saving to Visual Intelligence")
                        .font(.headline)
                    if let title, !title.isEmpty, title != url {
                        Text(title)
                            .font(.subheadline)
                            .lineLimit(2)
                    }
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            
            HStack {
                Spacer()
                Text("Saved to Library")
                    .font(.caption2.bold())
                    .foregroundStyle(.blue.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    SaveLinkSnippet(
        url: "https://example.com",
        title: "Example Site",
        tags: ["research", "swift"]
    )
}
