//
//  WebLinkProfileView.swift
//  DiverUI — cross-platform
//
//  normalize(color:) removed — replaced with .secondary.opacity(0.08)
//  RichWebView (WKWebView) guarded under #if os(iOS)
//

import SwiftUI
import DiverKit
import DiverShared

public struct WebLinkProfileView: View {
    public let item: ProcessedItem
    @StateObject private var viewModel = ReferenceDetailViewModel()

    public init(item: ProcessedItem) { self.item = item }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let web = item.webContext {
                WebInfoCard(context: web, url: item.resolvedWebURL).padding(.horizontal)
                if let json = web.structuredData {
                    StructuredDataCard(jsonString: json).padding(.horizontal)
                }
            } else if let url = item.resolvedWebURL {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Web Preview").font(.title3).bold()

                    #if os(iOS)
                    RichWebView(url: url) { title in
                        if !title.isEmpty && title != item.title { viewModel.updateTitle(title, for: item) }
                    }
                    .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    #else
                    Link(destination: url) {
                        Label("Open in Browser", systemImage: "safari").font(.subheadline)
                    }.buttonStyle(.bordered)
                    #endif

                    Button { viewModel.refreshLinkMetadata(item: item) } label: {
                        Label("Refresh Preview", systemImage: "arrow.clockwise").font(.caption)
                    }.buttonStyle(.bordered)
                }
                .padding().background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1).padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
}

// MARK: - Web Info Card

private struct WebInfoCard: View {
    let context: WebContext
    let url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Web Preview").font(.title3).bold()
                Spacer()
                if let url { Link(destination: url) { Image(systemName: "safari").font(.body) }.buttonStyle(.bordered).tint(.blue) }
            }
            if let snapshotPath = context.snapshotURL {
                AsyncImage(url: URL(fileURLWithPath: snapshotPath)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                            .frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            if let url {
                #if os(iOS)
                RichWebView(url: url).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                #else
                Link(destination: url) { Label("Open \(context.siteName ?? "Website")", systemImage: "safari") }
                    .buttonStyle(.bordered)
                #endif
            } else {
                GroupBox {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "safari").font(.title3).foregroundStyle(.blue).frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(context.siteName ?? "Website").font(.headline)
                            if let time = context.readingTimeMinutes {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                    Text("\(time) min read")
                                }
                                .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding().background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Structured Data Card

private struct StructuredDataCard: View {
    let jsonString: String

    var body: some View {
        if let data = parseJSON(), !data.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Structured Data").font(.title3).bold()
                ForEach(data.indices, id: \.self) { idx in
                    let item = data[idx]
                    VStack(alignment: .leading, spacing: 8) {
                        if let type = item["@type"] as? String {
                            Text(type).font(.headline).foregroundStyle(.blue)
                        }
                        ForEach(item.keys.sorted().filter { $0 != "@type" && $0 != "@context" }, id: \.self) { key in
                            if let value = item[key] as? String {
                                HStack(alignment: .top) {
                                    Text(formatKey(key)).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                                    Text(value).font(.caption).lineLimit(3)
                                }
                            }
                        }
                    }
                    .padding().glassEffect().clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding().background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 2)
        }
    }

    private func formatKey(_ key: String) -> String {
        key.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).capitalized
    }

    private func parseJSON() -> [[String: Any]]? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] { return arr }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return [obj] }
        return nil
    }
}
