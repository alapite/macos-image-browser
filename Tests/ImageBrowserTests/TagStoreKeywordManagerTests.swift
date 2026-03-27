import XCTest
import GRDB
@testable import ImageBrowser

@MainActor
final class TagStoreKeywordManagerTests: XCTestCase {
    private var dbPool: DatabasePool!
    private var tagStore: TagStore!

    override func setUp() async throws {
        try await super.setUp()

        let dbPath = NSTemporaryDirectory() + "tag_store_keyword_manager_\(UUID().uuidString).db"
        dbPool = try DatabasePool(path: dbPath)
        try await createSchema()
        tagStore = TagStore(dbPool: dbPool)
    }

    override func tearDown() async throws {
        tagStore = nil
        dbPool = nil
        try await super.tearDown()
    }

    func testRenameTagPreservesImageAssociations() async throws {
        let imageURL = "file:///tmp/rename.jpg"
        try await insertImage(url: imageURL)

        try await tagStore.addTag("Nature")
        try await tagStore.addTagToImage("Nature", for: imageURL)

        try await tagStore.renameTag(from: "Nature", to: "Landscape")

        let renamedTags = await tagStore.tagsForImage(imageURL)
        XCTAssertEqual(renamedTags, Set(["Landscape"]))

        let persistedTags = try await fetchTagNames()
        XCTAssertEqual(persistedTags, ["Landscape"])
    }

    func testMergeTagsMovesAssociationsAndRemovesSourceTag() async throws {
        let firstImage = "file:///tmp/merge-1.jpg"
        let secondImage = "file:///tmp/merge-2.jpg"
        try await insertImage(url: firstImage)
        try await insertImage(url: secondImage)

        try await tagStore.addTag("Travel")
        try await tagStore.addTag("Vacation")
        try await tagStore.addTagToImage("Travel", for: firstImage)
        try await tagStore.addTagToImage("Travel", for: secondImage)

        try await tagStore.mergeTags(source: "Travel", destination: "Vacation")

        let firstTags = await tagStore.tagsForImage(firstImage)
        let secondTags = await tagStore.tagsForImage(secondImage)

        XCTAssertEqual(firstTags, Set(["Vacation"]))
        XCTAssertEqual(secondTags, Set(["Vacation"]))

        let tagNames = try await fetchTagNames()
        XCTAssertEqual(tagNames, ["Vacation"])
    }

    func testMergeTagsIsIdempotentWhenDestinationAssociationExists() async throws {
        let imageURL = "file:///tmp/merge-idempotent.jpg"
        try await insertImage(url: imageURL)

        try await tagStore.addTag("Travel")
        try await tagStore.addTag("Vacation")
        try await tagStore.addTagToImage("Travel", for: imageURL)
        try await tagStore.addTagToImage("Vacation", for: imageURL)

        try await tagStore.mergeTags(source: "Travel", destination: "Vacation")

        let destinationAssociationCount = try await fetchAssociationCount(for: imageURL, tag: "Vacation")
        XCTAssertEqual(destinationAssociationCount, 1)

        let tagNames = try await fetchTagNames()
        XCTAssertEqual(tagNames, ["Vacation"])
    }

    func testTagLookup_normalizesFileURLVariants() async throws {
        let canonicalURL = "file:///tmp/canonical-tag.jpg"
        let variantURL = "file:///tmp/../tmp/canonical-tag.jpg"
        try await insertImage(url: canonicalURL)

        try await tagStore.addTag("Nature")
        try await tagStore.addTagToImage("Nature", for: variantURL)

        let tagsFromCanonical = await tagStore.tagsForImage(canonicalURL)
        let tagsFromVariant = await tagStore.tagsForImage(variantURL)

        XCTAssertEqual(tagsFromCanonical, Set(["Nature"]))
        XCTAssertEqual(tagsFromVariant, Set(["Nature"]))
    }

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

    private func fetchTagNames() async throws -> [String] {
        try await dbPool.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM tags ORDER BY name COLLATE NOCASE ASC")
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
