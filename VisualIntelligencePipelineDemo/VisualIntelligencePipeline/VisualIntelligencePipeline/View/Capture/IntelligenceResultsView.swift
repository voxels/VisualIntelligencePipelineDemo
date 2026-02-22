import SwiftUI
import DiverKit
#if os(iOS)
import UIKit
#endif

// MARK: - Intelligence Results View (Split Screen)

/// Intelligence Results View - Detailed results screen pushed from Capture View
struct IntelligenceResultsView: View {
    @Bindable var viewModel: VisualIntelligenceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isEnteringCustomContext = false
    @State private var customContextText = ""
    @State private var showingTextEditor = false // Toggle between image and text
    
    let onSave: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Location Bar at Top
                SessionLocationBar(viewModel: viewModel)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Image/TextEditor Section with Toggle
                        VStack(spacing: 12) {
                            // Toggle Buttons
                            HStack(spacing: 12) {
                                Button {
                                    withAnimation { showingTextEditor = false }
                                } label: {
                                    Text("Image")
                                        .font(.caption.bold())
                                        .foregroundStyle(showingTextEditor ? .white.opacity(0.6) : .white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(showingTextEditor ? Color.white.opacity(0.1) : Color.blue)
                                        .clipShape(Capsule())
                                }
                                
                                Button {
                                    withAnimation { showingTextEditor = true }
                                } label: {
                                    Text("Notes")
                                        .font(.caption.bold())
                                        .foregroundStyle(showingTextEditor ? .white : .white.opacity(0.6))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(showingTextEditor ? Color.blue : Color.white.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                            
                            // Content
                            if showingTextEditor {
                                TextEditor(text: Binding(
                                    get: { customContextText },
                                    set: { customContextText = $0 }
                                ))
                                .frame(height: 200)
                                .padding(12)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                                .foregroundStyle(.white)
                                .scrollContentBackground(.hidden)
                            } else if viewModel.sessionImages.count > 1 {
                                // Carousel of all session captures
                                TabView {
                                    ForEach(Array(viewModel.sessionImages.enumerated()), id: \.offset) { _, img in
                                        Image(uiImage: img)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .cornerRadius(12)
                                            .shadow(color: .black.opacity(0.3), radius: 10)
                                    }
                                }
                                .tabViewStyle(.page(indexDisplayMode: .automatic))
                                .frame(height: 200)
                            } else if let image = viewModel.capturedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 200)
                                    .cornerRadius(12)
                                    .shadow(color: .black.opacity(0.3), radius: 10)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Sectioned Grid of Buttons
                        VStack(spacing: 24) {
                            // Action Buttons Section
                            if !actionButtons.isEmpty {
                                buttonSection(title: "ACTIONS", buttons: actionButtons, columns: 2)
                            }
                            
                            // Context Buttons Section
                            if !contextButtons.isEmpty {
                                buttonSection(title: "CONTEXT", buttons: contextButtons, columns: 1, isContext: true)
                            }
                            
                            // Detected Buttons Section
                            if !detectedButtons.isEmpty {
                                buttonSection(title: "DETECTED", buttons: detectedButtons, columns: 2)
                            }
                            
                            // Commerce Intelligence Section
                            if hasCommerceData {
                                commerceSection
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 100) // Space for fixed save button
                }
                
                // Fixed Save Button at Bottom
                VStack(spacing: 0) {
                    Divider().background(Color.white.opacity(0.2))
                    
                    Button {
                        onSave()
                    } label: {
                        HStack(spacing: 12) {
                            if viewModel.isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.down.fill").font(.body.bold())
                                Text("Save Capture").fontWeight(.bold)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .glassCapsule()
                    }
                    .disabled(viewModel.isSaving)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .background(Color.black.opacity(0.95))
            }
        }
        .navigationTitle("Intelligence")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Dismiss") {
                    viewModel.shouldDismiss = true
                }
            }
        }
        .sheet(isPresented: $viewModel.showingPlaceSelection) {
            PlaceSelectionMapView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingDocumentView) {
            if let doc = viewModel.rectifiedDocument {
                DocumentDetailView(viewModel: viewModel, image: doc)
            }
        }
        .onAppear {
            // Initialize text editor with full transcript (OCR text + document text)
            if customContextText.isEmpty {
                // 1. Collect all OCR text lines from .text results
                let ocrLines = viewModel.results.compactMap { result -> String? in
                    if case .text(let text, _) = result {
                        return text
                    }
                    return nil
                }
                
                // 2. Collect document-specific text
                let documentLines = viewModel.results.compactMap { result -> String? in
                    if case .document(_, let text, _, _) = result {
                        return text
                    }
                    return nil
                }
                
                // 3. Combine: OCR text first (full transcript), then any additional document text
                var allText: [String] = []
                if !ocrLines.isEmpty {
                    allText.append(ocrLines.joined(separator: "\n"))
                }
                for docText in documentLines where !ocrLines.contains(docText) {
                    allText.append(docText)
                }
                
                let fullTranscript = allText.joined(separator: "\n\n")
                if !fullTranscript.isEmpty {
                    customContextText = fullTranscript
                }
            }
        }
        .alert("Add Context", isPresented: $isEnteringCustomContext) {
            TextField("E.g. Gift for Mom", text: $customContextText)
            Button("Cancel", role: .cancel) { }
            Button("Add") {
                viewModel.addUserContext(customContextText)
                customContextText = ""
            }
        } message: {
            Text("Add a custom label or purpose to this capture.")
        }
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func resultCard(for result: IntelligenceResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: result.icon)
                    .font(.title3)
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.8))
            
            Text(result.title)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
            
            let subtitle = result.subtitle
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func contextChip(text: String) -> some View {
        let isSelected = viewModel.selectedPurposes.contains(text)
        Button {
            withAnimation {
                if isSelected {
                    viewModel.selectedPurposes.remove(text)
                } else {
                    viewModel.selectedPurposes.insert(text)
                }
            }
        } label: {
            Text(text)
                .font(.caption.bold())
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white : Color.white.opacity(0.2))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
        }
    }
    
    private var allContexts: [String] {
        // Get purpose suggestions from results
        let suggestions: [String]
        if let purposeResult = viewModel.results.first(where: { if case .purpose = $0 { return true }; return false }),
           case .purpose(let statements) = purposeResult {
            suggestions = statements
        } else {
            suggestions = []
        }
        
        // Combine selected and unselected, remove duplicates
        let selected = Array(viewModel.selectedPurposes)
        let unselected = suggestions.filter { !viewModel.selectedPurposes.contains($0) }
        return (selected + unselected).sorted()
    }
    
    // MARK: - Button Categorization
    
    private var actionButtons: [(String, String, () -> Void)] {
        var buttons: [(String, String, () -> Void)] = []
        
        for result in viewModel.results {
            switch result {
            case .qr(let url):
                buttons.append(("QR Code", "qrcode", {
                    UIApplication.shared.open(url)
                }))
            case .richWeb(let url, _):
                buttons.append(("Open Link", "link", {
                    UIApplication.shared.open(url)
                }))
            case .document(let obs, _, _, let rectifiedData):
                buttons.append(("View Document", "doc.text", {
                    viewModel.handleDocumentSelection(obs, rectifiedImageData: rectifiedData)
                }))
            default:
                break
            }
        }
        
        return buttons
    }
    
    private var contextButtons: [(String, String, () -> Void)] {
        let contexts = allContexts
        return contexts.prefix(6).map { context in
            (context, "tag", {
                withAnimation {
                    if viewModel.selectedPurposes.contains(context) {
                        viewModel.selectedPurposes.remove(context)
                    } else {
                        viewModel.selectedPurposes.insert(context)
                    }
                }
            })
        }
    }
    
    private var detectedButtons: [(String, String, () -> Void)] {
        var buttons: [(String, String, () -> Void)] = []
        
        for result in viewModel.results {
            switch result {
            case .semantic(let label, _):
                buttons.append((label.capitalized, "eye", {
                    withAnimation {
                        if viewModel.selectedPurposes.contains(label) {
                            viewModel.selectedPurposes.remove(label)
                            if viewModel.sessionTitle == label { viewModel.sessionTitle = nil }
                        } else {
                            viewModel.selectedPurposes.insert(label)
                            viewModel.sessionTitle = label
                        }
                    }
                }))
            case .product(let code, _, _):
                let text = "Barcode: \(code)"
                buttons.append(("Barcode", "barcode", {
                    withAnimation {
                        if viewModel.selectedPurposes.contains(text) {
                            viewModel.selectedPurposes.remove(text)
                        } else {
                            viewModel.selectedPurposes.insert(text)
                        }
                    }
                }))
            case .siftedSubject(let mask, _, let label):
                if let label = label {
                    buttons.append((label, "viewfinder", {
                        withAnimation {
                            if viewModel.activeObservation != nil {
                                viewModel.activeObservation = nil
                            } else {
                                viewModel.activeObservation = mask
                            }
                        }
                    }))
                }
            default:
                break
            }
        }
        
        return buttons
    }
    
    // MARK: - Commerce Intelligence
    
    private var hasCommerceData: Bool {
        viewModel.results.contains { if case .product = $0 { return true }; return false }
    }
    
    @ViewBuilder
    private var commerceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cart.fill")
                    .foregroundStyle(.green)
                Text("COMMERCE")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            // Extract product info from results
            let productResult = viewModel.results.first { if case .product = $0 { return true }; return false }
            if case .product(let code, _, _) = productResult {
                ProductScoreAttachment(
                    productName: "Product (\(code))",
                    compositeScore: 0.0,
                    strategyScores: [],
                    recommendation: "Scoring…"
                )
                
                OwnershipButton(
                    productName: "Product",
                    barcode: code
                )
            }
        }
    }
    @ViewBuilder
    private func buttonSection(title: String, buttons: [(String, String, () -> Void)], columns: Int, isContext: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with optional regenerate button for CONTEXT
            if title == "CONTEXT" {
                HStack {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.6))
                    
                    Spacer()
                    
                    Button {
                        Task {
                            await viewModel.regenerateContextSuggestions(for: viewModel.selectedPlace)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            } else {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: columns), spacing: 12) {
                ForEach(0..<buttons.count, id: \.self) { index in
                    let button = buttons[index]
                    Button {
                        button.2()
                    } label: {
                        if isContext {
                            // Context buttons: no icon, multiline text, visual selection state
                            let isSelected = viewModel.selectedPurposes.contains(button.0)
                            Text(button.0)
                                .font(.caption.bold())
                                .foregroundStyle(isSelected ? .black : .white)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 8)
                                .background(isSelected ? Color.white : Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                                )
                        } else {
                            // Action/Detected buttons: icon + text with selection state
                            let isSelected = viewModel.selectedPurposes.contains(button.0) ||
                            viewModel.selectedPurposes.contains(where: { $0.contains(button.0) })
                            VStack(spacing: 8) {
                                Image(systemName: button.1)
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? .blue : .white.opacity(0.8))
                                
                                Text(button.0)
                                    .font(.caption.bold())
                                    .foregroundStyle(isSelected ? .blue : .white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var actionResults: [IntelligenceResult] {
        let documents = viewModel.results.filter { if case .document = $0 { return true }; return false }
        let others = viewModel.results.filter {
            if case .qr = $0 { return true }
            if case .richWeb = $0 { return true }
            return false
        }
        return documents + others
    }
    
    private var purposeSuggestions: [String] {
        guard let purposeResult = viewModel.results.first(where: { if case .purpose = $0 { return true }; return false }),
              case .purpose(let statements) = purposeResult else {
            return []
        }
        return statements.filter { !viewModel.selectedPurposes.contains($0) }
    }
    
    private func toggleContext(_ text: String) {
        withAnimation {
            if viewModel.selectedPurposes.contains(text) {
                viewModel.selectedPurposes.remove(text)
                if viewModel.sessionTitle == text { viewModel.sessionTitle = nil }
            } else {
                viewModel.selectedPurposes.insert(text)
                viewModel.sessionTitle = text
                viewModel.refineContext(with: text)
            }
        }
#if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
    }
    
    private func handleResultSelection(_ result: IntelligenceResult) {
        switch result {
        case .document(let obs, let text, _, let rectifiedData):
            viewModel.handleDocumentSelection(obs, text: text, rectifiedImageData: rectifiedData)
        case .qr(let url):
            UIApplication.shared.open(url)
        case .richWeb(let url, _):
            UIApplication.shared.open(url)
        default:
            break
        }
    }
}
