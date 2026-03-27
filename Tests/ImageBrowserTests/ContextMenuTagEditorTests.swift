import XCTest
import GRDB
@testable import ImageBrowser

/// Tests for context menu tag editor end-to-end flow
///
/// Regression tests for Issue 8: Context menu doesn't refresh to show applied tags
/// and bug where new tags aren't persisted (showing "Applying to 0 images").
@MainActor
final class ContextMenuTagEditorTests: XCTestCase {

    private var dbPool: DatabasePool!
    private var tagStore: TagStore!
    private var imageStore: ImageStore!
    private var filterStore: FilterStore!
    private var galleryStore: GalleryStore!
    private var appState: AppState!

    override func setUp() async throws {
        let dbPath = NSTemporaryDirectory() + "context_menu_editor_\(UUID().uuidString).db"
        dbPool = try DatabasePool(path: dbPath)
        try await createSchema()

        filterStore = FilterStore()
        tagStore = TagStore(dbPool: dbPool)
        imageStore = ImageStore(dbPool: dbPool, filtering: filterStore, tagLookup: tagStore)
        appState = makeAppState(preferencesStore: InMemoryPreferencesStore())

        galleryStore = GalleryStore(
            imageSource: appState,
            metadataSource: imageStore,
            filtering: filterStore,
            tagLookup: tagStore
        )
    }

    override func tearDown() async throws {
        galleryStore = nil
        appState = nil
        imageStore = nil
        filterStore = nil
        tagStore = nil
        dbPool = nil
    }

    // MARK: - Test: Single Image Context Menu Flow

    func testContextMenuEditor_SingleImage_URIsArePassed() async throws {
        // Given: 1 image in database and visible in gallery
        let imageURL = "file:///tmp/test-single.jpg"
        try await insertImage(url: imageURL)

        // Add image to AppState (simulating folder scan)
        let imageFile = ImageFile(
            url: URL(string: imageURL)!,
            name: "test-single.jpg",
            creationDate: Date()
        )
        appState.images = [imageFile]

        // Wait for galleryStore to recompute
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // When: Resolve target URLs for the image
        let displayImage = galleryStore.snapshot.visibleImages.first!
        let targetURLs = ContextMenuTaggingModel.resolveTargetImageURLs(
            clickedImageID: displayImage.id,
            selectedImageIDs: [],
            visibleImages: galleryStore.snapshot.visibleImages
        )

        // Then: Should have exactly 1 URL
        XCTAssertEqual(targetURLs.count, 1, "Should resolve 1 image URL")
        XCTAssertEqual(targetURLs.first, imageURL, "URL should match image URL")
    }

    // MARK: - Test: Apply New Tag to Single Image

    func testContextMenuEditor_ApplyNewTag_Succeeds() async throws {
        // Given: 1 image in database and visible in gallery
        let imageURL = "file:///tmp/test-apply.jpg"
        try await insertImage(url: imageURL)

        let imageFile = ImageFile(
            url: URL(string: imageURL)!,
            name: "test-apply.jpg",
            creationDate: Date()
        )
        appState.images = [imageFile]

        // Wait for galleryStore to recompute
        try await Task.sleep(nanoseconds: 200_000_000)

        let displayImage = galleryStore.snapshot.visibleImages.first!
        let targetURLs = ContextMenuTaggingModel.resolveTargetImageURLs(
            clickedImageID: displayImage.id,
            selectedImageIDs: [],
            visibleImages: galleryStore.snapshot.visibleImages
        )

        // Verify URL was resolved
        XCTAssertEqual(targetURLs.count, 1, "Should have 1 target URL")

        // When: Apply a NEW tag to the image
        let newTag = "TestTag"

        // This is what ContextMenuTagEditor.applyTags() does
        let result = try await tagStore.addTagsToImages([newTag], to: targetURLs)

        // Then: Tag should be saved successfully
        XCTAssertEqual(result.success, 1, "Should successfully tag 1 image")
        XCTAssertEqual(result.failed, 0, "Should have no failures")

        // Verify tag was created in database
        let allTags = await tagStore.fetchAllTags()
        XCTAssertTrue(allTags.contains(newTag), "New tag should be created")

        // Verify image has the tag
        let imageTags = await tagStore.tagsForImage(imageURL)
        XCTAssertEqual(imageTags, Set([newTag]), "Image should have the new tag")
    }

