import SwiftUI

struct FilterPopover: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var filterStore: FilterStore
    @EnvironmentObject var tagStore: TagStore
    @EnvironmentObject var collectionStore: CollectionStore

    private let showsDismissControls: Bool

    @State private var isTagsExpanded = false
    @State private var isFileSizeExpanded = false
    @State private var isDimensionsExpanded = false
    @State private var isDateFilterEnabled = false
    @State private var tagInputText = ""

    init(showsDismissControls: Bool = true) {
        self.showsDismissControls = showsDismissControls
    }

    var body: some View {
        VStack(spacing: 16) {
            header

            ScrollView {
                VStack(spacing: 16) {
                    primaryFilters

                    Divider()

                    // Collapsible secondary filters
                    tagsSection
                    fileSizeSection
                    dimensionsSection
                }
            }

            if showsDismissControls {
                Spacer()

                HStack(spacing: 12) {
                    resetButton
                    applyButton
                }
            } else {
                resetButton
            }
        }
        .padding()
        .frame(width: showsDismissControls ? 450 : 360, height: 500)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Filters")
                .font(.headline)
            Spacer()
            if filterStore.activeFilterCount > 0 {
                Text("\(filterStore.activeFilterCount) active")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Primary Filters

    private var primaryFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Favorites checkbox
            favoritesFilter

            Divider()

            // Rating slider
            ratingFilter

            Divider()

            // Date range picker
            dateRangeFilter
        }
    }

    private var favoritesFilter: some View {
        HStack {
            Toggle(isOn: $filterStore.showFavoritesOnly) {
                Text("Show only favorites")
            }
            .toggleStyle(.checkbox)
            Spacer()
        }
    }

    private var ratingFilter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Minimum Rating")
                .font(.subheadline)

            HStack {
                Text("0★")
                Slider(
                    value: Binding(
                        get: { Double(filterStore.minimumRating) },
                        set: { filterStore.minimumRating = Int($0) }
                    ),
                    in: 0...5,
                    step: 1
                )
                Text("5★")
            }

            if filterStore.minimumRating > 0 {
                Text("Filtering: \(filterStore.minimumRating)+ stars")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var dateRangeFilter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: $isDateFilterEnabled) {
                    Text("Date Range")
                        .font(.subheadline)
                }
                .toggleStyle(.checkbox)
                Spacer()
            }

            if isDateFilterEnabled {
                HStack {
                    DatePicker("Start", selection: dateRangeStart, displayedComponents: .date)
                    Text("–")
                    DatePicker("End", selection: dateRangeEnd, displayedComponents: .date)
                }
                .transition(.opacity)
            }
        }
        .onChange(of: isDateFilterEnabled) { _, newValue in
            if newValue {
                // Enable date filter - initialize with last 30 days if currently nil
                if filterStore.dateRange == nil {
                    let endDate = Date()
                    let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate) ?? endDate
                    filterStore.dateRange = startDate...endDate
                }
            } else {
                // Disable date filter - clear the range
                filterStore.dateRange = nil
            }
        }
    }

    // MARK: - Helper Bindings

    private var dateRangeStart: Binding<Date> {
        Binding(
            get: { filterStore.dateRange?.lowerBound ?? Date() },
            set: { newValue in
                let endDate = filterStore.dateRange?.upperBound ?? Date()
                filterStore.dateRange = newValue...endDate
            }
        )
    }

    private var dateRangeEnd: Binding<Date> {
        Binding(
            get: { filterStore.dateRange?.upperBound ?? Date() },
            set: { newValue in
                let startDate = filterStore.dateRange?.lowerBound ?? Date()
                filterStore.dateRange = startDate...newValue
            }
        )
    }

    // MARK: - Secondary Filters

    private var tagsSection: some View {
        DisclosureGroup("Tags", isExpanded: $isTagsExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add tags to filter by")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("Type a tag", text: $tagInputText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addTypedTag()
                        }

                    Button("Add") {
                        addTypedTag()
                    }
                    .disabled(normalizedTagInput.isEmpty)
                }

                if !filteredTagSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suggestions")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        ForEach(filteredTagSuggestions, id: \.self) { tag in
                            Button {
                                addTag(tag)
                            } label: {
                                HStack {
                                    Text(tag)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
                }

                if filterStore.selectedTags.isEmpty {
                    Text("No tags selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(filterStore.selectedTags.count) tag\(filterStore.selectedTags.count == 1 ? "" : "s") applied")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(Array(filterStore.selectedTags), id: \.self) { tag in
                        HStack {
                            Text(tag)
                                .font(.caption)
                            Spacer()
                            Button("Remove") {
                                filterStore.removeTag(tag)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }
            }
            .padding(.leading, 16)
        }
    }

    private var normalizedTagInput: String {
        tagInputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredTagSuggestions: [String] {
        guard !normalizedTagInput.isEmpty else {
            return []
        }

        return tagStore.allTags
            .filter { $0.localizedCaseInsensitiveContains(normalizedTagInput) }
            .filter { !filterStore.selectedTags.contains($0) }
            .prefix(6)
            .map { $0 }
    }

    private func addTypedTag() {
        let tag = normalizedTagInput
        guard !tag.isEmpty else {
            return
        }

        addTag(tag)
    }

    private func addTag(_ tag: String) {
        filterStore.addTag(tag)
        tagInputText = ""
    }

    private var fileSizeSection: some View {
        DisclosureGroup("File Size", isExpanded: $isFileSizeExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Size", selection: $filterStore.fileSizeFilter) {
                    Text("All sizes").tag(FilterStore.FileSizeFilter.all)
                    Text("Small (< 2MB)").tag(FilterStore.FileSizeFilter.small)
                    Text("Medium (2-10MB)").tag(FilterStore.FileSizeFilter.medium)
                    Text("Large (10-50MB)").tag(FilterStore.FileSizeFilter.large)
                    Text("Very Large (> 50MB)").tag(FilterStore.FileSizeFilter.veryLarge)
                }
                .pickerStyle(.radioGroup)
            }
            .padding(.leading, 16)
        }
    }

    private var dimensionsSection: some View {
        DisclosureGroup("Image Dimensions", isExpanded: $isDimensionsExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Orientation", selection: $filterStore.dimensionFilter) {
                    Text("All orientations").tag(FilterStore.DimensionFilter.all)
                    Text("Landscape (width > height)").tag(FilterStore.DimensionFilter.landscape)
                    Text("Portrait (height > width)").tag(FilterStore.DimensionFilter.portrait)
                    Text("Square (ratio ≈ 1:1)").tag(FilterStore.DimensionFilter.square)
                }
                .pickerStyle(.radioGroup)
            }
            .padding(.leading, 16)
        }
    }

    // MARK: - Reset Button

    private var resetButton: some View {
        Button("Show All Images") {
            clearAllFiltersAndCollection(filterStore: filterStore, collectionStore: collectionStore)
            if showsDismissControls {
                dismiss()
            }
        }
        .buttonStyle(.bordered)
        .disabled(!filterStore.isActive && collectionStore.activeCollection == nil)
        .frame(maxWidth: showsDismissControls ? .infinity : nil, alignment: .leading)
    }

    // MARK: - Apply Button

    private var applyButton: some View {
        Button("Apply") {
            dismiss()
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
    }
}

#if ENABLE_PREVIEWS
#Preview {
    FilterPopover()
        .environmentObject(FilterStore())
}
#endif
