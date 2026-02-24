//
//  MacContentView.swift
//  VisualIntelligenceMac
//
//  1:1 with the iPad app plus Mac-specific extras:
//  – Full 3-column sidebar (collections · sessions · favorites · daily summary · queue)
//  – Full detail pane via DiverUI profile views (Product, Place, Web, Document, …)
//  – Drop + file-picker ingestion wired to MetadataPipelineService
//  – Continuity Camera / file-import toolbar button
//  – Settings sheet (MacSettingsView) and ReprocessingWizard sheet (MacReprocessingView)
//  – Keyboard shortcuts, semantic toolbar search, drag-and-drop
//

import SwiftUI
import SwiftData
import DiverKit
import DiverShared
import DiverUI
import MapKit
import AppKit

// MARK: - Root View

struct MacContentView: View {

    // MARK: Environment
    @Environment(\.modelContext) private var modelContext
    @Environment(EdgeNodeInstallService.self) private var edgeNodeInstaller

    // MARK: Queries
    @Query(sort: \SessionMetadata.updatedAt, order: .reverse)
    private var allSessions: [SessionMetadata]

    @Query(sort: \SessionCollection.updatedAt, order: .reverse)
    private var collections: [SessionCollection]

    @Query(filter: #Predicate<ProcessedItem> {
        $0.statusRaw != "queued" && $0.statusRaw != "processing"
    }, sort: \ProcessedItem.updatedAt, order: .reverse)
    private var allItems: [ProcessedItem]

    @Query(sort: \UserConcept.weight, order: .reverse)
    private var allConcepts: [UserConcept]

    // MARK: View Models
    @State private var sidebarVM = SidebarViewModel()
    @State private var chatVM: AgenticChatViewModel = AgenticChatViewModel(
        searchService: Services.shared.agenticSearchService ?? NullAgenticSearchService()
    )
    @State private var ingestionService = MacIngestionService()

    // MARK: Selection
    @State private var selectedSession: SessionMetadata?
    @State private var selectedItem: ProcessedItem?

    // MARK: Panel visibility
    @State private var showChat = false
    @State private var showSettings = false
    @State private var showReprocessing = false
    @State private var isDroppingFile = false

    // MARK: Queue Progress
    @State private var queueIsProcessing = false
    @State private var queueTotalCount = 0
    @State private var queueCompletedCount = 0
    @State private var queueCurrentItemTitle: String?
    @State private var queueStatusMessage: String?
    @State private var queueProgress: Double = 0
    @State private var edgeNodeAvailable = false

    // MARK: Alert / Sheet State (passed to sidebar)
    @State private var sessionForLocationEdit: SessionMetadata?
    @State private var sessionToRename: SessionMetadata?
    @State private var newSessionTitle = ""
    @State private var collectionToRename: SessionCollection?
    @State private var newCollectionName = ""
    @State private var showingCreateCollection = false
    @State private var sessionForNewCollection: SessionMetadata?

    // MARK: Body
    var body: some View {
        NavigationSplitView {
            MacSidebarView(
                sessions: filteredSessions,
                collections: collections,
                readyItems: allItems.filter { $0.status == .ready },
                allConcepts: allConcepts,
                selectedSession: $selectedSession,
                viewModel: sidebarVM,
                edgeNodeAvailable: edgeNodeAvailable,
                queueIsProcessing: queueIsProcessing,
                queueTotalCount: queueTotalCount,
                queueCompletedCount: queueCompletedCount,
                queueCurrentItemTitle: queueCurrentItemTitle,
                queueStatusMessage: queueStatusMessage,
                queueProgress: queueProgress,
                showChat: $showChat,
                onShowSettings: { showSettings = true }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } content: {
            if showChat {
                MacChatView(viewModel: chatVM, onClose: { showChat = false })
            } else {
                MacItemListView(
                    session: selectedSession,
                    allItems: selectedSession == nil ? filteredItems : nil,
                    searchText: sidebarVM.searchText,
                    selectedItem: $selectedItem,
                    viewModel: sidebarVM
                )
            }
        } detail: {
            if let item = selectedItem {
                MacDetailView(item: item, viewModel: ReferenceDetailViewModel())
            } else {
                MacEmptyDetailView(showChat: $showChat) {
                    ingestionService.openFilePicker { handleDroppedFiles($0) }
                }
            }
        }
        // ── Toolbar ──────────────────────────────────────────────────────────
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                edgeNodeStatusButton
            }
            ToolbarItemGroup(placement: .primaryAction) {
                cameraImportButton
                importButton
                chatToggleButton
                maintenanceMenu
            }
        }
        // ── Search ───────────────────────────────────────────────────────────
        .searchable(text: $sidebarVM.searchText, placement: .toolbar, prompt: "Search library…")
        .onSubmit(of: .search) {
            Task.detached(priority: .userInitiated) {
                await sidebarVM.performSemanticSearch(
                    query: sidebarVM.searchText, keywordResultCount: 50)
            }
        }
        // ── Drop ────────────────────────────────────────────────────────────
        .overlay(alignment: .center) {
            if isDroppingFile { dropOverlay }
        }
        .onDrop(of: [.image, .url, .fileURL, .pdf],
                delegate: MacDropCoordinator(
                    onImages: { handleDroppedImages($0) },
                    onURLs: { handleDroppedURLs($0) },
                    onFiles: { handleDroppedFiles($0) }
                ))
        // ── Sheets ───────────────────────────────────────────────────────────
        .sheet(isPresented: $showSettings) {
            MacSettingsView(viewModel: sidebarVM)
                .frame(minWidth: 520, minHeight: 520)
        }
        .sheet(isPresented: $showReprocessing) {
            MacReprocessingView()
                .frame(minWidth: 480, minHeight: 380)
        }
        // Location editing for sessions not yet ported to Mac — handled via context menu rename flow
        .alert("Rename Session", isPresented: Binding(
            get: { sessionToRename != nil },
            set: { if !$0 { sessionToRename = nil } }
        )) {
            TextField("Session Title", text: $newSessionTitle)
            Button("Cancel", role: .cancel) { sessionToRename = nil; newSessionTitle = "" }
            Button("Save") {
                if let s = sessionToRename, !newSessionTitle.isEmpty {
                    sidebarVM.renameSession(s, title: newSessionTitle, context: modelContext)
                }
                sessionToRename = nil; newSessionTitle = ""
            }
        } message: { Text("Enter a new title for this session") }
        // ── Queue Progress ───────────────────────────────────────────────────
        .task {
            guard let pipeline = Services.shared.metadataPipelineService else { return }
            for await event in pipeline.progressStream {
                switch event {
                case .started(let total):
                    queueIsProcessing = true; queueTotalCount = total; queueCompletedCount = 0
                case .processingItem(let done, let total, let title, let status):
                    queueIsProcessing = true; queueTotalCount = total; queueCompletedCount = done
                    queueCurrentItemTitle = title; queueStatusMessage = status; queueProgress = event.progress
                case .itemCompleted(let done, let total):
                    queueCompletedCount = done; queueTotalCount = total; queueProgress = event.progress
                case .completed:
                    queueProgress = 1.0
                    try? await Task.sleep(for: .seconds(1.5))
                    queueIsProcessing = false; queueTotalCount = 0; queueCompletedCount = 0
                    queueStatusMessage = nil; queueCurrentItemTitle = nil
                case .cancelled:
                    queueIsProcessing = false; queueTotalCount = 0; queueProgress = 0
                }
            }
        }
        // ── Edge node poll ────────────────────────────────────────────────────
        .task {
            while !Task.isCancelled {
                if let d = Services.shared.discoveryService {
                    edgeNodeAvailable = await d.isEdgeNodeConnected
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: Computed

    private var filteredSessions: [SessionMetadata] {
        sidebarVM.filterSessions(allSessions)
    }
    private var filteredItems: [ProcessedItem] {
        sidebarVM.sortAndFilter(items: allItems)
    }

    // MARK: Toolbar Buttons

    private var edgeNodeStatusButton: some View {
        Button {} label: {
            HStack(spacing: 4) {
                Image(systemName: edgeNodeInstaller.isRunning
                      ? "brain.filled.head.profile" : "brain.head.profile")
                    .symbolRenderingMode(.multicolor)
                if edgeNodeInstaller.isRunning {
                    Circle().fill(.green).frame(width: 6, height: 6)
                }
            }
        }
        .help(edgeNodeInstaller.isRunning
              ? "Edge Node: \(edgeNodeInstaller.installStatus.rawValue)"
              : "Edge Node not active")
    }

    private var cameraImportButton: some View {
        Menu {
            if let cam = ingestionService.preferredCamera {
                Button {
                    // Trigger Continuity Camera capture via NSOpenPanel source
                    ingestionService.openFilePicker { handleDroppedFiles($0) }
                } label: {
                    Label(cam.name, systemImage: cam.isContinuityCamera ? "iphone" : "camera")
                }
            }
            if let warning = ingestionService.cameraWarning {
                Section(warning) {}
            }
        } label: {
            Label("Camera", systemImage: "camera")
        }
        .help("Capture with " + (ingestionService.preferredCamera?.name ?? "camera"))
        .keyboardShortcut("k", modifiers: [.command])
    }

    private var importButton: some View {
        Button {
            ingestionService.openFilePicker { handleDroppedFiles($0) }
        } label: {
            Label("Import", systemImage: "square.and.arrow.down")
        }
        .help("Import images, documents, or links")
        .keyboardShortcut("i", modifiers: [.command, .shift])
    }

    private var chatToggleButton: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { showChat.toggle() }
        } label: {
            Label("Chat", systemImage: showChat
                  ? "bubble.left.and.bubble.right.fill"
                  : "bubble.left.and.bubble.right")
        }
        .help("Chat with your library using CLaRa")
        .keyboardShortcut("l", modifiers: [.command])
    }

    private var maintenanceMenu: some View {
        Menu {
            Button("Settings…") { showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("Rebuild Library") {
                sidebarVM.rebuildLibrary(context: modelContext)
            }.disabled(sidebarVM.isMaintaining)

            Button("Reprocess Pipeline…") { showReprocessing = true }

            Divider()
            Button("Find & Fix Orphaned Items") {
                Task.detached(priority: .utility) {
                    try? await Services.shared.localPipelineService?.assignOrphanedItems()
                }
            }
            Button("Recover Stuck Items") {
                Task.detached(priority: .utility) {
                    try? await Services.shared.localPipelineService?.recoverStuckItems()
                }
            }
            Button("Consolidate Sessions") {
                Task.detached(priority: .utility) {
                    try? await Services.shared.localPipelineService?.consolidateSessions()
                }
            }
        } label: {
            Label(sidebarVM.isMaintaining ? sidebarVM.maintenanceStatus : "Library",
                  systemImage: sidebarVM.isMaintaining ? "arrow.triangle.2.circlepath" : "books.vertical")
        }
    }

    // MARK: Drop overlay
    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(.blue, style: StrokeStyle(lineWidth: 2, dash: [8]))
            .background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 40)).foregroundStyle(.blue)
                    Text("Drop to add to library").font(.headline).foregroundStyle(.secondary)
                }
            }
            .padding(40)
            .allowsHitTesting(false)
    }

    // MARK: Ingestion Handlers

    private func handleDroppedImages(_ images: [NSImage]) {
        guard let pipeline = Services.shared.metadataPipelineService else { return }
        let container = modelContext.container
        Task.detached(priority: .utility) {
            let ctx = ModelContext(container)
            ctx.autosaveEnabled = false
            for image in images {
                guard let data = image.tiffRepresentation else { continue }
                let input = LocalInput(url: nil, source: "mac-drop", inputType: "image", rawPayload: data)
                ctx.insert(input)
            }
            try? ctx.save()
            try? await pipeline.processPendingQueue()
        }
    }

    private func handleDroppedURLs(_ urls: [URL]) {
        guard let pipeline = Services.shared.metadataPipelineService else { return }
        let container = modelContext.container
        Task.detached(priority: .utility) {
            let ctx = ModelContext(container)
            ctx.autosaveEnabled = false
            for url in urls {
                let input = LocalInput(url: url.absoluteString, source: "mac-drop", inputType: "web")
                ctx.insert(input)
            }
            try? ctx.save()
            try? await pipeline.processPendingQueue()
        }
    }

    private func handleDroppedFiles(_ urls: [URL]) {
        guard let pipeline = Services.shared.metadataPipelineService else { return }
        let container = modelContext.container
        Task.detached(priority: .utility) {
            let ctx = ModelContext(container)
            ctx.autosaveEnabled = false
            for url in urls {
                let data = try? Data(contentsOf: url)
                let type = ["pdf"].contains(url.pathExtension.lowercased()) ? "document" : "image"
                let input = LocalInput(
                    url: url.absoluteString, source: "mac-import",
                    inputType: type, rawPayload: data
                )
                ctx.insert(input)
            }
            try? ctx.save()
            try? await pipeline.processPendingQueue()
        }
    }
}

