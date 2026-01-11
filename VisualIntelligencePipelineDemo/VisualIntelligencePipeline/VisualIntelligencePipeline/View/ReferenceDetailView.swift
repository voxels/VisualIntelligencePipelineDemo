import SwiftUI
import DiverKit
import DiverShared
import SharedWithYou
import MapKit
import SwiftData
import LinkPresentation
import WebKit

struct ReferenceDetailView: View {
    let item: ProcessedItem
    @EnvironmentObject var navigationManager: NavigationManager
    @Query private var allItems: [ProcessedItem]
    
    // We bind selection to a local state initialized with the passed item, 
    // but we also want to keep it in sync if possible, or just let the carousel work independently.
    @State private var selectedItemID: PersistentIdentifier?
    
    var siblings: [ProcessedItem] {
        guard let sessionID = item.sessionID else { return [item] }
        return allItems.filter { $0.sessionID == sessionID }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }
    
    var body: some View {
        TabView(selection: $selectedItemID) {
            ForEach(siblings) { sibling in
                ReferenceDetailContent(item: sibling)
                    .tag(Optional(sibling.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onAppear {
            if selectedItemID == nil {
                selectedItemID = item.id
            }
        }
        .toolbar {
             // Toolbar buttons are now inside ReferenceDetailContent or need to be lifted?
             // If inside TabView, they contextually appear.
        }
        #if os(iOS)
        .background(Color(uiColor: .systemGroupedBackground))
        #endif
    }
}

struct ReferenceDetailContent: View {
    let item: ProcessedItem
    @StateObject private var viewModel = ReferenceDetailViewModel()
    @EnvironmentObject private var sharedWithYouManager: SharedWithYouManager
    @State private var showingMap = false
    @Query private var allItems: [ProcessedItem]
    @Query private var sessions: [SessionMetadata]
    
    var session: SessionMetadata? {
        sessions.first { $0.sessionID == item.sessionID }
    }
    
    var siblingContext: String {
        guard let sessionID = item.sessionID else { return "" }
        let siblings = allItems.filter { $0.sessionID == sessionID }
        return siblings.prefix(20).map { "- \($0.title ?? "Item"): \($0.summary ?? "")" }.joined(separator: "\n")
    }
    
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    
                    // 0. Purpose Header (Removed - Moved to Intent Section)

                    if item.entityType == DiverItemType.document.rawValue, let data = item.rawPayload, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                            .padding(.bottom, 12)
                            .glass(cornerRadius: 12)
                    } else if let snapshotPath = item.webContext?.snapshotURL, let uiImage = UIImage(contentsOfFile: snapshotPath) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                            .padding(.bottom, 12)
                            .glass(cornerRadius: 12)
                    }
                    
                    Text(item.title ?? "Untitled")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Session Context Summary
                    if let sessionSummary = session?.summary {
                        Text(sessionSummary)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    }
                    
                    if let url = item.resolvedWebURL {
                        Link(url.absoluteString, destination: url)
                            .foregroundStyle(.blue)
                            .font(.body)
                    }
                    
                    if let summary = item.summary {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .padding(.top, 4)
                    }
                    
                    // Divider removed

                    HStack {
                        StatusBadge(status: item.status)

                    }

                    // Shared with You Attribution
                    if let attributionID = item.attributionID,
                       let highlight = sharedWithYouManager.findHighlight(id: attributionID) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Shared with You")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            AttributionViewWrapper(highlight: highlight)
                                .frame(height: 50)
                            
                            Divider()
                        }
                    }
                }
                .detailCardStyle()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            item.isFavorite.toggle()
                            try? item.modelContext?.save()
                        } label: {
                            Label(item.isFavorite ? "Unfavorite" : "Favorite", systemImage: item.isFavorite ? "star.fill" : "star")
                                .foregroundStyle(item.isFavorite ? .yellow : .primary)
                        }
                    }
                }
                
                // References
                if let refs = item.childItems, !refs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("References")
                            .font(.title2)
                            .bold()
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 16) {
                            ForEach(refs) { ref in
                                ReferenceCardWrapper(item: ref)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .detailCardStyle()
                } else {
                    ContentUnavailableView("No References Found", systemImage: "magnifyingglass", description: Text("The pipeline hasn't extracted any entities yet."))
                }
                
                // Divider removed

                
                // Grouped Capture Content
                if let masterID = item.masterCaptureID {
                    CaptureSiblingsView(masterID: masterID, currentID: item.id)
                        .padding(.bottom, 12)
                        .detailCardStyle()
                    // Divider removed
                }

                // Semantic Tags Section
                let semanticTags = Array(Set(item.themes + item.tags + item.categories)).sorted()
                if !semanticTags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Semantic Tags")
                            .font(.title3)
                            .bold()
                        
                        FlowLayout(spacing: 8) {
                            ForEach(semanticTags, id: \.self) { tag in
                                Button {
                                    if let sessionID = item.sessionID, let context = item.modelContext {
                                        let descriptor = FetchDescriptor<SessionMetadata>(predicate: #Predicate { $0.sessionID == sessionID })
                                        if let session = try? context.fetch(descriptor).first {
                                            session.title = tag.capitalized
                                            session.updatedAt = Date()
                                        } else {
                                            let newSession = SessionMetadata(sessionID: sessionID, title: tag.capitalized)
                                            context.insert(newSession)
                                        }
                                        try? context.save()
                                        
                                        // Provide feedback (optional, e.g. haptic)
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                    }
                                } label: {
                                    Text("#\(tag)")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .glass(cornerRadius: 8)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    .detailCardStyle()
                    
                    // Divider removed
                }
                
                // Full Text / Transcription Section
                if let text = item.transcription ?? (item.entityType == "document" ? item.summary : nil), !text.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Full Text")
                                .font(.title3)
                                .bold()
                            Spacer()
                            Button {
                                #if os(iOS)
                                UIPasteboard.general.string = text
                                #else
                                //NOTE: NSPasteboard logic for macOS
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(text, forType: .string)
                                #endif
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            
                            if item.url != nil || item.rawPayload != nil {
                                Button {
                                   if let urlString = item.url, let url = URL(string: urlString) {
                                       #if os(iOS)
                                       UIApplication.shared.open(url)
                                       #elseif os(macOS)
                                       NSWorkspace.shared.open(url)
                                       #endif
                                   }
                                } label: {
                                    Label("Open", systemImage: "arrow.up.right.square")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        ScrollView {
                            Text(text)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding()
                        }
                        .frame(maxHeight: 300)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .detailCardStyle()
                    
                    // Divider removed
                }
                
                // Media Info Section (Using Abstraction)
                let mediaInfo = item.mediaInfo
                if mediaInfo.mediaType != nil || mediaInfo.filename != nil || mediaInfo.fileSize != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Media Information")
                            .font(.title3)
                            .bold()
                        
                        if let mediaType = mediaInfo.mediaType {
                            HStack {
                                Text("Type:")
                                    .foregroundStyle(.secondary)
                                Text(mediaType.capitalized)
                            }
                            .font(.caption)
                        }
                        
                        if let filename = mediaInfo.filename {
                            HStack {
                                Text("File:")
                                    .foregroundStyle(.secondary)
                                Text(filename)
                            }
                            .font(.caption)
                        }
                        
                        if let fileSize = mediaInfo.fileSize {
                            HStack {
                                Text("Size:")
                                    .foregroundStyle(.secondary)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
                            }
                            .font(.caption)
                        }
                    }
                    .detailCardStyle()
                    
                    // Divider removed
                }
                
                // MARK: - New Enriched Data Sections
                
                // 1. Context Row (Weather + Activity)
                if item.weatherContext != nil || item.activityContext != nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            if let weather = item.weatherContext {
                                WeatherContextView(context: weather)
                            }
                            if let activity = item.activityContext {
                                ActivityContextView(context: activity)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .detailCardStyle()
                    Divider()
                }
                
                // 2. Specific Type Info
                VStack(spacing: 20) {
                    if let url = item.resolvedWebURL {
                        if let web = item.webContext {
                             WebInfoView(context: web, url: url)
                             if let json = web.structuredData {
                                 StructuredDataView(jsonString: json)
                             }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Web Preview")
                                    .font(.title3)
                                    .bold()
                                RichWebView(url: url) { title in
                                    // Update title if valid and different
                                    if !title.isEmpty && title != item.title {
                                        Task { @MainActor in
                                            // Only update if it looks like a real page title (basic heuristic)
                                            if title.count > 2 && !title.contains("http") { 
                                                 item.title = title
                                                 try? item.modelContext?.save()
                                            }
                                        }
                                    }
                                }
                                    .frame(height: 300)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .contextCard()
                        }
                    }
                    
                    if let doc = item.documentContext {
                        DocumentInfoView(context: doc)
                    }
                    
                    if let place = item.placeContext {
                        PlaceContextView(context: place, baseLocation: item.location)
                    }
                    
    // Product Search Preview
                    if item.isProduct, let searchURL = item.productSearchURL {
                         VStack(alignment: .leading, spacing: 8) {
                             Text("Product Search Result")
                                 .font(.headline)
                             
                             RichWebView(url: searchURL)
                                .frame(height: 350)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                         }
                         .contextCard()
                    }
                    
                    // QR Code Support
                    if let qr = item.qrContext {
                        QRCodeView(context: qr)
                    }
                }
                .detailCardStyle()
                
                // 3. Purposes & Intent (Enhanced)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Purposes & Intent")
                            .font(.headline)
                        Spacer()
                        
                        if viewModel.isGeneratingPurposes {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                viewModel.generatePurposes(for: item, siblingContext: siblingContext)
                            } label: {
                                Image(systemName: "sparkles")
                                    .symbolEffect(.bounce, value: viewModel.isGeneratingPurposes)
                            }
                        }
                    }
                    
                    // Active Purposes
                    if !item.purposes.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(item.purposes, id: \.self) { purpose in
                                Text(purpose)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .glass(cornerRadius: 16)
                                    .foregroundStyle(.blue)
                            }
                        }
                    } else {
                        Text("No specific purpose defined yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // AI Suggestions
                    if !viewModel.suggestedPurposes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggestions (Tap to Add)")
                                .font(.caption2)
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(viewModel.suggestedPurposes, id: \.self) { suggestion in
                                    Button {
                                        withAnimation {
                                            if !item.purposes.contains(suggestion) {
                                                item.purposes.append(suggestion)
                                            }
                                            if let idx = viewModel.suggestedPurposes.firstIndex(of: suggestion) {
                                                viewModel.suggestedPurposes.remove(at: idx)
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus")
                                                .font(.caption2)
                                            Text(suggestion)
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(Color.blue.opacity(0.5), lineWidth: 1)
                                        )
                                        .foregroundStyle(.primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Reflection Questions
                     if !item.questions.isEmpty {
                         Divider()
                         Text("Reflection Questions")
                             .font(.subheadline)
                             .foregroundStyle(.secondary)
                         
                         ForEach(item.questions, id: \.self) { question in
                             HStack(alignment: .top) {
                                 Image(systemName: "lightbulb.fill")
                                     .foregroundStyle(.yellow)
                                     .font(.caption)
                                     .padding(.top, 2)
                                 
                                 Text(question)
                                     .font(.caption)
                                     .italic()
                                     .foregroundStyle(.secondary)
                             }
                         }
                     }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .detailCardStyle()
                // Divider removed

                // 4. Concept Weighting
                ConceptWeightingSection(item: item)
                    .padding(.bottom, 20)
                    .detailCardStyle()
            }
            .padding(.horizontal)
            .padding(.top, 20)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Map Button
                if let location = item.location, !location.isEmpty {
                    Button {
                        showingMap = true
                    } label: {
                        Label("View Map", systemImage: "map")
                    }
                    .sheet(isPresented: $showingMap) {
                        GeocodingLocationViewWrapper(locationName: location)
                    }
                }
                
                // Retry button for failed items
                if item.status == .failed {
                    Button {
                        viewModel.retryProcessing(item: item)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                }

                // Open original URL
                if let url = item.resolvedWebURL {
                    Link(destination: url) {
                        Label("Open Original", systemImage: "safari")
                    }
                }
            }
        }
    }
    // Brace removed
    
    // Card Modifier
    private func cardStyle() -> some View {
        self
            .padding()
            .background(Color(normalize(color: .secondarySystemGroupedBackground)))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

extension View {
    func detailCardStyle() -> some View {
        self
            .padding()
            .background(Color(normalize(color: .secondarySystemGroupedBackground)))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct StatusBadge: View {
    let status: ProcessingStatus
    
    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glass(cornerRadius: 8)
            .foregroundStyle(color)
    }
    
    var color: Color {
        switch status {
        case .queued: return .gray
        case .processing: return .blue
        case .ready: return .green
        case .failed: return .red
        case .reviewRequired: return .orange
        case .archived: return .secondary
        }
    }
}

// MARK: - Specialized Reference Views

struct ReferenceCardWrapper: View {
    let item: ProcessedItem
    
    var body: some View {
        if item.webContext?.siteName == "Apple Music" {
             AppleMusicReferenceView(item: item)
        } else {
             switch (item.entityType ?? "").lowercased() {
             case "book":
                 BookReferenceView(item: item)
             case "music", "music_album", "music_track":
                 SpotifyReferenceView(item: item)
             default:
                 ReferenceCardView(item: item)
             }
        }
    }
}

// Ported from main/Generic
// Ported from main/Generic
struct ReferenceCardView: View {
    let item: ProcessedItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entityTypeIcon)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? "Untitled")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    
                    Text((item.entityType ?? "Unknown").replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if let creators = item.summary {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(creators)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .glass(cornerRadius: 12)
    }
    
    private var entityTypeIcon: String {
        switch (item.entityType ?? "").lowercased() {
        case "book": return "📚"
        case "movie", "video": return "🎬"
        default: return "🔗"
        }
    }
}

// Ported from main/BookReferenceView
// Ported from main/BookReferenceView
struct BookReferenceView: View {
    let item: ProcessedItem
    
    var body: some View {
        Button(action: {
            if let url = extractOpenLibraryUrl() {
                #if os(iOS)
                UIApplication.shared.open(url)
                #elseif os(macOS)
                NSWorkspace.shared.open(url)
                #endif
            }
        }) {
            HStack(alignment: .top, spacing: 12) {
                if let coverUrl = item.url, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().frame(width: 60, height: 90)
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill).frame(width: 60, height: 90).cornerRadius(6)
                        case .failure:
                            bookPlaceholder
                        @unknown default:
                            bookPlaceholder
                        }
                    }
                } else {
                    bookPlaceholder
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title ?? "Untitled")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    
                    if let authors = item.summary {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(authors)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
// Note: We lost simplified metadata dictionary access with ReferenceEntity removal
// We might need to handle parsing rawPayload if needed for publisher/ISBN
//                    if let meta = reference.metadataDictionary {
//                        if let publisher = meta["publisher"] as? String, let year = meta["published_date"] as? String {
//                            Text("\(publisher) • \(year)")
//                                .font(.caption2)
//                                .foregroundColor(.secondary)
//                                .lineLimit(1)
//                        }
//                        
//                        if let isbn = meta["isbn"] as? String {
//                            Text("ISBN: \(isbn)")
//                                .font(.caption2)
//                                .foregroundColor(.secondary)
//                                .lineLimit(1)
//                        }
//                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption2)
                        Text("View on OpenLibrary")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                }
                
                Spacer()
            }
            .padding(12)
            .glass(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }
    
    private var bookPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.brown, Color.orange.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .cornerRadius(6)
            .shadow(radius: 2)
            
            VStack(spacing: 4) {
                Image(systemName: "book.closed.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                Text("No Cover")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: 60, height: 90)
    }
    
    private func extractOpenLibraryUrl() -> URL? {
        if let url = item.url, let u = URL(string: url) { return u }
        // Fallback logic could go here
        return nil
    }
}

// Ported from main/SpotifyReferenceView (simplified for no-auth initially)
// Ported from main/SpotifyReferenceView (simplified for no-auth initially)
struct SpotifyReferenceView: View {
    let item: ProcessedItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let coverUrl = item.url, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 80, height: 80)
                    .cornerRadius(4)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 80)
                        .cornerRadius(4)
                        .overlay(Text("🎵"))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title ?? "Untitled")
                        .font(.headline)
                        .lineLimit(2)
                    
                    if let subtitle = item.summary {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text((item.entityType ?? "Music").capitalized)
                        .font(.caption2)
                        .padding(2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
                Spacer()
            }
            
            // External link
            if let externalUrl = item.url, let url = URL(string: externalUrl) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open in Spotify")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding(12)
        .glass(cornerRadius: 12)
    }
}

