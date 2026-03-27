import Foundation
import Combine

/// Filter criteria and active filters management store.
///
/// Responsibilities:
/// - Manage filter state independently from image and view state
/// - Track minimum rating, favorites, tags, and date range filters
/// - Provide computed property for active filter status
/// - Support filter reset to defaults
///
/// Design principles:
/// - Max 10 @Published properties to prevent bloat
/// - @MainActor ensures UI updates on main thread (SwiftUI requirement)
/// - Independent state prevents cascade updates when filters change
/// - No direct dependencies on ImageStore or ViewStore (loose coupling)
///
/// Usage pattern:
/// ```swift
/// @StateObject var filterStore = FilterStore()
///
/// // Apply filter
/// filterStore.minimumRating = 4
///
/// // Check if any filter is active
/// if filterStore.isActive {
///     // Apply filtering logic
/// }
///
/// // Reset all filters
/// filterStore.reset()
/// ```
@MainActor
final class FilterStore: ObservableObject {

    // MARK: - Published Properties (max 10)

    /// Minimum rating filter (0 = no rating filter)
    @Published var minimumRating: Int = 0

    /// Show only favorited images
    @Published var showFavoritesOnly: Bool = false

    /// Selected tags for filtering
    @Published var selectedTags: Set<String> = []

    /// Date range filter (nil = no date filter)
    @Published var dateRange: ClosedRange<Date>? = nil

    /// File size filter
    @Published var fileSizeFilter: FileSizeFilter = .all

    /// Image dimension filter
    @Published var dimensionFilter: DimensionFilter = .all

    // MARK: - Computed Properties

    /// Count of active filters
    ///
    /// Returns the number of filters currently set to non-default values
    var activeFilterCount: Int {
        var count = 0
        if minimumRating > 0 { count += 1 }
        if showFavoritesOnly { count += 1 }
        if !selectedTags.isEmpty { count += 1 }
        if dateRange != nil { count += 1 }
        if fileSizeFilter != .all { count += 1 }
        if dimensionFilter != .all { count += 1 }
        return count
    }

    /// Indicates if any filter is currently active
    ///
    /// Returns true if any filter is set to a non-default value:
    /// - minimumRating > 0
    /// - showFavoritesOnly is true
    /// - selectedTags is not empty
    /// - dateRange is not nil
    /// - fileSizeFilter is not .all
    /// - dimensionFilter is not .all
    var isActive: Bool {
        minimumRating > 0
            || showFavoritesOnly
            || !selectedTags.isEmpty
            || dateRange != nil
            || fileSizeFilter != .all
            || dimensionFilter != .all
    }

    // MARK: - Initialization

    /// Initialize with default filter values (all filters disabled)
    init() {
        // Default values set in property declarations
    }

    // MARK: - Filter Management

    /// Reset all filters to default values
    ///
    /// This sets:
    /// - minimumRating: 0 (no rating filter)
    /// - showFavoritesOnly: false (show all images)
    /// - selectedTags: empty set (no tag filter)
    /// - dateRange: nil (no date filter)
    /// - fileSizeFilter: .all
    /// - dimensionFilter: .all
    func reset() {
        minimumRating = 0
        showFavoritesOnly = false
        selectedTags.removeAll()
        dateRange = nil
        fileSizeFilter = .all
        dimensionFilter = .all
    }

    // MARK: - Tag Management

    /// Add a tag to the selected tags set
    /// - Parameter tag: Tag to add
    func addTag(_ tag: String) {
        selectedTags.insert(tag)
    }

    /// Remove a tag from the selected tags set
    /// - Parameter tag: Tag to remove
    func removeTag(_ tag: String) {
        selectedTags.remove(tag)
    }

    /// Toggle a tag in the selected tags set
    /// - Parameter tag: Tag to toggle
    func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    /// Check if a specific tag is selected
    /// - Parameter tag: Tag to check
    /// - Returns: True if tag is in selected tags
    func isTagSelected(_ tag: String) -> Bool {
        selectedTags.contains(tag)
    }

    // MARK: - Date Range Management

    /// Set date range filter
    /// - Parameter range: Date range to filter by (nil clears filter)
    func setDateRange(_ range: ClosedRange<Date>?) {
        dateRange = range
    }

    /// Clear date range filter
    func clearDateRange() {
        dateRange = nil
    }

    // MARK: - Nested Types

    /// File size filter categories
    enum FileSizeFilter: String, CaseIterable {
        case all
        case small
        case medium
        case large
        case veryLarge

        var displayName: String {
            switch self {
            case .all: return "All sizes"
            case .small: return "Small (< 2MB)"
            case .medium: return "Medium (2-10MB)"
            case .large: return "Large (10-50MB)"
            case .veryLarge: return "Very Large (> 50MB)"
            }
        }
    }

    /// Image dimension filter categories
    enum DimensionFilter: String, CaseIterable {
        case all
        case landscape
        case portrait
        case square

        var displayName: String {
            switch self {
            case .all: return "All orientations"
            case .landscape: return "Landscape (width > height)"
            case .portrait: return "Portrait (height > width)"
            case .square: return "Square (ratio ≈ 1:1)"
            }
        }
    }
}

@MainActor
extension FilterStore: ImageStoreFiltering {
    var selectedTagsPublisher: AnyPublisher<Set<String>, Never> {
        $selectedTags.eraseToAnyPublisher()
    }
}
