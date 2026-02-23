import SwiftUI
import DiverKit
import DiverShared

public struct DocumentProfileView: View {
    let item: ProcessedItem
    
    public init(item: ProcessedItem) {
        self.item = item
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Document Type / Info
            if let docCtx = item.documentContext {
                DocumentInfoView(context: docCtx)
                    .padding(.horizontal)
            }
            
            // Text Editor Section
            let showTextEditor = (item.transcription != nil && !item.transcription!.isEmpty) ||
                                 item.source == "ManualNote" ||
                                 (item.entityType == "document" && item.transcription != nil)
            
            if showTextEditor {
                TextEditorView(item: item)
                    .padding(.horizontal)
            }
            
            // Full Text / Transcription Copy Section
            if let text = item.transcription, !text.isEmpty {
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
                            print("📋 Copied text to clipboard: \(text.prefix(50))...")
                            #else
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(text, forType: .string)
                            #endif
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        
                        // Open URL
                        if let urlString = item.url, 
                           let url = URL(string: urlString),
                           !urlString.hasPrefix("secretatomics://") {
                            Button {
                                #if os(iOS)
                                UIApplication.shared.open(url)
                                #elseif os(macOS)
                                NSWorkspace.shared.open(url)
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
                    .background(Color(normalize(color: .secondarySystemBackground)))
                    .cornerRadius(12)
                }
                .padding()
                .background(Color(normalize(color: .secondarySystemGroupedBackground)))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
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
        .padding()
        .background(Color(normalize(color: .secondarySystemGroupedBackground)))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
