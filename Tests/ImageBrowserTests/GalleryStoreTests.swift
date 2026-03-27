import XCTest
import GRDB
@testable import ImageBrowser

@MainActor
final class GalleryStoreTests: XCTestCase {
    private var appState: AppState!
    private var filterStore: FilterStore!
    private var imageStore: ImageStore!
    private var tagStore: TagStore!
    private var collectionStore: CollectionStore!
    private var galleryStore: GalleryStore!
    private var dbPool: DatabasePool!

    override func setUp() async throws {
        try await super.setUp()

        let dbPath = NSTemporaryDirectory() + "gallery_store_test_\(UUID().uuidString).db"
        dbPool = try DatabasePool(path: dbPath)
        try await dbPool.write { db in
            try db.create(table: "image_metadata", ifNotExists: true) { table in
                table.column("url", .text).primaryKey()
                table.column("rating", .integer).notNull().defaults(to: 0)
                table.column("isFavorite", .boolean).notNull().defaults(to: false)
                table.column("isExcluded", .boolean).notNull().defaults(to: false)
                table.column("excludedAt", .datetime)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "tags", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).unique().notNull()
            }

            try db.create(table: "image_tags", ifNotExists: true) { table in
                table.column("url", .text).references("image_metadata", column: "url", onDelete: .cascade)
                table.column("tagId", .integer).references("tags", column: "id", onDelete: .cascade)
                table.primaryKey(["url", "tagId"])
            }

            try db.create(table: "smart_collections", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull().unique()
                table.column("rules", .blob).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
        }

        appState = makeAppState(preferencesStore: InMemoryPreferencesStore())
        filterStore = FilterStore()
        imageStore = ImageStore(dbPool: dbPool, filtering: filterStore)
        tagStore = TagStore(dbPool: dbPool)
        collectionStore = CollectionStore(
            dbPool: dbPool,
            imageSource: appState,
            tagStore: tagStore,
            includesPresetCollections: false
        )
        galleryStore = GalleryStore(
            imageSource: appState,
            metadataSource: imageStore,
            filtering: filterStore,
            tagLookup: tagStore,
            collectionSource: collectionStore
        )
    }

    override func tearDown() async throws {
        galleryStore = nil
        imageStore = nil
        tagStore = nil
        collectionStore = nil
        filterStore = nil
        appState = nil
        dbPool = nil
        try await super.tearDown()
    }

    func testSnapshot_usesAppStateImagesAndMergesMetadata() async {
        let firstURL = URL(fileURLWithPath: "/tmp/gallery-1.jpg")
        let secondURL = URL(fileURLWithPath: "/tmp/gallery-2.jpg")

        appState.images = [
            ImageFile(url: firstURL, name: "gallery-1.jpg", creationDate: Date(), fileSizeBytes: 1_000),
            ImageFile(url: secondURL, name: "gallery-2.jpg", creationDate: Date(), fileSizeBytes: 2_000)
        ]
        appState.failedImages = [secondURL]

        try? await upsertMetadata(url: firstURL, rating: 4, isFavorite: true)

        await waitForSnapshot {
            $0.filteredCount == 2
                && $0.currentDisplayImage?.rating == 4
                && $0.currentDisplayImage?.isFavorite == true
        }

        XCTAssertEqual(galleryStore.snapshot.totalCount, 2)
        XCTAssertEqual(galleryStore.snapshot.filteredCount, 2)
        XCTAssertEqual(galleryStore.snapshot.currentDisplayImage?.rating, 4, "Current image should include metadata merge")
        XCTAssertEqual(galleryStore.snapshot.currentDisplayImage?.isFavorite, true, "Current image should include metadata merge")
        XCTAssertEqual(galleryStore.snapshot.visibleImages.last?.hasLoadError, true, "Failed image state should be reflected in snapshot")
    }

