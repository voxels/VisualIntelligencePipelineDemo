import WidgetKit
import SwiftUI
import AppIntents

struct DiverScanWidget: Widget {
    let kind: String = "DiverScanWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScanProvider()) { entry in
            DiverScanWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Diver Scan")
        .description("Scan your screen for URLs and save them to Diver.")
        .supportedFamilies([.systemSmall, .systemMedium])
        // .systemLarge omitted as it's less suited for a single action button
    }
}

struct ScanEntry: TimelineEntry {
    let date: Date
}

struct ScanProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScanEntry {
        ScanEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (ScanEntry) -> Void) {
        completion(ScanEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScanEntry>) -> Void) {
        let entry = ScanEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct DiverScanWidgetView: View {
    var entry: ScanEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack {
            if family == .systemSmall {
                ScanButton(isSmall: true)
            } else {
                ScanButton(isSmall: false)
            }
        }
    }
}

struct ScanButton: View {
    var isSmall: Bool

    var body: some View {
        Link(destination: URL(string: "diver://scan")!) {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [.purple, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                VStack(spacing: isSmall ? 8 : 12) {
                    Image(systemName: "viewfinder")
                        .font(isSmall ? .system(size: 32) : .system(size: 40))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, options: .repeating)
                    
                    Text("Scan Screen")
                        .font(isSmall ? .caption : .headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
