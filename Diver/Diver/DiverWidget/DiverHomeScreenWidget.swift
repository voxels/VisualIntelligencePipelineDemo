import WidgetKit
import SwiftUI
import AppIntents

struct DiverHomeScreenWidget: Widget {
    let kind: String = "DiverHomeScreenWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SearchLinksIntent.self,
            provider: LinkTimelineProvider()
        ) { entry in
            DiverWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Diver Links")
        .description("View and access your recent Diver links")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DiverWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: LinkEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            Text("Unsupported")
        }
    }
}

// MARK: - Small Widget (Single Link)

struct SmallWidgetView: View {
    let entry: LinkEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let link = entry.links.first {
                // Icon and host
                HStack {
                    Image(systemName: "link.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    
                    if link.isShared {
                        WidgetAttributionPill()
                    }
                    
                    Spacer()
                    if let host = link.url?.host {
                        Text(host)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Title
                Text(link.title ?? "Untitled Link")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(3)

                // Date
                Text(link.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                // Empty state
                VStack {
                    Image(systemName: "link.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Links")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .widgetURL(entry.links.first?.url)
    }
}

// MARK: - Medium Widget (3 Links)

struct MediumWidgetView: View {
    let entry: LinkEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "link.circle.fill")
                    .foregroundStyle(.blue)
                Text("Recent Links")
                    .font(.headline)
                Spacer()
                Text("\(entry.links.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Links
            if entry.links.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack {
                        Image(systemName: "link.badge.plus")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No links saved yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(entry.links.prefix(3)) { link in
                    LinkRow(link: link)
                }
            }
        }
        .padding()
    }
}

// MARK: - Large Widget (5 Links + Search)

struct LargeWidgetView: View {
    let entry: LinkEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with link count
            HStack {
                Image(systemName: "link.circle.fill")
                    .foregroundStyle(.blue)
                Text("Diver Links")
                    .font(.headline)
                Spacer()
                Text("\(entry.links.count) recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Links
            if entry.links.isEmpty {
                Spacer()
                VStack {
                    Image(systemName: "link.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No links saved yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Share links to Diver to see them here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(entry.links.prefix(5)) { link in
                    LinkRow(link: link, showSummary: true)
                    if link.id != entry.links.prefix(5).last?.id {
                        Divider()
                    }
                }
            }

            Spacer()

            // Footer
            HStack {
                Text("Tap to open in Diver")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }
}

// MARK: - Shared Components

struct WidgetAttributionPill: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 8, weight: .bold))
            Text("SHARED")
                .font(.system(size: 8, weight: .black))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.blue.opacity(0.2))
        .foregroundStyle(.blue)
        .clipShape(Capsule())
    }
}

struct LinkRow: View {
    let link: LinkEntity
    var showSummary: Bool = false

    var body: some View {
        Link(destination: URL(string: "diver://open?id=\(link.id)") ?? link.url ?? URL(string: "diver://")!) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 4) {
                    if link.isShared {
                        WidgetAttributionPill()
                    }
                    Text(link.title ?? "Untitled")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                if showSummary, let summary = link.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if let host = link.url?.host {
                    Text(host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
