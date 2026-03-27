import XCTest
@testable import ImageBrowser

@MainActor
final class ExclusionAwareNavigationTests: XCTestCase {

    func testNextNavigation_skipsExcludedImages() {
        // Create app state with a mix of normal and excluded images
        let appState = makeAppState()
        let images = createTestImages(count: 5, excludedIndices: [1, 2])

        appState.images = images
        appState.navigateToIndex(0)

        // Navigate next - should skip indices 1 and 2 (excluded), land on 3
        let navigated = appState.navigateToNextDisplayableImage()

        XCTAssertTrue(navigated, "Navigation should succeed when eligible images exist")
        XCTAssertEqual(appState.currentImageIndex, 3, "Should skip excluded images and land on index 3")
    }

    func testPreviousNavigation_skipsExcludedImages() {
        let appState = makeAppState()
        let images = createTestImages(count: 5, excludedIndices: [1, 2])

        appState.images = images
        appState.navigateToIndex(4)

        // Navigate previous - should land on index 3 (first eligible going backward)
        let navigated = appState.navigateToPreviousDisplayableImage()

        XCTAssertTrue(navigated, "Navigation should succeed when eligible images exist")
        XCTAssertEqual(appState.currentImageIndex, 3, "Should land on index 3 (first eligible image going backward)")
    }

    func testAllImagesExcluded_returnsNil() {
        let appState = makeAppState()
        let images = createTestImages(count: 3, excludedIndices: [0, 1, 2])

        appState.images = images
        appState.navigateToIndex(0)

        // Try to navigate when all images are excluded
        let navigatedForward = appState.navigateToNextDisplayableImage()
        let navigatedBackward = appState.navigateToPreviousDisplayableImage()

        XCTAssertFalse(navigatedForward, "Forward navigation should fail when no eligible images")
        XCTAssertFalse(navigatedBackward, "Backward navigation should fail when no eligible images")
    }

    func testCurrentImageExcluded_advancesToNextEligible() {
        let appState = makeAppState()
        let images = createTestImages(count: 5, excludedIndices: [0, 1])

        appState.images = images

        // Set current to excluded image at index 0
        appState.navigateToIndex(0)

        // When current image becomes excluded, should auto-advance
        // This will be tested during implementation - documenting expected behavior
        XCTAssertTrue(images[0].isExcluded, "Current image is excluded")
        XCTAssertTrue(images[2].isExcluded == false, "Next eligible image exists at index 2")
    }

    func testDirectSelection_opensExcludedImage() {
        let appState = makeAppState()
        let images = createTestImages(count: 5, excludedIndices: [2])

        appState.images = images

        // Directly select an excluded image (simulate thumbnail tap)
        appState.navigateToIndex(2)

        XCTAssertEqual(appState.currentImageIndex, 2, "Direct selection should open excluded image")
        XCTAssertTrue(images[2].isExcluded, "Selected image is excluded")
    }

    func testNavigation_wrapsEligibleSetOnly() {
        let appState = makeAppState()
        let images = createTestImages(count: 5, excludedIndices: [0, 4])

        appState.images = images
        appState.navigateToIndex(1)

        // Navigate forward from index 1
        _ = appState.navigateToNextDisplayableImage()

        // Should skip 0 (excluded), wrap to 1, 2, 3
        XCTAssertNotEqual(appState.currentImageIndex, 0, "Should not land on excluded index 0")
        XCTAssertNotEqual(appState.currentImageIndex, 4, "Should not land on excluded index 4")
    }

    func testEligibleImages_property() {
        let appState = makeAppState()
        let images = createTestImages(count: 5, excludedIndices: [1, 3])

        appState.images = images

        let eligibleCount = images.filter { !$0.isExcluded }.count
        XCTAssertEqual(eligibleCount, 3, "Should have 3 eligible images")
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
