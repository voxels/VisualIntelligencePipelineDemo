import WidgetKit
import SwiftUI
import AppIntents

struct VisualIntelligenceScanWidget: Widget {
    let kind: String = "VisualIntelligenceScanWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScanProvider()) { entry in
            VisualIntelligenceScanWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Visual Intelligence")
        .description("See your daily narrative and quickly scan to add more.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ScanEntry: TimelineEntry {
    let date: Date
    let summary: String
}

struct ScanProvider: TimelineProvider {
    // Replicating simple state struct to read shared JSON
    struct PersistedState: Codable {
        let contexts: [String]
        let summary: String
        let date: Date
    }
    
    // Logic to read from App Group
    private func loadSummary() -> String {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.secretatomics.VisualIntelligence")?.appendingPathComponent("daily_context_state.json") else {
            return "Ready to capture."
        }
        
        do {
            let data = try Data(contentsOf: url)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            
            // Check day freshness
            if Calendar.current.isDateInToday(state.date) {
                return state.summary.isEmpty ? "No activity yet today." : state.summary
            } else {
                return "Start your story for today."
            }
        } catch {
            return "Ready to capture."
        }
    }

    func placeholder(in context: Context) -> ScanEntry {
        ScanEntry(date: Date(), summary: "Your daily narrative appears here...")
    }

    func getSnapshot(in context: Context, completion: @escaping (ScanEntry) -> Void) {
        completion(ScanEntry(date: Date(), summary: loadSummary()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScanEntry>) -> Void) {
        let entry = ScanEntry(date: Date(), summary: loadSummary())
        // Refresh every 15 minutes or when app reloads widget
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct VisualIntelligenceScanWidgetView: View {
    var entry: ScanEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Link(destination: URL(string: "secretatomics://scan")!) {
            ZStack(alignment: .leading) {
                // Subtle gradient background
                ContainerRelativeShape()
                    .fill(LinearGradient(colors: [Color.indigo.opacity(0.1), Color.purple.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                VStack(alignment: .leading, spacing: 0) {
                    
                    // Header Area
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.purple)
                        Text("Daily Narrative")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        
                        Spacer()
                        
                        // Scan Icon (Action Indicator)
                        Image(systemName: "viewfinder")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Circle().fill(Color.purple))
                    }
                    .padding(.bottom, 8)
                    
                    // Summary Text
                    Text(entry.summary)
                        .font(family == .systemSmall ? .system(size: 13) : .system(size: 15))
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(family == .systemSmall ? 4 : 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if family == .systemMedium {
                         Spacer()
                         // Call to action for medium
                         HStack {
                             Spacer()
                             Text("Tap to Capture")
                                 .font(.caption2)
                                 .foregroundStyle(.secondary)
                         }
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .padding()
            }
        }
    }
}
