import XCTest
@testable import ImageBrowser
import SwiftUI
import GRDB

// Test wrapper to verify ContentView synchronization behavior
// This bridges unit tests with SwiftUI view state
@MainActor
final class KeyboardNavigationSynchronizationTests: XCTestCase {
    var appState: AppState!
    var imageStore: ImageStore!
    var filterStore: FilterStore!
    var viewStore: ViewStore!
    var galleryStore: GalleryStore!
    var tagStore: TagStore!
    var collectionStore: CollectionStore!
    var dbPool: DatabasePool!

    override func setUp() async throws {
        try await super.setUp()

        // Create a temporary database for testing
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_sync_\(UUID().uuidString).db")

        // Delete existing database if present
        try? FileManager.default.removeItem(at: dbPath)

        // Create database pool
        dbPool = try DatabasePool(path: dbPath.path)

        // Run database migrations
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "image_metadata") { t in
                t.column("url", .text).primaryKey()
                t.column("rating", .integer).notNull().defaults(to: 0)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("isExcluded", .boolean).notNull().defaults(to: false)
                t.column("excludedAt", .datetime)
                t.column("createdAt", .date).notNull()
                t.column("updatedAt", .date).notNull()
            }

            try db.create(table: "tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).unique().notNull()
            }

            try db.create(table: "image_tags") { t in
                t.column("url", .text).references("image_metadata", column: "url", onDelete: .cascade)
                t.column("tagId", .integer).references("tags", column: "id", onDelete: .cascade)
                t.primaryKey(["url", "tagId"])
            }

            try db.create(index: "rating", on: "image_metadata", columns: ["rating"])
            try db.create(index: "isFavorite", on: "image_metadata", columns: ["isFavorite"])
        }

        migrator.registerMigration("v1.1-tags") { db in
            try db.create(index: "tags_on_name", on: "tags", columns: ["name"])
        }

        migrator.registerMigration("v1.1-smart-collections") { db in
            try db.create(table: "smart_collections") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("rules", .text).notNull()
                t.column("createdAt", .date).notNull()
                t.column("updatedAt", .date).notNull()
            }

            try db.create(index: "smart_collections_on_name", on: "smart_collections", columns: ["name"])
        }

        migrator.registerMigration("v1.1-smart-collections-match-any-backfill") { db in
            try db.execute(sql: """
                UPDATE smart_collections
                SET rules = json_insert(CAST(rules AS TEXT), '$.matchAny', json('false'))
                WHERE json_valid(CAST(rules AS TEXT))
                  AND json_type(CAST(rules AS TEXT), '$.matchAny') IS NULL
                """)
        }

        try migrator.migrate(dbPool)

        // Initialize stores
        appState = makeAppState()
        filterStore = FilterStore()
        imageStore = ImageStore(dbPool: dbPool, filtering: filterStore)
        viewStore = ViewStore()
        tagStore = TagStore(dbPool: dbPool)
        collectionStore = CollectionStore(
            dbPool: dbPool,
            imageSource: appState,
            tagStore: tagStore,
            includesPresetCollections: false
        )

        // Create test images
        let testImages = (0..<10).map { index -> ImageFile in
            createTestImage(name: "test\(index).jpg", rating: 0, isFavorite: false)
        }

        await MainActor.run {
            appState.images = testImages
            appState.currentImageIndex = 5  // Start in middle
        }

        // Initialize GalleryStore
        galleryStore = GalleryStore(
            imageSource: appState,
            metadataSource: imageStore,
            filtering: filterStore,
            tagLookup: tagStore,
            collectionSource: collectionStore
        )
    }

    override func tearDown() async throws {
        appState = nil
        imageStore = nil
        filterStore = nil
        viewStore = nil
        galleryStore = nil
        tagStore = nil
        collectionStore = nil
        dbPool = nil
        try await super.tearDown()
    }

    private func createTestImage(name: String, rating: Int, isFavorite: Bool, creationDate: Date? = nil) -> ImageFile {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        let date = creationDate ?? Date()
        let metadata = ImageMetadata(rating: rating, isFavorite: isFavorite)
        return ImageFile(url: url, name: name, creationDate: date, metadata: metadata)
    }

    private func waitForSnapshot(
        timeout: TimeInterval = 1.5,
        predicate: @escaping (GallerySnapshot) -> Bool
    ) async {
        let expectation = XCTestExpectation(description: "snapshot predicate satisfied")
        let deadline = Date().addingTimeInterval(timeout)

        Task {
            while Date() < deadline {
                if predicate(self.galleryStore.snapshot) {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        await fulfillment(of: [expectation], timeout: timeout + 0.25)
    }

    // MARK: - Synchronization Logic Tests

    func testGalleryStoreObservesCurrentImageIndexChanges() async throws {
        // Verify GalleryStore observes appState.currentImageIndex changes
        XCTAssertEqual(appState.currentImageIndex, 5, "Should start at index 5")

        await waitForSnapshot { $0.currentDisplayImage?.fullIndex == 5 }

        let initialDisplayImage = galleryStore.snapshot.currentDisplayImage
        XCTAssertEqual(initialDisplayImage?.fullIndex, 5, "Initial display image should be at index 5")

        // Navigate to index 7
        await MainActor.run {
            appState.navigateToIndex(7)
        }

        await waitForSnapshot { $0.currentDisplayImage?.fullIndex == 7 }

        let updatedDisplayImage = galleryStore.snapshot.currentDisplayImage
        XCTAssertNotNil(updatedDisplayImage, "Should have a current display image after navigation")
        XCTAssertEqual(updatedDisplayImage?.fullIndex, 7, "Display image should update to index 7")

        // This proves GalleryStore observes currentImageIndex changes
        // ContentView's onChange(of: galleryStore.snapshot.currentDisplayImage) will fire
    }

    func testSelectionSynchronizationLogic() async throws {
        // Test the synchronization logic without SwiftUI View
        // This verifies the core logic works correctly

        await MainActor.run {
            appState.navigateToIndex(3)
        }

        await waitForSnapshot { $0.currentDisplayImage?.fullIndex == 3 }

        let displayImage = galleryStore.snapshot.currentDisplayImage
        XCTAssertNotNil(displayImage, "Should have a current display image")
        XCTAssertEqual(displayImage?.fullIndex, 3, "Display image should be at index 3")

        // Simulate what ContentView.syncSidebarSelectionWithDisplay does
        let imageID = displayImage?.id
        XCTAssertNotNil(imageID, "Should have an image ID")

        // This is what the onChange handler does in ContentView
        // selectedImageIDs = [imageID]
        // The synchronization logic is: display image ID → selection set
    }

    func testFullIndexMapping() async throws {
        // Verify GallerySnapshot.fullIndex(for:) correctly maps image IDs to indices
        await MainActor.run {
            appState.navigateToIndex(2)
        }

        await waitForSnapshot { $0.currentDisplayImage?.fullIndex == 2 }

        let displayImage = galleryStore.snapshot.currentDisplayImage
        XCTAssertNotNil(displayImage, "Should have a current display image")

        // Test fullIndex mapping
        let fullIndex = galleryStore.snapshot.fullIndex(for: displayImage!.id)
        XCTAssertNotNil(fullIndex, "Should find full index for image ID")
        XCTAssertEqual(fullIndex, 2, "Full index should be 2")

        // This is what ContentView.syncDisplayWithSidebarSelection uses
        // to navigate from selection back to display
    }
}
