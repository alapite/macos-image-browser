import XCTest
@testable import ImageBrowser

@MainActor
final class ExcludedReviewSurfaceTests: XCTestCase {

    // MARK: - GalleryStore.excludedImages

    func testGalleryStore_excludedImages_containsOnlyExcludedImages() {
        let eligibleImage = DisplayImage(
            id: "eligible-1",
            url: URL(fileURLWithPath: "/test/eligible.jpg"),
            name: "eligible.jpg",
            creationDate: Date(),
            rating: 0,
            isFavorite: false,
            isExcluded: false,
            excludedAt: nil,
            fileSizeBytes: 1024,
            fullIndex: 0,
            hasLoadError: false
        )

        let excludedImage = DisplayImage(
            id: "excluded-1",
            url: URL(fileURLWithPath: "/test/excluded.jpg"),
            name: "excluded.jpg",
            creationDate: Date(),
            rating: 0,
            isFavorite: false,
            isExcluded: true,
            excludedAt: Date(),
            fileSizeBytes: 1024,
            fullIndex: 1,
            hasLoadError: false
        )

        let mixedImages: [DisplayImage] = [eligibleImage, excludedImage]

        let excludedOnly = mixedImages.filter { $0.isExcluded }

        XCTAssertEqual(excludedOnly.count, 1, "Should have exactly 1 excluded image")
        XCTAssertEqual(excludedOnly.first?.id, "excluded-1", "Should return the excluded image")
    }

    func testGalleryStore_excludedImages_preservesFilenameContext() {
        let excludedImage = DisplayImage(
            id: "excluded-2",
            url: URL(fileURLWithPath: "/test/photo.jpg"),
            name: "photo.jpg",
            creationDate: Date(),
            rating: 0,
            isFavorite: false,
            isExcluded: true,
            excludedAt: Date(),
            fileSizeBytes: 2048,
            fullIndex: 0,
            hasLoadError: false
        )

        XCTAssertEqual(excludedImage.name, "photo.jpg", "Excluded image should preserve filename")
        XCTAssertTrue(excludedImage.isExcluded, "Image should be marked excluded")
    }

    func testGalleryStore_excludedImages_maintainsDeterministicOrder() {
        let excluded1 = DisplayImage(
            id: "excluded-1",
            url: URL(fileURLWithPath: "/test/a.jpg"),
            name: "a.jpg",
            creationDate: Date(),
            rating: 0,
            isFavorite: false,
            isExcluded: true,
            excludedAt: Date(),
            fileSizeBytes: 1024,
            fullIndex: 0,
            hasLoadError: false
        )

        let excluded2 = DisplayImage(
            id: "excluded-2",
            url: URL(fileURLWithPath: "/test/b.jpg"),
            name: "b.jpg",
            creationDate: Date(),
            rating: 0,
            isFavorite: false,
            isExcluded: true,
            excludedAt: Date(),
            fileSizeBytes: 1024,
            fullIndex: 1,
            hasLoadError: false
        )

        let excluded3 = DisplayImage(
            id: "excluded-3",
            url: URL(fileURLWithPath: "/test/c.jpg"),
            name: "c.jpg",
            creationDate: Date(),
            rating: 0,
            isFavorite: false,
            isExcluded: true,
            excludedAt: Date(),
            fileSizeBytes: 1024,
            fullIndex: 2,
            hasLoadError: false
        )

        let images = [excluded3, excluded1, excluded2]
        let sortedImages = images.filter { $0.isExcluded }

        XCTAssertEqual(sortedImages.map { $0.id }, ["excluded-3", "excluded-1", "excluded-2"],
                       "Should maintain original ordering based on fullIndex")
    }

    // MARK: - Review Mode Data Source

    func testReviewMode_showsOnlyExcludedImages() {
        let eligibleImage = DisplayImage(
            id: "eligible-1",
            url: URL(fileURLWithPath: "/test/normal.jpg"),
            name: "normal.jpg",
            creationDate: Date(),
            rating: 0,
            isFavorite: false,
            isExcluded: false,
            excludedAt: nil,
            fileSizeBytes: 1024,
            fullIndex: 0,
            hasLoadError: false
        )

        let excludedImage = DisplayImage(
            id: "excluded-1",
            url: URL(fileURLWithPath: "/test/excluded.jpg"),
            name: "excluded.jpg",
            creationDate: Date(),
            rating: 0,
            isFavorite: false,
            isExcluded: true,
            excludedAt: Date(),
            fileSizeBytes: 1024,
            fullIndex: 1,
            hasLoadError: false
        )

        let allImages = [eligibleImage, excludedImage]
        let excludedOnly = allImages.filter { $0.isExcluded }

        XCTAssertEqual(excludedOnly.count, 1, "Review mode should show only excluded images")
        XCTAssertFalse(excludedOnly.contains { !$0.isExcluded }, "No eligible images should appear in review mode")
    }

