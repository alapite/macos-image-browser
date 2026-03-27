import Foundation
import Combine
import GRDB

@MainActor
protocol ImageStoreFiltering: AnyObject {
    var minimumRating: Int { get }
    var showFavoritesOnly: Bool { get }
    var selectedTags: Set<String> { get }
    var dateRange: ClosedRange<Date>? { get }
    var fileSizeFilter: FilterStore.FileSizeFilter { get }
    var dimensionFilter: FilterStore.DimensionFilter { get }
    var selectedTagsPublisher: AnyPublisher<Set<String>, Never> { get }
}

@MainActor
protocol AsyncImageTagLookupProviding: AnyObject {
    func tagsForImageSync(_ imageUrl: String) -> Set<String>
    func tagsForImage(_ imageUrl: String) async -> Set<String>
}

/// Image data and loading state management store.
///
/// Responsibilities:
/// - Manage list of images from filesystem
/// - Track loading state and progress
/// - Observe database changes reactively via ValueObservation
/// - Provide metadata update methods (rating, favorite status)
///
/// Design principles:
/// - Max 10 @Published properties to prevent bloat
/// - @MainActor ensures UI updates on main thread (SwiftUI requirement)
/// - ValueObservation auto-triggers UI updates when database changes
/// - Does NOT manage filters (see FilterStore) or navigation (see ViewStore)
@MainActor
final class ImageStore: ObservableObject {

    // MARK: - Published Properties (max 10)

    /// List of images from filesystem
    @Published var images: [ImageFile] = [] {
        didSet {
            // Clear tag cache when images array changes to ensure consistency
            imageTagsCache.removeAll()
        }
    }

    /// Indicates if images are currently being loaded
    @Published var isLoadingImages: Bool = false

    /// Set of image URLs that failed to load
    @Published var failedImages: Set<URL> = []

    /// Loading progress (0.0 to 1.0)
    @Published var loadingProgress: Double = 0.0

    // MARK: - Private Properties

    /// Database pool for concurrent reads
    private let dbPool: DatabasePool

    /// Filter state source for tag prefetch criteria.
    private let filtering: ImageStoreFiltering

    /// Tag lookup source used to hydrate the tag cache.
    private let tagLookup: AsyncImageTagLookupProviding?

    /// Cache for image tags to avoid repeated database queries
    ///
    /// Maps image URL string to Set of tag names. Cleared when images array changes.
    private var imageTagsCache: [String: Set<String>] = [:]

    /// Tracks whether tags have been pre-fetched for current filter
    private var tagsPreFetchedForCurrentFilter: Set<String> = []

    /// Combine cancellables for observation subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization

    /// Initialize store with database pool and filter state
    /// - Parameters:
    ///   - dbPool: GRDB database pool for metadata access
    ///   - filtering: Tag filter source
    ///   - tagLookup: Tag lookup source for prefetching
    init(
        dbPool: DatabasePool,
        filtering: ImageStoreFiltering,
        tagLookup: AsyncImageTagLookupProviding? = nil
    ) {
        self.dbPool = dbPool
        self.filtering = filtering
        self.tagLookup = tagLookup
        self.imageTagsCache = [:]
        self.tagsPreFetchedForCurrentFilter = []
        setupDatabaseObservation()
        setupTagFilterObservation()
    }

