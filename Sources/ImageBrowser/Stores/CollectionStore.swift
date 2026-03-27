import Foundation
import Combine
import GRDB

@MainActor
protocol CollectionImageSource: AnyObject {
    var collectionImages: [ImageFile] { get }
    var collectionImagesPublisher: AnyPublisher<Void, Never> { get }
}

/// Smart collection management store.
///
/// Responsibilities:
/// - Manage list of smart collections from database
/// - Provide CRUD operations (create, read, update, delete)
/// - Observe database changes reactively via ValueObservation
/// - Create preset collections at app startup
///
/// Design principles:
/// - Max 10 @Published properties to prevent bloat
/// - @MainActor ensures UI updates on main thread (SwiftUI requirement)
/// - ValueObservation auto-triggers UI updates when database changes
/// - Stores sorted alphabetically by name for consistent ordering
@MainActor
final class CollectionStore: ObservableObject {

    // MARK: - Published Properties (max 10)

    /// List of smart collections sorted alphabetically by name
    @Published var collections: [SmartCollection] = []

    /// Currently active collection (nil = showing all images)
    ///
    /// When set, the main image grid filters to show only images from this collection.
    /// When nil, the grid shows all images (or filter-based results if filters are active).
    @Published var activeCollection: SmartCollection? = nil

    // MARK: - Private Properties

    /// Database pool for concurrent reads
    private let dbPool: DatabasePool

    /// Full image source (filesystem-scanned images) for rule evaluation.
    private let imageSource: CollectionImageSource

    /// Tag store for tag-based filtering in smart collections
    private let tagStore: TagStore?

    /// Whether default preset collections should be created during initialization.
    private let includesPresetCollections: Bool

    /// Cached smart collection records from the database.
    ///
    /// The published `collections` array is a derived view over these records plus
    /// current image/tag metadata, so we retain the raw records and recompute when
    /// image metadata changes.
    private var collectionRecords: [SmartCollectionRecord] = []

    /// Latest metadata snapshot keyed by standardized image URL.
    private var metadataByURL: [String: ImageMetadata] = [:]

    /// Combine cancellables for observation subscriptions
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Initialize store with database pool and image store
    /// - Parameters:
    ///   - dbPool: GRDB database pool for collection access
    ///   - imageSource: Full image source for rule evaluation
    ///   - tagStore: Tag store for tag-based filtering (optional)
    init(
        dbPool: DatabasePool,
        imageSource: CollectionImageSource,
        tagStore: TagStore? = nil,
        includesPresetCollections: Bool = true
    ) {
        self.dbPool = dbPool
        self.imageSource = imageSource
        self.tagStore = tagStore
        self.includesPresetCollections = includesPresetCollections
        if includesPresetCollections {
            ensurePresetCollectionsExist()
        }
        observeCollections()
        observeImageAndTagChanges()
    }

    // MARK: - Database Observation