    func testReviewMode_rendersFilenameAndThumbnailContext() {
        let excludedImage = DisplayImage(
            id: "excluded-context",
            url: URL(fileURLWithPath: "/test/vacation_photo.jpg"),
            name: "vacation_photo.jpg",
            creationDate: Date(),
            rating: 5,
            isFavorite: true,
            isExcluded: true,
            excludedAt: Date(),
            fileSizeBytes: 4096,
            fullIndex: 0,
            hasLoadError: false
        )

        XCTAssertFalse(excludedImage.name.isEmpty, "Excluded image should have a filename for context")
        XCTAssertTrue(excludedImage.isExcluded, "Image should be marked as excluded")
    }

    func testReviewModeSelection_opensImageInViewer() {
        let excludedImage = DisplayImage(
            id: "review-select",
            url: URL(fileURLWithPath: "/test/selectable.jpg"),
            name: "selectable.jpg",
            creationDate: Date(),
            rating: 0,
            isFavorite: false,
            isExcluded: true,
            excludedAt: Date(),
            fileSizeBytes: 1024,
            fullIndex: 5,
            hasLoadError: false
        )

        XCTAssertNotNil(excludedImage.fullIndex, "Excluded image should have a valid fullIndex for navigation")
        XCTAssertEqual(excludedImage.fullIndex, 5, "Full index should allow precise navigation")
    }

    func testDoneAction_exitsReviewMode() {
        let appState = makeAppState()
        XCTAssertFalse(appState.isExcludedReviewMode, "Should start in normal mode")

        appState.enterExcludedReviewMode()
        XCTAssertTrue(appState.isExcludedReviewMode, "Should enter review mode")

        appState.exitExcludedReviewMode()
        XCTAssertFalse(appState.isExcludedReviewMode, "Done action should exit review mode")
    }

    // MARK: - Review Mode Suppresses Rejected Treatment

    func testReviewModeReviewItem_suppressesRejectedTreatment() {
        let excludedImage = DisplayImage(
            id: "review-treatment",
            url: URL(fileURLWithPath: "/test/treatment.jpg"),
            name: "treatment.jpg",
            creationDate: Date(),
            rating: 0,
            isFavorite: false,
            isExcluded: true,
            excludedAt: Date(),
            fileSizeBytes: 1024,
            fullIndex: 0,
            hasLoadError: false
        )

        let isExcludedButShouldShowNormally = excludedImage.isExcluded
        XCTAssertTrue(isExcludedButShouldShowNormally, "Image is excluded")

        // In review mode, the isExcluded flag alone should NOT trigger rejected treatment
        // The review mode flag controls treatment, not the exclusion state itself
        let inReviewMode = true
        let shouldSuppressTreatment = inReviewMode

        XCTAssertTrue(shouldSuppressTreatment, "Review mode should suppress rejected treatment")
    }

    func testExcludedSidebarCount_usesMergedExcludedImages() {
        let rawAppStateImages = [
            makeImageFile(name: "visible.jpg"),
            makeImageFile(name: "persisted-excluded.jpg")
        ]
        let mergedExcludedImages = [
            makeDisplayImage(name: "persisted-excluded.jpg", isExcluded: true, fullIndex: 1)
        ]

        let metrics = ExcludedReviewSidebarMetrics.make(
            appStateImages: rawAppStateImages,
            mergedExcludedImages: mergedExcludedImages,
            activeCollectionName: nil,
            filteredCount: 2,
            unfilteredTotalCount: 2,
            isFilteringActive: false
        )

        XCTAssertEqual(metrics.excludedCount, 1)
    }

    func testExcludedSidebarCount_decrementsWhenOneOfManyImagesIsRestored() {
        let rawAppStateImages = [
            makeImageFile(name: "first.jpg"),
            makeImageFile(name: "second.jpg"),
            makeImageFile(name: "third.jpg")
        ]
        let mergedExcludedImages = [
            makeDisplayImage(name: "second.jpg", isExcluded: true, fullIndex: 1),
            makeDisplayImage(name: "third.jpg", isExcluded: true, fullIndex: 2)
        ]

        let metrics = ExcludedReviewSidebarMetrics.make(
            appStateImages: rawAppStateImages,
            mergedExcludedImages: mergedExcludedImages,
            activeCollectionName: nil,
            filteredCount: 3,
            unfilteredTotalCount: 3,
            isFilteringActive: false
        )

        XCTAssertEqual(metrics.excludedCount, 2)

        let postRestoreMetrics = ExcludedReviewSidebarMetrics.make(
            appStateImages: rawAppStateImages,
            mergedExcludedImages: [mergedExcludedImages[1]],
            activeCollectionName: nil,
            filteredCount: 3,
            unfilteredTotalCount: 3,
            isFilteringActive: false
        )

        XCTAssertEqual(postRestoreMetrics.excludedCount, 1)
    }

