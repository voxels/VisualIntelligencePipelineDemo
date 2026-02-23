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
                HStack {
                    Label(docCtx.fileType.uppercased(), systemImage: "doc.text")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if let author = docCtx.author {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
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
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .textSelection(.enabled) // Allow user to select text natively
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }
}
