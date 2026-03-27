import SwiftUI

/// Form for creating and editing smart collections.
///
/// Provides a simple interface for defining collection filter rules:
/// - Collection name (required)
/// - Minimum rating (optional)
/// - Favorites only (optional)
/// - Required tags (optional)
///
/// Uses the same form for both create and edit modes based on collectionToEdit parameter.
struct SmartCollectionForm: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var collectionStore: CollectionStore
    @EnvironmentObject var tagStore: TagStore

    /// Collection being edited (nil = create mode)
    let collectionToEdit: SmartCollection?

    // MARK: - Form State

    /// Collection name binding
    @State private var collectionName: String

    /// Minimum rating filter (nil = no rating filter)
    @State private var minimumRating: Int?

    /// Favorites filter (nil = no favorite filter, true = favorites only, false = exclude favorites)
    @State private var favoritesOnly: Bool?

    /// Required tags filter (nil = no tag filter, non-empty = must have all tags)
    @State private var requiredTags: Set<String>

    /// Match mode (false = AND logic, true = OR logic)
    @State private var matchAny: Bool

    /// Error state
    @State private var showingError = false
    @State private var errorMessage = ""

    /// Tag picker presentation state
    @State private var showingTagInput = false

    // MARK: - Initialization

    /// Initialize form (create mode)
    init() {
        self.collectionToEdit = nil
        self.collectionName = ""
        self.minimumRating = nil
        self.favoritesOnly = nil
        self.requiredTags = []
        self.matchAny = false
    }

    /// Initialize form (edit mode)
    init(collectionToEdit: SmartCollection) {
        self.collectionToEdit = collectionToEdit
        self.collectionName = collectionToEdit.name
        self.minimumRating = collectionToEdit.rules.minimumRating
        self.favoritesOnly = collectionToEdit.rules.favoritesOnly
        self.requiredTags = collectionToEdit.rules.requiredTags ?? []
        self.matchAny = collectionToEdit.rules.matchAny
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                matchModeSection
                ratingSection
                favoritesSection
                tagsSection
            }
            .formStyle(.grouped)
            .navigationTitle(collectionToEdit == nil ? "New Smart Collection" : "Edit Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .modalKeyboardShortcut(ModalKeyboardShortcuts.role(for: .smartCollectionCancel))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                        }
                    }
                    .modalKeyboardShortcut(ModalKeyboardShortcuts.role(for: .smartCollectionSave))
                    .disabled(collectionName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingTagInput) {
                TagPickerView(
                    availableTags: tagStore.allTags,
                    selectedTags: $requiredTags
                )
            }
        }
        .frame(width: 450, height: 400)
    }

    // MARK: - Form Sections

    /// Collection name text field (required)
    private var nameSection: some View {
        Section {
            TextField("Collection Name", text: $collectionName)
                .textFieldStyle(.plain)
        } header: {
            Text("Name")
        } footer: {
            Text("A descriptive name for this collection (required)")
        }
    }

    /// Match mode picker (Match All / Match Any)
    private var matchModeSection: some View {
        Section {
            Picker("Match Mode", selection: $matchAny) {
                Text("Match All").tag(false)
                Text("Match Any").tag(true)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Logic")
        } footer: {
            Text(matchAny
                ? "Images matching ANY criterion will be included"
                : "Images matching ALL criteria will be included")
        }
    }

    /// Minimum rating picker
    private var ratingSection: some View {
        Section {
            Picker("Minimum Rating", selection: $minimumRating) {
                Text("Any").tag(nil as Int?)
                Divider()
                Text("1★").tag(1 as Int?)
                Text("2★").tag(2 as Int?)
                Text("3★").tag(3 as Int?)
                Text("4★").tag(4 as Int?)
                Text("5★").tag(5 as Int?)
            }
            .pickerStyle(.menu)
        } header: {
            Text("Rating")
        } footer: {
            Text("Minimum star rating for images in this collection")
        }
    }

    /// Favorites toggle
    private var favoritesSection: some View {
        Section {
            Toggle("Favorites Only", isOn: favoritesBinding)
        } header: {
            Text("Favorites")
        } footer: {
            Text("When enabled, only favorited images are included")
        }
    }

    /// Required tags input
    private var tagsSection: some View {
        Section {
            if requiredTags.isEmpty {
                Text("No tags selected")
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(requiredTags), id: \.self) { tag in
                    HStack {
                        Text(tag)
                        Spacer()
                        Button("Remove") {
                            requiredTags.remove(tag)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Button("Add Tag") {
                showTagInput()
            }
        } header: {
            Text("Required Tags")
        } footer: {
            Text(matchAny
                ? "Images must have ANY selected tag (OR logic)"
                : "Images must have ALL selected tags (AND logic)")
        }
    }

    // MARK: - Helper Bindings

    /// Binding for favorites toggle that handles three-state logic
    ///
    /// Converts Bool? (nil, true, false) to Bool binding:
    /// - nil → true (enable favorites filter)
    /// - true → false (disable favorites filter)
    /// - false → true (toggle back to true)
    private var favoritesBinding: Binding<Bool> {
        Binding(
            get: {
                // If nil or true, show as on (true)
                // If false, show as off (false)
                favoritesOnly != false
            },
            set: { newValue in
                if newValue {
                    // Toggle: nil → true, false → true
                    favoritesOnly = true
                } else {
                    // Toggle: true → false, nil → false
                    favoritesOnly = false
                }
            }
        )
    }

    // MARK: - Actions

    /// Save collection (create or update)
    private func save() async {
        // Validate collection name
        let trimmedName = collectionName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Collection name cannot be empty"
            showingError = true
            return
        }

        // Create collection rules from form state
        let rules = CollectionRules(
            minimumRating: minimumRating,
            favoritesOnly: favoritesOnly,
            requiredTags: requiredTags.isEmpty ? nil : requiredTags,
            matchAny: matchAny
        )

        do {
            if let collection = collectionToEdit {
                // Update existing collection
                try await collectionStore.updateCollection(
                    collection,
                    name: trimmedName,
                    rules: rules
                )
            } else {
                // Create new collection
                try await collectionStore.createCollection(
                    name: trimmedName,
                    rules: rules
                )
            }

            // Dismiss form on success
            dismiss()
        } catch {
            errorMessage = "Failed to save collection: \(error.localizedDescription)"
            showingError = true
        }
    }

    /// Show tag input dialog
    private func showTagInput() {
        showingTagInput = true
    }
}

// MARK: - TagPickerView

/// Tag picker for selecting tags in smart collection rules.
///
/// Shows all available tags from TagStore with multi-select toggle chips.
struct TagPickerView: View {
    let availableTags: [String]
    @Binding var selectedTags: Set<String>

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if availableTags.isEmpty {
                    Text("No tags available")
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(availableTags.sorted(), id: \.self) { tag in
                        Toggle(tag, isOn: Binding(
                            get: { selectedTags.contains(tag) },
                            set: { isSelected in
                                if isSelected {
                                    selectedTags.insert(tag)
                                } else {
                                    selectedTags.remove(tag)
                                }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("Select Tags")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 350, height: 400)
    }
}

// MARK: - Preview

#if ENABLE_PREVIEWS
#Preview("Create Collection") {
    let container = PreviewContainer.shared

    SmartCollectionForm()
        .environmentObject(container.collectionStore)
        .environmentObject(container.tagStore)
}

#Preview("Edit Collection") {
    let container = PreviewContainer.shared
    let collection = SmartCollection(
        id: 1,
        name: "5-Star Favorites",
        rules: CollectionRules(minimumRating: 5, favoritesOnly: true, requiredTags: nil),
        imageCount: 42
    )

    return SmartCollectionForm(collectionToEdit: collection)
        .environmentObject(container.collectionStore)
        .environmentObject(container.tagStore)
}
#endif
