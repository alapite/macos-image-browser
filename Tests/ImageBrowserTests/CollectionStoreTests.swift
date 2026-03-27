import XCTest
import GRDB
@testable import ImageBrowser

@MainActor
final class CollectionStoreTests: XCTestCase {
    private var dbPool: DatabasePool!
    private var imageStore: ImageStore!
    private var appState: AppState!
    private var collectionStore: CollectionStore!

    override func setUp() async throws {
        let dbPath = NSTemporaryDirectory() + "collection_store_test_\(UUID().uuidString).db"
        dbPool = try DatabasePool(path: dbPath)
        try await createSchema()

        let filterStore = FilterStore()
        imageStore = ImageStore(dbPool: dbPool, filtering: filterStore)
        appState = makeAppState(preferencesStore: InMemoryPreferencesStore())
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
        dbPool = nil
    }

    func testMalformedRowDoesNotHideValidCollections() async throws {
        try await insertRawCollection(name: "Broken", rulesJSON: "not-json")
        try await insertValidCollection(name: "Valid")

        let updated = await waitForCollections { collections in
            collections.map(\.name) == ["Valid"]
        }

        XCTAssertTrue(updated, "Malformed row should be skipped while valid rows still publish")
    }

    func testObservationContinuesAfterMalformedRow() async throws {
        try await insertRawCollection(name: "Broken", rulesJSON: "not-json")
        try await insertValidCollection(name: "Alpha")

        let initialLoaded = await waitForCollections { collections in
            collections.map(\.name) == ["Alpha"]
        }
        XCTAssertTrue(initialLoaded)

        try await insertValidCollection(name: "Bravo")

        let updated = await waitForCollections { collections in
            collections.map(\.name) == ["Alpha", "Bravo"]
        }

        XCTAssertTrue(updated, "Observation should keep publishing after malformed rows")
    }

    func testCreateAndUpdateCollectionPublishSortedCollections() async throws {
        try await collectionStore.createCollection(name: "Zulu", rules: CollectionRules(minimumRating: 4))
        try await collectionStore.createCollection(name: "Alpha", rules: CollectionRules(favoritesOnly: true))

        let createdSorted = await waitForCollections { collections in
            collections.map(\.name) == ["Alpha", "Zulu"]
        }
        XCTAssertTrue(createdSorted)

        guard let zulu = collectionStore.collections.first(where: { $0.name == "Zulu" }) else {
            XCTFail("Expected created collection to exist")
            return
        }

        try await collectionStore.updateCollection(zulu, name: "Beta", rules: CollectionRules(minimumRating: 5))

        let updatedSorted = await waitForCollections { collections in
            collections.map(\.name) == ["Alpha", "Beta"]
        }
        XCTAssertTrue(updatedSorted, "Create/update flows should continue publishing sorted collections")
    }

    func testFilteredImages_usesAppStateImagesWithMetadataOverlay() async throws {
        let unratedURL = URL(fileURLWithPath: "/tmp/collection-unrated.jpg")
        let ratedURL = URL(fileURLWithPath: "/tmp/collection-rated.jpg")

        appState.images = [
            ImageFile(url: unratedURL, name: "collection-unrated.jpg", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: ratedURL, name: "collection-rated.jpg", creationDate: Date(), fileSizeBytes: 100)
        ]

        try await dbPool.write { db in
            let record = ImageMetadataRecord(
                url: ratedURL.standardizedFileURL.absoluteString,
                rating: 5,
                isFavorite: false
            )
            try record.insert(db)
        }

        let onlyRatedRules = CollectionRules(minimumRating: 1)
        let collection = SmartCollectionRecord(id: 1, name: "Rated", rules: onlyRatedRules)
        let matched = await waitUntil {
            let filtered = self.collectionStore.filteredImages(for: SmartCollection(from: collection, images: self.appState.images))
            return filtered.map(\.name) == ["collection-rated.jpg"]
        }
        XCTAssertTrue(matched, "CollectionStore should apply metadata overlay when evaluating app-state images")
    }

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

    private func insertValidCollection(name: String) async throws {
        let record = SmartCollectionRecord(
            id: nil,
            name: name,
            rules: CollectionRules(minimumRating: 1),
            createdAt: Date(),
            updatedAt: Date()
        )

        try await dbPool.write { db in
            try record.insert(db)
        }
    }

    private func insertRawCollection(name: String, rulesJSON: String) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                INSERT INTO smart_collections (name, rules, createdAt, updatedAt)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [name, rulesJSON, Date(), Date()]
            )
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

    private func waitUntil(
        timeoutSeconds: TimeInterval = 2,
        predicate: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if predicate() {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return predicate()
    }
}
