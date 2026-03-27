import SwiftUI

/// Dedicated manager for creating, renaming, deleting, and merging tags.
struct KeywordManager: View {
    @EnvironmentObject var tagStore: TagStore

    @State private var selectedTag: String?
    @State private var newTagName: String = ""
    @State private var renameTagName: String = ""
    @State private var mergeDestination: String = ""
    @State private var isPerformingAction = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var tagPendingDeletion: String?

    private var sortedTags: [String] {
        tagStore.allTags.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private var mergeDestinations: [String] {
        guard let selectedTag else { return [] }
        return sortedTags.filter { $0.caseInsensitiveCompare(selectedTag) != .orderedSame }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            tagsList
            actionsPanel
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 420)
        .onChange(of: selectedTag) { _, newValue in
            renameTagName = newValue ?? ""
            if !mergeDestinations.contains(where: { $0.caseInsensitiveCompare(mergeDestination) == .orderedSame }) {
                mergeDestination = mergeDestinations.first ?? ""
            }
            clearMessages()
        }
        .onChange(of: sortedTags) { _, _ in
            guard let selectedTag else { return }
            if !sortedTags.contains(where: { $0.caseInsensitiveCompare(selectedTag) == .orderedSame }) {
                self.selectedTag = nil
            }
        }
        .confirmationDialog(
            "Delete Tag?",
            isPresented: deleteConfirmationIsPresented,
            presenting: tagPendingDeletion
        ) { tag in
            Button("Delete Tag", role: .destructive) {
                deleteSelectedTag(named: tag)
            }

            Button("Cancel", role: .cancel) { }
        } message: { tag in
            Text("\"\(tag)\" will be removed from the library and from any images that use it.")
        }
    }

    private var tagsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)

            List(sortedTags, id: \.self, selection: $selectedTag) { tag in
                Text(tag)
                    .tag(tag)
            }
            .frame(minWidth: 220)

            Text("\(sortedTags.count) total")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            createSection
            Divider()
            renameSection
            Divider()
            deleteSection
            Divider()
            mergeSection
            Divider()
            statusSection
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create")
                .font(.headline)

            HStack {
                TextField("New tag", text: $newTagName)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    createTag()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPerformingAction || trimmed(newTagName).isEmpty)
            }
        }
    }

    private var renameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rename")
                .font(.headline)

            HStack {
                TextField("New name", text: $renameTagName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(selectedTag == nil)

                Button("Rename") {
                    renameSelectedTag()
                }
                .buttonStyle(.bordered)
                .disabled(!canRename)
            }
        }
    }

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Delete")
                .font(.headline)

            Button("Delete Selected Tag", role: .destructive) {
                tagPendingDeletion = selectedTag
            }
            .buttonStyle(.bordered)
            .disabled(isPerformingAction || selectedTag == nil)
        }
    }

    private var mergeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Merge")
                .font(.headline)

            HStack {
                Picker("Into", selection: $mergeDestination) {
                    if mergeDestinations.isEmpty {
                        Text("No destination available").tag("")
                    } else {
                        ForEach(mergeDestinations, id: \.self) { tag in
                            Text(tag).tag(tag)
                        }
                    }
                }
                .pickerStyle(.menu)
                .disabled(selectedTag == nil || mergeDestinations.isEmpty)

                Button("Merge") {
                    mergeSelectedTag()
                }
                .buttonStyle(.bordered)
                .disabled(!canMerge)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isPerformingAction {
                ProgressView("Working...")
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var canRename: Bool {
        guard let selectedTag else { return false }
        let trimmedRename = trimmed(renameTagName)
        guard !trimmedRename.isEmpty else { return false }
        return selectedTag.caseInsensitiveCompare(trimmedRename) != .orderedSame && !isPerformingAction
    }

    private var canMerge: Bool {
        guard selectedTag != nil else { return false }
        return !mergeDestination.isEmpty && !isPerformingAction
    }

    private func createTag() {
        let name = trimmed(newTagName)
        guard !name.isEmpty else { return }

        performAction(successMessage: "Created tag \"\(name)\".") {
            try await tagStore.addTag(name)
            await MainActor.run {
                selectedTag = name
                newTagName = ""
            }
        }
    }

    private func renameSelectedTag() {
        guard let selectedTag else { return }
        let newName = trimmed(renameTagName)
        guard !newName.isEmpty else { return }

        performAction(successMessage: "Renamed \"\(selectedTag)\" to \"\(newName)\".") {
            try await tagStore.renameTag(from: selectedTag, to: newName)
            await MainActor.run {
                self.selectedTag = newName
            }
        }
    }

    private func deleteSelectedTag(named tag: String) {
        tagPendingDeletion = nil

        performAction(successMessage: "Deleted tag \"\(tag)\".") {
            try await tagStore.removeTag(tag)
            await MainActor.run {
                self.selectedTag = nil
                renameTagName = ""
                mergeDestination = ""
            }
        }
    }

    private func mergeSelectedTag() {
        guard let selectedTag else { return }
        let destination = trimmed(mergeDestination)
        guard !destination.isEmpty else { return }

        performAction(successMessage: "Merged \"\(selectedTag)\" into \"\(destination)\".") {
            try await tagStore.mergeTags(source: selectedTag, destination: destination)
            await MainActor.run {
                self.selectedTag = destination
            }
        }
    }

    private func performAction(
        successMessage: String,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        clearMessages()
        isPerformingAction = true

        Task {
            do {
                try await operation()
                await MainActor.run {
                    statusMessage = successMessage
                    isPerformingAction = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isPerformingAction = false
                }
            }
        }
    }

    private func clearMessages() {
        statusMessage = nil
        errorMessage = nil
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { tagPendingDeletion != nil },
            set: { newValue in
                if !newValue {
                    tagPendingDeletion = nil
                }
            }
        )
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if ENABLE_PREVIEWS
#Preview {
    KeywordManager()
        .environmentObject(PreviewContainer.shared.tagStore)
}
#endif
