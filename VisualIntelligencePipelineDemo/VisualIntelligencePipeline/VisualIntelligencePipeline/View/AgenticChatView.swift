//
//  AgenticChatView.swift
//  VisualIntelligencePipeline
//
//  An iMessage-style chat interface for Agentic Search via CLaRa.
//  Lives in the content (middle) pane of the NavigationSplitView.
//  Tapping cited items navigates to their ReferenceDetailView in the detail pane.
//

import SwiftUI
import SwiftData
import DiverKit

struct AgenticChatView: View {
    @StateObject var viewModel: AgenticChatViewModel
    @ObservedObject var navigationManager: NavigationManager
    @Query private var allItems: [ProcessedItem]
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                allItems: allItems,
                                onItemTapped: { item in
                                    navigationManager.selection = item
                                }
                            )
                            .id(message.id)
                        }
                        
                        if viewModel.isThinking {
                            HStack {
                                ProgressView()
                                    .padding(12)
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
        .navigationTitle("CLaRa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    navigationManager.showingAgenticChat = false
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
    }
}

fileprivate struct MessageBubble: View {
    let message: AgenticChatMessage
    let allItems: [ProcessedItem]
    let onItemTapped: (ProcessedItem) -> Void
    @State private var sourcesExpanded = false
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(message.text)
                    .foregroundStyle(message.isUser ? .white : .primary)
                    .textSelection(.enabled)
                
                if !message.isUser, !message.citedDocumentIDs.isEmpty {
                    let matchedItems = message.citedDocumentIDs.compactMap { docID in
                        allItems.first(where: { $0.id == docID })
                    }
                    
                    if !matchedItems.isEmpty {
                        DisclosureGroup(isExpanded: $sourcesExpanded) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(matchedItems) { item in
                                    Button {
                                        onItemTapped(item)
                                    } label: {
                                        HStack(spacing: 8) {
                                            if let data = item.rawPayload,
                                               let uiImage = UIImage(data: data) {
                                                Image(uiImage: uiImage)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 32, height: 32)
                                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                            } else {
                                                Image(systemName: "doc.text")
                                                    .font(.caption)
                                                    .frame(width: 32, height: 32)
                                                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(item.title ?? "Untitled")
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                    .lineLimit(1)
                                                if let location = item.location, !location.isEmpty {
                                                    Text(location)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(8)
                                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                                        .cornerRadius(10)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } label: {
                            Label("\(matchedItems.count) Sources", systemImage: "doc.on.doc")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.blue)
                        }
                        .tint(.blue)
                        .padding(.top, 4)
                    }
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
