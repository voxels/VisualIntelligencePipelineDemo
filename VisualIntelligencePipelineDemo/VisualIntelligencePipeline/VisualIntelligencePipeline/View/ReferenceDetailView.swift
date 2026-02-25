import SwiftUI
import SwiftData
import DiverKit
import DiverShared
import SharedWithYou
import MapKit
import LinkPresentation
import WebKit
import AVKit
import ImageIO
import Photos

struct ReferenceDetailView: View {
    let item: ProcessedItem
    
    var body: some View {
        ReferenceDetailContent(item: item)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            #if os(iOS)
            .background(Color(uiColor: .systemGroupedBackground))
            #endif
    }
}

struct ReferenceDetailContent: View {
    let item: ProcessedItem
    @StateObject private var viewModel = ReferenceDetailViewModel()
    @EnvironmentObject private var sharedWithYouManager: SharedWithYouManager
    @State private var showingEditLocation = false
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    
    @Environment(\.modelContext) private var modelContext
    
    private func buildSiblingContext() -> String {
        guard let sessionID = item.sessionID else { return "" }
        var descriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        descriptor.fetchLimit = 20
        let siblings = (try? modelContext.fetch(descriptor)) ?? []
        return siblings.prefix(20).map { "- \($0.title ?? "Item"): \($0.summary ?? "")" }.joined(separator: "\n")
    }
    
    var body: some View {
        if item.modelContext == nil {
            ContentUnavailableView("Item Deleted", systemImage: "trash", description: Text("This item has been removed."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: - Generic Header
                    buildHeader()
                    
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
                    }
                    
                    // Capture Siblings
                    if let masterID = item.masterCaptureID {
                        CaptureSiblingsView(masterID: masterID, currentID: item.id)
                            .padding(.bottom, 12)
                            .detailCardStyle()
                    }
                    
                    // MARK: - Specialized Profile Switch
                    buildSpecializedProfile()
                    
                    // MARK: - Generic Footer
                    buildFooter()
                }
                .padding(.horizontal)
                .padding(.top, 20)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    // Edit Location
                    Button {
                        showingEditLocation = true
                    } label: {
                        Label("Edit Location", systemImage: "pencil.and.outline")
                    }
                    .sheet(isPresented: $showingEditLocation) {
                        EditLocationView(item: item)
                    }
                    
                    // Retry button for failed items
                    if item.status == .failed {
                        Button {
                            viewModel.retryProcessing(item: item)
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                    }
                    
                    // Process Now button
                    Button {
                        viewModel.refreshLinkMetadata(item: item)
                    } label: {
                        Label("Process Now", systemImage: "bolt.fill")
                    }

                    // Open original URL
                    if let url = item.resolvedWebURL {
                        Link(destination: url) {
                            Label("Open Original", systemImage: "safari")
                        }
                    }
                    
                    // Favorite button
                    Button {
                        item.isFavorite.toggle()
                        Task { @MainActor in try? item.modelContext?.save() }
                    } label: {
                        Label(item.isFavorite ? "Unfavorite" : "Favorite", systemImage: item.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(item.isFavorite ? .yellow : .primary)
                    }
                }
            }
        }
    }
    
    // MARK: - Header Builder
    @ViewBuilder
    private func buildHeader() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Media Content (Video or Image)
            if item.mediaType == "video" {
                if let assetID = item.photosAssetIdentifier {
                    PhotosVideoPlayerView(assetIdentifier: assetID)
                        .frame(height: 300)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                        .padding(.bottom, 12)
                } else if let data = item.rawPayload {
                    DataVideoPlayer(data: data)
                        .frame(height: 300)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                        .padding(.bottom, 12)
                }
            } else {
                AsyncItemImageView(item: item)
            }
            
            // Text Editor Content for Note type
            let showTextEditor = item.source == "ManualNote" || (item.entityType != "document" && item.entityType != "web_link" && item.transcription.map { !$0.isEmpty } == true)
            if showTextEditor {
                TextEditorView(item: item).padding(.bottom, 12)
            }
            