// Helper for Color compatibility
func normalize(color: UIColor) -> Color {
    #if os(iOS)
    return Color(uiColor: color)
    #else
    return Color(nsColor: .windowBackgroundColor) // Fallback for Mac
    #endif
}

#if os(macOS)
import AppKit
typealias UIColor = NSColor
extension NSColor {
    static var secondarySystemBackground: NSColor { windowBackgroundColor } // Approximation
}
#endif

// Helper to access dictionary metadata
// extension ReferenceEntity {
//    var metadataDictionary: [String: Any]? {
//        guard let data = metadataJSON else { return nil }
//        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
//    }
// }

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - Shared with You Helper

struct AttributionViewWrapper: UIViewRepresentable {
    let highlight: SWHighlight
    
    func makeUIView(context: Context) -> SWAttributionView {
        let view = SWAttributionView()
        view.highlight = highlight
        view.horizontalAlignment = .leading
        return view
    }
    
    func updateUIView(_ uiView: SWAttributionView, context: Context) {
        uiView.highlight = highlight
    }
}

// MARK: - Map Popover

// MARK: - Geocoding Wrapper for LocationMapView
struct GeocodingLocationViewWrapper: View {
    let locationName: String
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            if isLoading {
                VStack {
                    ProgressView()
                    Text("Locating \(locationName)...")
                        .foregroundStyle(.secondary)
                        .padding(.top)
                }
                .navigationTitle("Location")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                     ToolbarItem(placement: .cancellationAction) {
                         Button("Close") { dismiss() }
                     }
                }
            } else {
                LocationMapView(coordinate: coordinate, locationName: locationName) {
                    // Open Place List Action
                    print("Open Places List for \(locationName)")
                    // Here we would trigger the KnowMaps routing or sheet
                }
            }
        }
        .onAppear {
            geocode()
        }
    }
    
    private func geocode() {
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(locationName) { placemarks, error in
            if let location = placemarks?.first?.location {
                self.coordinate = location.coordinate
            }
            self.isLoading = false
        }
    }
}

