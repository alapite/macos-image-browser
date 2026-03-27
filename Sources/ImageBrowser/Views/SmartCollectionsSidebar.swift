import SwiftUI

/// Sidebar section for smart collections management.
///
/// Displays a collapsible list of smart collections with:
/// - Section header with "New Smart Collection" button
/// - Collection list with image counts
/// - Context menu for Edit/Delete actions
/// - Selection highlighting for active collection
///
/// Uses DisclosureGroup pattern matching FilterPopover structure.
struct SmartCollectionsSidebar: View {
    @EnvironmentObject var collectionStore: CollectionStore
    @EnvironmentObject var filterStore: FilterStore

    /// Disclosure expansion state
    @State private var isExpanded: Bool = true

    /// Show new collection form
    @State private var showingNewCollectionForm: Bool = false

    /// Collection being edited (nil = no edit in progress)
    @State private var editingCollection: SmartCollection? = nil
    @State private var collectionPendingDeletion: SmartCollection? = nil
    @State private var deletionErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header with "New Smart Collection" button
            header

            Divider()

            // Collapsible collections list
            collectionsList
        }
        .sheet(isPresented: $showingNewCollectionForm) {
            // New collection form
            SmartCollectionForm()
                .environmentObject(collectionStore)
        }
        .sheet(item: $editingCollection) { collection in
            // Edit collection form
            SmartCollectionForm(collectionToEdit: collection)
                .environmentObject(collectionStore)
        }
        .confirmationDialog(
            "Delete Smart Collection?",
            isPresented: deleteConfirmationIsPresented,
            presenting: collectionPendingDeletion
        ) { collection in
            Button("Delete Collection", role: .destructive) {
                Task {
                    await deleteCollection(collection)
                }
            }

            Button("Cancel", role: .cancel) { }
        } message: { collection in
            Text("\"\(collection.name)\" will be removed from the sidebar. This can’t be undone.")
        }
        .alert("Couldn’t Delete Collection", isPresented: deletionErrorIsPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deletionErrorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Header

    /// Section header with title and "New Smart Collection" button
    private var header: some View {
        HStack {
            Button(action: {
                withAnimation {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("Smart Collections")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // "New Smart Collection" button (plus icon)
            Button(action: {
                showingNewCollectionForm = true
            }) {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("New Smart Collection")
            .accessibilityLabel("New Smart Collection")
            .accessibilityIdentifier("smart-collections-new-button")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Collections List

    /// Collapsible list of smart collections
    private var collectionsList: some View {
        Group {
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    if shouldShowResetToAll {
                        resetToAllButton
                            .padding(.bottom, 6)
                    }

                    if collectionStore.collections.isEmpty {
                        // Empty state
                        emptyCollectionsState
                    } else {
                        // Collection list
                        ForEach(collectionStore.collections) { collection in
                            collectionRow(collection)
                        }
                    }
                }
                .padding(.leading, 16)
            }
        }
    }

    private var shouldShowResetToAll: Bool {
        collectionStore.activeCollection != nil || filterStore.isActive
    }

    private var resetToAllButton: some View {
        Button {
            clearAllFiltersAndCollection(filterStore: filterStore, collectionStore: collectionStore)
        } label: {
            Label("Show All Images", systemImage: "line.3.horizontal.decrease.circle.badge.xmark")
                .font(.caption)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .help("Clear active collection and all filters")
    }

    /// Empty state when no collections exist
    private var emptyCollectionsState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No collections")
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("smart-collections-empty-label")

            Button("Create your first collection") {
                showingNewCollectionForm = true
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(.vertical, 8)
    }

    /// Single collection row with name, count, and context menu.
    ///
    /// **Interaction Pattern (Single-Click Toggle):**
    /// - First click on inactive collection → Applies collection (shows matching images)
    /// - Second click on same collection → Clears selection (shows all images)
    /// - Click on different collection → Switches to new collection immediately
    ///
    /// This toggle pattern is implemented in `CollectionStore.setActiveCollection(_:)`
    /// and provides immediate, single-click interaction without focus hacks.
    private func collectionRow(_ collection: SmartCollection) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.badge.gearshape")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("\(collection.name) (\(collection.imageCount))")
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            if isCollectionActive(collection) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .accessibilityIdentifier("smart-collection-active-indicator-\(collection.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            isCollectionActive(collection)
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
        .onTapGesture {
            collectionStore.setActiveCollection(collection)
        }
        .accessibilityRepresentation {
            HStack(spacing: 6) {
                Button {
                    collectionStore.setActiveCollection(collection)
                } label: {
                    Text(collection.name)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("smart-collection-activate-\(collection.id)")
                .accessibilityLabel(collection.name)
                .accessibilityValue("\(collection.imageCount) image\(collection.imageCount == 1 ? "" : "s"), \(isCollectionActive(collection) ? "Active" : "Inactive")")

                if isCollectionActive(collection) {
                    Image(systemName: "chevron.right")
                        .accessibilityIdentifier("smart-collection-active-indicator-\(collection.id)")
                }
            }
        }
        .contextMenu {
            Button("Edit Collection") {
                editingCollection = collection
            }

            Divider()

            Button("Delete Collection", role: .destructive) {
                collectionPendingDeletion = collection
            }
        }
        .help(collection.name)
    }

    private func isCollectionActive(_ collection: SmartCollection) -> Bool {
        collectionStore.activeCollection?.id == collection.id
    }

    // MARK: - Actions

    /// Delete a collection with confirmation
    /// - Parameter collection: Collection to delete
    private func deleteCollection(_ collection: SmartCollection) async {
        do {
            try await collectionStore.deleteCollection(collection)
            collectionPendingDeletion = nil

            // If deleted collection was active, clear active collection
            if collectionStore.activeCollection?.id == collection.id {
                collectionStore.clearActiveCollection()
            }
        } catch {
            deletionErrorMessage = error.localizedDescription
        }
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { collectionPendingDeletion != nil },
            set: { newValue in
                if !newValue {
                    collectionPendingDeletion = nil
                }
            }
        )
    }

    private var deletionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { deletionErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    deletionErrorMessage = nil
                }
            }
        )
    }
}

// MARK: - Preview

#if ENABLE_PREVIEWS
#Preview {
    let container = PreviewContainer.shared

    SmartCollectionsSidebar()
        .environmentObject(container.collectionStore)
        .frame(width: 250)
}
#endif