// MARK: - Daily Summary Banner (Mac-native, replaces iOS DailySummaryCard)

private struct MacDailySummaryBanner: View {
    let service: DailyContextService

    var body: some View {
        Section {
            if service.isGenerating {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Generating daily brief…").font(.caption).foregroundStyle(.secondary)
                }
            } else if !service.dailySummary.isEmpty {
                Text(service.dailySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.vertical, 2)
            }
        } header: {
            HStack {
                Image(systemName: "sun.horizon.fill").foregroundStyle(.orange)
                Text("Daily Brief")
                Spacer()
                Button { service.requestUpdate() } label: {
                    Image(systemName: "arrow.clockwise").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Sidebar


struct MacSidebarView: View {
    let sessions: [SessionMetadata]
    let collections: [SessionCollection]
    let readyItems: [ProcessedItem]
    let allConcepts: [UserConcept]
    @Binding var selectedSession: SessionMetadata?
    @Bindable var viewModel: SidebarViewModel
    let edgeNodeAvailable: Bool
    let queueIsProcessing: Bool
    let queueTotalCount: Int
    let queueCompletedCount: Int
    let queueCurrentItemTitle: String?
    let queueStatusMessage: String?
    let queueProgress: Double
    @Binding var showChat: Bool
    let onShowSettings: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var sessionForLocationEdit: SessionMetadata?
    @State private var sessionToRename: SessionMetadata?
    @State private var newSessionTitle = ""
    @State private var collectionToRename: SessionCollection?
    @State private var newCollectionName = ""
    @State private var showingCreateCollection = false
    @State private var sessionForNewCollection: SessionMetadata?

    private var collectionSessionIDs: Set<String> {
        Set(collections.flatMap { $0.sessionIDs })
    }
    private var standaloneSessions: [SessionMetadata] {
        sessions.filter { !collectionSessionIDs.contains($0.sessionID) }
    }

    var body: some View {
        List(selection: $selectedSession) {
            // Agentic Chat
            if edgeNodeAvailable || ContextQuestionService.isAvailable {
                Section {
                    Button {
                        showChat = true
                    } label: {
                        Label("Chat with Librarian", systemImage: "sparkles")
                            .foregroundStyle(.blue)
                    }
                }
            }

            // Daily Summary
            if ContextQuestionService.isAvailable, let svc = Services.shared.dailyContextService {
                MacDailySummaryBanner(service: svc)
            }

            // Favorites
            let favorites = readyItems.filter { $0.isFavorite }
            if !favorites.isEmpty {
                Section("Favorites") {
                    ForEach(favorites.prefix(5)) { item in
                        MacFavoriteRow(item: item, selectedSession: $selectedSession, sessions: sessions)
                    }
                }
            }

            // Library (Collections + Standalone Sessions)
            Section("Library") {
                ForEach(collections) { collection in
                    MacCollectionRow(
                        collection: collection,
                        sessions: sessions.filter { collection.sessionIDs.contains($0.sessionID) },
                        selectedSession: $selectedSession,
                        viewModel: viewModel,
                        onLocationEdit: { sessionForLocationEdit = $0 },
                        onRename: { s in sessionToRename = s; newSessionTitle = s.displayTitle }
                    )
                }
                ForEach(standaloneSessions) { session in
                    MacSessionRowView(
                        session: session,
                        selectedSession: $selectedSession,
                        viewModel: viewModel,
                        onLocationEdit: { sessionForLocationEdit = $0 },
                        onRename: { s in sessionToRename = s; newSessionTitle = s.displayTitle }
                    )
                }
            }

            // Memory
            Section("Memory") {
                NavigationLink {
                    ConceptListView()
                } label: {
                    Label("Concepts", systemImage: "brain.head.profile").foregroundStyle(.purple)
                }
            }


        }
        .listStyle(.sidebar)
        .navigationTitle("Visual Intelligence")
        .overlay(alignment: .bottom) {
            VStack(spacing: 6) {
                if viewModel.isMaintaining {
                    VStack(spacing: 4) {
                        ProgressView(value: viewModel.maintenanceProgress).progressViewStyle(.linear)
                        Text("Rebuilding Library (\(Int(viewModel.maintenanceProgress * 100))%)…")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                }
                if queueIsProcessing {
                    QueueProgressView(
                        totalCount: queueTotalCount,
                        completedCount: queueCompletedCount,
                        currentItemTitle: queueCurrentItemTitle,
                        statusMessage: queueStatusMessage,
                        progress: queueProgress
                    )
                }
            }
            .padding(.bottom, 8)
        }
        // Note: Location sheet deferred to future Mac port
        .alert("Rename Session", isPresented: Binding(
            get: { sessionToRename != nil },
            set: { if !$0 { sessionToRename = nil } }
        )) {
            TextField("Session Title", text: $newSessionTitle)
            Button("Cancel", role: .cancel) { sessionToRename = nil; newSessionTitle = "" }
            Button("Save") {
                if let s = sessionToRename, !newSessionTitle.isEmpty {
                    viewModel.renameSession(s, title: newSessionTitle, context: modelContext)
                }
                sessionToRename = nil; newSessionTitle = ""
            }
        } message: { Text("Enter a new title for this session") }
    }
}

// MARK: - Session Row

private struct MacSessionRowView: View {
    let session: SessionMetadata
    @Binding var selectedSession: SessionMetadata?
    @Bindable var viewModel: SidebarViewModel
    let onLocationEdit: (SessionMetadata) -> Void
    let onRename: (SessionMetadata) -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button {
            selectedSession = session
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle)
                    .font(.subheadline.weight(.medium)).lineLimit(1)
                HStack(spacing: 4) {
                    if let loc = session.locationName {
                        Label(loc, systemImage: "mappin").font(.caption).lineLimit(1)
                    }
                    Spacer()
                    Text(session.updatedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .listRowBackground(selectedSession?.id == session.id ? Color.accentColor.opacity(0.15) : Color.clear)
        .contextMenu {
            Button { onRename(session) } label: { Label("Rename", systemImage: "pencil") }
            Button { onLocationEdit(session) } label: { Label("Edit Location", systemImage: "mappin.and.ellipse") }
            Button { viewModel.analyzeSession(session, context: modelContext) } label: {
                Label("Analyze Session", systemImage: "sparkles")
            }
            Divider()
            Button(role: .destructive) {
                viewModel.deleteSession(session, context: modelContext)
            } label: { Label("Delete Session", systemImage: "trash") }
        }
    }
}

// MARK: - Favorite Row

private struct MacFavoriteRow: View {
    let item: ProcessedItem
    @Binding var selectedSession: SessionMetadata?
    let sessions: [SessionMetadata]

    var body: some View {
        Button {
            if let sid = item.sessionID {
                selectedSession = sessions.first { $0.sessionID == sid }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                Text(item.title ?? "Untitled").font(.caption).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Collection Row

private struct MacCollectionRow: View {
    let collection: SessionCollection
    let sessions: [SessionMetadata]
    @Binding var selectedSession: SessionMetadata?
    @Bindable var viewModel: SidebarViewModel
    let onLocationEdit: (SessionMetadata) -> Void
    let onRename: (SessionMetadata) -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        DisclosureGroup {
            ForEach(sessions) { session in
                MacSessionRowView(
                    session: session,
                    selectedSession: $selectedSession,
                    viewModel: viewModel,
                    onLocationEdit: onLocationEdit,
                    onRename: onRename
                )
            }
        } label: {
            Label(collection.name, systemImage: "folder.fill").foregroundStyle(.purple)
        }
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteCollection(collection, context: modelContext)
            } label: { Label("Delete Collection", systemImage: "trash") }
        }
    }
}

// MARK: - Item List (Content Pane)

private struct MacItemListView: View {
    let session: SessionMetadata?
    let allItems: [ProcessedItem]?
    let searchText: String
    @Binding var selectedItem: ProcessedItem?
    @Bindable var viewModel: SidebarViewModel
    @Environment(\.modelContext) private var modelContext

    private var items: [ProcessedItem] {
        if let all = allItems { return all }
        return session?.items?.sorted { $0.updatedAt > $1.updatedAt } ?? []
    }

    var body: some View {
        List(items, id: \.id, selection: $selectedItem) { item in
            MacItemRow(item: item)
                .contextMenu {
                    Button {
                        item.isFavorite.toggle()
                        Task { @MainActor in try? item.modelContext?.save() }
                    } label: {
                        Label(item.isFavorite ? "Unfavorite" : "Favorite",
                              systemImage: item.isFavorite ? "star.slash" : "star.fill")
                    }
                    Button { viewModel.itemToReprocess = item } label: {
                        Label("Reprocess", systemImage: "arrow.clockwise")
                    }
                    Divider()
                    Button(role: .destructive) {
                        modelContext.delete(item)
                        Task { @MainActor in try? modelContext.save() }
                    } label: { Label("Delete", systemImage: "trash") }
                }
        }
        .listStyle(.inset)
        .navigationTitle(session?.displayTitle ?? (searchText.isEmpty ? "All Captures" : "Results"))
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Captures" : "No Results",
                    systemImage: searchText.isEmpty ? "photo.stack" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Import files or drop them onto this window."
                        : "Try a different search term.")
                )
            }
        }
        .onChange(of: viewModel.itemToReprocess) { _, item in
            guard let item else { return }
            viewModel.itemToReprocess = nil
            Task.detached(priority: .utility) {
                try? await Services.shared.metadataPipelineService?.processItemByID(item.id, force: true)
            }
        }
    }
}

private struct MacItemRow: View {
    let item: ProcessedItem
    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "Untitled").font(.subheadline).lineLimit(1)
                if let summary = item.summary {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 4) {
                    statusBadge
                    if let loc = item.placeContext?.name ?? item.location {
                        Label(loc, systemImage: "mappin").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var thumbnail: some View {
        Group {
            if let data = item.rawPayload, let img = NSImage(data: data) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: entityIcon).font(.title3).foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
        .background(.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder private var statusBadge: some View {
        if item.status != .ready {
            Text(item.status.rawValue.capitalized)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.orange.opacity(0.15), in: Capsule())
                .foregroundStyle(.orange)
        }
    }

    private var entityIcon: String {
        switch item.entityType {
        case "product": "barcode"
        case "document": "doc.text"
        case "web_link", "web": "link"
        case "person": "person.circle"
        case "place": "mappin.circle"
        default: "photo"
        }
    }
}

// MARK: - Detail Pane (Full DiverUI Profiles)

struct MacDetailView: View {
    let item: ProcessedItem
    @StateObject var viewModel: ReferenceDetailViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var showingEditLocation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                // Specialized Profiles (DiverUI)
                if item.productMetadata != nil || item.commerceContext != nil {
                    ProductProfileView(item: item).macDetailCardStyle()
                }
                if item.rawPayload != nil || item.photosAssetIdentifier != nil {
                    ImageProfileView(item: item).macDetailCardStyle()
                }
                if item.resolvedWebURL != nil || item.webContext != nil {
                    WebLinkProfileView(item: item).macDetailCardStyle()
                }
                if item.documentContext != nil {
                    DocumentProfileView(item: item).macDetailCardStyle()
                }
                if item.placeContext != nil {
                    PlaceProfileView(item: item).macDetailCardStyle()
                }
                if item.qrContext != nil {
                    QRCodeProfileView(item: item).macDetailCardStyle()
                }
                if !item.contactIdentifiers.isEmpty {
                    PersonProfileView(item: item).macDetailCardStyle()
                }

                // Footer
                footerSection
            }
            .padding(24)
        }
        .navigationTitle(item.title ?? "Capture")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showingEditLocation = true } label: {
                    Label("Edit Location", systemImage: "pencil.and.outline")
                }
                Button {
                    item.isFavorite.toggle()
                    Task { @MainActor in try? item.modelContext?.save() }
                } label: {
                    Label(item.isFavorite ? "Unfavorite" : "Favorite",
                          systemImage: item.isFavorite ? "star.fill" : "star")
                }
                .foregroundStyle(item.isFavorite ? .yellow : .primary)

                if let url = item.resolvedWebURL {
                    Link(destination: url) { Label("Open", systemImage: "safari") }
                }

                Button { viewModel.retryProcessing(item: item) } label: {
                    Label("Reprocess", systemImage: "arrow.clockwise")
                }
                .help("Re-run full pipeline")
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        // Location editing sheet — deferred to Mac-specific implementation
    }

    // MARK: Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Image
            if let data = item.rawPayload, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 6)
            }

            // Title
            Text(item.title ?? "Untitled").font(.title2.bold())
            if let url = item.resolvedWebURL {
                Link(url.absoluteString, destination: url).font(.body).foregroundStyle(.blue)
            }
            if let summary = item.summary, !summary.isEmpty, item.entityType != "product" {
                Text(summary).font(.body).foregroundStyle(.primary)
            }

            // Status
            HStack {
                Text(item.status.rawValue.capitalized)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            // Tags
            let tags = Array(Set(item.visualTags + item.tags + item.categories + item.purposes)).sorted()
            if !tags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Semantic Tags").font(.subheadline.weight(.semibold))
                    MacFlowLayout(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.blue.opacity(0.1), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .macDetailCardStyle()
    }

    // MARK: Footer
    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Purposes
            if !item.purposes.isEmpty || viewModel.isGeneratingPurposes {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Purposes & Intent").font(.headline)
                        Spacer()
                        Button { viewModel.generatePurposes(for: item, siblingContext: "") } label: {
                            Image(systemName: "sparkles")
                        }
                    }
                    MacFlowLayout(spacing: 6) {
                        ForEach(item.purposes.sorted(), id: \.self) { p in
                            Text(p).font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.blue.opacity(0.1), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }

            // VLM Insights
            if let vlm = item.fastVLMAnalysis, !vlm.statements.isEmpty {
                Divider()
                Text("Insights").font(.subheadline).foregroundStyle(.secondary)
                ForEach(vlm.statements, id: \.self) { s in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "eye.fill").foregroundStyle(.purple).font(.caption).padding(.top, 2)
                        Text(s).font(.caption)
                    }
                }
            }

            // Media Info
            let mi = item.mediaInfo
            if mi.mediaType != nil || mi.filename != nil || mi.fileSize != nil {
                Divider()
                Text("Media Information").font(.subheadline).foregroundStyle(.secondary)
                if let t = mi.mediaType { macInfoRow("Type", t.capitalized) }
                if let f = mi.filename { macInfoRow("File", f) }
                if let s = mi.fileSize { macInfoRow("Size", ByteCountFormatter.string(fromByteCount: Int64(s), countStyle: .file)) }
            }

            // Concept Weighting
            ConceptWeightingSection(item: item)
        }
        .macDetailCardStyle()
    }

    private func macInfoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }.font(.caption)
    }
}