    func testSnapshot_fileSizeFilterUsesStoredFileSize() async {
        appState.images = [
            ImageFile(
                url: URL(fileURLWithPath: "/tmp/small.jpg"),
                name: "small.jpg",
                creationDate: Date(),
                fileSizeBytes: 1_500_000
            ),
            ImageFile(
                url: URL(fileURLWithPath: "/tmp/large.jpg"),
                name: "large.jpg",
                creationDate: Date(),
                fileSizeBytes: 12_000_000
            )
        ]

        await waitForSnapshot { $0.filteredCount == 2 }

        filterStore.fileSizeFilter = .large
        await waitForSnapshot { $0.filteredCount == 1 }

        XCTAssertEqual(galleryStore.snapshot.visibleImages.first?.name, "large.jpg")
    }

    func testSnapshot_marksUnsupportedAdvancedFormatsSeparatelyFromGenericLoadErrors() async {
        let unsupportedURL = URL(fileURLWithPath: "/tmp/unsupported.cr3")
        let failedURL = URL(fileURLWithPath: "/tmp/broken.jpg")

        appState.images = [
            ImageFile(url: unsupportedURL, name: "unsupported.cr3", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: failedURL, name: "broken.jpg", creationDate: Date(), fileSizeBytes: 100)
        ]
        appState.unsupportedImages = [unsupportedURL]
        appState.failedImages = [failedURL]

        await waitForSnapshot { snapshot in
            snapshot.visibleImages.count == 2
        }

        let unsupportedImage = galleryStore.snapshot.visibleImages.first(where: { $0.url == unsupportedURL })
        let failedImage = galleryStore.snapshot.visibleImages.first(where: { $0.url == failedURL })
        XCTAssertEqual(unsupportedImage?.isUnsupportedFormat, true)
        XCTAssertEqual(unsupportedImage?.hasLoadError, false)
        XCTAssertEqual(failedImage?.isUnsupportedFormat, false)
        XCTAssertEqual(failedImage?.hasLoadError, true)
    }

    func testSnapshot_preservesHeicTiffAndWebpWhenNoUnsupportedStateExists() async {
        appState.images = [
            ImageFile(url: URL(fileURLWithPath: "/tmp/phone.heic"), name: "phone.heic", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: URL(fileURLWithPath: "/tmp/archive.tiff"), name: "archive.tiff", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: URL(fileURLWithPath: "/tmp/web.webp"), name: "web.webp", creationDate: Date(), fileSizeBytes: 100)
        ]

        await waitForSnapshot { snapshot in
            snapshot.visibleImages.count == 3
        }

        XCTAssertEqual(
            Set(galleryStore.snapshot.visibleImages.map(\.name)),
            Set(["phone.heic", "archive.tiff", "web.webp"])
        )
        XCTAssertTrue(galleryStore.snapshot.visibleImages.allSatisfy { !$0.isUnsupportedFormat })
    }

    func testSnapshot_tracksSelectionAndFullIndexMapping() async {
        let urlA = URL(fileURLWithPath: "/tmp/a.jpg")
        let urlB = URL(fileURLWithPath: "/tmp/b.jpg")
        let urlC = URL(fileURLWithPath: "/tmp/c.jpg")

        let imageA = ImageFile(url: urlA, name: "a.jpg", creationDate: Date(), fileSizeBytes: 100)
        let imageB = ImageFile(url: urlB, name: "b.jpg", creationDate: Date(), fileSizeBytes: 200)
        let imageC = ImageFile(url: urlC, name: "c.jpg", creationDate: Date(), fileSizeBytes: 300)
        appState.images = [imageA, imageB, imageC]
        appState.currentImageIndex = 1

        await waitForSnapshot { $0.filteredCount == 3 && $0.selectedImageID == imageB.id }
        XCTAssertEqual(galleryStore.snapshot.selectedImageID, imageB.id)
        XCTAssertEqual(galleryStore.snapshot.fullIndex(for: imageC.id), 2)

        try? await upsertMetadata(url: urlC, rating: 5, isFavorite: true)
        filterStore.showFavoritesOnly = true

        await waitForSnapshot { $0.filteredCount == 1 && $0.visibleImages.first?.id == imageC.id }
        XCTAssertNil(galleryStore.snapshot.selectedImageID, "Selection should clear if current image is filtered out")
        XCTAssertEqual(galleryStore.snapshot.visibleImages.first?.id, imageC.id)
    }

