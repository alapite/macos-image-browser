import XCTest
import GRDB
@testable import ImageBrowser

/// Tests for batch tag apply to multiple images
///
/// Regression tests for G11-03: Context-menu tagging for multi-select fails
/// with SQLite FOREIGN KEY constraint error on image_tags insert.
///
/// These tests ensure:
/// 1. Existing tags apply to multiple images successfully
/// 2. NEW tags create and apply to multiple images atomically
/// 3. Mixed existing/new tags apply successfully
/// 4. Transactional integrity (all-or-nothing)
@MainActor
final class BatchTaggingTests: XCTestCase {

    private var dbPool: DatabasePool!
    private var tagStore: TagStore!

    override func setUp() async throws {
        let dbPath = NSTemporaryDirectory() + "batch_tagging_\(UUID().uuidString).db"
        dbPool = try DatabasePool(path: dbPath)
        try await createSchema()
        tagStore = TagStore(dbPool: dbPool)
    }

    override func tearDown() async throws {
        tagStore = nil
        dbPool = nil
    }

    // MARK: - Test: Existing Tag to Multiple Images

    func testMultiImageTagApply_ExistingTag_Succeeds() async throws {
        // Given: 3 images in database and an existing tag "Nature"
        let image1URL = "file:///tmp/image1.jpg"
        let image2URL = "file:///tmp/image2.jpg"
        let image3URL = "file:///tmp/image3.jpg"

        try await insertImage(url: image1URL)
        try await insertImage(url: image2URL)
        try await insertImage(url: image3URL)

        try await tagStore.addTag("Nature")

        // When: Apply existing tag to all 3 images
        _ = try await tagStore.addTagsToImages(["Nature"], to: [image1URL, image2URL, image3URL])

        // Then: All 3 images should have the tag
        let tags1 = await tagStore.tagsForImage(image1URL)
        let tags2 = await tagStore.tagsForImage(image2URL)
        let tags3 = await tagStore.tagsForImage(image3URL)

        XCTAssertEqual(tags1, Set(["Nature"]), "Image 1 should have Nature tag")
        XCTAssertEqual(tags2, Set(["Nature"]), "Image 2 should have Nature tag")
        XCTAssertEqual(tags3, Set(["Nature"]), "Image 3 should have Nature tag")
    }

    // MARK: - Test: NEW Tag to Multiple Images

    func testMultiImageTagApply_NewTag_Succeeds() async throws {
        // Given: 3 images in database, tag "Sunset" does NOT exist
        let image1URL = "file:///tmp/sunset1.jpg"
        let image2URL = "file:///tmp/sunset2.jpg"
        let image3URL = "file:///tmp/sunset3.jpg"

        try await insertImage(url: image1URL)
        try await insertImage(url: image2URL)
        try await insertImage(url: image3URL)

        // Verify tag doesn't exist
        let allTagsBefore = await tagStore.fetchAllTags()
        XCTAssertFalse(allTagsBefore.contains("Sunset"), "Sunset tag should not exist yet")

        // When: Apply NEW tag to all 3 images
        _ = try await tagStore.addTagsToImages(["Sunset"], to: [image1URL, image2URL, image3URL])

        // Then: Tag should be created and linked to all 3 images
        let allTagsAfter = await tagStore.fetchAllTags()
        XCTAssertTrue(allTagsAfter.contains("Sunset"), "Sunset tag should be created")

        let tags1 = await tagStore.tagsForImage(image1URL)
        let tags2 = await tagStore.tagsForImage(image2URL)
        let tags3 = await tagStore.tagsForImage(image3URL)

        XCTAssertEqual(tags1, Set(["Sunset"]), "Image 1 should have Sunset tag")
        XCTAssertEqual(tags2, Set(["Sunset"]), "Image 2 should have Sunset tag")
        XCTAssertEqual(tags3, Set(["Sunset"]), "Image 3 should have Sunset tag")

        // Verify tag was created only once
        let tagCount = try await fetchTagCount()
        XCTAssertEqual(tagCount, 1, "Only one Sunset tag should exist")
    }