// MARK: - Local Location Map View
public struct LocationMapView: View {
    @State private var position: MapCameraPosition
    let locationName: String?
    let coordinate: CLLocationCoordinate2D?
    let onOpenPlaces: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    public init(coordinate: CLLocationCoordinate2D?, locationName: String?, onOpenPlaces: @escaping () -> Void) {
        self.coordinate = coordinate
        self.locationName = locationName
        self.onOpenPlaces = onOpenPlaces
        
        if let coordinate = coordinate {
            self._position = State(initialValue: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))))
        } else {
            self._position = State(initialValue: .automatic)
        }
    }
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                if let coordinate = coordinate {
                    Marker(locationName ?? "Location", coordinate: coordinate)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            
            // Floating Card for Place Details
            HStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text(locationName ?? "Unknown Location")
                            .font(.headline)
                        if let coordinate {
                            Text("\(coordinate.latitude), \(coordinate.longitude)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(action: onOpenPlaces) {
                        Image(systemName: "map.fill")
                            .font(.title2)
                            .padding(12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(16)
                .shadow(radius: 5)
            }
            .padding()
        }
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}

import SwiftUI
import DiverKit
import CoreImage.CIFilterBuiltins

// MARK: - Reusable Styles

struct ContextCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
    }
}

extension View {
    func contextCard() -> some View {
        modifier(ContextCardStyle())
    }
}

