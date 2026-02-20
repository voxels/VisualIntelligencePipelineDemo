//
//  AgenticChatView.swift
//  VisualIntelligencePipeline
//
//  An iMessage-style chat interface for Agentic Search via CLaRa.
//

import SwiftUI
import SwiftData
import DiverKit

struct AgenticChatView: View {
    @StateObject var viewModel: AgenticChatViewModel
    @Environment(\.dismiss) private var dismiss
    @Query private var allItems: [ProcessedItem]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message, allItems: allItems)
                                    .id(message.id)
                            }
                            
                            if viewModel.isThinking {
                                HStack {
                                    ProgressView()
                                        .padding()
                                        .background(Color(UIColor.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .id("thinking")
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: viewModel.messages) { oldValue, newValue in
                        withAnimation {
                            if let last = newValue.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.isThinking) { oldValue, newValue in
                        if newValue {
                            withAnimation {
                                proxy.scrollTo("thinking", anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }
                
                HStack(alignment: .bottom) {
                    TextField("Ask your library...", text: $viewModel.inputText, axis: .vertical)
                        .lineLimit(1...5)
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .onSubmit {
                            viewModel.sendMessage()
                        }
                    
                    Button {
                        viewModel.sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                    }
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isThinking)
                }
                .padding()
            }
            .navigationTitle("Agentic Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

fileprivate struct MessageBubble: View {
    let message: AgenticChatMessage
    let allItems: [ProcessedItem]
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(message.text)
                    .foregroundStyle(message.isUser ? .white : .primary)
                
                if !message.citedDocumentIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sources:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        ForEach(message.citedDocumentIDs, id: \.self) { docID in
                            if let item = allItems.first(where: { $0.id == docID }) {
                                HStack {
                                    Image(systemName: "doc.text")
                                        .font(.caption)
                                    Text(item.title ?? "Untitled Document")
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .padding(6)
                                .background(Color(UIColor.tertiarySystemGroupedBackground))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .background(message.isUser ? Color.blue : Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            if !message.isUser {
                Spacer()
            }
        }
        .padding(.horizontal)
    }
}