    func testGallerySnapshot_currentImageChangeAvoidsFullRecomputePath() async {
        appState.images = (0..<500).map { index in
            ImageFile(
                url: URL(fileURLWithPath: "/tmp/gallery-selection-\(index).jpg"),
                name: "gallery-selection-\(index).jpg",
                creationDate: Date(timeIntervalSince1970: TimeInterval(index)),
                fileSizeBytes: 100
            )
        }
        appState.currentImageIndex = 10

        await waitForSnapshot { $0.filteredCount == 500 && $0.currentDisplayImage?.id == self.appState.images[10].id }
        try? await Task.sleep(nanoseconds: 200_000_000)
        galleryStore.resetInstrumentationCounts()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(galleryStore.fullRecomputeCount, 0)

        appState.navigateToIndex(200)

        await waitForSnapshot { $0.currentDisplayImage?.id == self.appState.images[200].id }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(
            galleryStore.fullRecomputeCount,
            0,
            "Changing only the current image should avoid rebuilding the full gallery snapshot"
        )
        XCTAssertEqual(galleryStore.snapshot.currentDisplayImage?.id, appState.images[200].id)
        XCTAssertGreaterThan(
            galleryStore.selectionOnlyUpdateCount,
            0,
            "Selection changes should flow through the lightweight snapshot path"
        )
    }

    func testGallerySnapshot_folderSwitchPublishesNoStaleVisibleImages() async throws {
        let folderAURL = URL(fileURLWithPath: "/tmp/folder-a-visible.jpg")
        let folderBURL = URL(fileURLWithPath: "/tmp/folder-b-visible.jpg")

        appState.images = [
            ImageFile(
                url: folderAURL,
                name: "folder-a-visible.jpg",
                creationDate: Date(),
                fileSizeBytes: 100,
                metadata: ImageMetadata(rating: 5, isFavorite: true)
            )
        ]
        filterStore.showFavoritesOnly = true
        await waitForSnapshot { $0.visibleImages.map(\.name) == ["folder-a-visible.jpg"] }

        appState.images = [
            ImageFile(
                url: folderBURL,
                name: "folder-b-visible.jpg",
                creationDate: Date(),
                fileSizeBytes: 100,
                metadata: ImageMetadata(rating: 5, isFavorite: true)
            )
        ]

        await waitForSnapshot { $0.visibleImages.map(\.name) == ["folder-b-visible.jpg"] }
        XCTAssertEqual(galleryStore.snapshot.visibleImages.map(\.name), ["folder-b-visible.jpg"])
        XCTAssertFalse(
            galleryStore.snapshot.visibleImages.contains(where: { $0.name == "folder-a-visible.jpg" }),
            "Publishing a new folder snapshot must not retain stale visible images from the previous folder"
        )
    }

    func testSnapshot_selectedTagsIncludesOnlyMatchingImages() async throws {
        let matchingURL = URL(fileURLWithPath: "/tmp/tag-match.jpg")
        let otherURL = URL(fileURLWithPath: "/tmp/tag-other.jpg")

        appState.images = [
            ImageFile(url: matchingURL, name: "tag-match.jpg", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: otherURL, name: "tag-other.jpg", creationDate: Date(), fileSizeBytes: 100)
        ]

        try await upsertMetadata(url: matchingURL, rating: 0, isFavorite: false)
        try await upsertMetadata(url: otherURL, rating: 0, isFavorite: false)
        try await linkTag("vacation", to: matchingURL)

        await waitForSnapshot { $0.filteredCount == 2 }

        filterStore.selectedTags = ["vacation"]
        await waitForSnapshot { $0.filteredCount == 1 }

        XCTAssertEqual(galleryStore.snapshot.visibleImages.map(\.name), ["tag-match.jpg"])
    }