extension View {
    func macDetailCardStyle() -> some View {
        self
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Mac Flow Layout

struct MacFlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 0
        var height: CGFloat = 0; var rw: CGFloat = 0; var rh: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if rw + s.width > w && rw > 0 { height += rh + spacing; rw = 0; rh = 0 }
            rw += s.width + spacing; rh = max(rh, s.height)
        }
        return CGSize(width: w, height: height + rh)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rh: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { y += rh + spacing; x = bounds.minX; rh = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rh = max(rh, s.height)
        }
    }
}

// MARK: - Chat Panel

private struct MacChatView: View {
    @ObservedObject var viewModel: AgenticChatViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "brain.head.profile").foregroundStyle(.purple)
                Text("Chat with Library").font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain).keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16).padding(.vertical, 12).background(.bar)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { msg in
                            MacChatBubble(message: msg).id(msg.id)
                        }
                        if viewModel.isThinking {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Thinking…").font(.caption).foregroundStyle(.secondary)
                            }.padding(.leading, 16)
                        }
                    }.padding(16)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Ask anything about your library…", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...4).onSubmit { viewModel.sendMessage() }
                Button { viewModel.sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                        .foregroundStyle(viewModel.inputText.isEmpty ? Color.secondary : Color.blue)
                }.buttonStyle(.plain).disabled(viewModel.inputText.isEmpty || viewModel.isThinking)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
        }
    }
}

private struct MacChatBubble: View {
    let message: AgenticChatMessage
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 60)
                Text(message.text).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white).textSelection(.enabled)
            } else {
                Image(systemName: "brain.head.profile").foregroundStyle(.purple).frame(width: 24)
                Text(message.text).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .textSelection(.enabled)
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Empty Detail

private struct MacEmptyDetailView: View {
    @Binding var showChat: Bool
    let onImport: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Select a capture, or…").font(.headline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button { withAnimation(.spring(duration: 0.3)) { showChat = true } } label: {
                    Label("Chat with Library", systemImage: "bubble.left.and.bubble.right.fill")
                }.buttonStyle(.borderedProminent)
                Button(action: onImport) {
                    Label("Import Files", systemImage: "square.and.arrow.down")
                }.buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Null Search Service

private final class NullAgenticSearchService: AgenticSearching {
    func ingestDocument(id: String, text: String, metadata: [String: String]) async throws -> Bool { false }
    func performSearch(query: String, topK: Int) async throws -> AgenticSearchResult {
        AgenticSearchResult(generatedAnswer: "CLaRa not available on this Mac yet.", citedDocumentIDs: [])
    }
}