    // MARK: - Test: Multi-Select Context Menu Flow

    func testContextMenuEditor_MultiSelect_URIsArePassed() async throws {
        // Given: 3 images in database and visible in gallery
        let image1URL = "file:///tmp/multi1.jpg"
        let image2URL = "file:///tmp/multi2.jpg"
        let image3URL = "file:///tmp/multi3.jpg"

        try await insertImage(url: image1URL)
        try await insertImage(url: image2URL)
        try await insertImage(url: image3URL)

        let images = [
            ImageFile(url: URL(string: image1URL)!, name: "multi1.jpg", creationDate: Date()),
            ImageFile(url: URL(string: image2URL)!, name: "multi2.jpg", creationDate: Date()),
            ImageFile(url: URL(string: image3URL)!, name: "multi3.jpg", creationDate: Date())
        ]
        appState.images = images

        // Wait for galleryStore to recompute
        try await Task.sleep(nanoseconds: 200_000_000)

        let visibleImages = galleryStore.snapshot.visibleImages
        let selectedIDs = Set([visibleImages[0].id, visibleImages[2].id])

        // When: Resolve target URLs for multi-select (first and third images)
        let targetURLs = ContextMenuTaggingModel.resolveTargetImageURLs(
            clickedImageID: visibleImages[0].id,
            selectedImageIDs: selectedIDs,
            visibleImages: visibleImages
        )

        // Then: Should have exactly 2 URLs
        XCTAssertEqual(targetURLs.count, 2, "Should resolve 2 selected image URLs")
        XCTAssertTrue(targetURLs.contains(image1URL), "Should contain first image URL")
        XCTAssertTrue(targetURLs.contains(image3URL), "Should contain third image URL")
        XCTAssertFalse(targetURLs.contains(image2URL), "Should NOT contain second image URL")
    }

    // MARK: - Test: URL Format Consistency

    func testContextMenuEditor_URLFormat_ConsistentWithDatabase() async throws {
        // Given: 1 image with URL as stored in database
        let imageURL = "file:///tmp/url-format.jpg"
        try await insertImage(url: imageURL)

        let imageFile = ImageFile(
            url: URL(string: imageURL)!,
            name: "url-format.jpg",
            creationDate: Date()
        )
        appState.images = [imageFile]

        try await Task.sleep(nanoseconds: 200_000_000)

        // When: Resolve target URLs
        let displayImage = galleryStore.snapshot.visibleImages.first!
        let targetURLs = ContextMenuTaggingModel.resolveTargetImageURLs(
            clickedImageID: displayImage.id,
            selectedImageIDs: [],
            visibleImages: galleryStore.snapshot.visibleImages
        )

        // Then: URL format should match database format
        let resolvedURL = targetURLs.first!

        // Verify URL exists in database
        let existsInDB = try await dbPool.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM image_metadata WHERE url = ?)",
                arguments: [resolvedURL]
            ) ?? false
        }

        XCTAssertTrue(existsInDB, "Resolved URL should exist in database")
    }

    // MARK: - Private Helpers

    private func createSchema() async throws {
        try await dbPool.write { db in
            try db.execute(sql: """
                CREATE TABLE image_metadata (
                    url TEXT PRIMARY KEY,
                    rating INTEGER NOT NULL DEFAULT 0,
                    isFavorite BOOLEAN NOT NULL DEFAULT 0,
                    isExcluded BOOLEAN NOT NULL DEFAULT 0,
                    excludedAt TEXT,
                    createdAt TEXT NOT NULL,
                    updatedAt TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE tags (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL COLLATE NOCASE UNIQUE
                )
                """)

            try db.execute(sql: """
                CREATE TABLE image_tags (
                    url TEXT NOT NULL REFERENCES image_metadata(url) ON DELETE CASCADE,
                    tagId INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
                    PRIMARY KEY (url, tagId)
                )
                """)
        }
    }

    private func insertImage(url: String) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                INSERT INTO image_metadata (url, rating, isFavorite, isExcluded, excludedAt, createdAt, updatedAt)
                VALUES (?, 0, 0, 0, NULL, ?, ?)
                """,
                arguments: [url, Date(), Date()]
            )
        }
    }
}