    func testSnapshot_selectedTagsAppliesOnFirstChange() async throws {
        let vacationURL = URL(fileURLWithPath: "/tmp/first-apply-vacation.jpg")
        let familyURL = URL(fileURLWithPath: "/tmp/first-apply-family.jpg")

        appState.images = [
            ImageFile(url: vacationURL, name: "first-apply-vacation.jpg", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: familyURL, name: "first-apply-family.jpg", creationDate: Date(), fileSizeBytes: 100)
        ]

        try await upsertMetadata(url: vacationURL, rating: 0, isFavorite: false)
        try await upsertMetadata(url: familyURL, rating: 0, isFavorite: false)
        try await linkTag("vacation", to: vacationURL)

        await waitForSnapshot { $0.filteredCount == 2 }

        filterStore.selectedTags.insert("vacation")
        await waitForSnapshot { $0.filteredCount == 1 }

        XCTAssertEqual(galleryStore.snapshot.visibleImages.first?.name, "first-apply-vacation.jpg")
    }

    func testSnapshot_clearingSelectedTagsRestoresAllImages() async throws {
        let vacationURL = URL(fileURLWithPath: "/tmp/clear-vacation.jpg")
        let familyURL = URL(fileURLWithPath: "/tmp/clear-family.jpg")

        appState.images = [
            ImageFile(url: vacationURL, name: "clear-vacation.jpg", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: familyURL, name: "clear-family.jpg", creationDate: Date(), fileSizeBytes: 100)
        ]

        try await upsertMetadata(url: vacationURL, rating: 0, isFavorite: false)
        try await upsertMetadata(url: familyURL, rating: 0, isFavorite: false)
        try await linkTag("vacation", to: vacationURL)

        await waitForSnapshot { $0.filteredCount == 2 }

        filterStore.selectedTags = ["vacation"]
        await waitForSnapshot { $0.filteredCount == 1 }

        filterStore.selectedTags.removeAll()
        await waitForSnapshot { $0.filteredCount == 2 }

        XCTAssertEqual(galleryStore.snapshot.visibleImages.count, 2)
    }

    func testSnapshot_selectedTagsRequireAllTagsToMatch() async throws {
        let bothTagsURL = URL(fileURLWithPath: "/tmp/both-tags.jpg")
        let oneTagURL = URL(fileURLWithPath: "/tmp/one-tag.jpg")

        appState.images = [
            ImageFile(url: bothTagsURL, name: "both-tags.jpg", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: oneTagURL, name: "one-tag.jpg", creationDate: Date(), fileSizeBytes: 100)
        ]

        try await upsertMetadata(url: bothTagsURL, rating: 0, isFavorite: false)
        try await upsertMetadata(url: oneTagURL, rating: 0, isFavorite: false)

        try await linkTag("vacation", to: bothTagsURL)
        try await linkTag("family", to: bothTagsURL)
        try await linkTag("vacation", to: oneTagURL)

        await waitForSnapshot { $0.filteredCount == 2 }

        filterStore.selectedTags = ["vacation", "family"]
        await waitForSnapshot { $0.filteredCount == 1 }

        XCTAssertEqual(galleryStore.snapshot.visibleImages.first?.name, "both-tags.jpg")
    }