    // MARK: - Test: Mixed Existing and NEW Tags

    func testMultiImageTagApply_MixedTags_Succeeds() async throws {
        // Given: 3 images, "Nature" exists, "Beach" and "Mountain" are NEW
        let image1URL = "file:///tmp/mixed1.jpg"
        let image2URL = "file:///tmp/mixed2.jpg"
        let image3URL = "file:///tmp/mixed3.jpg"

        try await insertImage(url: image1URL)
        try await insertImage(url: image2URL)
        try await insertImage(url: image3URL)

        try await tagStore.addTag("Nature")  // Existing tag

        // When: Apply mix of existing and new tags to all 3 images
        _ = try await tagStore.addTagsToImages(
            ["Nature", "Beach", "Mountain"],
            to: [image1URL, image2URL, image3URL]
        )

        // Then: All tags should be created/linked to all images
        let allTags = await tagStore.fetchAllTags()
        XCTAssertTrue(allTags.contains("Nature"), "Nature tag should exist")
        XCTAssertTrue(allTags.contains("Beach"), "Beach tag should be created")
        XCTAssertTrue(allTags.contains("Mountain"), "Mountain tag should be created")

        let tags1 = await tagStore.tagsForImage(image1URL)
        let tags2 = await tagStore.tagsForImage(image2URL)
        let tags3 = await tagStore.tagsForImage(image3URL)

        let expectedTags = Set(["Nature", "Beach", "Mountain"])
        XCTAssertEqual(tags1, expectedTags, "Image 1 should have all 3 tags")
        XCTAssertEqual(tags2, expectedTags, "Image 2 should have all 3 tags")
        XCTAssertEqual(tags3, expectedTags, "Image 3 should have all 3 tags")
    }

    // MARK: - Test: Auto-Create Missing Metadata

