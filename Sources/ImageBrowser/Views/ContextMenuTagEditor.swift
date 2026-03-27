import SwiftUI

struct ContextMenuTagEditor: View {
    @EnvironmentObject var tagStore: TagStore
    @Environment(\.dismiss) private var dismiss

    let targetImageURLs: [String]

    @State private var inputText: String = ""
    @State private var selectedTags: Set<String> = []
    @State private var showSuggestions = false
    @State private var statusMessage: String?
    @State private var isLoading: Bool = true

    private var filteredSuggestions: [String] {
        guard !inputText.isEmpty else { return [] }

        return tagStore.allTags
            .filter { $0.localizedCaseInsensitiveContains(inputText) }
            .prefix(12)
            .map { $0 }
    }

    private var hasPendingInput: Bool {
        !ContextMenuTaggingModel.committedTags(from: inputText, existingTags: []).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Tags")
                .font(.headline)

            Text("Applying to \(targetImageURLs.count) image\(targetImageURLs.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("Type tags and press Enter", text: $inputText)
                .onChange(of: inputText) { _, newValue in
                    if newValue.contains(",") || newValue.contains("\n") {
                        commitPendingInputTags()
                    } else {
                        showSuggestions = !newValue.isEmpty
                    }
                }
                .onSubmit {
                    commitPendingInputTags()
                }
                .popover(isPresented: $showSuggestions, arrowEdge: .bottom) {
                    suggestionsPopover
                }

            selectedTagsView

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .modalKeyboardShortcut(ModalKeyboardShortcuts.role(for: .contextMenuTagEditorCancel))

                Button("Apply") {
                    applyTags()
                }
                .modalKeyboardShortcut(ModalKeyboardShortcuts.role(for: .contextMenuTagEditorApply))
                .buttonStyle(.borderedProminent)
                .disabled(selectedTags.isEmpty && !hasPendingInput)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .onAppear {
            loadExistingTags()
        }
    }

    /// Load existing tags for target images when editor opens
    private func loadExistingTags() {
        guard !targetImageURLs.isEmpty else { return }

        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }

            if targetImageURLs.count == 1 {
                selectedTags = await tagStore.tagsForImage(targetImageURLs[0])
            } else {
                var allTags: Set<String> = []
                for url in targetImageURLs {
                    let tags = await tagStore.tagsForImage(url)
                    if allTags.isEmpty {
                        allTags = tags
                    } else {
                        allTags = allTags.intersection(tags)
                    }
                }
                selectedTags = allTags
            }
        }
    }

    private var selectedTagsView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(selectedTags).sorted(), id: \.self) { tag in
                    HStack(spacing: 6) {
                        Text(tag)
                            .lineLimit(1)

                        Button {
                            selectedTags.remove(tag)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.quaternaryLabelColor).opacity(0.18))
                    .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 80, maxHeight: 180)
    }

    private var suggestionsPopover: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredSuggestions, id: \.self) { tag in
                    Button {
                        selectedTags.insert(tag)
                        inputText = ""
                        showSuggestions = false
                    } label: {
                        HStack {
                            Text(tag)
                                .lineLimit(1)
                            Spacer()
                            if selectedTags.contains(tag) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                    Divider()
                }
            }
        }
        .frame(width: 320, height: 220)
    }

    private func commitPendingInputTags() {
        selectedTags = ContextMenuTaggingModel.committedTags(from: inputText, existingTags: selectedTags)
        inputText = ""
        showSuggestions = false
    }

    private func applyTags() {
        commitPendingInputTags()
        guard !selectedTags.isEmpty else { return }

        let tagsToApply = selectedTags
        Task {
            do {
                let result = try await tagStore.addTagsToImages(tagsToApply, to: targetImageURLs)
                await MainActor.run {
                    if result.failed == 0 {
                        statusMessage = "Added \(tagsToApply.count) tag(s) to \(result.success) image record(s)."
                    } else {
                        statusMessage = "Added with partial failures: \(result.failed)."
                    }
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