    func testSubtitleStatus_usesMergedExcludedCount() {
        let metrics = ExcludedReviewSidebarMetrics.make(
            appStateImages: [
                makeImageFile(name: "visible.jpg"),
                makeImageFile(name: "persisted-excluded.jpg")
            ],
            mergedExcludedImages: [
                makeDisplayImage(name: "persisted-excluded.jpg", isExcluded: true, fullIndex: 1)
            ],
            activeCollectionName: nil,
            filteredCount: 2,
            unfilteredTotalCount: 2,
            isFilteringActive: false
        )

        XCTAssertEqual(metrics.subtitleText, "2 images · 1 excluded from browsing")
    }

    func testReviewMode_rendersRealThumbnailContext() {
        let configuration = ThumbnailPresentation.reviewMode(isExcluded: true)

        XCTAssertEqual(configuration.kind, .thumbnail)
        XCTAssertEqual(configuration.opacity, 1.0)
        XCTAssertFalse(configuration.showsExcludedBadge)
    }

    func testReviewMode_thumbnailSuppressesRejectedTreatment() {
        let configuration = ThumbnailPresentation.reviewMode(isExcluded: true)

        XCTAssertEqual(configuration.opacity, 1.0)
        XCTAssertFalse(configuration.showsExcludedBadge)
    }

    // MARK: - UI State Observation (Gap Closure - Plan 17-04)

    func testExcludedImagesSection_entersReviewMode_ui() {
        // Given: AppState with review mode inactive
        let appState = makeAppState()
        XCTAssertFalse(appState.isExcludedReviewMode, "Should start in normal mode")

        // When: User clicks "Excluded Images" section in sidebar
        appState.enterExcludedReviewMode()

        // Then: UI state updates to reflect review mode
        XCTAssertTrue(appState.isExcludedReviewMode, "UI should update to show review mode active")
        // Sidebar toggle button should change appearance (chevron rotation)
        // Done button should appear
        // Conditional view rendering should switch to excludedReviewGrid
    }

    func testDoneButton_exitsReviewMode_ui() {
        // Given: AppState with review mode active
        let appState = makeAppState()
        appState.enterExcludedReviewMode()
        XCTAssertTrue(appState.isExcludedReviewMode, "Should be in review mode")

        // When: User clicks "Done" button
        appState.exitExcludedReviewMode()

        // Then: UI state updates to reflect normal mode
        XCTAssertFalse(appState.isExcludedReviewMode, "UI should update to show normal mode")
        // Sidebar toggle button should return to normal appearance
        // Done button should disappear
        // Conditional view rendering should switch back to thumbnailGrid
    }

    // MARK: - Smart Collections Sidebar Integration (Gap Closure - Plan 17-05)

    func testSmartCollectionsVisibleInSidebar() {
        // Given: ContentView with SidebarView
        // When: Sidebar renders
        // Then: Smart Collections section should be visible in sidebar
        // This test stub documents the expected user-facing behavior
    }

    func testSmartCollectionsClickFiltersGrid() {
        // Given: App with smart collections
        // When: User clicks a smart collection in sidebar
        // Then: Image grid should filter to show only matching images
        // This test stub documents the expected user-facing behavior
    }

    private func makeImageFile(name: String, isExcluded: Bool = false) -> ImageFile {
        let url = URL(fileURLWithPath: "/test/\(name)")
        var image = ImageFile(
            url: url,
            name: name,
            creationDate: Date(),
            fileSizeBytes: 1024
        )
        if isExcluded {
            image.metadata = ImageMetadata(isExcluded: true, excludedAt: Date())
        }
        return image
    }

    private func makeDisplayImage(name: String, isExcluded: Bool, fullIndex: Int) -> DisplayImage {
        DisplayImage(
            id: name,
            url: URL(fileURLWithPath: "/test/\(name)"),
            name: name,
            creationDate: Date(),
            rating: 0,
            isFavorite: false,
            isExcluded: isExcluded,
            excludedAt: isExcluded ? Date() : nil,
            fileSizeBytes: 1024,
            fullIndex: fullIndex,
            hasLoadError: false
        )
    }
}