    func testMultiImageTagApply_AutoCreatesMetadata_WhenMissing() async throws {
        // Given: 2 images in database, 1 image NOT in database
        let image1URL = "file:///tmp/rollback1.jpg"
        let image2URL = "file:///tmp/rollback2.jpg"
        let missingURL = "file:///tmp/not-in-metadata.jpg"

        try await insertImage(url: image1URL)
        try await insertImage(url: image2URL)
        // Intentionally NOT inserting missingURL

        // Verify missingURL doesn't exist in metadata table
        let existsBefore = try await dbPool.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM image_metadata WHERE url = ?)",
                arguments: [missingURL]
            ) ?? false
        }
        XCTAssertFalse(existsBefore, "Missing URL should not exist in metadata table initially")

        // When: Apply tag to mix of existing and missing images
        let result = try await tagStore.addTagsToImages(
            ["TestTag"],
            to: [image1URL, missingURL, image2URL]  // Mix of existing and missing
        )

        // Then: All images should be tagged (metadata auto-created for missing image)
        let tags1 = await tagStore.tagsForImage(image1URL)
        let tags2 = await tagStore.tagsForImage(image2URL)
        let tagsMissing = await tagStore.tagsForImage(missingURL)

        XCTAssertEqual(tags1, Set(["TestTag"]), "Existing image 1 should be tagged")
        XCTAssertEqual(tags2, Set(["TestTag"]), "Existing image 2 should be tagged")
        XCTAssertEqual(tagsMissing, Set(["TestTag"]), "Missing image should be auto-created and tagged")
        XCTAssertEqual(result.success, 3, "All 3 tag operations should succeed")
        XCTAssertEqual(result.failed, 0, "Should have no failures")

        // Verify metadata was auto-created
        let existsAfter = try await dbPool.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM image_metadata WHERE url = ?)",
                arguments: [missingURL]
            ) ?? false
        }
        XCTAssertTrue(existsAfter, "Missing URL should now exist in metadata table")
    }

    // MARK: - Test: Deduplication

    func testMultiImageTagApply_Deduplication_IgnoresDuplicates() async throws {
        // Given: 1 image with "Nature" tag already applied
        let imageURL = "file:///tmp/dedupe.jpg"
        try await insertImage(url: imageURL)

        try await tagStore.addTag("Nature")
        try await tagStore.addTagToImage("Nature", for: imageURL)

        // Verify tag is already applied
        let tagsBefore = await tagStore.tagsForImage(imageURL)
        XCTAssertEqual(tagsBefore, Set(["Nature"]), "Tag should exist before")

        // When: Apply same tag again (should not error or duplicate)
        let result = try await tagStore.addTagsToImages(["Nature"], to: [imageURL])

        // Then: Tag should still exist once (no duplicates)
        let tagsAfter = await tagStore.tagsForImage(imageURL)
        XCTAssertEqual(tagsAfter, Set(["Nature"]), "Tag should exist once after")
        XCTAssertEqual(result.success, 0, "No new association should be counted for duplicate inserts")
        XCTAssertEqual(result.failed, 0)

        // Verify no duplicate associations in database
        let associationCount = try await fetchAssociationCount(for: imageURL, tag: "Nature")
        XCTAssertEqual(associationCount, 1, "Only one association should exist")
    }

    func testMultiImageTagRemove_CountsOnlyActualDeletes() async throws {
        let imageURL = "file:///tmp/remove-count.jpg"
        try await insertImage(url: imageURL)
        try await tagStore.addTag("Nature")
        try await tagStore.addTagToImage("Nature", for: imageURL)

        let firstResult = try await tagStore.removeTagsFromImages(["Nature"], from: [imageURL])
        XCTAssertEqual(firstResult.success, 1, "First delete should count one removed association")
        XCTAssertEqual(firstResult.failed, 0)

        let secondResult = try await tagStore.removeTagsFromImages(["Nature"], from: [imageURL])
        XCTAssertEqual(secondResult.success, 0, "Second delete should be a no-op")
        XCTAssertEqual(secondResult.failed, 0)
    }

    // MARK: - Test: Empty Inputs

    func testMultiImageTagApply_EmptyInputs_ReturnsZero() async throws {
        // Given: Empty inputs
        let emptyTags: Set<String> = []
        let emptyURLs: [String] = []

        // When: Apply with empty inputs
        let result1 = try await tagStore.addTagsToImages(emptyTags, to: ["file:///tmp/test.jpg"])
        let result2 = try await tagStore.addTagsToImages(["Test"], to: emptyURLs)

        // Then: Should return zero success without error
        XCTAssertEqual(result1.success, 0, "Empty tags should return 0")
        XCTAssertEqual(result2.success, 0, "Empty URLs should return 0")
    }

    // MARK: - Test: Large Batch

    func testMultiImageTagApply_LargeBatch_Succeeds() async throws {
        // Given: 10 images and 5 tags (3 existing, 2 new)
        var imageURLs: [String] = []
        for i in 1...10 {
            let url = "file:///tmp/batch\(i).jpg"
            try await insertImage(url: url)
            imageURLs.append(url)
        }

        try await tagStore.addTag("Nature")
        try await tagStore.addTag("Travel")
        // "Wildlife" and "Landscape" are new tags

        // When: Apply 4 tags to 10 images (40 tag operations)
        _ = try await tagStore.addTagsToImages(
            ["Nature", "Travel", "Wildlife", "Landscape"],
            to: imageURLs
        )

        // Then: All images should have all tags
        let expectedTags = Set(["Nature", "Travel", "Wildlife", "Landscape"])
        for imageURL in imageURLs {
            let tags = await tagStore.tagsForImage(imageURL)
            XCTAssertEqual(tags, expectedTags, "Image \(imageURL) should have all tags")
        }

        // Verify all tags exist
        let allTags = await tagStore.fetchAllTags()
        XCTAssertEqual(allTags.count, 4, "All 4 tags should be created")
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

    private func fetchTagCount() async throws -> Int {
        try await dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags") ?? 0
        }
    }

    private func fetchAssociationCount(for imageURL: String, tag: String) async throws -> Int {
        try await dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM image_tags
                WHERE url = ?
                AND tagId = (SELECT id FROM tags WHERE name = ?)
                """,
                arguments: [imageURL, tag]
            ) ?? 0
        }
    }
}
