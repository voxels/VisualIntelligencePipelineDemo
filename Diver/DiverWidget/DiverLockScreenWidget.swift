import WidgetKit
import SwiftUI
import AppIntents

struct DiverLockScreenWidget: Widget {
    let kind: String = "DiverLockScreenWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SearchLinksIntent.self,
            provider: LinkTimelineProvider()
        ) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Diver")
        .description("Quick access to recent links")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: LinkEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularLockScreenView(entry: entry)
        case .accessoryRectangular:
            RectangularLockScreenView(entry: entry)
        case .accessoryInline:
            InlineLockScreenView(entry: entry)
        default:
            Text("?")
        }
    }
}

// MARK: - Circular (Link Count Badge)

struct CircularLockScreenView: View {
    let entry: LinkEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: "link.circle.fill")
                    .font(.title2)
                Text("\(entry.links.count)")
                    .font(.headline)
            }
        }
    }
}

// MARK: - Rectangular (2 Recent Links)

struct RectangularLockScreenView: View {
    let entry: LinkEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "link.circle")
                    .font(.caption)
                Text("Recent Links")
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            if let first = entry.links.first {
                HStack(spacing: 4) {
                    Image(systemName: "1.circle.fill")
                        .font(.caption2)
                    Text(first.title ?? "Untitled")
                        .font(.caption2)
                        .lineLimit(1)
                }
            }

            if entry.links.count > 1, let second = entry.links.dropFirst().first {
                HStack(spacing: 4) {
                    Image(systemName: "2.circle.fill")
                        .font(.caption2)
                    Text(second.title ?? "Untitled")
                        .font(.caption2)
                        .lineLimit(1)
                }
            } else if entry.links.isEmpty {
                Text("No links yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .widgetURL(entry.links.first?.url)
    }
}

// MARK: - Inline (Most Recent Link Title)

struct InlineLockScreenView: View {
    let entry: LinkEntry

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
            if let first = entry.links.first {
                Text(first.title ?? first.url?.host ?? "Link")
            } else {
                Text("No recent links")
            }
        }
        .widgetURL(entry.links.first?.url)
    }
}
