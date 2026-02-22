#!/usr/bin/env python3
"""Generate wiki HTML pages for Visual Intelligence Pipeline documentation."""

SIDEBAR = """<nav class="sidebar">
  <div class="sidebar-header"><h1>Visual Intelligence Pipeline</h1><div class="version">v1.1 Developer Wiki</div></div>
  <div class="search-box"><input type="text" id="search" placeholder="Search types…" oninput="filterTypes(this.value)"></div>
  <div class="sidebar-section">
    <div class="sidebar-section-title">Overview</div>
    <a class="sidebar-link{active_index}" href="index.html">Home</a>
    <a class="sidebar-link{active_arch}" href="architecture.html">Architecture</a>
  </div>
  <div class="sidebar-section">
    <div class="sidebar-section-title">Modules</div>
    <a class="sidebar-link{active_ds}" href="divershared.html">DiverShared</a>
    <a class="sidebar-link{active_dkm}" href="diverkit-models.html">DiverKit — Models</a>
    <a class="sidebar-link{active_dks}" href="diverkit-services.html">DiverKit — Services</a>
    <a class="sidebar-link{active_dkv}" href="diverkit-viewmodels.html">DiverKit — ViewModels</a>
    <a class="sidebar-link{active_dkc}" href="diverkit-core.html">DiverKit — Core</a>
    <a class="sidebar-link{active_dkst}" href="diverkit-storage.html">DiverKit — Storage &amp; Auth</a>
    <a class="sidebar-link{active_av}" href="app-views.html">App — Views</a>
    <a class="sidebar-link{active_as}" href="app-services.html">App — Services</a>
    <a class="sidebar-link{active_ai}" href="app-intents.html">App — Intents &amp; Widgets</a>
  </div>
</nav>"""

SCRIPT = """<script>
function filterTypes(q) {
  document.querySelectorAll('.searchable').forEach(el => {
    el.style.display = (!q || el.dataset.name.toLowerCase().includes(q.toLowerCase())) ? 'flex' : 'none';
  });
}
</script>"""

def sidebar(active_key):
    keys = ["index","arch","ds","dkm","dks","dkv","dkc","dkst","av","as","ai"]
    replacements = {}
    for k in keys:
        replacements[f"active_{k}"] = " active" if k == active_key else ""
    return SIDEBAR.format(**replacements)

def badge(kind):
    return f'<span class="badge badge-{kind}">{kind}</span>'

def type_item(name, kind, desc=""):
    desc_html = f'<div class="conformances">{desc}</div>' if desc else ""
    return f'''<li class="type-item searchable" data-name="{name}">
  {badge(kind)}
  <div class="name"><strong>{name}</strong></div>
  {desc_html}
</li>'''

def section(title, items, note=""):
    items_html = "\n".join(items)
    note_html = f'<p style="color:var(--text-secondary);font-size:13px;margin-top:12px;">{note}</p>' if note else ""
    return f'''<div class="section">
  <h2 class="section-title">{title}</h2>
  <ul class="type-list">{items_html}</ul>
  {note_html}
</div>'''

def page(title, subtitle, active_key, stats, body):
    stats_html = ""
    if stats:
        stat_divs = "".join(f'<div class="stat"><div class="stat-value">{v}</div><div class="stat-label">{l}</div></div>' for v, l in stats)
        stats_html = f'<div class="stats-bar">{stat_divs}</div>'
    return f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{title} — Developer Wiki</title>
<link rel="stylesheet" href="styles.css">
</head>
<body>
<div class="layout">
{sidebar(active_key)}
<main class="main">
  <div class="breadcrumb"><a href="index.html">Wiki</a> <span class="sep">›</span> {title}</div>
  <h1 class="page-title">{title}</h1>
  <p class="page-subtitle">{subtitle}</p>
  {stats_html}
  {body}
