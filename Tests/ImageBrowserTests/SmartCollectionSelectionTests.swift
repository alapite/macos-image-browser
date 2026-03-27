import XCTest
import GRDB
@testable import ImageBrowser

/// Tests for single-click smart collection selection with toggle behavior.
///
/// These tests verify the gap identified in G11-02:
/// - First click on a collection applies it immediately
/// - Second click on the same collection clears the selection
/// - Clicking a different collection switches immediately
///
/// All tests should FAIL initially (RED phase) because the current
/// implementation uses a Button action without toggle logic.
@MainActor
final class SmartCollectionSelectionTests: XCTestCase {
    private var dbPool: DatabasePool!
    private var appState: AppState!
    private var imageStore: ImageStore!
    private var filterStore: FilterStore!
    private var collectionStore: CollectionStore!

    override func setUp() async throws {
        let dbPath = NSTemporaryDirectory() + "smart_collection_selection_test_\(UUID().uuidString).db"
        dbPool = try DatabasePool(path: dbPath)
        try await createSchema()

        filterStore = FilterStore()
        appState = makeAppState(preferencesStore: InMemoryPreferencesStore())
        imageStore = ImageStore(dbPool: dbPool, filtering: filterStore)
        collectionStore = CollectionStore(
            dbPool: dbPool,
            imageSource: appState,
            includesPresetCollections: false
        )
    }

    override func tearDown() async throws {
        collectionStore = nil
        appState = nil
        imageStore = nil
        filterStore = nil
        dbPool = nil
    }

    // MARK: - Test: First Click Applies Collection

    func testFirstClickAppliesCollection() async throws {
        // Given: Two collections exist
        try await collectionStore.createCollection(
            name: "Favorites",
            rules: CollectionRules(favoritesOnly: true)
        )
        try await collectionStore.createCollection(
            name: "Five Stars",
            rules: CollectionRules(minimumRating: 5)
        )

        let loaded = await waitForCollections { $0.count == 2 }
        XCTAssertTrue(loaded, "Collections should be loaded")

        guard let favorites = collectionStore.collections.first(where: { $0.name == "Favorites" }) else {
            XCTFail("Favorites collection should exist")
            return
        }

        // When: User clicks on Favorites collection (simulating first click)
        // This simulates the button action in SmartCollectionsSidebar.collectionRow
        collectionStore.setActiveCollection(favorites)

        // Then: Favorites should be the active collection
        XCTAssertEqual(
            collectionStore.activeCollection?.id,
            favorites.id,
            "First click should apply the collection immediately"
        )
    }

    // MARK: - Test: Second Click Clears Collection

    func testSecondClickClearsCollection() async throws {
        // Given: A collection is currently active
        try await collectionStore.createCollection(
            name: "Favorites",
            rules: CollectionRules(favoritesOnly: true)
        )

        let loaded = await waitForCollections { $0.count == 1 }
        XCTAssertTrue(loaded, "Collection should be loaded")

        guard let favorites = collectionStore.collections.first else {
            XCTFail("Favorites collection should exist")
            return
        }

        // First click - apply the collection
        collectionStore.setActiveCollection(favorites)
        XCTAssertEqual(
            collectionStore.activeCollection?.id,
            favorites.id,
            "First click should apply the collection"
        )

        // When: User clicks the same collection again (simulating second click)
        // This should toggle off (clear) the active collection
        collectionStore.setActiveCollection(favorites)

        // Then: Active collection should be cleared (nil)
        XCTAssertNil(
            collectionStore.activeCollection,
            "Second click on the same collection should clear selection (toggle off)"
        )
    }

    // MARK: - Test: Switching Collections

    func testSwitchingCollections() async throws {
        // Given: Two collections exist and one is active
        try await collectionStore.createCollection(
            name: "Favorites",
            rules: CollectionRules(favoritesOnly: true)
        )
        try await collectionStore.createCollection(
            name: "Five Stars",
            rules: CollectionRules(minimumRating: 5)
        )

        let loaded = await waitForCollections { $0.count == 2 }
        XCTAssertTrue(loaded, "Collections should be loaded")

        guard let favorites = collectionStore.collections.first(where: { $0.name == "Favorites" }),
              let fiveStars = collectionStore.collections.first(where: { $0.name == "Five Stars" }) else {
            XCTFail("Both collections should exist")
            return
        }

        // First collection is active
        collectionStore.setActiveCollection(favorites)
        XCTAssertEqual(
            collectionStore.activeCollection?.id,
            favorites.id,
            "Favorites should be active initially"
        )

        // When: User clicks a different collection
        collectionStore.setActiveCollection(fiveStars)

        // Then: The new collection should be active (not cleared, not the old one)
        XCTAssertEqual(
            collectionStore.activeCollection?.id,
            fiveStars.id,
            "Clicking different collection should switch to the new collection"
        )
        XCTAssertNotEqual(
            collectionStore.activeCollection?.id,
            favorites.id,
            "Old collection should no longer be active"
        )
    }

