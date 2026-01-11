import WidgetKit
import SwiftUI
import AppIntents

struct DiverInteractiveWidget: Widget {
    let kind: String = "DiverInteractiveWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: InteractiveTimelineProvider()) { entry in
            InteractiveWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Actions")
        .description("Quick save and search buttons")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// Simple timeline provider for interactive widgets
struct InteractiveTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = SimpleEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }

    struct SimpleEntry: TimelineEntry {
        let date: Date
    }
}

struct InteractiveWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: InteractiveTimelineProvider.SimpleEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallInteractiveView()
        case .systemMedium:
            MediumInteractiveView()
        default:
            Text("Unsupported")
        }
    }
}

// MARK: - Small Interactive Widget (Save from Clipboard)

struct SmallInteractiveView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            Text("Save Link")
                .font(.headline)

            Button(intent: SaveFromClipboardIntent()) {
                Text("From Clipboard")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding()
    }
}

// MARK: - Medium Interactive Widget (Multiple Actions)

struct MediumInteractiveView: View {
    var body: some View {
        HStack(spacing: 12) {
            // Save from clipboard
            VStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .font(.title)
                    .foregroundStyle(.blue)
                Text("Save")
                    .font(.caption)
                    .fontWeight(.semibold)
                Button(intent: SaveFromClipboardIntent()) {
                    Text("Clipboard")
                        .font(.caption2)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Open recent
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title)
                    .foregroundStyle(.green)
                Text("Recent")
                    .font(.caption)
                    .fontWeight(.semibold)
                Button(intent: OpenRecentIntent()) {
                    Text("Open")
                        .font(.caption2)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
}

// MARK: - App Intents for Interactive Buttons

struct SaveFromClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Save from Clipboard"
    static var description = IntentDescription("Save URL from clipboard to Diver")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Get clipboard content
        #if canImport(UIKit)
        import UIKit
        guard let clipboardString = UIPasteboard.general.string,
              let url = URL(string: clipboardString),
              Validation.isValidURL(clipboardString) else {
            return .result(dialog: "No valid URL found in clipboard")
        }
        #else
        import AppKit
        guard let clipboardString = NSPasteboard.general.string(forType: .string),
              let url = URL(string: clipboardString),
              Validation.isValidURL(clipboardString) else {
            return .result(dialog: "No valid URL found in clipboard")
        }
        #endif

        // Use SaveLinkIntent
        var intent = SaveLinkIntent()
        intent.url = url
        intent.tags = []

        return try await intent.perform()
    }
}

struct OpenRecentIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Recent Link"
    static var description = IntentDescription("Open most recent link")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Use SearchLinksIntent with empty query
        var searchIntent = SearchLinksIntent()
        searchIntent.query = ""
        searchIntent.limit = 1

        let result = try await searchIntent.perform()

        // Open the link
        if let url = result.value.url {
            #if canImport(UIKit)
            await UIApplication.shared.open(url)
            #else
            NSWorkspace.shared.open(url)
            #endif
            return .result(dialog: "Opened \(result.value.title ?? "link")")
        } else {
            return .result(dialog: "No recent links found")
        }
    }
}