            if isEditingTitle {
                TextField("Title", text: $editedTitle, onCommit: {
                    if !editedTitle.isEmpty {
                        item.title = editedTitle
                        Task { @MainActor in try? item.modelContext?.save() }
                    }
                    isEditingTitle = false
                })
                .font(.largeTitle)
                .fontWeight(.bold)
                .textFieldStyle(.roundedBorder)
                .onAppear {
                    editedTitle = item.title ?? "Untitled"
                }
            } else {
                Text(item.title ?? "Untitled")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)
                    .onLongPressGesture {
                        editedTitle = item.title ?? "Untitled"
                        isEditingTitle = true
                    }
            }
            
            if let url = item.resolvedWebURL {
                Link(url.absoluteString, destination: url)
                    .foregroundStyle(.blue)
                    .font(.body)
            }
            
            if let summary = item.summary, !summary.isEmpty, item.entityType != "product" {
                let parsed = parseSummaryModelBadge(from: summary)
                Text(parsed.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.top, 4)
                    
                if let badge = parsed.badge {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text(badge)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 2)
                }
            }
            
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
        
        // Semantic Tags Section
        let semanticTags = Array(Set(item.visualTags + item.tags + item.categories + item.purposes)).sorted()
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
                                Task { @MainActor in try? context.save() }
                                #if os(iOS)
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                #endif
                            }
                        } label: {
                            Text("#\(tag)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .glass(cornerRadius: 8)
                                .foregroundStyle(.blue)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.removeSemanticTag(tag, from: item)
                            } label: {
                                Label("Delete Tag", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .detailCardStyle()
        }
    }
    
    // MARK: - Additive Context Sections
    // The original monolith showed ALL applicable sections via `if let` context checks.
    // A product with a place context shows BOTH commerce AND place sections.
    // This is NOT an exclusive switch — every section that has data is rendered.
    @ViewBuilder
    private func buildSpecializedProfile() -> some View {
        // 1. Full Text / Transcription (generic — shown for ALL types with text)
        if let text = item.transcription, !text.isEmpty,
           item.entityType?.lowercased() != "document" { // Document profile has its own text section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Full Text")
                        .font(.title3)
                        .bold()
                    Spacer()
                    Button {
                        #if os(iOS)
                        UIPasteboard.general.string = text
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        #endif
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    
                    if let urlString = item.url,
                       let url = URL(string: urlString),
                       !urlString.hasPrefix("secretatomics://") {
                        Button {
                            #if os(iOS)
                            UIApplication.shared.open(url)
                            #endif
                        } label: {
                            Label("Open", systemImage: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
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
        }
        
        // 2. Commerce Intelligence (shown for any item with product data)
        if item.productMetadata != nil || item.commerceContext != nil {
            ProductProfileView(item: item)
        }
        
        // 3. Image profile (aesthetics + EXIF + ML-Sharp) — shown for any item with image data
        if item.rawPayload != nil || item.photosAssetIdentifier != nil {
            ImageProfileView(item: item)
        }
        
        // 4. Web context (shown for any item with a web URL)
        if item.resolvedWebURL != nil || item.webContext != nil {
            WebLinkProfileView(item: item)
        }
        
        // 5. Document context (shown for any item with document data)
        if item.documentContext != nil {
            DocumentProfileView(item: item)
        }
        
        // 6. Place context (shown for any item with place data)
        if item.placeContext != nil {
            PlaceProfileView(item: item)
        }
        
        // 7. QR Code context
        if item.qrContext != nil {
            QRCodeProfileView(item: item)
        }
        
        // 8. Person context
        if !item.contactIdentifiers.isEmpty {
            PersonProfileView(item: item)
        }
        
        // 9. Product Search Preview (for products without direct commerce data)
        if item.isProduct, item.commerceContext == nil, let searchURL = item.productSearchURL {
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
            .detailCardStyle()
        }
        
    }
    
    // MARK: - Footer Builder
    @ViewBuilder
    private func buildFooter() -> some View {
        // Media Info (kept in footer/generic)
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
        }

        // Environment Context (if not already handled strictly by entityType)
        if item.entityType?.lowercased() != "environment" && (item.weatherContext != nil || item.activityContext != nil) {
            EnvironmentProfileView(item: item)
        }
        
        // Purposes & Intent
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
                        viewModel.generatePurposes(for: item, siblingContext: buildSiblingContext())
                    } label: {
                        Image(systemName: "sparkles")
                            .symbolEffect(.bounce, value: viewModel.isGeneratingPurposes)
                    }
                }
            }
            
            if !item.purposes.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(item.purposes.sorted(), id: \.self) { purpose in
                        Text(purpose)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glass(cornerRadius: 16)
                            .foregroundStyle(.blue)
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.removePurpose(purpose, from: item)
                                } label: {
                                    Label("Delete Purpose", systemImage: "trash")
                                }
                            }
                    }
                }
            } else {
                Text("No specific purpose defined yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if !viewModel.suggestedPurposes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggestions (Tap to Add)")
                        .font(.caption2)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(viewModel.suggestedPurposes, id: \.self) { suggestion in
                            Button {
                                viewModel.addPurpose(suggestion, to: item)
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
            
            if let vlm = item.fastVLMAnalysis, !vlm.statements.isEmpty {
                Divider()
                Text("Insights")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                ForEach(vlm.statements, id: \.self) { statement in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "eye.fill")
                            .foregroundStyle(.purple)
                            .font(.caption)
                            .padding(.top, 2)
                        
                        Text(statement)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }
            }
            
             if !item.questions.isEmpty {
                 Divider()
                 Text("Reflection Questions")
                 .font(.subheadline)
                 .foregroundStyle(.secondary)
                 
                 ForEach(Array(Set(item.questions)).sorted(), id: \.self) { question in
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

        ConceptWeightingSection(item: item)
            .padding(.bottom, 20)
            .detailCardStyle()
    }
    
    // MARK: - Utilities
    private func parseSummaryModelBadge(from summary: String) -> (text: String, badge: String?) {
        let pattern = #"^\s*(.*?)\s*\[Model:\s*(.*?)\]\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return (summary, nil)
        }
        
        let nsString = summary as NSString
        let results = regex.matches(in: summary, range: NSRange(location: 0, length: nsString.length))
        
        if let match = results.first, match.numberOfRanges == 3 {
             let cleanedText = nsString.substring(with: match.range(at: 1))
             let modelBadge = nsString.substring(with: match.range(at: 2))
             return (cleanedText, modelBadge)
        }
        
        return (summary, nil)
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
        case .captured: return .teal
        case .enriching: return .blue
        case .ready: return .green
        case .failed: return .red
        case .reviewRequired: return .orange
        case .archived: return .secondary
        }
    }
}


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
        Task {
            do {
                if let request = MKGeocodingRequest(addressString: locationName) {
                    let mapItems = try await request.mapItems
                    if let coordinate = mapItems.first?.location.coordinate {
                        self.coordinate = coordinate
                    }
                }
            } catch {
                print("⚠️ Geocoding failed: \(error)")
            }
            self.isLoading = false
        }
    }
}


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