    // MARK: - Test: Toggle Pattern with Multiple Collections

    func testTogglePatternWithMultipleCollections() async throws {
        // Given: Three collections exist
        try await collectionStore.createCollection(
            name: "Favorites",
            rules: CollectionRules(favoritesOnly: true)
        )
        try await collectionStore.createCollection(
            name: "Five Stars",
            rules: CollectionRules(minimumRating: 5)
        )
        try await collectionStore.createCollection(
            name: "Recently Rated",
            rules: CollectionRules(minimumRating: 1)
        )

        let loaded = await waitForCollections { $0.count == 3 }
        XCTAssertTrue(loaded, "All collections should be loaded")

        guard let favorites = collectionStore.collections.first(where: { $0.name == "Favorites" }),
              let fiveStars = collectionStore.collections.first(where: { $0.name == "Five Stars" }),
              let recentlyRated = collectionStore.collections.first(where: { $0.name == "Recently Rated" }) else {
            XCTFail("All collections should exist")
            return
        }

        // Click 1: Apply Favorites
        collectionStore.setActiveCollection(favorites)
        XCTAssertEqual(collectionStore.activeCollection?.id, favorites.id, "Click 1: Favorites should be active")

        // Click 2: Apply Five Stars (switch)
        collectionStore.setActiveCollection(fiveStars)
        XCTAssertEqual(collectionStore.activeCollection?.id, fiveStars.id, "Click 2: Five Stars should be active")

        // Click 3: Toggle off Five Stars (click same collection again)
        collectionStore.setActiveCollection(fiveStars)
        XCTAssertNil(collectionStore.activeCollection, "Click 3: Should be cleared (no active collection)")

        // Click 4: Apply Recently Rated
        collectionStore.setActiveCollection(recentlyRated)
        XCTAssertEqual(collectionStore.activeCollection?.id, recentlyRated.id, "Click 4: Recently Rated should be active")

        // Click 5: Toggle off Recently Rated
        collectionStore.setActiveCollection(recentlyRated)
        XCTAssertNil(collectionStore.activeCollection, "Click 5: Should be cleared again")
    }

    func testCollectionCountUpdatesWhenFavoriteMetadataChanges() async throws {
        try await collectionStore.createCollection(
            name: "All Favorites",
            rules: CollectionRules(favoritesOnly: true)
        )

        let loaded = await waitForCollections { collections in
            collections.first(where: { $0.name == "All Favorites" }) != nil
        }
        XCTAssertTrue(loaded, "Favorites collection should be loaded")
        XCTAssertEqual(
            collectionStore.collections.first(where: { $0.name == "All Favorites" })?.imageCount,
            0,
            "Favorites collection should start empty"
        )

        let favoriteURL = URL(fileURLWithPath: "/tmp/smart-collection-favorite.jpg")
        appState.images = [
            ImageFile(url: favoriteURL, name: "smart-collection-favorite.jpg", creationDate: Date(), fileSizeBytes: 100)
        ]
        let updateSucceeded = await imageStore.updateFavoriteWithRetry(
            for: favoriteURL.standardizedFileURL.absoluteString,
            isFavorite: true
        )
        XCTAssertTrue(updateSucceeded, "Favorite metadata update should succeed")

        let updated = await waitForCollections { collections in
            collections.first(where: { $0.name == "All Favorites" })?.imageCount == 1
        }
        XCTAssertTrue(updated, "Favorites collection count should refresh when favorite metadata changes")
    }

    // MARK: - Helper Methods

    private func createSchema() async throws {
        try await dbPool.write { db in
            try db.create(table: "image_metadata", ifNotExists: true) { t in
                t.column("url", .text).primaryKey()
                t.column("rating", .integer).notNull().defaults(to: 0)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("isExcluded", .boolean).notNull().defaults(to: false)
                t.column("excludedAt", .datetime)
                t.column("createdAt", .date).notNull()
                t.column("updatedAt", .date).notNull()
            }

            try db.create(table: "smart_collections", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("rules", .text).notNull()
                t.column("createdAt", .date).notNull()
                t.column("updatedAt", .date).notNull()
            }
        }
    }

    private func waitForCollections(
        timeoutSeconds: TimeInterval = 2,
        predicate: ([SmartCollection]) -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if predicate(collectionStore.collections) {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return predicate(collectionStore.collections)
    }
}
