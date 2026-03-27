import Foundation

// MARK: - Filtered Images Extension

/// Extension to AppState that provides filtered images based on FilterStore criteria
///
/// This allows filtering of the primary image array (appState.images) which
/// is populated from filesystem scanning, rather than imageStore.images which
/// only contains database metadata records.
extension AppState {

    /// Returns images from the primary array filtered by FilterStore criteria
    ///
    /// This computed property applies all active filters from the provided FilterStore
    /// to the images array, returning only images that match all criteria (AND logic).
    ///
    /// Filters applied:
    /// - Minimum rating
    /// - Favorites only
    /// - Selected tags
    /// - Date range
    /// - File size
    /// - Image dimensions
    ///
    /// - Parameter filterStore: The filter store containing active filter criteria
    /// - Returns: Filtered array of images matching all active criteria
    func filteredImages(using filterStore: FilterStore) -> [ImageFile] {
        return images.filter { image in
            satisfiesRatingFilter(image, filterStore: filterStore)
                && satisfiesFavoriteFilter(image, filterStore: filterStore)
                && satisfiesTagFilter(image, filterStore: filterStore)
                && satisfiesDateFilter(image, filterStore: filterStore)
                && satisfiesFileSizeFilter(image, filterStore: filterStore)
                && satisfiesDimensionFilter(image, filterStore: filterStore)
        }
    }

    // MARK: - Filter Helpers

    /// Check if image satisfies minimum rating filter
    private func satisfiesRatingFilter(_ image: ImageFile, filterStore: FilterStore) -> Bool {
        guard filterStore.minimumRating > 0 else { return true }
        return image.rating >= filterStore.minimumRating
    }

    /// Check if image satisfies favorites filter
    private func satisfiesFavoriteFilter(_ image: ImageFile, filterStore: FilterStore) -> Bool {
        guard filterStore.showFavoritesOnly else { return true }
        return image.isFavorite
    }

    /// Check if image satisfies tag filter
    private func satisfiesTagFilter(_ image: ImageFile, filterStore: FilterStore) -> Bool {
        guard !filterStore.selectedTags.isEmpty else { return true }

        // For now, return true until tags are implemented in Phase 11
        // TODO: Implement in Phase 11 when tag support is added
        return true
    }

    /// Check if image satisfies date range filter
    private func satisfiesDateFilter(_ image: ImageFile, filterStore: FilterStore) -> Bool {
        guard let range = filterStore.dateRange else { return true }
        return range.contains(image.creationDate)
    }

    /// Check if image satisfies file size filter
    private func satisfiesFileSizeFilter(_ image: ImageFile, filterStore: FilterStore) -> Bool {
        guard filterStore.fileSizeFilter != .all else { return true }

        let fileSize = image.fileSizeBytes

        switch filterStore.fileSizeFilter {
        case .all: return true
        case .small: return fileSize < 2_000_000
        case .medium: return fileSize >= 2_000_000 && fileSize < 10_000_000
        case .large: return fileSize >= 10_000_000 && fileSize < 50_000_000
        case .veryLarge: return fileSize >= 50_000_000
        }
    }

    /// Check if image satisfies dimension filter
    private func satisfiesDimensionFilter(_ image: ImageFile, filterStore: FilterStore) -> Bool {
        guard filterStore.dimensionFilter != .all else { return true }

        // Get dimensions from ImageIO or metadata
        // For now, return true until dimension loading is implemented
        // TODO: Implement in Phase 12 when enhanced viewing is added
        return true
    }
}
