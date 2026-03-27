import XCTest
@testable import ImageBrowser
import SwiftUI
import GRDB

@MainActor
final class KeyboardNavigationTests: XCTestCase {
    var appState: AppState!
    var imageStore: ImageStore!
    var filterStore: FilterStore!
    var viewStore: ViewStore!
    var galleryStore: GalleryStore!
    var tagStore: TagStore!
    var collectionStore: CollectionStore!
    var dbPool: DatabasePool!

    override func setUp() async throws {
        // Create a temporary database for testing
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("test_keyboard_nav_\(UUID().uuidString).db")

        // Delete existing database if present
        try? FileManager.default.removeItem(at: dbPath)

        // Create database pool
        dbPool = try DatabasePool(path: dbPath.path)

        // Run database migrations to create schema
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        // Register migrations (mirroring AppDatabase.migrator)
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

        // Initialize stores (order matters - some stores depend on others)
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

        // Initialize GalleryStore with all dependencies
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
    }

    // Helper to create test images
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

    private func waitForDisplayIndex(_ index: Int, timeout: TimeInterval = 1.5) async {
        await waitForSnapshot(timeout: timeout) { snapshot in
            snapshot.currentDisplayImage?.fullIndex == index
        }
    }

    // MARK: - Test 1: Up Arrow Synchronization
    func testUpDownArrowSync() async throws {
        // Start at index 5
        XCTAssertEqual(appState.currentImageIndex, 5, "Should start at index 5")

        // Simulate up arrow (previous navigation)
        await MainActor.run {
            appState.navigateToPrevious()
        }

        await waitForDisplayIndex(4)

        // After up arrow: currentImageIndex should be 4
        XCTAssertEqual(appState.currentImageIndex, 4, "Up arrow should decrease currentImageIndex to 4")

        // Check that gallery store's current image reflects the change
        let newCurrentImage = await MainActor.run {
            galleryStore.snapshot.currentDisplayImage
        }
        XCTAssertNotNil(newCurrentImage, "Should have a current display image")
        XCTAssertEqual(newCurrentImage?.fullIndex, 4, "Current display image should be at index 4")
    }

    // MARK: - Test 2: Down Arrow Synchronization
    func testDownArrowSync() async throws {
        // Start at index 5
        XCTAssertEqual(appState.currentImageIndex, 5, "Should start at index 5")

        // Simulate down arrow (next navigation)
        await MainActor.run {
            appState.navigateToNext()
        }

        await waitForDisplayIndex(6)

        // After down arrow: currentImageIndex should be 6
        XCTAssertEqual(appState.currentImageIndex, 6, "Down arrow should increase currentImageIndex to 6")

        // Check that gallery store's current image reflects the change
        let newCurrentImage = await MainActor.run {
            galleryStore.snapshot.currentDisplayImage
        }
        XCTAssertNotNil(newCurrentImage, "Should have a current display image")
        XCTAssertEqual(newCurrentImage?.fullIndex, 6, "Current display image should be at index 6")
    }

    // MARK: - Test 3: Left Arrow Synchronization
    func testLeftRightArrowSync() async throws {
        // Start at index 5
        XCTAssertEqual(appState.currentImageIndex, 5, "Should start at index 5")

        // Simulate left arrow (previous navigation)
        await MainActor.run {
            appState.navigateToPrevious()
        }

        await waitForDisplayIndex(4)

        // After left arrow: currentImageIndex should be 4
        XCTAssertEqual(appState.currentImageIndex, 4, "Left arrow should decrease currentImageIndex to 4")

        // Check that gallery store's current image reflects the change
        let newCurrentImage = await MainActor.run {
            galleryStore.snapshot.currentDisplayImage
        }
        XCTAssertNotNil(newCurrentImage, "Should have a current display image")
        XCTAssertEqual(newCurrentImage?.fullIndex, 4, "Current display image should be at index 4")
    }

    // MARK: - Test 4: Right Arrow Synchronization
    func testRightArrowSync() async throws {
        // Start at index 5
        XCTAssertEqual(appState.currentImageIndex, 5, "Should start at index 5")

        // Simulate right arrow (next navigation)
        await MainActor.run {
            appState.navigateToNext()
        }

        await waitForDisplayIndex(6)

        // After right arrow: currentImageIndex should be 6
        XCTAssertEqual(appState.currentImageIndex, 6, "Right arrow should increase currentImageIndex to 6")

        // Check that gallery store's current image reflects the change
        let newCurrentImage = await MainActor.run {
            galleryStore.snapshot.currentDisplayImage
        }
        XCTAssertNotNil(newCurrentImage, "Should have a current display image")
        XCTAssertEqual(newCurrentImage?.fullIndex, 6, "Current display image should be at index 6")
    }

    // MARK: - Test 5: Selection After Manual Click
    func testSelectionAfterClick() async throws {
        // Start at index 5
        XCTAssertEqual(appState.currentImageIndex, 5, "Should start at index 5")

        // Simulate clicking a thumbnail at index 2 (navigate to that index)
        appState.navigateToIndex(2)

        await waitForDisplayIndex(2)

        // After click: currentImageIndex should be 2
        XCTAssertEqual(appState.currentImageIndex, 2, "Click should set currentImageIndex to 2")

        // Check that gallery store's current image reflects the change
        let newCurrentImage = galleryStore.snapshot.currentDisplayImage
        XCTAssertNotNil(newCurrentImage, "Should have a current display image")
        XCTAssertEqual(newCurrentImage?.fullIndex, 2, "Current display image should be at index 2")

        // Note: Testing subsequent navigation from clicked position is disabled due to
        // Combine publisher timing issues with @MainActor properties in unit tests.
        // The actual SwiftUI integration works correctly as verified by manual testing.
    }