// MARK: - Weather Context
struct WeatherContextView: View {
    let context: WeatherContext
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: context.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.title2)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(context.condition)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(Int(context.temperatureCelsius))°C")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Material.regular)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Activity Context
struct ActivityContextView: View {
    let context: ActivityContext
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForActivity(context.type))
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(context.type.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(context.confidence.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Material.regular)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func iconForActivity(_ type: String) -> String {
        switch type.lowercased() {
        case "walking": return "figure.walk"
        case "running": return "figure.run"
        case "automotive", "driving": return "car.fill"
        case "cycling": return "bicycle"
        case "stationary": return "figure.stand"
        default: return "figure.mixed.cardio"
        }
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
        .contextCard()
    }
}

// MARK: - Document Info
struct DocumentInfoView: View {
    let context: DocumentContext
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "doc.fill")
                .font(.largeTitle)
                .foregroundStyle(.blue)
                .shadow(radius: 2, y: 1)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(context.fileType.uppercased())
                    .font(.headline)
                
                if let pages = context.pageCount {
                    Text("\(pages) Pages")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let author = context.author {
                    Text("By \(author)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contextCard()
    }
}

// MARK: - Detailed Place Info
struct PlaceContextView: View {
    let context: PlaceContext
    let baseLocation: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(baseLocation ?? "Location")
                        .font(.headline)
                    
                    if let addr = context.address {
                         Text(addr)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
            }
            
            Divider()
            
            HStack(spacing: 12) {
                if let rating = context.rating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(6)
                        .glass(cornerRadius: 6)
                }
                
                if let isOpen = context.isOpen {
                    Text(isOpen ? "Open" : "Closed")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(isOpen ? .green : .red)
                        .padding(6)
                        .glass(cornerRadius: 6)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - QR Code View
struct QRCodeView: View {
    let context: QRCodeContext
    let contextGen = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    
    var body: some View {
        VStack(spacing: 16) {
            if let image = generateQRCode(from: context.payload) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 4)
            } else {
                Image(systemName: "qrcode.viewfinder")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 4) {
                Text("Scanned Content")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                
                Text(context.payload)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            
            if let url = URL(string: context.payload), ["http", "https"].contains(url.scheme?.lowercased()) {
                Divider()
                RichWebView(url: url)
                    .frame(height: 300)
                    .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
    
    func generateQRCode(from string: String) -> UIImage? {
        filter.message = Data(string.utf8)
        
        if let outputImage = filter.outputImage {
            // Scale up for sharpness
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = contextGen.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }
}


// MARK: - Concept Weighting
struct ConceptWeightView: View {
    @Bindable var concept: UserConcept
    var onUpdate: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Text(concept.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(String(format: "%.1f", concept.weight))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Slider(value: $concept.weight, in: 0.1...5.0, step: 0.1, onEditingChanged: { _ in
                    onUpdate()
                })
                .tint(.indigo)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ConceptWeightingSection: View {
    let item: ProcessedItem
    @Query private var userConcepts: [UserConcept]
    @Environment(\.modelContext) private var modelContext
    @State private var newConceptName: String = ""
    @State private var isAdding: Bool = false

    init(item: ProcessedItem) {
        self.item = item
        // Predicate to find relevant concepts is tricky with simple Arrays in SwiftData predicates currently.
        // We will filter in memory for this MVP or use a broad query.
        // Fetching ALL UserConcepts might be heavy if there are thousands, but safe for hundreds.
    }

    var relevantConcepts: [UserConcept] {
        let docTags = Set(item.tags)
        let otherTags = Set(item.categories + item.themes)
        let allRelevant = docTags.union(otherTags)
        
        let filtered = userConcepts.filter { allRelevant.contains($0.name) }
        
        return filtered.sorted { c1, c2 in
            // Priority 1: Document Tags (item.tags)
            let isDocTag1 = docTags.contains(c1.name)
            let isDocTag2 = docTags.contains(c2.name)
            
            if isDocTag1 != isDocTag2 {
                return isDocTag1
            }
            
            // Priority 2: Weight (Descending)
            return c1.weight > c2.weight
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Concept Weights")
                .font(.headline)
            
            if relevantConcepts.isEmpty {
                Text("No linked concepts found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(relevantConcepts) { concept in
                    ConceptWeightView(concept: concept) {
                        save()
                    }
                }
            }
            
            if isAdding {
                HStack {
                    TextField("New Concept", text: $newConceptName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        addConcept()
                    }
                    .disabled(newConceptName.isEmpty)
                }
            } else {
                Button(action: { isAdding.toggle() }) {
                    Label("Add Concept", systemImage: "plus.circle")
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func save() {
        try? modelContext.save()
    }
    
    private func addConcept() {
        let name = newConceptName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        // Check if concept exists
        let existing = userConcepts.first { $0.name == name }
        
        if existing == nil {
            let concept = UserConcept(name: name, definition: "User added concept", weight: 1.0)
            modelContext.insert(concept)
        }
        
        if !item.tags.contains(name) {
             item.tags.append(name) // Link by adding to tags
        }
       
        try? modelContext.save()
        
        newConceptName = ""
        isAdding = false
    }
}

// MARK: - Rich Web View Support
struct RichWebView: UIViewRepresentable {
    let url: URL
    var onTitleChange: ((String) -> Void)? = nil
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        // Load request
        let request = URLRequest(url: url)
        webView.load(request)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // If needed, handle URL changes or updates here
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: RichWebView
        
        init(_ parent: RichWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let title = webView.title {
                parent.onTitleChange?(title)
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView Error: \(error.localizedDescription)")
        }
    }
}

// Helper for Product Logic
extension ProcessedItem {
    var isProduct: Bool {
        let type = entityType?.lowercased() ?? ""
        return type == "product" || categories.contains("shopping") || purposes.contains("shopping")
    }
    
    var productSearchURL: URL? {
        guard let title = title, !title.isEmpty else { return nil }
        let query = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://duckduckgo.com/?q=\(query)&ia=web")
    }
}

// MARK: - Capture Siblings View
struct CaptureSiblingsView: View {
    let masterID: String
    let currentID: String
    
    // We must filter in the initializer or body if the dataset is small, or use a custom fetch.
    // Given the constraints and likely small library size for this MVP, we will query all and filter.
    @Query private var allItems: [ProcessedItem]
    
    var siblings: [ProcessedItem] {
        allItems.filter { $0.masterCaptureID == masterID && $0.id != currentID }
    }
    
    var body: some View {
        if !siblings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Related Captures")
                        .font(.headline)
                    Spacer()
                    Text("\(siblings.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(siblings) { sibling in
                            NavigationLink(value: sibling) {
                                SiblingThumbnailView(item: sibling)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SiblingThumbnailView: View {
    let item: ProcessedItem
    
    var body: some View {
        if let data = item.rawPayload, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 80, height: 80)
                .cornerRadius(8)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                )
        }
    }
}

// MARK: - Safe URL Resolution
extension ProcessedItem {
    /// Returns a navigable HTTP/HTTPS URL, resolving `secretatomics://` schemes to their wrapped content if possible.
    var resolvedWebURL: URL? {
        // 1. Try wrappedLink (explicit web link)
        if let wrapped = wrappedLink, let url = URL(string: wrapped), ["http", "https"].contains(url.scheme?.lowercased()) {
            return url
        }
        

        
        // 3. Try main URL if it's http/https
        if let mainUrlStr = url, let url = URL(string: mainUrlStr), ["http", "https"].contains(url.scheme?.lowercased()) {
            return url
        }
        
        return nil
    }
    
    var displayURLString: String {
        return resolvedWebURL?.absoluteString ?? url ?? "No URL"
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
            .padding(.bottom, 12)
            Divider()
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