struct CaptureSiblingsView: View {
    let masterID: String
    let currentID: String
    
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSibling: ProcessedItem?
    
    var siblings: [ProcessedItem] {
        let mid = masterID
        let cid = currentID
        var descriptor = FetchDescriptor<ProcessedItem>(
            predicate: #Predicate { $0.masterCaptureID == mid && $0.id != cid }
        )
        descriptor.fetchLimit = 20
        return (try? modelContext.fetch(descriptor)) ?? []
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
                            Button {
                                selectedSibling = sibling
                            } label: {
                                SiblingThumbnailView(item: sibling)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .sheet(item: $selectedSibling) { sibling in
                NavigationStack {
                    ReferenceDetailView(item: sibling)
                }
            }
        }
    }
}


struct SiblingThumbnailView: View {
    let item: ProcessedItem
    
    var body: some View {
        ThumbnailView(item: item, size: 80, cornerRadius: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }
}


struct PhotosVideoPlayerView: View {
    let assetIdentifier: String
    
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var loadError: String?
    
    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else if isLoading {
                ZStack {
                    Color.black.opacity(0.1)
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading video...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error = loadError {
                ZStack {
                    Color.gray.opacity(0.1)
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            } else {
                ZStack {
                    Color.gray.opacity(0.1)
                    Image(systemName: "video.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            loadVideo()
        }
    }
    
    private func loadVideo() {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        
        guard let asset = fetchResult.firstObject else {
            isLoading = false
            loadError = "Video not found in Photos library"
            return
        }
        
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
            DispatchQueue.main.async {
                isLoading = false
                
                if let urlAsset = avAsset as? AVURLAsset {
                    player = AVPlayer(url: urlAsset.url)
                } else if let avAsset = avAsset {
                    let playerItem = AVPlayerItem(asset: avAsset)
                    player = AVPlayer(playerItem: playerItem)
                } else {
                    loadError = "Could not load video"
                }
            }
        }
    }
}


struct TextEditorView: View {
    let item: ProcessedItem
    @State private var editedText: String = ""
    @State private var hasUnsavedChanges = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Text Content")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if hasUnsavedChanges {
                    Button {
                        saveChanges()
                    } label: {
                        Label("Save", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
            
            TextEditor(text: $editedText)
                .frame(minHeight: 200)
                .padding(8)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: editedText) { oldValue, newValue in
                    hasUnsavedChanges = newValue != (item.transcription ?? "")
                }
        }
        .onAppear {
            editedText = item.transcription ?? ""
        }
    }
    
    private func saveChanges() {
        item.transcription = editedText
        item.summary = editedText.isEmpty ? nil : String(editedText.prefix(200))
        Task { @MainActor in try? item.modelContext?.save() }
        hasUnsavedChanges = false
        
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}


struct AsyncItemImageView: View {
    let item: ProcessedItem
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400) // Add constraint to prevent "too large" issues
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    .padding(.bottom, 12)
                    .glass(cornerRadius: 12)
                    .transition(.opacity)
            } else if isLoading {
                ZStack {
                    Color.gray.opacity(0.1)
                    ProgressView()
                }
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .cornerRadius(12)
                .padding(.bottom, 12)
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        // Extract data on MainActor to avoid SwiftData concurrency issues
        let rectData = item.documentContext?.rectifiedPayload
        let rawData = item.rawPayload
        let snapshotPath = item.webContext?.snapshotURL
        let isDocument = item.entityType == "document"
        
        // Priority 1: For document-type items, show the rectified/original document image.
        // For non-documents, skip rectifiedPayload — the user wants their original photo,
        // not a pipeline-detected document crop.
        if isDocument {
            // Document items: rawPayload IS the rectified image from CIPerspectiveCorrection
            if let data = rawData {
                if let decoded = await decodeImage(from: data) {
                    withAnimation {
                        self.image = decoded
                        self.isLoading = false
                    }
                    return
                }
            }
            // Fallback: rectifiedPayload from documentContext (reprocessed master captures)
            if let rectData {
                if let decoded = await decodeImage(from: rectData) {
                    withAnimation {
                        self.image = decoded
                        self.isLoading = false
                    }
                    return
                }
            }
        }
        
        // Priority 2: Raw Payload (original photo for non-document items)
        if let data = rawData {
            if let decoded = await decodeImage(from: data) {
                withAnimation {
                    self.image = decoded
                    self.isLoading = false
                }
                return
            }
        }
        
        // Priority 3: Photos Asset (Imported)
        if let assetID = item.photosAssetIdentifier {
            if let data = await PhotosAssetLoader.shared.loadImageData(identifier: assetID),
               let decoded = await decodeImage(from: data) {
                withAnimation {
                    self.image = decoded
                    self.isLoading = false
                }
                return
            }
        }

        // Priority 4: Payload Reference (Disk persistence)
        if let payloadRef = item.payloadRef {
            let fileURL = URL(fileURLWithPath: payloadRef)
            if let data = try? Data(contentsOf: fileURL),
               let decoded = await decodeImage(from: data) {
                withAnimation {
                    self.image = decoded
                    self.isLoading = false
                }
                return
            }
        }
        
        // Priority 5: Web Snapshot or URL as File Path
        if let path = snapshotPath {
             let url = URL(fileURLWithPath: path)
             if let data = try? Data(contentsOf: url),
                let decoded = await decodeImage(from: data) {
                 withAnimation {
                     self.image = decoded
                     self.isLoading = false
                 }
                 return
             }
        }
        
        // Check generic URL if it's a file path
        if let urlString = item.url, 
           urlString.hasPrefix("file://") || urlString.hasPrefix("/"),
           let url = URL(string: urlString) {
             let fileURL = url.scheme == nil ? URL(fileURLWithPath: urlString) : url
             if let data = try? Data(contentsOf: fileURL),
                let decoded = await decodeImage(from: data) {
                 withAnimation {
                     self.image = decoded
                     self.isLoading = false
                 }
                 return
             }
        }
        
        // Check generic URL if it's a file path
        if let urlString = item.url, 
           (urlString.hasPrefix("file://") || urlString.hasPrefix("/")),
           let url = URL(string: urlString) {
             let fileURL = url.scheme == nil ? URL(fileURLWithPath: urlString) : url
             if let data = try? Data(contentsOf: fileURL),
                let decoded = await decodeImage(from: data) {
                 withAnimation {
                     self.image = decoded
                     self.isLoading = false
                 }
                 return
             }
        }
        
        // No image found
        withAnimation {
            self.isLoading = false
        }
    }
    
    private func decodeImage(from data: Data) async -> UIImage? {
        return await Task.detached(priority: .userInitiated) {
            guard let initialImage = UIImage(data: data) else { return nil }
            // Bake orientation into pixels — handles legacy data saved without normalization
            return initialImage.fixedOrientation()
        }.value
    }
}


struct DataVideoPlayer: View {
    let data: Data
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
            } else {
                ZStack {
                    Color.black
                    ProgressView().tint(.white)
                }
            }
        }
        .onAppear {
            if player == nil {
                // Write data to temporary file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
                do {
                    try data.write(to: tempURL)
                    self.player = AVPlayer(url: tempURL)
                } catch {
                    print("❌ DataVideoPlayer: Failed to write temp video: \(error)")
                }
            }
        }
    }
}



func normalize(color: UIColor) -> UIColor {
    #if os(iOS)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return UIColor(red: r, green: g, blue: b, alpha: a)
    #else
    return color
    #endif
}
