import XCTest
import GRDB
@testable import ImageBrowser

@MainActor
final class ContextMenuExclusionTests: XCTestCase {
    private var dbPool: DatabasePool!
    private var imageStore: ImageStore!
    private var filterStore: FilterStore!
    private var tagStore: TagStore!
    private var galleryStore: GalleryStore!
    private var appState: AppState!

    override func setUp() async throws {
        let dbPath = NSTemporaryDirectory() + "context_menu_exclusion_\(UUID().uuidString).db"
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

    func testContextMenuExclude_persistsExcludedStateForResolvedTargets() async throws {
        let imageOneURL = "file:///tmp/context-exclude-1.jpg"
        let imageTwoURL = "file:///tmp/context-exclude-2.jpg"
        let imageThreeURL = "file:///tmp/context-exclude-3.jpg"
        try await insertImage(url: imageOneURL)
        try await insertImage(url: imageTwoURL)
        try await insertImage(url: imageThreeURL)

        appState.images = [
            ImageFile(url: URL(string: imageOneURL)!, name: "context-exclude-1.jpg", creationDate: Date()),
            ImageFile(url: URL(string: imageTwoURL)!, name: "context-exclude-2.jpg", creationDate: Date()),
            ImageFile(url: URL(string: imageThreeURL)!, name: "context-exclude-3.jpg", creationDate: Date())
        ]
        try await waitForVisibleImages(count: 3)

        let visibleImages = galleryStore.snapshot.visibleImages
        let selectedIDs = Set([visibleImages[0].id, visibleImages[2].id])

        let result = await ContextMenuExclusionModel.excludeTargets(
            clickedImageID: visibleImages[0].id,
            selectedImageIDs: selectedIDs,
            visibleImages: visibleImages,
            persist: { [imageStore] imageURL in
                await imageStore?.updateExcludedWithRetry(for: imageURL, isExcluded: true) ?? false
            }
        )

        XCTAssertEqual(
            Set(result.targetURLs),
            Set([imageOneURL, imageThreeURL])
        )
        XCTAssertEqual(result.successfulExclusionCount, 2)
        XCTAssertEqual(result.failedExclusionCount, 0)
        XCTAssertEqual(result.toastMessage, "Excluded 2 images from normal browsing")

        let savedMetadata = try await dbPool.read { db in
            try ImageMetadataRecord
                .filter(Column("url") == imageOneURL || Column("url") == imageThreeURL)
                .fetchAll(db)
        }
        XCTAssertEqual(savedMetadata.count, 2)
        XCTAssertTrue(savedMetadata.allSatisfy(\.isExcluded))
        XCTAssertTrue(savedMetadata.allSatisfy { $0.excludedAt != nil })
    }

    func testContextMenuExclude_usesClickedImageWhenSelectionDoesNotContainIt() async throws {
        let imageOneURL = "file:///tmp/context-clicked-1.jpg"
        let imageTwoURL = "file:///tmp/context-clicked-2.jpg"
        let imageThreeURL = "file:///tmp/context-clicked-3.jpg"
        try await insertImage(url: imageOneURL)
        try await insertImage(url: imageTwoURL)
        try await insertImage(url: imageThreeURL)

        appState.images = [
            ImageFile(url: URL(string: imageOneURL)!, name: "context-clicked-1.jpg", creationDate: Date()),
            ImageFile(url: URL(string: imageTwoURL)!, name: "context-clicked-2.jpg", creationDate: Date()),
            ImageFile(url: URL(string: imageThreeURL)!, name: "context-clicked-3.jpg", creationDate: Date())
        ]
        try await waitForVisibleImages(count: 3)

        let visibleImages = galleryStore.snapshot.visibleImages
        let result = await ContextMenuExclusionModel.excludeTargets(
            clickedImageID: visibleImages[1].id,
            selectedImageIDs: [visibleImages[0].id],
            visibleImages: visibleImages,
            persist: { _ in true }
        )

        XCTAssertEqual(result.targetURLs, [imageTwoURL])
        XCTAssertEqual(result.successfulExclusionCount, 1)
        XCTAssertEqual(result.failedExclusionCount, 0)
        XCTAssertEqual(result.toastMessage, "Excluded from normal browsing")
    }

    func testContextMenuExclude_isNonDestructiveToUnderlyingFile() async throws {
        let imageURL = try makeRealImageFileURL(named: "context-menu-nondestructive.jpg")
        let standardizedURL = imageURL.standardizedFileURL.absoluteString
        try await insertImage(url: standardizedURL)

        appState.images = [
            ImageFile(url: imageURL, name: imageURL.lastPathComponent, creationDate: Date())
        ]
        try await waitForVisibleImages(count: 1)

        let visibleImage = try XCTUnwrap(galleryStore.snapshot.visibleImages.first)
        let result = await ContextMenuExclusionModel.excludeTargets(
            clickedImageID: visibleImage.id,
            selectedImageIDs: [],
            visibleImages: [visibleImage],
            persist: { [imageStore] imageURL in
                await imageStore?.updateExcludedWithRetry(for: imageURL, isExcluded: true) ?? false
            }
        )

        XCTAssertEqual(result.targetURLs, [standardizedURL])
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
    }

    func testContextMenuExclude_resultMessageMatchesSingleAndMultiSelectCounts() async {
        let visibleImages = [
            DisplayImage(
                id: "one",
                url: URL(fileURLWithPath: "/tmp/message-one.jpg"),
                name: "message-one.jpg",
                creationDate: Date(),
                rating: 0,
                isFavorite: false,
                fileSizeBytes: 100,
                fullIndex: 0,
                hasLoadError: false,
                isUnsupportedFormat: false
            ),
            DisplayImage(
                id: "two",
                url: URL(fileURLWithPath: "/tmp/message-two.jpg"),
                name: "message-two.jpg",
                creationDate: Date(),
                rating: 0,
                isFavorite: false,
                fileSizeBytes: 100,
                fullIndex: 1,
                hasLoadError: false,
                isUnsupportedFormat: false
            )
        ]

        let singleResult = await ContextMenuExclusionModel.excludeTargets(
            clickedImageID: "one",
            selectedImageIDs: [],
            visibleImages: visibleImages,
            persist: { _ in true }
        )
        XCTAssertEqual(singleResult.toastMessage, "Excluded from normal browsing")

        let multiResult = await ContextMenuExclusionModel.excludeTargets(
            clickedImageID: "one",
            selectedImageIDs: ["one", "two"],
            visibleImages: visibleImages,
            persist: { _ in true }
        )
        XCTAssertEqual(multiResult.toastMessage, "Excluded 2 images from normal browsing")
    }

    // MARK: - Restore Targets Tests

    func testRestoreTargets_singleSelection_resolvesClickedImage() async {
        let visibleImages = [
            DisplayImage(
                id: "excluded-one",
                url: URL(fileURLWithPath: "/tmp/restore-single.jpg"),
                name: "restore-single.jpg",
                creationDate: Date(),
                rating: 0,
                isFavorite: false,
                isExcluded: true,
                excludedAt: nil,
                fileSizeBytes: 100,
                fullIndex: 0,
                hasLoadError: false,
                isUnsupportedFormat: false
            )
        ]

        let result = await ContextMenuExclusionModel.restoreTargets(
            clickedImageID: "excluded-one",
            selectedImageIDs: [],
            visibleImages: visibleImages,
            persist: { _ in true }
        )

        XCTAssertEqual(result.targetURLs, ["file:///tmp/restore-single.jpg"])
        XCTAssertEqual(result.successfulExclusionCount, 1)
        XCTAssertEqual(result.failedExclusionCount, 0)
    }

    func testRestoreTargets_multiSelection_resolvesSelectedSet() async {
        let visibleImages = [
            DisplayImage(
                id: "excluded-one",
                url: URL(fileURLWithPath: "/tmp/restore-multi-1.jpg"),
                name: "restore-multi-1.jpg",
                creationDate: Date(),
                rating: 0,
                isFavorite: false,
                isExcluded: true,
                excludedAt: nil,
                fileSizeBytes: 100,
                fullIndex: 0,
                hasLoadError: false,
                isUnsupportedFormat: false
            ),
            DisplayImage(
                id: "excluded-two",
                url: URL(fileURLWithPath: "/tmp/restore-multi-2.jpg"),
                name: "restore-multi-2.jpg",
                creationDate: Date(),
                rating: 0,
                isFavorite: false,
                isExcluded: true,
                excludedAt: nil,
                fileSizeBytes: 100,
                fullIndex: 1,
                hasLoadError: false,
                isUnsupportedFormat: false
            )
        ]

        let result = await ContextMenuExclusionModel.restoreTargets(
            clickedImageID: "excluded-one",
            selectedImageIDs: ["excluded-one", "excluded-two"],
            visibleImages: visibleImages,
            persist: { _ in true }
        )

        XCTAssertEqual(Set(result.targetURLs), Set(["file:///tmp/restore-multi-1.jpg", "file:///tmp/restore-multi-2.jpg"]))
        XCTAssertEqual(result.successfulExclusionCount, 2)
        XCTAssertEqual(result.failedExclusionCount, 0)
    }

    func testRestoreTargets_successUpdatesResult() async {
        let visibleImages = [
            DisplayImage(
                id: "restore-success",
                url: URL(fileURLWithPath: "/tmp/restore-success.jpg"),
                name: "restore-success.jpg",
                creationDate: Date(),
                rating: 0,
                isFavorite: false,
                isExcluded: true,
                excludedAt: nil,
                fileSizeBytes: 100,
                fullIndex: 0,
                hasLoadError: false,
                isUnsupportedFormat: false
            )
        ]

        let result = await ContextMenuExclusionModel.restoreTargets(
            clickedImageID: "restore-success",
            selectedImageIDs: [],
            visibleImages: visibleImages,
            persist: { _ in true }
        )

        XCTAssertEqual(result.toastMessage, "Restored to normal browsing")
        XCTAssertEqual(result.successfulExclusionCount, 1)
        XCTAssertEqual(result.failedExclusionCount, 0)
    }

    func testRestoreTargets_multipleImages_showsCorrectToast() async {
        let visibleImages = [
            DisplayImage(
                id: "restore-multi-1",
                url: URL(fileURLWithPath: "/tmp/restore-2a.jpg"),
                name: "restore-2a.jpg",
                creationDate: Date(),
                rating: 0,
                isFavorite: false,
                isExcluded: true,
                excludedAt: nil,
                fileSizeBytes: 100,
                fullIndex: 0,
                hasLoadError: false,
                isUnsupportedFormat: false
            ),
            DisplayImage(
                id: "restore-multi-2",
                url: URL(fileURLWithPath: "/tmp/restore-2b.jpg"),
                name: "restore-2b.jpg",
                creationDate: Date(),
                rating: 0,
                isFavorite: false,
                isExcluded: true,
                excludedAt: nil,
                fileSizeBytes: 100,
                fullIndex: 1,
                hasLoadError: false,
                isUnsupportedFormat: false
            )
        ]

        let result = await ContextMenuExclusionModel.restoreTargets(
            clickedImageID: "restore-multi-1",
            selectedImageIDs: ["restore-multi-1", "restore-multi-2"],
            visibleImages: visibleImages,
            persist: { _ in true }
        )

        XCTAssertEqual(result.toastMessage, "Restored 2 images to normal browsing")
        XCTAssertEqual(result.successfulExclusionCount, 2)
    }

    func testRestoreTargets_usesClickedImageWhenSelectionDoesNotContainIt() async {
        let visibleImages = [
            DisplayImage(
                id: "not-selected",
                url: URL(fileURLWithPath: "/tmp/not-selected.jpg"),
                name: "not-selected.jpg",
                creationDate: Date(),
                rating: 0,
                isFavorite: false,
                isExcluded: true,
                excludedAt: nil,
                fileSizeBytes: 100,
                fullIndex: 0,
                hasLoadError: false,
                isUnsupportedFormat: false
            ),
            DisplayImage(
                id: "selected",
                url: URL(fileURLWithPath: "/tmp/selected.jpg"),
                name: "selected.jpg",
                creationDate: Date(),
                rating: 0,
                isFavorite: false,
                isExcluded: true,
                excludedAt: nil,
                fileSizeBytes: 100,
                fullIndex: 1,
                hasLoadError: false,
                isUnsupportedFormat: false
            )
        ]

        let result = await ContextMenuExclusionModel.restoreTargets(
            clickedImageID: "not-selected",
            selectedImageIDs: ["selected"],
            visibleImages: visibleImages,
            persist: { _ in true }
        )

        XCTAssertEqual(result.targetURLs, ["file:///tmp/not-selected.jpg"])
        XCTAssertEqual(result.successfulExclusionCount, 1)
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

    private func waitForVisibleImages(count: Int) async throws {
        let timeout = Date().addingTimeInterval(2)
        while Date() < timeout {
            if galleryStore.snapshot.visibleImages.count == count {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("Timed out waiting for \(count) visible images")
    }

    private func makeRealImageFileURL(named name: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        let data = Data("test-image".utf8)
        try data.write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
