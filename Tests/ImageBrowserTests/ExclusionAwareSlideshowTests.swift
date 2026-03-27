import XCTest
import Combine
@testable import ImageBrowser

@MainActor
final class ExclusionAwareSlideshowTests: XCTestCase {

    func testSlideshow_skipsExcludedImages() {
        let appState = makeAppState()
        let images = createTestImages(count: 5, excludedIndices: [1, 2])

        appState.images = images
        appState.navigateToIndex(0)

        // Start slideshow
        appState.startSlideshow()
        XCTAssertTrue(appState.isSlideshowRunning, "Slideshow should be running")

        // Advance slideshow - should skip excluded indices 1 and 2
        let advanced = appState.advanceSlideshowIfPossible()

        XCTAssertTrue(advanced, "Slideshow should advance to next eligible image")
        XCTAssertEqual(appState.currentImageIndex, 3, "Should skip excluded images and land on index 3")
    }

    func testSlideshow_stopsWhenNoEligibleRemain() {
        let appState = makeAppState()
        let images = createTestImages(count: 3, excludedIndices: [0, 1, 2])

        appState.images = images
        appState.navigateToIndex(0)

        // Start slideshow
        appState.startSlideshow()

        // Try to advance slideshow when all images are excluded
        let advanced = appState.advanceSlideshowIfPossible()

        XCTAssertFalse(advanced, "Slideshow should not advance when no eligible images remain")
    }

    func testSlideshowControls_disabledWhenNoEligible() {
        let appState = makeAppState()
        let images = createTestImages(count: 3, excludedIndices: [0, 1, 2])

        appState.images = images

        // Verify no eligible images
        XCTAssertFalse(appState.hasEligibleImages, "Should have no eligible images")

        // Controls should be disabled (this will be verified by UI binding)
        // For now, verify the property that controls would bind to
        XCTAssertFalse(appState.hasEligibleImages, "hasEligibleImages should be false")
    }

    func testSlideshowRestoresWhenEligibleReturns() {
        let appState = makeAppState()
        var images = createTestImages(count: 3, excludedIndices: [0, 1, 2])

        appState.images = images
        XCTAssertFalse(appState.hasEligibleImages, "Should have no eligible images initially")

        // Simulate restoring an image (unexclude index 0)
        images[0] = ImageFile(
            url: images[0].url,
            name: images[0].name,
            creationDate: images[0].creationDate,
            fileSizeBytes: images[0].fileSizeBytes,
            metadata: ImageMetadata(rating: 0, isFavorite: false, isExcluded: false, excludedAt: nil)
        )

        appState.images = images
        XCTAssertTrue(appState.hasEligibleImages, "Should have eligible images after restoring")
    }

    func testSlideshow_wrapsEligibleSetOnly() {
        let appState = makeAppState()
        let images = createTestImages(count: 5, excludedIndices: [0, 4])

        appState.images = images
        appState.navigateToIndex(1)

        // Start slideshow
        appState.startSlideshow()

        // Advance slideshow multiple times
        _ = appState.advanceSlideshowIfPossible()
        let firstIndex = appState.currentImageIndex

        _ = appState.advanceSlideshowIfPossible()
        let secondIndex = appState.currentImageIndex

        // Should wrap through eligible indices only (1, 2, 3)
        XCTAssertTrue(firstIndex >= 1 && firstIndex <= 3, "First advance should land in eligible range")
        XCTAssertTrue(secondIndex >= 1 && secondIndex <= 3, "Second advance should land in eligible range")
    }

    // MARK: - Helper Functions

    private func createTestImages(count: Int, excludedIndices: [Int]) -> [ImageFile] {
        (0..<count).map { index in
            let metadata = ImageMetadata(
                rating: 0,
                isFavorite: false,
                isExcluded: excludedIndices.contains(index),
                excludedAt: excludedIndices.contains(index) ? Date() : nil
            )

            return ImageFile(
                url: URL(fileURLWithPath: "/test/image\(index).jpg"),
                name: "image\(index).jpg",
                creationDate: Date(),
                fileSizeBytes: 1024,
                metadata: metadata
            )
        }
    }
}