    func testSnapshot_clearAllRestoresAllImagesWithCollectionAndFilters() async throws {
        let beachURL = URL(fileURLWithPath: "/tmp/clear-all-beach.jpg")
        let cityURL = URL(fileURLWithPath: "/tmp/clear-all-city.jpg")

        appState.images = [
            ImageFile(url: beachURL, name: "clear-all-beach.jpg", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: cityURL, name: "clear-all-city.jpg", creationDate: Date(), fileSizeBytes: 100)
        ]

        try await upsertMetadata(url: beachURL, rating: 5, isFavorite: true)
        try await upsertMetadata(url: cityURL, rating: 0, isFavorite: false)

        try await collectionStore.createCollection(
            name: "Five Stars",
            rules: CollectionRules(minimumRating: 5)
        )

        await waitForCollection(named: "Five Stars")

        guard let fiveStarsCollection = collectionStore.collections.first(where: { $0.name == "Five Stars" }) else {
            XCTFail("Expected Five Stars collection to exist")
            return
        }

        collectionStore.setActiveCollection(fiveStarsCollection)
        await waitForSnapshot { $0.totalCount == 1 && $0.filteredCount == 1 }

        filterStore.showFavoritesOnly = true
        await waitForSnapshot { $0.filteredCount == 1 }

        clearAllFiltersAndCollection(filterStore: filterStore, collectionStore: collectionStore)
        await waitForSnapshot { $0.totalCount == 2 && $0.filteredCount == 2 }

        XCTAssertNil(collectionStore.activeCollection)
        XCTAssertFalse(filterStore.isActive)
        XCTAssertEqual(galleryStore.snapshot.visibleImages.count, 2)
    }

    func testSnapshot_clearingOnlyCollectionKeepsActiveFiltersApplied() async throws {
        let beachURL = URL(fileURLWithPath: "/tmp/clear-collection-beach.jpg")
        let cityURL = URL(fileURLWithPath: "/tmp/clear-collection-city.jpg")

        appState.images = [
            ImageFile(url: beachURL, name: "clear-collection-beach.jpg", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: cityURL, name: "clear-collection-city.jpg", creationDate: Date(), fileSizeBytes: 100)
        ]

        try await upsertMetadata(url: beachURL, rating: 4, isFavorite: true)
        try await upsertMetadata(url: cityURL, rating: 1, isFavorite: false)

        try await collectionStore.createCollection(
            name: "Four Plus",
            rules: CollectionRules(minimumRating: 4)
        )

        await waitForCollection(named: "Four Plus")

        guard let fourPlusCollection = collectionStore.collections.first(where: { $0.name == "Four Plus" }) else {
            XCTFail("Expected Four Plus collection to exist")
            return
        }

        collectionStore.setActiveCollection(fourPlusCollection)
        await waitForSnapshot { $0.totalCount == 1 && $0.filteredCount == 1 }

        filterStore.showFavoritesOnly = true
        await waitForSnapshot { $0.filteredCount == 1 }

        collectionStore.clearActiveCollection()
        await waitForSnapshot { $0.totalCount == 2 && $0.filteredCount == 1 }

        XCTAssertTrue(filterStore.showFavoritesOnly)
        XCTAssertEqual(galleryStore.snapshot.visibleImages.map(\.name), ["clear-collection-beach.jpg"])
    }

    func testSnapshot_clearAllIsIdempotent() async throws {
        let beachURL = URL(fileURLWithPath: "/tmp/idempotent-beach.jpg")
        let cityURL = URL(fileURLWithPath: "/tmp/idempotent-city.jpg")

        appState.images = [
            ImageFile(url: beachURL, name: "idempotent-beach.jpg", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: cityURL, name: "idempotent-city.jpg", creationDate: Date(), fileSizeBytes: 100)
        ]

        try await upsertMetadata(url: beachURL, rating: 5, isFavorite: true)
        try await upsertMetadata(url: cityURL, rating: 2, isFavorite: false)

        try await collectionStore.createCollection(
            name: "Only Five",
            rules: CollectionRules(minimumRating: 5)
        )

        await waitForCollection(named: "Only Five")

        guard let onlyFiveCollection = collectionStore.collections.first(where: { $0.name == "Only Five" }) else {
            XCTFail("Expected Only Five collection to exist")
            return
        }

        collectionStore.setActiveCollection(onlyFiveCollection)
        filterStore.showFavoritesOnly = true
        await waitForSnapshot { $0.totalCount == 1 && $0.filteredCount == 1 }

        clearAllFiltersAndCollection(filterStore: filterStore, collectionStore: collectionStore)
        await waitForSnapshot { $0.totalCount == 2 && $0.filteredCount == 2 }

        clearAllFiltersAndCollection(filterStore: filterStore, collectionStore: collectionStore)
        await waitForSnapshot { $0.totalCount == 2 && $0.filteredCount == 2 }

        XCTAssertNil(collectionStore.activeCollection)
        XCTAssertFalse(filterStore.isActive)
        XCTAssertEqual(galleryStore.snapshot.visibleImages.count, 2)
    }

