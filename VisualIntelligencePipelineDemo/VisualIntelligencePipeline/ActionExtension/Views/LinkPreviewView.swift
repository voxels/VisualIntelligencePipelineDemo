//
//  LinkPreviewView.swift
//  ActionExtension
//
//  Created by Claude on 12/24/25.
//

import SwiftUI

struct LinkPreviewView: View {
    let url: URL
    @ObservedObject var viewModel: MetadataViewModel
    let suggestedTags: [String]

    @State private var selectedTags: Set<String> = []
    @State private var showingCustomTagInput = false
    @State private var customTag = ""
    @State private var isProcessing = false

    let onSave: ([String]) async -> Void
    let onSaveAndShare: ([String]) async -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Link preview card
                    LinkCard(metadata: viewModel.metadata)

                    // Suggested tags
                    if !suggestedTags.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Suggested Tags")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            TagGrid(
                                tags: suggestedTags,
                                selectedTags: $selectedTags
                            )
                        }
                    }

                    // Custom tag input
                    VStack(alignment: .leading, spacing: 8) {
                        if showingCustomTagInput {
                            HStack {
                                TextField("Custom tag", text: $customTag)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()

                                Button("Add") {
                                    addCustomTag()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(customTag.isEmpty)
                            }
                        } else {
                            Button(action: { showingCustomTagInput = true }) {
                                Label("Add Custom Tag", systemImage: "plus.circle")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                    }

                    // Selected tags display
                    if !selectedTags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected Tags")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            FlowLayout(spacing: 8) {
                                ForEach(Array(selectedTags).sorted(), id: \.self) { tag in
                                    TagChip(tag: tag, isSelected: true) {
                                        selectedTags.remove(tag)
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    // Action buttons
                    VStack(spacing: 12) {
                        Button(action: { handleSave() }) {
                            Label("Save to Diver", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isProcessing)

                        Button(action: { handleSaveAndShare() }) {
                            Label("Save & Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isProcessing)
                    }

                    if isProcessing {
                        ProgressView("Processing...")
                            .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Save to Diver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func addCustomTag() {
        guard let validated = SmartTagGenerator.validateTag(customTag) else {
            return
        }
        selectedTags.insert(validated)
        customTag = ""
        showingCustomTagInput = false
    }

    private func handleSave() {
        isProcessing = true
        Task {
            await onSave(Array(selectedTags))
            isProcessing = false
        }
    }

    private func handleSaveAndShare() {
        isProcessing = true
        Task {
            await onSaveAndShare(Array(selectedTags))
            isProcessing = false
        }
    }
}

// MARK: - Link Card Component

struct LinkCard: View {
    let metadata: LinkMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "link.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata.title ?? "Link")
                        .font(.headline)
                        .lineLimit(2)

                    Text(metadata.domain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let description = metadata.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Tag Grid Component

struct TagGrid: View {
    let tags: [String]
    @Binding var selectedTags: Set<String>

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                TagChip(
                    tag: tag,
                    isSelected: selectedTags.contains(tag)
                ) {
                    toggleTag(tag)
                }
            }
        }
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

// MARK: - Tag Chip Component

struct TagChip: View {
    let tag: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(tag)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if isSelected {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.tertiarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout (Tag Wrapping)

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

// MARK: - Preview

#Preview {
    LinkPreviewView(
        url: URL(string: "https://developer.apple.com/documentation/swiftui")!,
        viewModel: MetadataViewModel(
            metadata: LinkMetadata(
                url: URL(string: "https://developer.apple.com")!,
                title: "SwiftUI Documentation",
                description: "Build apps across all Apple platforms with SwiftUI",
                imageURL: nil
            )
        ),
        suggestedTags: ["docs", "dev", "apple", "work"],
        onSave: { tags in
            print("Save with tags: \(tags)")
        },
        onSaveAndShare: { tags in
            print("Save and share with tags: \(tags)")
        },
        onDismiss: {
            print("Dismissed")
        }
    )
}
