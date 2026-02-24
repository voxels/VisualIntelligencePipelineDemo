//
//  AgenticChatView.swift
//  DiverUI
//
//  iMessage-style chat interface for Agentic Search via CLaRa.
//  Cross-platform: iOS, macOS, visionOS.
//
//  Navigation integration:
//  - Pass `onItemTapped` closure; the shell (SidebarView / MacContentView)
//    handles platform-appropriate navigation to ReferenceDetailView.
//

import SwiftUI
import SwiftData
import DiverKit

// MARK: - AgenticChatView

public struct AgenticChatView: View {
    @StateObject public var viewModel: AgenticChatViewModel
    public let onDismiss: (() -> Void)?
    public let onItemTapped: ((ProcessedItem) -> Void)?

    @Query private var allItems: [ProcessedItem]

    public init(
        viewModel: AgenticChatViewModel,
        onDismiss: (() -> Void)? = nil,
        onItemTapped: ((ProcessedItem) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onDismiss = onDismiss
        self.onItemTapped = onItemTapped
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Message list ──────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageBubble(
                                message: message,
                                allItems: allItems,
                                onItemTapped: onItemTapped
                            )
                            .id(message.id)
                        }

                        if viewModel.isThinking {
                            HStack {
                                ProgressView()
                                    .padding(12)
                                    .background(.secondary.opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("thinking")
                        }
                    }
                    .padding(.vertical)
                }
                .onChange(of: viewModel.messages) { _, newValue in
                    withAnimation {
                        proxy.scrollTo(newValue.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.isThinking) { _, thinking in
                    if thinking {
                        withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                    }
                }
            }

            Divider()

            // ── Error ─────────────────────────────────────────────────────
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 6)
            }

            // ── Input bar ─────────────────────────────────────────────────
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask your library…", text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(12)
                    .background(.secondary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onSubmit { viewModel.sendMessage() }

                Button { viewModel.sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? .gray : .blue
                        )
                }
                .disabled(
                    viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.isThinking
                )
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding()
        }
        .navigationTitle("CLaRa")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let dismiss = onDismiss {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
        }
        #endif
    }
}

// MARK: - Message Bubble

public struct ChatMessageBubble: View {
    public let message: AgenticChatMessage
    public let allItems: [ProcessedItem]
    public let onItemTapped: ((ProcessedItem) -> Void)?

    @State private var sourcesExpanded = false

    public init(
        message: AgenticChatMessage,
        allItems: [ProcessedItem],
        onItemTapped: ((ProcessedItem) -> Void)? = nil
    ) {
        self.message = message
        self.allItems = allItems
        self.onItemTapped = onItemTapped
    }

    public var body: some View {
        HStack {
            if message.isUser { Spacer() }

            VStack(alignment: .leading, spacing: 8) {
                Text(message.text)
                    .foregroundStyle(message.isUser ? .white : .primary)
                    .textSelection(.enabled)

                // ── Cited sources ─────────────────────────────────────────
                if !message.isUser, !message.citedDocumentIDs.isEmpty {
                    let matched = message.citedDocumentIDs.compactMap { id in
                        allItems.first(where: { $0.id == id })
                    }
                    if !matched.isEmpty {
                        DisclosureGroup(isExpanded: $sourcesExpanded) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(matched) { item in
                                    Button {
                                        onItemTapped?(item)
                                    } label: {
                                        ChatCitationRow(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } label: {
                            Label("\(matched.count) Sources", systemImage: "doc.on.doc")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.blue)
                        }
                        .tint(.blue)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(12)
            .background(
                message.isUser
                    ? Color.blue
                    : Color.secondary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )

            if !message.isUser { Spacer() }
        }
        .padding(.horizontal)
    }
}

// MARK: - Citation Row

private struct ChatCitationRow: View {
    let item: ProcessedItem

    var body: some View {
        HStack(spacing: 8) {
            DiverThumbnail(data: item.rawPayload, fallbackIcon: "doc.text", size: 32, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title ?? "Untitled")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let loc = item.location, !loc.isEmpty {
                    Text(loc)
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
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