    func testSnapshot_activeCollectionUsesUnfilteredTotalCountInSubtitle() async throws {
        let favoriteURL = URL(fileURLWithPath: "/tmp/subtitle-favorite.jpg")
        let otherURL = URL(fileURLWithPath: "/tmp/subtitle-other.jpg")

        appState.images = [
            ImageFile(url: favoriteURL, name: "subtitle-favorite.jpg", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: otherURL, name: "subtitle-other.jpg", creationDate: Date(), fileSizeBytes: 100)
        ]

        try await upsertMetadata(url: favoriteURL, rating: 0, isFavorite: true)
        try await upsertMetadata(url: otherURL, rating: 0, isFavorite: false)

        try await collectionStore.createCollection(
            name: "Favorites Only",
            rules: CollectionRules(favoritesOnly: true)
        )
        await waitForCollection(named: "Favorites Only")

        guard let favoritesCollection = collectionStore.collections.first(where: { $0.name == "Favorites Only" }) else {
            XCTFail("Expected Favorites Only collection to exist")
            return
        }

        collectionStore.setActiveCollection(favoritesCollection)
        await waitForSnapshot { $0.filteredCount == 1 && $0.unfilteredTotalCount == 1 }

        XCTAssertEqual(galleryStore.snapshot.subtitle, "1 image (filtered from 1)")
        XCTAssertEqual(galleryStore.snapshot.activeCollectionName, "Favorites Only")
    }

    func testSnapshot_activeCollectionAndFilterUsesCollectionUnfilteredTotalCount() async throws {
        let favoriteFiveURL = URL(fileURLWithPath: "/tmp/subtitle-five-favorite.jpg")
        let favoriteThreeURL = URL(fileURLWithPath: "/tmp/subtitle-three-favorite.jpg")
        let nonFavoriteFiveURL = URL(fileURLWithPath: "/tmp/subtitle-five-nonfavorite.jpg")

        appState.images = [
            ImageFile(url: favoriteFiveURL, name: "subtitle-five-favorite.jpg", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: favoriteThreeURL, name: "subtitle-three-favorite.jpg", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: nonFavoriteFiveURL, name: "subtitle-five-nonfavorite.jpg", creationDate: Date(), fileSizeBytes: 100)
        ]

        try await upsertMetadata(url: favoriteFiveURL, rating: 5, isFavorite: true)
        try await upsertMetadata(url: favoriteThreeURL, rating: 3, isFavorite: true)
        try await upsertMetadata(url: nonFavoriteFiveURL, rating: 5, isFavorite: false)

        try await collectionStore.createCollection(
            name: "All Favorites",
            rules: CollectionRules(favoritesOnly: true)
        )
        await waitForCollection(named: "All Favorites")

        guard let allFavoritesCollection = collectionStore.collections.first(where: { $0.name == "All Favorites" }) else {
            XCTFail("Expected All Favorites collection to exist")
            return
        }

        collectionStore.setActiveCollection(allFavoritesCollection)
        await waitForSnapshot { $0.filteredCount == 2 && $0.unfilteredTotalCount == 2 }

        filterStore.minimumRating = 5
        await waitForSnapshot { $0.filteredCount == 1 && $0.unfilteredTotalCount == 2 }

        XCTAssertEqual(galleryStore.snapshot.subtitle, "1 image (filtered from 2)")
        XCTAssertEqual(galleryStore.snapshot.activeCollectionName, "All Favorites")
    }

