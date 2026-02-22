import SwiftUI
import DiverKit
import WebKit
#if os(iOS)
import UIKit
#endif

struct DocumentDetailView: View {
    var viewModel: VisualIntelligenceViewModel
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var hasSaved = false
    
    // OCR Text Editing State
    @State private var editableText: String = ""
    @State private var isTextExpanded: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Image Section
                ZStack {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                }
                .frame(maxHeight: isTextExpanded ? UIScreen.main.bounds.height * 0.4 : .infinity)
                
                // OCR Text Section
                if !editableText.isEmpty || viewModel.rectifiedDocumentText != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        // Header with toggle
                        HStack {
                            Text("Recognized Text")
                                .font(.headline)
                                .foregroundStyle(.white)
                            
                            Spacer()
                            
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isTextExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(isTextExpanded ? "Collapse" : "Expand")
                                        .font(.caption)
                                    Image(systemName: isTextExpanded ? "chevron.down" : "chevron.up")
                                }
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .glassEffect()
                            }
                        }
                        .padding(.horizontal)
                        
                        if isTextExpanded {
                            // Editable Text Area
                            TextEditor(text: $editableText)
                                .scrollContentBackground(.hidden)
                                .background(Color.white.opacity(0.1))
                                .foregroundStyle(.white)
                                .font(.body)
                                .frame(minHeight: 150, maxHeight: 300)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                                .padding(.horizontal)
                            
                            // Copy button
                            HStack {
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = editableText
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Label("Copy Text", systemImage: "doc.on.doc")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .glassEffect()
                                }
                                .padding(.horizontal)
                            }
                        } else {
                            // Preview (collapsed state)
                            Text(editableText.prefix(100) + (editableText.count > 100 ? "..." : ""))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.9))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .background(Color.black)
            .navigationTitle("Scanned Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Scanned Document", image: Image(uiImage: image)))
                }
            }
            .onAppear {
                // Initialize editable text from ViewModel
                editableText = viewModel.rectifiedDocumentText ?? ""
                // Auto-expand if there's text to show
                if !editableText.isEmpty {
                    isTextExpanded = true
                }
            }
        }
    }
}

// MARK: - WebView Helper
struct WebView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            let request = URLRequest(url: url)
            uiView.load(request)
        }
    }
}

struct FullScreenImageView: View {
    let image: UIImage // Fallback/Single
    var sessionImages: [UIImage] = []
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedImage: UIImage?
    
    init(image: UIImage, sessionImages: [UIImage] = []) {
        self.image = image
        self.sessionImages = sessionImages
        _selectedImage = State(initialValue: image)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if !sessionImages.isEmpty {
                TabView(selection: $selectedImage) {
                    ForEach(sessionImages, id: \.self) { img in
                        GeometryReader { proxy in
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                        .tag(img as UIImage?)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            } else {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            
            // Interaction overlay
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .padding()
                            .shadow(radius: 5)
                    }
                    Spacer()
                }
                Spacer()
            }
        }
        .ignoresSafeArea()
    }
}