    // MARK: - NEW TESTS FOR SYNCHRONIZATION (G11-01 Gap Closure)

    // Test 6: Up Arrow Updates Both Selection and Display
    func testUpArrowUpdatesSelectionAndDisplay() async throws {
        // Start at index 5
        XCTAssertEqual(appState.currentImageIndex, 5, "Should start at index 5")

        await waitForDisplayIndex(5)

        // Simulate up arrow (previous navigation)
        await MainActor.run {
            appState.navigateToPrevious()
        }

        await waitForDisplayIndex(4)

        // CRITICAL CHECK: Both currentImageIndex AND currentDisplayImage should update to 4
        XCTAssertEqual(appState.currentImageIndex, 4, "Up arrow should decrease currentImageIndex to 4")

        let newDisplayImage = await MainActor.run {
            galleryStore.snapshot.currentDisplayImage
        }
        XCTAssertNotNil(newDisplayImage, "Should have a current display image after up arrow")
        XCTAssertEqual(newDisplayImage?.fullIndex, 4, "Display image should update to index 4 after up arrow")

        // This test FAILS before fix - up arrow updates index but display might not sync
        // Gap G11-01: "Up/down updates thumbnail selection without updating full image"
    }

    // Test 7: Down Arrow Updates Both Selection and Display
    func testDownArrowUpdatesSelectionAndDisplay() async throws {
        // Start at index 5
        XCTAssertEqual(appState.currentImageIndex, 5, "Should start at index 5")

        // Simulate down arrow (next navigation)
        await MainActor.run {
            appState.navigateToNext()
        }

        await waitForDisplayIndex(6)

        // CRITICAL CHECK: Both currentImageIndex AND currentDisplayImage should update to 6
        XCTAssertEqual(appState.currentImageIndex, 6, "Down arrow should increase currentImageIndex to 6")

        let newDisplayImage = await MainActor.run {
            galleryStore.snapshot.currentDisplayImage
        }
        XCTAssertNotNil(newDisplayImage, "Should have a current display image after down arrow")
        XCTAssertEqual(newDisplayImage?.fullIndex, 6, "Display image should update to index 6 after down arrow")

        // This test FAILS before fix - down arrow updates index but display might not sync
    }

    // Test 8: Left Arrow Updates Both Selection and Display
    func testLeftArrowUpdatesSelectionAndDisplay() async throws {
        // Start at index 5
        XCTAssertEqual(appState.currentImageIndex, 5, "Should start at index 5")

        // Simulate left arrow (previous navigation)
        await MainActor.run {
            appState.navigateToPrevious()
        }

        await waitForDisplayIndex(4)

        // CRITICAL CHECK: Both currentImageIndex AND currentDisplayImage should update to 4
        XCTAssertEqual(appState.currentImageIndex, 4, "Left arrow should decrease currentImageIndex to 4")

        let newDisplayImage = await MainActor.run {
            galleryStore.snapshot.currentDisplayImage
        }
        XCTAssertNotNil(newDisplayImage, "Should have a current display image after left arrow")
        XCTAssertEqual(newDisplayImage?.fullIndex, 4, "Display image should update to index 4 after left arrow")

        // This test FAILS before fix - left arrow updates display but selection might not sync
        // Gap G11-01: "Left/right updates full image without selected thumbnail"
    }

    // Test 9: Right Arrow Updates Both Selection and Display
    func testRightArrowUpdatesSelectionAndDisplay() async throws {
        // Start at index 5
        XCTAssertEqual(appState.currentImageIndex, 5, "Should start at index 5")

        // Simulate right arrow (next navigation)
        await MainActor.run {
            appState.navigateToNext()
        }

        await waitForDisplayIndex(6)

        // CRITICAL CHECK: Both currentImageIndex AND currentDisplayImage should update to 6
        XCTAssertEqual(appState.currentImageIndex, 6, "Right arrow should increase currentImageIndex to 6")

        let newDisplayImage = await MainActor.run {
            galleryStore.snapshot.currentDisplayImage
        }
        XCTAssertNotNil(newDisplayImage, "Should have a current display image after right arrow")
        XCTAssertEqual(newDisplayImage?.fullIndex, 6, "Display image should update to index 6 after right arrow")

        // This test FAILS before fix - right arrow updates display but selection might not sync
    }

    // Test 10: Click Then Arrow Navigation Continues From Clicked Position
    func testClickThenArrowNavigation() async throws {
        // Start at index 5
        XCTAssertEqual(appState.currentImageIndex, 5, "Should start at index 5")

        // Simulate clicking thumbnail at index 2
        await MainActor.run {
            appState.navigateToIndex(2)
        }

        await waitForDisplayIndex(2)

        XCTAssertEqual(appState.currentImageIndex, 2, "Click should set currentImageIndex to 2")

        let clickedDisplayImage = await MainActor.run {
            galleryStore.snapshot.currentDisplayImage
        }
        XCTAssertEqual(clickedDisplayImage?.fullIndex, 2, "Display image should be at index 2 after click")

        // Now press right arrow (next) from index 2
        await MainActor.run {
            appState.navigateToNext()
        }

        await waitForDisplayIndex(3)

        // CRITICAL CHECK: Should navigate to index 3 (next from clicked position 2)
        XCTAssertEqual(appState.currentImageIndex, 3, "After click then right arrow, should be at index 3")

        let finalDisplayImage = await MainActor.run {
            galleryStore.snapshot.currentDisplayImage
        }
        XCTAssertNotNil(finalDisplayImage, "Should have a current display image after arrow")
        XCTAssertEqual(finalDisplayImage?.fullIndex, 3, "Display image should be at index 3 after arrow from clicked position")

        // This test FAILS before fix - arrow navigation might not continue from clicked position
        // or selection/desynchronization might occur
    }
}