    func testSnapshot_activeCollectionIncludesImagesWithoutMetadataWhenRulesAllow() async throws {
        let unratedURL = URL(fileURLWithPath: "/tmp/collection-unrated-visible.jpg")
        let ratedURL = URL(fileURLWithPath: "/tmp/collection-rated-visible.jpg")

        appState.images = [
            ImageFile(url: unratedURL, name: "collection-unrated-visible.jpg", creationDate: Date(), fileSizeBytes: 100),
            ImageFile(url: ratedURL, name: "collection-rated-visible.jpg", creationDate: Date(), fileSizeBytes: 100)
        ]

        try await upsertMetadata(url: ratedURL, rating: 4, isFavorite: false)

        try await collectionStore.createCollection(
            name: "Not Favorite",
            rules: CollectionRules(favoritesOnly: false)
        )
        await waitForCollection(named: "Not Favorite")

        guard let collection = collectionStore.collections.first(where: { $0.name == "Not Favorite" }) else {
            XCTFail("Expected Not Favorite collection")
            return
        }

        collectionStore.setActiveCollection(collection)
        await waitForSnapshot { $0.filteredCount == 2 && $0.unfilteredTotalCount == 2 }

        XCTAssertEqual(Set(galleryStore.snapshot.visibleImages.map(\.name)), Set(["collection-unrated-visible.jpg", "collection-rated-visible.jpg"]))
    }

    func testSnapshot_tagFilterMatchesStandardizedURLWhenTagStoredWithCanonicalPath() async throws {
        let canonicalURL = URL(fileURLWithPath: "/tmp/tag-canonical.jpg")
        let nonCanonicalURL = URL(fileURLWithPath: "/tmp/../tmp/tag-canonical.jpg")

        appState.images = [
            ImageFile(url: nonCanonicalURL, name: "tag-canonical.jpg", creationDate: Date(), fileSizeBytes: 100)
        ]

        try await upsertMetadata(url: canonicalURL, rating: 0, isFavorite: false)
        try await linkTag("canon", to: canonicalURL)

        await waitForSnapshot { $0.filteredCount == 1 }

        filterStore.selectedTags = ["canon"]
        await waitForSnapshot { $0.filteredCount == 1 }

        XCTAssertEqual(galleryStore.snapshot.visibleImages.first?.name, "tag-canonical.jpg")
    }

    private func upsertMetadata(url: URL, rating: Int, isFavorite: Bool) async throws {
        let key = url.standardizedFileURL.absoluteString
        try await dbPool.write { db in
            if var existingRecord = try ImageMetadataRecord.fetchOne(db, key: key) {
                existingRecord.rating = rating
                existingRecord.isFavorite = isFavorite
                try existingRecord.update(db)
            } else {
                let record = ImageMetadataRecord(url: key, rating: rating, isFavorite: isFavorite)
                try record.insert(db)
            }
        }
    }

    private func linkTag(_ tagName: String, to url: URL) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO tags (name) VALUES (?)",
                arguments: [tagName]
            )

            let tagID = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM tags WHERE name = ?",
                arguments: [tagName]
            )

            guard let tagID else {
                XCTFail("Tag id should be available after insert")
                return
            }

            try db.execute(
                sql: "INSERT OR IGNORE INTO image_tags (url, tagId) VALUES (?, ?)",
                arguments: [url.standardizedFileURL.absoluteString, tagID]
            )
        }
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

    private func waitForCollection(named name: String, timeout: TimeInterval = 1.5) async {
        let expectation = XCTestExpectation(description: "collection loaded: \(name)")
        let deadline = Date().addingTimeInterval(timeout)

        Task {
            while Date() < deadline {
                if self.collectionStore.collections.contains(where: { $0.name == name }) {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        await fulfillment(of: [expectation], timeout: timeout + 0.25)
    }
}
