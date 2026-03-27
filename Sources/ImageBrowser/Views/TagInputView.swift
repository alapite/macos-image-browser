import SwiftUI

/// Tag input view with autocomplete suggestions and mode toggle.
///
/// Provides a TextField with popover-based autocomplete for tag selection.
/// Supports both add and remove modes for safe batch tagging operations.
///
/// Design patterns:
/// - TextField + Popover for autocomplete (RESEARCH.md Pattern 1)
/// - Prefix matching for performance (Pitfall 1 prevention)
/// - Mode toggle prevents accidental tag removals
struct TagInputView: View {
    // MARK: - Environment

    @EnvironmentObject var tagStore: TagStore

    // MARK: - Bindings

    /// Selected images for multi-select batch tagging
    @Binding var selectedImages: [DisplayImage]

    // MARK: - State

    /// Current text input in the tag field
    @State private var inputText: String = ""

    /// Controls autocomplete popover visibility
    @State private var showSuggestions: Bool = false

    /// Tag application mode (add or remove)
    @State private var tagMode: TagMode = .add

    /// Temporary selection of tags before applying
    @State private var selectedTags: Set<String> = []

    /// Status message for user feedback
    @State private var statusMessage: String?

    // MARK: - Computed Properties

    /// Filtered autocomplete suggestions based on input text
    ///
    /// Returns up to 10 tags that start with the input text (prefix matching).
    /// Case-insensitive filtering for user convenience.
    private var filteredSuggestions: [String] {
        guard !inputText.isEmpty else { return [] }

        return tagStore.allTags
            .filter { $0.localizedCaseInsensitiveContains(inputText) }
            .prefix(10)
            .map { $0 }
    }

    /// Whether the tag input should be enabled
    ///
    /// Input is only enabled when images are selected for batch tagging.
    private var isInputEnabled: Bool {
        !selectedImages.isEmpty
    }

    private var hasPendingInput: Bool {
        !TagCommitParser.committedTags(from: inputText, existingTags: []).isEmpty
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            // Mode toggle button
            modeToggleButton

            // Tag input field
            TextField(
                tagMode == .add ? "Add tags..." : "Remove tags...",
                text: $inputText
            )
            .disabled(!isInputEnabled)
            .onChange(of: inputText) { _, newValue in
                if newValue.contains(",") || newValue.contains("\n") {
                    commitPendingInputTags()
                    return
                }

                showSuggestions = !newValue.isEmpty
            }
            .onSubmit {
                commitPendingInputTags()
            }
            .popover(isPresented: $showSuggestions, arrowEdge: .bottom) {
                suggestionsPopover
            }

            // Apply button
            applyButton
        }
        .overlay(alignment: .bottomTrailing) {
            if let statusMessage = statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .transition(.opacity)
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
            }
        }
        .onChange(of: statusMessage) { _, newMessage in
            guard let newMessage else { return }

            // Auto-hide status message after delay
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    if statusMessage == newMessage {
                        withAnimation {
                            statusMessage = nil
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    /// Mode toggle button (Add/Remove)
    private var modeToggleButton: some View {
        Button(action: { toggleMode() }) {
            Label(
                tagMode.displayName,
                systemImage: tagMode == .add ? "plus.circle" : "minus.circle"
            )
            .help("Toggle between add and remove mode")
        }
        .disabled(!isInputEnabled)
        .buttonStyle(.borderless)
    }

    /// Apply button to add/remove tags to selected images
    private var applyButton: some View {
        Button(action: { applyTags() }) {
            Label("Apply", systemImage: "checkmark.circle.fill")
        }
        .disabled(!isInputEnabled || (selectedTags.isEmpty && !hasPendingInput))
        .buttonStyle(.borderedProminent)
    }

    /// Autocomplete suggestions popover
    private var suggestionsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(filteredSuggestions, id: \.self) { tag in
                Button(action: { selectTag(tag) }) {
                    HStack {
                        Text(tag)
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedTags.contains(tag) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)

                Divider()
            }
        }
        .frame(maxWidth: 200, maxHeight: 200)
    }

    // MARK: - Actions

    /// Toggle between add and remove mode
    private func toggleMode() {
        withAnimation {
            tagMode = tagMode == .add ? .remove : .add
        }
    }

    /// Select a tag from autocomplete suggestions
    /// - Parameter tag: Tag name to select
    private func selectTag(_ tag: String) {
        selectedTags.insert(tag)
        inputText = ""

        // Show current selection in input
        updateInputText()
    }

    /// Apply tags to selected images
    private func applyTags() {
        commitPendingInputTags()
        guard !selectedTags.isEmpty else { return }

        let tagsToApply = selectedTags

        let imageUrls = selectedImages.map { $0.url.standardizedFileURL.absoluteString }

        Task {
            do {
                let (success, failed) = try await performBatchOperation(
                    tags: tagsToApply,
                    imageUrls: imageUrls
                )

                await MainActor.run {
                    let action = tagMode == .add ? "Added" : "Removed"
                    if failed == 0 {
                        statusMessage = "\(action) \(tagsToApply.count) tag(s) on \(success) image(s)"
                    } else {
                        statusMessage = "\(action) \(tagsToApply.count) tag(s): \(success) image(s) succeeded, \(failed) failed"
                    }

                    // Clear selection after successful apply
                    selectedTags.removeAll()
                    inputText = ""
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func commitPendingInputTags() {
        selectedTags = TagCommitParser.committedTags(
            from: inputText,
            existingTags: selectedTags
        )
        inputText = ""
        showSuggestions = false
    }

    /// Perform batch tag operation based on current mode
    /// - Parameters:
    ///   - tags: Tags to add/remove
    ///   - imageUrls: Image URLs to process
    /// - Returns: Tuple with (successCount, failureCount)
    private func performBatchOperation(
        tags: Set<String>,
        imageUrls: [String]
    ) async throws -> (success: Int, failed: Int) {
        if tagMode == .add {
            return try await tagStore.addTagsToImages(tags, to: imageUrls)
        } else {
            return try await tagStore.removeTagsFromImages(tags, from: imageUrls)
        }
    }

    /// Update input text to reflect current tag selection
    private func updateInputText() {
        inputText = selectedTags
            .sorted()
            .joined(separator: ", ")
    }
}

// MARK: - Tag Mode Enum

/// Tag application mode
extension TagInputView {
    enum TagMode {
        case add
        case remove

        /// Display name for the mode
        var displayName: String {
            switch self {
            case .add: return "Add"
            case .remove: return "Remove"
            }
        }
    }
}

#if ENABLE_PREVIEWS
#Preview {
    TagInputView(
        selectedImages: .constant([])
    )
    .environmentObject(PreviewContainer.shared.tagStore)
}
#endif
