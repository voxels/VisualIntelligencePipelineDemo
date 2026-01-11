import SwiftUI

/// Snippet view for ShareLinkIntent shown in Siri/Shortcuts UI.
struct ShareLinkSnippet: View {
    let host: String
    let wrappedLink: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "link")
                    .foregroundColor(.green)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sharing Link")
                        .font(.headline)
                    Text(host)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(wrappedLink)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            HStack {
                Spacer()
                Text("Ready to Share")
                    .font(.caption2.bold())
                    .foregroundStyle(.green.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    ShareLinkSnippet(
        host: "example.com",
        wrappedLink: "https://diver.link/w/abc123?v=1&sig=xyz..."
    )
}