    /// Setup reactive database observation for automatic UI updates
    ///
    /// Uses GRDB's ValueObservation to track changes to the smart_collections table.
    /// When collections are added/updated/deleted in the database, the collections
    /// array is automatically refreshed, triggering SwiftUI re-renders.
    private func observeCollections() {
        let shouldObserveImageTags = tagStore != nil
        let observation = ValueObservation.tracking { db in
            // Fetch all rows sorted alphabetically by name so malformed rows
            // can be skipped without terminating observation updates.
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM smart_collections ORDER BY name ASC")
            var records: [SmartCollectionRecord] = []
            records.reserveCapacity(rows.count)

            for row in rows {
                do {
                    records.append(try SmartCollectionRecord(row: row))
                } catch {
                    let rowID: Int64? = row["id"]
                    print("⚠️ Skipping malformed smart collection row id=\(rowID?.description ?? "unknown"): \(error.localizedDescription)")
                }
            }

            let metadataRecords = try ImageMetadataRecord.fetchAll(db)
            let metadataByURL = Dictionary(
                uniqueKeysWithValues: metadataRecords.map { record in
                    (
                        Self.standardizedURLKey(from: record.url),
                        ImageMetadata(rating: record.rating, isFavorite: record.isFavorite)
                    )
                }
            )

            // Track tag association changes so tag-based collection counts refresh.
            if shouldObserveImageTags {
                _ = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM image_tags") ?? 0
            }

            return CollectionObservationState(records: records, metadataByURL: metadataByURL)
        }

        // Observe changes via Combine publisher
        observation.publisher(in: dbPool)
            .receive(on: DispatchQueue.main)  // Ensure UI updates on main thread
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        // Log errors but don't crash - observation continues
                        print("⚠️ CollectionStore database observation error: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] state in
                    self?.collectionRecords = state.records
                    self?.metadataByURL = state.metadataByURL
                    self?.refreshCollections()
                }
            )
            .store(in: &cancellables)
    }

    /// Recompute derived collections when image metadata or tag assignments change.
    ///
    /// Smart collection counts are derived from image metadata, so the `collections`
    /// array must refresh when favorites, ratings, or tags change even if the
    /// `smart_collections` table itself remains untouched.
    private func observeImageAndTagChanges() {
        imageSource.collectionImagesPublisher
            .sink { [weak self] _ in
                self?.refreshCollections()
            }
            .store(in: &cancellables)

        tagStore?.$imageTagsVersion
            .sink { [weak self] _ in
                self?.refreshCollections()
            }
            .store(in: &cancellables)
    }

    private func refreshCollections() {
        let resolvedImages = resolvedCollectionImages()
        let refreshedCollections = collectionRecords.map { record in
            SmartCollection(from: record, images: resolvedImages, tagStore: tagStore)
        }
        collections = refreshedCollections

        guard let activeCollectionID = activeCollection?.id else {
            return
        }

        activeCollection = refreshedCollections.first(where: { $0.id == activeCollectionID })
    }

    nonisolated private static func standardizedURLKey(from value: String) -> String {
        if let parsed = URL(string: value), parsed.isFileURL {
            return parsed.standardizedFileURL.absoluteString
        }

        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value).standardizedFileURL.absoluteString
        }

        return URL(fileURLWithPath: value).standardizedFileURL.absoluteString
    }

    private func resolvedCollectionImages() -> [ImageFile] {
        imageSource.collectionImages.map { image in
            var resolved = image
            let key = image.url.standardizedFileURL.absoluteString
            if let metadata = metadataByURL[key] {
                resolved.metadata = metadata
            }
            return resolved
        }
    }

    // MARK: - CRUD Operations

    /// Create a new smart collection
    /// - Parameters:
    ///   - name: Collection name
    ///   - rules: Filter rules for the collection
    /// - Throws: Database error if creation fails
    ///
    /// This method writes to the database, and ValueObservation automatically
    /// triggers UI updates - no manual UI refresh needed.
    func createCollection(name: String, rules: CollectionRules) async throws {
        let record = SmartCollectionRecord(
            id: nil,
            name: name,
            rules: rules,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await dbPool.write { db in
            try record.insert(db)
        }
    }

    /// Update an existing smart collection
    /// - Parameters:
    ///   - collection: Collection to update
    ///   - name: New collection name
    ///   - rules: New filter rules
    /// - Throws: Database error if update fails
    ///
    /// This method writes to the database, and ValueObservation automatically
    /// triggers UI updates - no manual UI refresh needed.
    func updateCollection(
        _ collection: SmartCollection,
        name: String,
        rules: CollectionRules
    ) async throws {
        try await dbPool.write { db in
            // Fetch existing record
            guard let record = try SmartCollectionRecord.fetchOne(db, key: collection.id) else {
                throw CollectionError.collectionNotFound(collection.id)
            }

            // Update properties
            var updatedRecord = record
            updatedRecord.name = name
            updatedRecord.rules = rules

            // Save to database
            try updatedRecord.update(db)
        }
    }

    /// Delete a smart collection
    /// - Parameter collection: Collection to delete
    /// - Throws: Database error if deletion fails
    ///
    /// This method writes to the database, and ValueObservation automatically
    /// triggers UI updates - no manual UI refresh needed.
    func deleteCollection(_ collection: SmartCollection) async throws {
        try await dbPool.write { db in
            // Fetch and delete record
            guard let record = try SmartCollectionRecord.fetchOne(db, key: collection.id) else {
                throw CollectionError.collectionNotFound(collection.id)
            }

            try record.delete(db)
        }
    }

    // MARK: - Active Collection Management

    /// Set the active collection for filtering the image grid with toggle behavior
    /// - Parameter collection: Collection to activate (nil = show all images)
    ///
    /// Toggle behavior:
    /// - If collection is different from active collection, activate it
    /// - If same collection is already active, clear selection (toggle off)
    ///
    /// When a collection is active, the main image grid shows only images
    /// matching that collection's rules. When nil, shows all images or filter results.
    func setActiveCollection(_ collection: SmartCollection?) {
        // Toggle off if clicking the same collection again
        if activeCollection?.id == collection?.id {
            activeCollection = nil
        } else {
            activeCollection = collection
        }
    }

    /// Clear the active collection (return to all images view)
    ///
    /// This resets the grid to show all images or filter-based results.
    func clearActiveCollection() {
        activeCollection = nil
    }

    /// Get filtered images for a specific collection
    /// - Parameter collection: Collection to filter by
    /// - Returns: Array of images matching the collection's rules
    ///
    /// Uses the evaluateImages helper function to filter images against
    /// the collection's rules using AND logic (all criteria must match).
    func filteredImages(for collection: SmartCollection) -> [ImageFile] {
        let allImages = resolvedCollectionImages()
        return evaluateImages(allImages, against: collection.rules, tagStore: tagStore)
    }

    // MARK: - Preset Collections

    /// Create preset collections at app startup
    ///
    /// Creates three default collections if they don't already exist:
    /// - "All Favorites" - All favorited images
    /// - "5-Star Photos" - Images rated 5 stars
    /// - "Recently Rated" - All rated images (rating >= 1)
    ///
    /// Uses dbPool.read to check existence before creating to avoid duplicates.
    func createPresetCollections() async {
        guard includesPresetCollections else { return }
        ensurePresetCollectionsExist()
    }

    private func ensurePresetCollectionsExist() {
        do {
            try dbPool.write { db in
                for preset in Self.presetCollections {
                    let exists = try SmartCollectionRecord
                        .filter(Column("name") == preset.name)
                        .fetchCount(db) > 0

                    guard !exists else {
                        continue
                    }

                    let record = SmartCollectionRecord(
                        id: nil,
                        name: preset.name,
                        rules: preset.rules,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    try record.insert(db)
                }
            }
        } catch {
            print("⚠️ Failed to ensure preset collections exist: \(error.localizedDescription)")
        }
    }

    private static let presetCollections: [(name: String, rules: CollectionRules)] = [
        ("All Favorites", CollectionRules(favoritesOnly: true)),
        ("5-Star Photos", CollectionRules(minimumRating: 5)),
        ("Recently Rated", CollectionRules(minimumRating: 1))
    ]
}

// MARK: - Collection Errors

enum CollectionError: LocalizedError {
    case collectionNotFound(Int64)

    var errorDescription: String? {
        switch self {
        case .collectionNotFound(let id):
            return "Collection with ID \(id) not found"
        }
    }
}

private struct CollectionObservationState: Sendable {
    let records: [SmartCollectionRecord]
    let metadataByURL: [String: ImageMetadata]
}

@MainActor
extension AppState: CollectionImageSource {
    var collectionImages: [ImageFile] { images }
    var collectionImagesPublisher: AnyPublisher<Void, Never> { $images.map { _ in () }.eraseToAnyPublisher() }
}
