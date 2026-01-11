import WidgetKit
import SwiftUI
import AppIntents
import DiverShared
import OSLog

private let logger = Logger(subsystem: "com.secretatomics.Diver", category: "InteractiveWidget")

#if canImport(UIKit)
import UIKit
import DiverKit
#else
import AppKit

#endif

struct VisualIntelligencePipelineInteractiveWidget: Widget {
    let kind: String = "VisualIntelligencePipelineInteractiveWidget"

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

            Link(destination: URL(string: "secretatomics://save-clipboard")!) {
                Text("From Clipboard")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
            }
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
                Link(destination: URL(string: "secretatomics://save-clipboard")!) {
                    Text("Clipboard")
                        .font(.caption2)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(6)
                }
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
                Link(destination: URL(string: "secretatomics://open-recent")!) {
                    Text("Open")
                        .font(.caption2)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .cornerRadius(6)
                }
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

    // Force app to foreground so we can reliably read the pasteboard
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Get clipboard content
        logger.debug("📥 SaveFromClipboardIntent: perform() started")
        
        #if canImport(UIKit)
        let clipboardString = UIPasteboard.general.string
        #else
        let clipboardString = NSPasteboard.general.string(forType: .string)
        #endif
        
        guard let clipboardString, !clipboardString.isEmpty else {
            logger.warning("⚠️ SaveFromClipboardIntent: Clipboard is empty")
            return .result(dialog: "Clipboard is empty")
        }
        
        guard let url = URL(string: clipboardString), Validation.isValidURL(clipboardString) else {
            logger.warning("⚠️ SaveFromClipboardIntent: Invalid URL in clipboard: \(clipboardString)")
            return .result(dialog: "No valid URL found in clipboard")
        }

        logger.info("✅ SaveFromClipboardIntent: Found URL: \(url.absoluteString)")

        // Use SaveLinkIntent
        let intent = SaveLinkIntent()
        intent.url = url
        intent.tags = ["clipboard"]

        do {
            _ = try await intent.perform()
            logger.info("✅ SaveFromClipboardIntent: Successfully saved link")
            return .result(dialog: "Saved link from clipboard")
        } catch {
            logger.error("❌ SaveFromClipboardIntent: Failed to save: \(error.localizedDescription)")
            return .result(dialog: "Failed to save: \(error.localizedDescription)")
        }
    }
}
import AppIntents

struct OpenRecentIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Recent Link"
    static var description = IntentDescription("Open most recent link")
    
    // 1. Remove 'openAppWhenRun = true'.
    // We want the result (OpenURLIntent) to handle the opening transition explicitly.
    // Set to true to ensure the app is alive to handle the deep link/pasteboard
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        logger.debug("🔘 OpenRecentIntent: perform() started")
        
        do {
            // Directly fetch latest entities without search overhead
            let entities = try LinkEntityQuery().fetchAllEntities()
            
            // Filter for ready items and sort by date descending
            if let latest = entities
                .filter({ $0.status == .ready && !$0.id.hasPrefix("debug-") })
                .sorted(by: { $0.createdAt > $1.createdAt })
                .first {
                
                let id = latest.id
                logger.info("✅ OpenRecentIntent: Found latest item \(latest.title ?? "Untitled") (id: \(id))")
                let deepLink = URL(string: "secretatomics://open?id=\(id)")!
                return .result(opensIntent: OpenURLIntent(deepLink))
            } else {
                logger.warning("⚠️ OpenRecentIntent: No ready items found")
                throw Error.noRecentLinks
            }
        } catch {
            logger.error("❌ OpenRecentIntent: Fetch failed: \(error.localizedDescription)")
            throw Error.noRecentLinks
        }
    }
}

// Define a custom error for the "not found" case
enum Error: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noRecentLinks
    
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noRecentLinks: return "No recent links found"
        }
    }
}