</main>
</div>
{SCRIPT}
</body>
</html>'''


def generate_all():
    pages = {}

    # --- DiverKit Models ---
    pages["diverkit-models.html"] = page(
        "DiverKit — Models",
        "Core data models for enriched items, sessions, collections, and pipeline types.",
        "dkm",
        [("20", "Files"), ("20", "Types")],
        "\n".join([
            section("ProcessedItem.swift", [
                type_item("MediaMetadata", "struct", "Codable, Hashable, Sendable — image dimensions, orientation, format"),
            ], "The primary enriched item model. Stored in SwiftData, synced via CloudKit. Contains title, summary, concepts, context snapshot, media data, location, and session reference."),
            section("DiverSession.swift", [
                type_item("DiverSession", "typealias", "Typealias for SessionMetadata — use DiverSession in new code"),
            ], "Session grouping model. Captures are auto-grouped by location and time. Sessions have AI-generated summaries and support bulk location editing."),
            section("DiverCollection.swift", [
                type_item("DiverCollection", "class", "SwiftData @Model — user-created collections of sessions"),
            ], "User-created collections for organizing sessions by topic."),
            section("UserConcept.swift", [
                type_item("UserConcept", "class", "SwiftData @Model — concept tag with weight"),
            ], "Concept/tag model. Weights are incremented during reprocessing to track concept importance."),
            section("DiverObject.swift", [
                type_item("DiverObject", "protocol", "Identifiable — common interface for displayable items"),
                type_item("DiverObjectDTO", "struct", "Identifiable, Sendable, Hashable — lightweight transfer object"),
                type_item("DiverObjectType", "enum", "String, Sendable, Codable — item, session, collection"),
            ]),
            section("LocalInput.swift", [
                type_item("LocalInput", "struct", "Raw input before pipeline processing — URL, type, context"),
            ]),
            section("AestheticsTypes.swift", [
                type_item("Frame", "struct", "Video frame with timestamp and quality score"),
                type_item("ImportedAsset", "struct", "Identifiable, Sendable — photo/video import wrapper"),
            ]),
            section("DiverQueueItem+Intelligence.swift", [
                type_item("DiverQueueItem+Intelligence", "extension", "Intelligence metadata extensions on DiverQueueItem"),
            ], "Extends DiverQueueItem with computed properties for extracted concepts, summaries, and enrichment data."),
            section("SSEEvent.swift", [
                type_item("BaseEventData", "struct", "Codable — SSE event base"),
                type_item("LogEventData", "struct", "Codable — pipeline log events"),
                type_item("ItemEventData", "struct", "Codable — item update events"),
                type_item("TikTokMetadataEventData", "struct", "Codable"),
                type_item("ChatMessageEventData", "struct", "Codable"),
            ]),
            section("TikTokMetadata.swift", [
                type_item("TikTokContentType", "enum", "String, Codable"),
                type_item("StandardTikTokAuthor", "struct", "Codable"),
                type_item("StandardTikTokStats", "struct", "Codable"),
            ]),
            section("TypeAliases.swift", [
                type_item("User", "typealias", "→ UserRead"),
                type_item("Profile", "typealias", "→ UserProfile"),
                type_item("Item", "typealias", "→ ItemRead"),
                type_item("Input", "typealias", "→ InputRead"),
                type_item("Message", "typealias", "→ MessageRead"),
            ]),
            section("Other Models", [
                type_item("ProcessingStatus", "enum", "String, Codable, Sendable — pending, processing, complete, failed"),
                type_item("JobProgress", "class", "Observable job tracking with log entries"),
                type_item("JSONCoding", "struct", "JSON encode/decode helpers"),
            ]),
        ])
    )

    # --- DiverKit Services ---
    pages["diverkit-services.html"] = page(
        "DiverKit — Services",
        "65 services covering pipeline orchestration, location/weather/web/music enrichment, ML inference, session management, distributed edge scaling, and commerce.",
        "dks",
        [("62", "Files"), ("62+", "Types")],
        "\n".join([
            section("Pipeline Orchestration", [
                type_item("LocalPipelineService", "struct", "2,732 lines — core orchestrator: ingestion → enrichment → persistence"),
                type_item("MetadataPipelineService", "struct", "1,002 lines — queue item → LocalInput, metadata extraction"),
                type_item("PipelineImportService", "struct", "Photo/video import into the pipeline"),
                type_item("ReprocessContext", "struct", "Configuration for silent background reprocessing"),
                type_item("ParallelEnrichmentResult", "struct", "Aggregated results from parallel enrichment services"),
            ], "LocalPipelineService is the central orchestrator. It receives raw input, fans out to enrichment services in parallel, and persists the enriched ProcessedItem to SwiftData."),
            section("Intelligence &amp; ML", [
                type_item("IntelligenceProcessor", "class", "568 lines — on-device LLM prompts via SystemLanguageModel"),
                type_item("IntelligenceResult", "enum", "Pipeline result: .detected, .sifted, .enriched"),
                type_item("FastVLMEnrichmentService", "class", "Multimodal image analysis via FastVLM 0.5B / 7B (MLX Swift). Two-pass: image description + context synthesis. Prompt excludes camera/capture equipment to prevent hallucinations."),
                type_item("FoundationModelsIntentClassifier", "class", "Intent classification using Foundation Models"),
                type_item("AestheticsScoringService", "struct", "CoreML image quality scoring"),
                type_item("EdgeInferenceActor", "distributed actor", "Distributed ML Router to MacOS neural engine for FastVLM 7B, SAM 2.1, and CLaRa execution."),
            ], "IntelligenceProcessor generates summaries, concepts, and tags by composing LLM prompts enriched with weather, location, OCR text, and web data. FastVLMEnrichmentService runs Apple's FastVLM models for multimodal image understanding, scaling up parameters via the Edge node."),
            section("Location Services", [
                type_item("LocationSearchAggregator", "struct", "Parallel Foursquare + MapKit search with merged results"),
                type_item("SimpleMapFeature", "struct", "Lightweight map annotation model"),
                type_item("FoursquareEnrichmentService", "class", "Venue search and detail enrichment"),
                type_item("MapKitEnrichmentService", "class", "Apple Maps landmark/address enrichment"),
                type_item("ReverseGeocodingService", "struct", "CLGeocoder coordinate → address"),
                type_item("LocationProvider", "protocol", "AnyObject, Sendable — CLLocationManager abstraction"),
                type_item("LocationService", "class", "GPS coordinate provider"),
                type_item("SessionClusteringService", "struct", "Location/time-based session grouping"),
            ], "LocationSearchAggregator runs Foursquare and MapKit searches in parallel, deduplicates by proximity, and returns a unified result set."),
            section("Content Enrichment", [
                type_item("WeatherEnrichmentService", "actor", "WeatherKit current conditions"),
                type_item("DuckDuckGoEnrichmentService", "struct", "Web search enrichment"),
                type_item("WebViewLinkEnrichmentService", "struct", "URL metadata extraction via WKWebView"),
                type_item("AppleMusicEnrichmentService", "struct", "LinkEnrichmentService — MusicKit matching"),
                type_item("SpotifyService", "class", "Spotify track/album identification"),
                type_item("FoursquareLinkEnrichmentService", "struct", "Foursquare URL enrichment"),
                type_item("YahooSearchService", "struct", "Web search via LocalPackages/YahooSearch"),
            ]),
            section("Enrichment Protocols", [
                type_item("EnrichmentData", "struct", "Sendable, Codable, Identifiable — venue/place result"),
                type_item("LinkEnrichmentService", "protocol", "Sendable — async enrich(url:) → EnrichmentData"),
                type_item("ContextualEnrichmentService", "protocol", "Sendable — enrichment with context injection"),
                type_item("KnowledgeGraphIndexingService", "protocol", "Sendable — index items for semantic search"),
                type_item("KnowledgeGraphRetrievalService", "protocol", "Sendable — retrieve by vector similarity"),
            ]),
            section("Other Services", [
                type_item("DailyContextService", "class", "ObservableObject — Daily Focus summary generation"),
                type_item("CameraManager", "class", "AVFoundation camera session management"),
                type_item("PhotoLibraryImportService", "struct", "683 lines — PHAsset import with EXIF extraction"),
                type_item("PhotosAssetLoader", "struct", "PHAsset loading and thumbnail generation"),
                type_item("DocumentManager", "struct", "Sendable — document detection, perspective correction, saving"),
                type_item("ContactService", "protocol", "ContactServiceProvider — CNContact enrichment"),
                type_item("ContextQuestionService", "class", "Interactive context question generation"),
                type_item("ContextEnrichmentCoordinator", "actor", "Coordinates parallel enrichment tasks"),
                type_item("DiverLinkGenerator", "struct", "HMAC-signed DiverLink creation"),
                type_item("SSEStreamService", "class", "Server-Sent Events streaming client"),
                type_item("Probe", "struct", "Diagnostic/performance measurement utility"),
            ]),
        ])
    )

    # --- DiverKit ViewModels ---
    pages["diverkit-viewmodels.html"] = page(
        "DiverKit — ViewModels",
        "Six ObservableObject view models that bridge services to SwiftUI views.",
        "dkv",
        [("6", "Files"), ("5,200+", "Lines")],
        "\n".join([
            section("VisualIntelligenceViewModel", [
                type_item("VisualIntelligenceViewModel", "class", "ObservableObject — 2,884 lines"),
                type_item("PlatformImage", "typealias", "→ UIImage (iOS) / NSImage (macOS)"),
                type_item("PipelineStatus", "enum", "idle, detecting, sifting, enriching, complete"),
            ], """The largest view model. Manages camera lifecycle, real-time subject detection, sifting, capture review stack, photo library import, location state, document detection, and context suggestions. Key public methods: <code>setupCameraBridge()</code>, <code>handleCapture()</code>, <code>commitReviewSave()</code>, <code>processImportedPhotos()</code>, <code>analyzeStaticImage()</code>, <code>saveDocument()</code>, <code>reprocessPipeline()</code>, <code>selectPlace()</code>, <code>addUserContext()</code>."""),
            section("SidebarViewModel", [
                type_item("SidebarViewModel", "class", "ObservableObject — 1,259 lines"),
            ], """Centralizes sidebar state: session list, collection management, inbox, favorites, drag-and-drop between sessions, search (keyword + semantic), and library maintenance (orphan cleanup, session merging). Key methods: <code>loadSessions()</code>, <code>moveItems()</code>, <code>deleteSession()</code>, <code>performSearch()</code>."""),
            section("ReferenceDetailViewModel", [
                type_item("ReferenceDetailViewModel", "class", "ObservableObject"),
            ], "Manages item detail view state: loading enrichment data, editing text/notes, triggering reprocessing, and managing location updates for a single ProcessedItem."),
            section("ProcessedItemViewModel", [
                type_item("ProcessedItemViewModel", "class", "ObservableObject"),
            ], "Lightweight view model for individual item operations: delete, reprocess, share, and concept weight management."),
            section("AgenticChatViewModel & MetadataViewModel", [
                type_item("AgenticChatViewModel", "class", "ObservableObject — memory querying via CLaRa UI"),
                type_item("MetadataViewModel", "class", "ObservableObject — ActionExtension payload extraction"),
            ], "Manages complex async interfaces like NLP library parsing and background extension URL ingestion."),
        ])
    )

    # --- DiverKit Core ---
    pages["diverkit-core.html"] = page(
        "DiverKit — Core",
        "Networking stack, JSON helpers, configuration, localization, icon service, toast management, and utilities.",
        "dkc",
        [],
        "\n".join([
            section("Networking", [
                type_item("HTTP", "enum", "Static HTTP method definitions and request building"),
                type_item("MultipartFormData", "class", "Multipart form data builder"),
                type_item("MultipartFormField", "enum", "Field types: text, file, data"),
                type_item("MultipartFormDataConvertible", "protocol", "Convert types to multipart fields"),
                type_item("QueryParameter", "enum", "URL query parameter encoding"),
                type_item("RequestOptions", "struct", "Headers, timeout, retry config"),
            ]),
            section("Data Types", [
                type_item("JSONValue", "enum", "Codable, Hashable, Sendable — dynamic JSON value type"),
                type_item("APIErrorResponse", "struct", "Codable, Sendable — server error response"),
                type_item("ClientError", "enum", "Error — network, decoding, auth failures"),
                type_item("Nullable", "enum", "Codable wrapper for optional JSON fields"),
                type_item("FormFile", "struct", "File upload metadata"),
                type_item("LinkMetadata", "struct", "Codable, Sendable — extracted link metadata (LinkUnpacker)"),
                type_item("CalendarDate", "struct", "Codable, Hashable, Comparable — date without time"),
            ]),
            section("Serialization", [
                type_item("EncodableValue", "struct", "Type-erased Encodable wrapper"),
                type_item("StringKey", "struct", "CodingKey — dynamic coding key"),
            ]),
            section("Configuration", [
                type_item("APIConfig", "enum", "Static API endpoints, keys, base URLs"),
                type_item("IconService", "enum", "SF Symbol icon helpers"),
                type_item("IconWeight", "enum", "String — ultraLight, thin, light, regular, etc."),
            ]),
            section("Localization", [
                type_item("LocalizationManager", "class", "ObservableObject — runtime language switching"),
                type_item("AppLanguage", "enum", "String, CaseIterable — supported languages"),
                type_item("LocalizedStringKey", "enum", "All localized string keys"),
                type_item("LocalizationExporter", "struct", "Export strings for translation"),
            ]),
            section("Managers", [
                type_item("ToastManager", "class", "ObservableObject — in-app toast notifications"),
                type_item("ToastNotification", "struct", "Identifiable, Equatable — toast data"),
                type_item("ToastType", "enum", "success, error, info, warning"),
                type_item("StoreHealthMonitor", "struct", "SwiftData container health checks"),
                type_item("StoreHealthSnapshot", "struct", "Sendable — container status report"),
            ]),
            section("Utilities", [
                type_item("DiverLogger", "enum", "Static structured logging with subsystems"),
                type_item("DiverBundle", "enum", "Static bundle resource accessors"),
                type_item("RichLinkSharer", "class", "NSObject — share sheet with rich link previews"),
                type_item("RichLinkActivitySource", "class", "UIActivityItemSource — custom share content"),
            ]),
            section("Transfer Types", [
                type_item("ItemTransfer", "struct", "Codable, Transferable, Sendable — drag-and-drop item"),
                type_item("SessionTransfer", "struct", "Codable, Transferable, Sendable — drag-and-drop session"),
                type_item("DiverKitInfo", "enum", "Static version and build info"),
            ]),
        ])
    )

    # --- DiverKit Storage & Auth ---
    pages["diverkit-storage.html"] = page(
        "DiverKit — Storage &amp; Auth",
        "SwiftData container management, keychain services, token validation, and data seeding.",
        "dkst",
        [],
        "\n".join([
            section("Storage", [
                type_item("DiverDataStore", "class", "SwiftData ModelContainer — single entry point for all persistence"),
                type_item("UnifiedDataManager", "class", "Wraps DiverDataStore for convenience"),
                type_item("ReferencePayloadStore", "class", "Compressed JSON blob storage for large payloads"),
                type_item("StorageClient", "class", "File system storage helpers"),
                type_item("DataSeeder", "struct", "Development-time sample data generation"),
            ], "DiverDataStore creates and manages the SwiftData ModelContainer with CloudKit backing. All models (ProcessedItem, DiverSession, DiverCollection, UserConcept) are registered here."),
            section("Authentication", [
                type_item("AuthenticationState", "enum", "Sendable, Equatable — unauthenticated, authenticating, authenticated, failed"),
                type_item("KeychainError", "enum", "Error, Sendable — itemNotFound, duplicateItem, unexpectedData"),
                type_item("KeychainService", "enum", "Static Keychain read/write/delete"),
                type_item("JWTClaims", "struct", "Codable, Sendable — JWT payload parsing"),
                type_item("TokenValidator", "enum", "Static JWT expiration and refresh checks"),
                type_item("TokenResponse", "struct", "Codable, Sendable — OAuth token response"),
            ]),
        ])
    )

    # --- App Views ---
    pages["app-views.html"] = page(
        "App — Views",
        "42 SwiftUI views composing the camera, sidebar, detail, review, commerce overlays, settings, and widget interfaces.",
        "av",
        [("42", "Files"), ("18,000+", "Lines")],
        "\n".join([
            section("Camera &amp; Capture", [
                type_item("VisualIntelligenceView", "struct", "View — 1,795 lines. Camera + overlays + review stack"),
                type_item("VisualIntelligenceReviewLayer", "struct", "View — review card overlay"),
                type_item("VisualIntelligenceCameraLayer", "struct", "View — camera preview layer"),
                type_item("VisualIntelligenceHUD", "struct", "View — heads-up display overlay"),
                type_item("CaptureReviewView", "struct", "View — card-stack review interface"),
                type_item("CameraPreviewView", "struct", "UIViewRepresentable — AVCaptureSession preview"),
                type_item("ResultsOverlayView", "struct", "View — detection results overlay"),
                type_item("SiftedOverlayView", "struct", "View — sifted subject overlay"),
                type_item("SessionLocationBar", "struct", "View — pinned location bar"),
                type_item("ContextChipBar", "struct", "View — context tag chips"),
                type_item("PipelineStatusView", "struct", "View — enrichment progress indicator"),
            ], "VisualIntelligenceView is the primary camera interface. It layers camera preview, detection overlays, sifted subjects, location bar, and the review stack."),
            section("Sidebar &amp; Navigation", [
                type_item("SidebarView", "struct", "View — 1,444 lines. Sessions, collections, inbox, favorites"),
                type_item("SessionRowLabel", "struct", "View — session list row"),
                type_item("ItemRow", "struct", "View — item list row"),
                type_item("ItemRowWithActions", "struct", "View — item row with swipe actions"),
                type_item("ThumbnailView", "struct", "View — item thumbnail with fallback"),
                type_item("ContentView", "struct", "View — root navigation split view"),
                type_item("DetailPane", "struct", "View — detail column content"),
                type_item("SessionItemsView", "struct", "View — items within a session"),
            ]),
            section("Detail &amp; Editing", [
                type_item("ReferenceDetailView", "struct", "View — 2,486 lines. Full item detail"),
                type_item("ReferenceDetailContent", "struct", "View — detail card content"),
                type_item("ReferenceCardWrapper", "struct", "View — card layout wrapper"),
                type_item("ReferenceCardView", "struct", "View — individual enrichment card"),
                type_item("StatusBadge", "struct", "View — processing status indicator"),
                type_item("EditLocationView", "struct", "View — 663 lines. MapKit location search + selection"),
                type_item("LocationCandidateRow", "struct", "View — search result row"),
                type_item("EditSessionLocationView", "struct", "View — bulk session location edit"),
                type_item("PlaceSelectionMapView", "struct", "View — map pin placement"),
                type_item("ConceptListView", "struct", "View — concept tag list"),
                type_item("ConceptWeightingSection", "struct", "View — concept weight editor"),
                type_item("ConceptWeightView", "struct", "View — individual weight slider"),
            ]),
            section("Reprocessing", [
                type_item("ReprocessingWizardView", "struct", "View — 459 lines. Multi-step reprocess wizard"),
                type_item("ReprocessMetadataView", "struct", "View — metadata review before reprocess"),
                type_item("ReviewItemRow", "struct", "View — item in reprocess review list"),
                type_item("ReviewApprovalState", "enum", "approved, rejected, pending"),
                type_item("ItemSnapshot", "struct", "Frozen item state for review comparison"),
            ]),
            section("Settings &amp; Utilities", [
                type_item("SettingsView", "struct", "View — 518 lines. App configuration and diagnostics"),
                type_item("LogExport", "struct", "Codable — diagnostic log export data"),
                type_item("LogExportShareSheet", "struct", "UIViewControllerRepresentable — share log files"),
                type_item("StorageInfoRow", "struct", "View — storage usage display"),
                type_item("ShortcutGalleryView", "struct", "View — 619 lines. Shortcuts discovery"),
                type_item("AppleMusicReferenceView", "struct", "View — Apple Music match display"),
                type_item("SharedWithYouView", "struct", "View — Shared With You items"),
                type_item("SharedHighlightRow", "struct", "View — individual shared highlight"),
                type_item("QueueProgressView", "struct", "View — queue drain progress"),
                type_item("LinkPreviewView", "struct", "UIViewRepresentable — LPLinkView wrapper"),
                type_item("RichWebView", "struct", "UIViewRepresentable — WKWebView wrapper"),
            ]),
        ])
    )

    # --- App Services ---
    pages["app-services.html"] = page(
        "App — Services",
        "App-level service wiring, dependency injection, and system integrations.",
        "as",
        [("7", "Files")],
        "\n".join([
            section("Dependency Injection", [
                type_item("KnowMapsServiceContainer", "class", "Consolidates ML, search, cache, and analytics services"),
                type_item("KnowMapsAdapter", "enum", "Static mapping: ProcessedItem ↔ Know Maps ItemMetadata"),
                type_item("KnowMapsCacheStore", "class", "In-memory cache for service results"),
            ], "KnowMapsServiceContainer is initialized at app launch and injected into view models and services. It owns the ML models, search indices, and analytics pipelines."),
            section("Queue Processing", [
                type_item("DiverQueueProcessingService", "class", "23K lines — drains file-based queue on app launch"),
            ], "Reads DiverQueueItem files from the app group container, validates HMAC signatures, and feeds items into the pipeline. Handles retry logic and failure cleanup."),
            section("System Integration", [
                type_item("SharedWithYouManager", "class", "NSObject, ObservableObject — Shared With You framework integration"),
                type_item("NavigationManager", "class", "ObservableObject — app-level navigation state"),
                type_item("FoursquareLinkEnrichmentService", "class", "Foursquare URL enrichment (app-level)"),
            ]),
            section("App Entry Point", [
                type_item("VisualIntelligencePipelineApp", "struct", "App — @main entry point, service initialization, scene setup"),
            ], "Initializes KnowMapsServiceContainer, DiverDataStore, and DiverQueueProcessingService. Sets up the SwiftUI scene with NavigationSplitView."),
        ])
    )

    # --- App Intents ---
    pages["app-intents.html"] = page(
        "App — Intents &amp; Widgets",
        "5 App Intents for Siri/Shortcuts, widget extension, entities, and shortcut templates.",
        "ai",
        [("5", "Intents"), ("20", "Widget Files")],
        "\n".join([
            section("App Intents", [
                type_item("SaveLinkIntent", "struct", "AppIntent — save a URL to the library via Siri"),
                type_item("ShareLinkIntent", "struct", "AppIntent — share an item via Siri"),
                type_item("SearchLinksIntent", "struct", "AppIntent, WidgetConfigurationIntent — search the library"),
                type_item("OpenLinkIntent", "struct", "AppIntent — open a saved link"),
                type_item("AskCLaRaIntent", "struct", "AppIntent — NLP memory querying via Siri"),
                type_item("VisualIntelligenceIntent", "struct", "AppIntent — launch capture and analyze"),
                type_item("OpenVisualIntelligenceIntent", "struct", "AppIntent — open the camera view"),
                type_item("OpenLinkError", "enum", "Error — itemNotFound, invalidURL"),
            ], "Each intent is registered with Siri and available in Shortcuts. SearchLinksIntent also serves as a WidgetConfigurationIntent for interactive widgets."),
            section("Entities", [
                type_item("LinkEntity", "struct", "AppEntity, Identifiable, Hashable, Codable, Sendable"),
                type_item("LinkEntityQuery", "struct", "EntityQuery — search and lookup for LinkEntity"),
            ], "LinkEntity wraps ProcessedItem for the App Intents framework. LinkEntityQuery provides string-based search and ID-based lookup."),
            section("Shortcut Provider", [
                type_item("DiverShortcuts", "struct", "AppShortcutsProvider — pre-built shortcut templates"),
            ]),
            section("Intent Views", [
                type_item("SaveLinkSnippet", "struct", "View — confirmation snippet after save"),
                type_item("ShareLinkSnippet", "struct", "View — share confirmation snippet"),
                type_item("SearchLinkSnippet", "struct", "View — search results snippet"),
                type_item("VisualIntelligenceSnippet", "struct", "View — capture result snippet"),
                type_item("IntentConfigurationView", "struct", "View — widget configuration"),
            ]),
            section("Intent Services", [
                type_item("URLCompletenessAnalyzer", "struct", "Validates and normalizes URLs from Siri input"),
                type_item("ScreenshotProcessor", "actor", "Screenshot capture and processing for intents"),
            ]),
            section("Widget Extension", [
            ], "The VisualIntelligencePipelineWidget target (20 files, 2,622 lines) provides Home and Lock screen widgets showing recent captures, search, and quick actions. Uses WidgetKit with SearchLinksIntent for interactive configuration."),
            section("Shortcut Gallery", [
                type_item("ShortcutsManifest", "struct", "Codable — shortcut template catalog"),
                type_item("WidgetTemplate", "struct", "Identifiable, Codable — widget configuration template"),
                type_item("ShortcutTemplate", "struct", "Identifiable, Codable — shortcut recipe"),
                type_item("ShortcutAction", "struct", "Codable — individual shortcut step"),
                type_item("AdvancedWorkflow", "struct", "Identifiable, Codable — multi-step automation"),
            ]),
        ])
    )

    # --- Architecture ---
    pages["architecture.html"] = page(
        "Architecture",
        "System design, data flow, and module dependency overview for Visual Intelligence Pipeline.",
        "arch",
        [("50,800+", "Lines"), ("316", "Files"), ("53+", "Commits"), ("37", "Days")],
        """
<div class="section">
  <h2 class="section-title">Module Dependencies</h2>
  <div style="background:var(--bg-secondary);border:1px solid var(--border);border-radius:var(--radius);padding:24px;font-family:'JetBrains Mono',monospace;font-size:13px;line-height:2.2;color:var(--text-secondary);">
    <span style="color:var(--accent-green)">DiverShared</span> <span style="color:var(--text-muted)">(pure Swift, zero deps)</span><br>
    &nbsp;&nbsp;&bull; AppGroupConfig, ContextSnapshot, DiverQueueStore, LinkWrapping, Validation<br>
    &nbsp;&nbsp;&nbsp;&nbsp;↑<br>
    <span style="color:var(--accent-blue)">DiverKit</span> <span style="color:var(--text-muted)">(depends on DiverShared)</span><br>
     &nbsp;&nbsp;&bull; Services (36), Models (14), ViewModels (4), Storage (5), Core, Auth, Schemas (56)<br>
    &nbsp;&nbsp;&nbsp;&nbsp;↑<br>
    <span style="color:var(--accent-purple)">VisualIntelligencePipeline</span> <span style="color:var(--text-muted)">(depends on DiverKit + DiverShared)</span><br>
    &nbsp;&nbsp;&bull; Views (25), Services (7), AppIntents (5+), Widget (20 files), ActionExtension (5 files)<br>
    &nbsp;&nbsp;&nbsp;&nbsp;↑<br>
    <span style="color:var(--accent-cyan)">LocalPackages/YahooSearch</span> <span style="color:var(--text-muted)">(optional web search)</span>
  </div>
</div>

<div class="section">
  <h2 class="section-title">Data Flow</h2>
  <div style="background:var(--bg-secondary);border:1px solid var(--border);border-radius:var(--radius);padding:24px;font-family:'JetBrains Mono',monospace;font-size:12px;line-height:2.4;color:var(--text-secondary);">
    <strong style="color:var(--accent-cyan)">Input Sources</strong><br>
    &nbsp;&nbsp;Camera → VisualIntelligenceViewModel.handleCapture()<br>
    &nbsp;&nbsp;Photo Library → PhotoLibraryImportService.importAssets()<br>
    &nbsp;&nbsp;Share Sheet → ActionExtension → DiverQueueStore.enqueue()<br>
    &nbsp;&nbsp;Siri/Shortcuts → SaveLinkIntent.perform()<br><br>
    <strong style="color:var(--accent-green)">Pipeline</strong><br>
    &nbsp;&nbsp;Raw Input → LocalPipelineService.process()<br>
    &nbsp;&nbsp;&nbsp;&nbsp;├── LocationSearchAggregator (Foursquare + MapKit, parallel)<br>
    &nbsp;&nbsp;&nbsp;&nbsp;├── WeatherEnrichmentService (WeatherKit)<br>
     &nbsp;&nbsp;&nbsp;&nbsp;├── AestheticsScoringService (CoreML quality scoring)<br>
     &nbsp;&nbsp;&nbsp;&nbsp;├── FastVLMEnrichmentService (FastVLM 0.5B / 7B Edge multimodal image analysis)<br>
     &nbsp;&nbsp;&nbsp;&nbsp;├── DuckDuckGoEnrichmentService (web intelligence)<br>
     &nbsp;&nbsp;&nbsp;&nbsp;├── AppleMusicEnrichmentService (music matching)<br>
     &nbsp;&nbsp;&nbsp;&nbsp;├── DocumentManager (perspective correction)<br>
     &nbsp;&nbsp;&nbsp;&nbsp;├── InferenceService (SAM 2.1 Object Segmentation Edge routing)<br>
     &nbsp;&nbsp;&nbsp;&nbsp;└── IntelligenceProcessor (SystemLanguageModel: summaries, concepts, tags)<br><br>
    <strong style="color:var(--accent-purple)">Persistence</strong><br>
    &nbsp;&nbsp;ProcessedItem → SwiftData (DiverDataStore) → CloudKit sync<br>
    &nbsp;&nbsp;SessionClusteringService → DiverSession grouping<br>
    &nbsp;&nbsp;DailyContextService → Daily Focus summary
  </div>
</div>

<div class="section">
  <h2 class="section-title">Key Architectural Patterns</h2>
  <ul class="type-list">
    <li class="type-item">
      <span class="badge badge-struct">pattern</span>
      <div class="name"><strong>Local-First + CloudKit Sync</strong></div>
      <div class="conformances">All data persisted to SwiftData first, synced via CloudKit transparently</div>
    </li>
    <li class="type-item">
      <span class="badge badge-struct">pattern</span>
      <div class="name"><strong>File-Based Queue</strong></div>
      <div class="conformances">Extensions write JSON files to app group; main app drains on launch</div>
    </li>
    <li class="type-item">
      <span class="badge badge-protocol">pattern</span>
      <div class="name"><strong>Protocol-Based Enrichment</strong></div>
      <div class="conformances">LinkEnrichmentService protocol enables pluggable enrichment sources</div>
    </li>
    <li class="type-item">
      <span class="badge badge-actor">pattern</span>
      <div class="name"><strong>Parallel Enrichment</strong></div>
      <div class="conformances">ContextEnrichmentCoordinator fans out enrichment tasks via TaskGroup</div>
    </li>
    <li class="type-item">
      <span class="badge badge-class">pattern</span>
      <div class="name"><strong>Non-Destructive Reprocessing</strong></div>
      <div class="conformances">Reprocessing reuses existing item IDs to prevent duplicates</div>
    </li>
    <li class="type-item">
      <span class="badge badge-enum">pattern</span>
      <div class="name"><strong>HMAC-Signed Links</strong></div>
      <div class="conformances">DiverLinkWrapper signs URLs before storage; validated on ingestion</div>
    </li>
  </ul>
</div>

<div class="section">
  <h2 class="section-title">Technology Stack</h2>
  <table class="members-table">
    <tr><th>Layer</th><th>Technology</th></tr>
    <tr><td>UI Framework</td><td>SwiftUI (iOS 26+, macOS 26+, visionOS 26+)</td></tr>
    <tr><td>Persistence</td><td>SwiftData + CloudKit</td></tr>
    <tr><td>Computer Vision</td><td>Vision framework (subject detection, text recognition, barcode scanning)</td></tr>
    <tr><td>ML Inference</td><td>CoreML (SAM 2.1 Subject Sifting, Aesthetics Scoring)</td></tr>
    <tr><td>Generative AI</td><td>Apple SystemLanguageModel (SLM), MLX Swift (FastVLM 7B, CLaRa memory search)</td></tr>
    <tr><td>Location</td><td>MapKit, CLGeocoder, Foursquare Places API</td></tr>
    <tr><td>Weather</td><td>WeatherKit</td></tr>
    <tr><td>Camera</td><td>AVFoundation (AVCaptureSession)</td></tr>
    <tr><td>Music</td><td>MusicKit (Apple Music), Spotify Web API</td></tr>
    <tr><td>Intents</td><td>AppIntents framework, WidgetKit</td></tr>
    <tr><td>Networking</td><td>URLSession, WKWebView (metadata extraction)</td></tr>
    <tr><td>Security</td><td>Keychain Services, HMAC-SHA256 (link signing)</td></tr>
  </table>
</div>
"""
    )

    # Write all pages
    import os
    wiki_dir = os.path.dirname(os.path.abspath(__file__))
    for filename, content in pages.items():
        path = os.path.join(wiki_dir, filename)
        with open(path, "w") as f:
            f.write(content)
        print(f"Generated {filename}")

if __name__ == "__main__":
    generate_all()