    /// Setup observation for tag filter changes to pre-fetch tags
    ///
    /// When selectedTags changes, we pre-fetch tags for all images to ensure
    /// the synchronous satisfiesTagFilter has cached data available.
    private func setupTagFilterObservation() {
        guard tagLookup != nil else { return }

        filtering.selectedTagsPublisher
            .removeDuplicates()
            .sink { [weak self] newTags in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.preFetchTags(for: self.images, selectedTags: newTags)
                }
            }
            .store(in: &cancellables)
    }

    /// Pre-fetch tags for images to populate cache
    ///
    /// This is called when selectedTags changes to ensure the synchronous
    /// satisfiesTagFilter has cached data available. Uses cache-first strategy
    /// and only fetches tags for images not yet in cache.
    ///
    /// - Parameters:
    ///   - images: Array of images to fetch tags for
    ///   - selectedTags: The tag filter that triggered this pre-fetch
    @MainActor
    func preFetchTags(for images: [ImageFile], selectedTags: Set<String>) async {
        // Skip if no tag filter is active
        guard !selectedTags.isEmpty, let tagLookup = tagLookup else {
            tagsPreFetchedForCurrentFilter = []
            return
        }

        // Skip if already pre-fetched for this filter
        guard tagsPreFetchedForCurrentFilter != selectedTags else { return }

        // Fetch tags for all images that don't have cached tags
        for image in images {
            let imageUrl = image.url.absoluteString
            if imageTagsCache[imageUrl] == nil {
                let fetchedTags = await tagLookup.tagsForImage(imageUrl)
                imageTagsCache[imageUrl] = fetchedTags
            }
        }

        // Mark as pre-fetched for this filter
        tagsPreFetchedForCurrentFilter = selectedTags
    }
    
    // MARK: - Database Observation
    
    /// Setup reactive database observation for automatic UI updates
    ///
    /// Uses GRDB's ValueObservation to track changes to the image_metadata table.
    /// When metadata is added/updated in the database, the images array is
    /// automatically refreshed, triggering SwiftUI re-renders.
    private func setupDatabaseObservation() {
        let observation = ValueObservation.tracking { db in
            // Fetch all metadata records from database
            try ImageMetadataRecord.fetchAll(db)
        }
        
        // Observe changes via Combine publisher
        observation.publisher(in: dbPool)
            .receive(on: DispatchQueue.main)  // Ensure UI updates on main thread
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        // Log errors but don't crash - observation continues
                        print("⚠️ ImageStore database observation error: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] metadataRecords in
                    // Map metadata records to in-memory ImageFile objects
                    // Note: This is a simplified implementation - Phase 08-04 will
                    // integrate with actual filesystem scanning
                    self?.updateImagesFromMetadata(metadataRecords)
                }
            )
            .store(in: &cancellables)
    }
    
    /// Update images array from metadata records
    /// - Parameter metadataRecords: Metadata records fetched from database
    private func updateImagesFromMetadata(_ metadataRecords: [ImageMetadataRecord]) {
        // Map database records to ImageFile objects with metadata
        // Note: This will be enhanced in Phase 08-04 to sync with filesystem
        images = metadataRecords.map { record in
            let url = Self.metadataURL(from: record.url)
            let metadata = ImageMetadata(
                rating: record.rating,
                isFavorite: record.isFavorite,
                isExcluded: record.isExcluded,
                excludedAt: record.excludedAt
            )
            return ImageFile(url: url, name: url.lastPathComponent, creationDate: record.createdAt, metadata: metadata)
        }
    }

    private static func metadataURL(from value: String) -> URL {
        if let parsed = URL(string: value), parsed.isFileURL {
            return parsed.standardizedFileURL
        }

        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value).standardizedFileURL
        }

        return URL(fileURLWithPath: value)
    }

    private static func metadataKey(from value: String) -> String {
        metadataURL(from: value).absoluteString
    }
    
    // MARK: - Metadata Updates
    
    /// Update rating for an image
    /// - Parameters:
    ///   - imageUrl: URL string of the image
    ///   - rating: New rating value (0-5)
    /// - Throws: Database error if update fails
    ///
    /// This method writes to the database, and ValueObservation automatically
    /// triggers UI updates - no manual UI refresh needed.
    func updateRating(for imageUrl: String, rating: Int) async throws {
        let metadataKey = Self.metadataKey(from: imageUrl)

        try await dbPool.write { db in
            // Fetch existing metadata
            if let existingRecord = try ImageMetadataRecord.fetchOne(db, key: metadataKey) {
                // Update existing record
                var record = existingRecord
                record.rating = rating
                try record.update(db)
            } else {
                // Create new record if it doesn't exist
                let newRecord = ImageMetadataRecord(url: metadataKey, rating: rating)
                try newRecord.insert(db)
            }
        }
        // ValueObservation will auto-trigger UI update via `images` publisher
    }

    /// Update favorite status for an image
    /// - Parameters:
    ///   - imageUrl: URL string of the image
    ///   - isFavorite: New favorite status
    /// - Throws: Database error if update fails
    ///
    /// This method writes to the database, and ValueObservation automatically
    /// triggers UI updates - no manual UI refresh needed.
    func updateFavorite(for imageUrl: String, isFavorite: Bool) async throws {
        let metadataKey = Self.metadataKey(from: imageUrl)

        try await dbPool.write { db in
            // Fetch existing metadata
            if let existingRecord = try ImageMetadataRecord.fetchOne(db, key: metadataKey) {
                // Update existing record
                var record = existingRecord
                record.isFavorite = isFavorite
                try record.update(db)
            } else {
                // Create new record if it doesn't exist
                let newRecord = ImageMetadataRecord(url: metadataKey, isFavorite: isFavorite)
                try newRecord.insert(db)
            }
        }
        // ValueObservation will auto-trigger UI update via `images` publisher
    }

    /// Update excluded status for an image.
    /// - Parameters:
    ///   - imageUrl: URL string of the image
    ///   - isExcluded: New exclusion status
    func updateExcluded(for imageUrl: String, isExcluded: Bool) async throws {
        let metadataKey = Self.metadataKey(from: imageUrl)
        let excludedAt = isExcluded ? Date() : nil

        try await dbPool.write { db in
            if let existingRecord = try ImageMetadataRecord.fetchOne(db, key: metadataKey) {
                var record = existingRecord
                record.isExcluded = isExcluded
                record.excludedAt = excludedAt
                try record.update(db)
            } else {
                let newRecord = ImageMetadataRecord(
                    url: metadataKey,
                    isExcluded: isExcluded,
                    excludedAt: excludedAt
                )
                try newRecord.insert(db)
            }
        }
    }

    // MARK: - Error Handling

    /// Update favorite with automatic retry on transient errors.
    /// - Parameters:
    ///   - imageUrl: URL string of the image
    ///   - isFavorite: New favorite status
    /// - Returns: True when update succeeds, false after all retries fail
    ///
    /// Retries up to 3 times with exponential backoff (0.1s, 0.2s, 0.4s).
    func updateFavoriteWithRetry(for imageUrl: String, isFavorite: Bool) async -> Bool {
        for attempt in 1...3 {
            do {
                try await updateFavorite(for: imageUrl, isFavorite: isFavorite)
                return true
            } catch {
                if attempt == 3 {
                    print("Failed to update favorite after 3 attempts: \(error.localizedDescription)")
                } else {
                    let delay = 0.1 * pow(2.0, Double(attempt - 1))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        return false
    }

    /// Update rating with automatic retry on transient errors.
    /// - Parameters:
    ///   - imageUrl: URL string of the image
    ///   - rating: New rating value (0-5)
    /// - Returns: True when update succeeds, false after all retries fail
    ///
    /// Retries up to 3 times with exponential backoff (0.1s, 0.2s, 0.4s).
    func updateRatingWithRetry(for imageUrl: String, rating: Int) async -> Bool {
        for attempt in 1...3 {
            do {
                try await updateRating(for: imageUrl, rating: rating)
                return true
            } catch {
                if attempt == 3 {
                    print("Failed to update rating after 3 attempts: \(error.localizedDescription)")
                } else {
                    let delay = 0.1 * pow(2.0, Double(attempt - 1))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        return false
    }

    /// Update excluded status with automatic retry on transient errors.
    func updateExcludedWithRetry(for imageUrl: String, isExcluded: Bool) async -> Bool {
        for attempt in 1...3 {
            do {
                try await updateExcluded(for: imageUrl, isExcluded: isExcluded)
                return true
            } catch {
                if attempt == 3 {
                    print("Failed to update exclusion after 3 attempts: \(error.localizedDescription)")
                } else {
                    let delay = 0.1 * pow(2.0, Double(attempt - 1))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        return false
    }
    
    // MARK: - Loading State Management
    
    /// Begin loading images
    public func startLoading() {
        isLoadingImages = true
        loadingProgress = 0.0
        failedImages.removeAll()
    }
    
    /// Update loading progress
    /// - Parameter progress: Progress value (0.0 to 1.0)
    public func updateProgress(_ progress: Double) {
        loadingProgress = max(0.0, min(1.0, progress))
    }
    
    /// Finish loading images
    public func finishLoading() {
        isLoadingImages = false
        loadingProgress = 1.0
    }
    
    /// Mark image as failed to load
    /// - Parameter url: URL of the failed image
    public func markFailed(_ url: URL) {
        failedImages.insert(url)
    }

    // MARK: - Filtering

    /// Filtered images based on FilterStore criteria
    ///
    /// This computed property applies all active filters from FilterStore to the
    /// images array, returning only images that match all criteria (AND logic).
    ///
    /// Filters applied:
    /// - Minimum rating
    /// - Favorites only
    /// - Selected tags
    /// - Date range
    /// - File size
    /// - Image dimensions
    var filteredImages: [ImageFile] {
        return images.filter { image in
            satisfiesRatingFilter(image)
                && satisfiesFavoriteFilter(image)
                && satisfiesTagFilter(image)
                && satisfiesDateFilter(image)
                && satisfiesFileSizeFilter(image)
                && satisfiesDimensionFilter(image)
        }
    }

    // MARK: - Filter Helpers

    /// Check if image satisfies minimum rating filter
    private func satisfiesRatingFilter(_ image: ImageFile) -> Bool {
        guard filtering.minimumRating > 0 else { return true }
        return image.rating >= filtering.minimumRating
    }

    /// Check if image satisfies favorites filter
    private func satisfiesFavoriteFilter(_ image: ImageFile) -> Bool {
        guard filtering.showFavoritesOnly else { return true }
        return image.isFavorite
    }

    /// Check if image satisfies tag filter
    ///
    /// Fetches tags for the image from TagStore and checks if all selected tags
    /// are present (AND logic). Uses caching to avoid repeated database queries.
    /// Tags are pre-fetched when selectedTags changes via setupTagFilterObservation.
    private func satisfiesTagFilter(_ image: ImageFile) -> Bool {
        guard !filtering.selectedTags.isEmpty else { return true }

        // If tagStore is not available, return true (filter disabled)
        guard let tagLookup = tagLookup else { return true }

        // Check cache for image tags
        let imageUrl = image.url.absoluteString

        // Use cached tags if available, otherwise fetch synchronously
        let imageTags: Set<String>
        if let cachedTags = imageTagsCache[imageUrl] {
            imageTags = cachedTags
        } else {
            // Fetch tags synchronously if not in cache
            imageTags = tagLookup.tagsForImageSync(imageUrl)
            imageTagsCache[imageUrl] = imageTags
        }

        // Check if all selected tags are present in image tags (AND logic)
        return filtering.selectedTags.isSubset(of: imageTags)
    }

    /// Check if image satisfies date range filter
    private func satisfiesDateFilter(_ image: ImageFile) -> Bool {
        guard let range = filtering.dateRange else { return true }
        return range.contains(image.creationDate)
    }

    /// Check if image satisfies file size filter
    private func satisfiesFileSizeFilter(_ image: ImageFile) -> Bool {
        guard filtering.fileSizeFilter != .all else { return true }

        let fileSize = image.fileSizeBytes

        switch filtering.fileSizeFilter {
        case .all: return true
        case .small: return fileSize < 2_000_000
        case .medium: return fileSize >= 2_000_000 && fileSize < 10_000_000
        case .large: return fileSize >= 10_000_000 && fileSize < 50_000_000
        case .veryLarge: return fileSize >= 50_000_000
        }
    }

    /// Check if image satisfies dimension filter
    private func satisfiesDimensionFilter(_ image: ImageFile) -> Bool {
        guard filtering.dimensionFilter != .all else { return true }

        // Get dimensions from ImageIO or metadata
        // For now, return true until dimension loading is implemented
        // TODO: Implement in Phase 12 when enhanced viewing is added
        return true
    }
}
