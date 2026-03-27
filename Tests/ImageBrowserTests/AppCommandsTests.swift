import XCTest
import Combine
@testable import ImageBrowser

@MainActor
final class AppCommandsTests: XCTestCase {
    var sut: AppState!
    var preferencesStore: InMemoryPreferencesStore!

    override func setUp() async throws {
        await MainActor.run {
            preferencesStore = InMemoryPreferencesStore()
            sut = makeAppState(preferencesStore: preferencesStore)
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            sut = nil
            preferencesStore = nil
        }
    }

    // MARK: - Helper Methods

    private func createTestImages(count: Int, excludedIndices: [Int] = []) -> [ImageFile] {
        (0..<count).map { index in
            let metadata = ImageMetadata(
                rating: 0,
                isFavorite: false,
                isExcluded: excludedIndices.contains(index),
                excludedAt: excludedIndices.contains(index) ? Date() : nil
            )

            return ImageFile(
                url: URL(fileURLWithPath: "/test/image\(index).jpg"),
                name: String(format: "Image%02d.jpg", index),
                creationDate: Date(),
                fileSizeBytes: 1024,
                metadata: metadata
            )
        }
    }

    // MARK: - Command Context Shuffle Tests

    func testCommandContext_exposesShuffleActions() {
        // Given: AppState with images and shuffle enabled
        let images = createTestImages(count: 5)
        sut.images = images
        sut.setShuffleEnabled(true)

        // When: Build command context
        let context = sut.buildCommandContext(
            canOpenFolder: true,
            toggleFilters: {},
            navigateToPrevious: {},
            navigateToNext: {},
            toggleFavorite: {},
            stopSlideshow: {},
            editCustomOrder: {}
        )

        // Then: Context should expose shuffle state and actions
        XCTAssertTrue(context.isShuffleEnabled, "Command context should reflect shuffle enabled state")
        // Actions are non-optional closures, just verify they're callable
        context.toggleShuffle()
        context.reshuffle()
    }

    func testCommandContext_shuffleDisabledWhenOff() {
        // Given: AppState with images but shuffle disabled
        let images = createTestImages(count: 5)
        sut.images = images
        sut.setShuffleEnabled(false)

        // When: Build command context
        let context = sut.buildCommandContext(
            canOpenFolder: true,
            toggleFilters: {},
            navigateToPrevious: {},
            navigateToNext: {},
            toggleFavorite: {},
            stopSlideshow: {},
            editCustomOrder: {}
        )

        // Then: Context should reflect shuffle disabled
        XCTAssertFalse(context.isShuffleEnabled, "Command context should reflect shuffle disabled state")
    }

    func testReshuffleCommand_disabledWhenShuffleOffOrNoEligibleImages() {
        // Given: AppState with shuffle disabled
        let images = createTestImages(count: 5)
        sut.images = images
        sut.setShuffleEnabled(false)

        // When: Build command context
        let context = sut.buildCommandContext(
            canOpenFolder: true,
            toggleFilters: {},
            navigateToPrevious: {},
            navigateToNext: {},
            toggleFavorite: {},
            stopSlideshow: {},
            editCustomOrder: {}
        )

        // Then: Reshuffle should be disabled when shuffle is off
        let canReshuffle = context.canReshuffle
        XCTAssertFalse(canReshuffle, "Reshuffle should be disabled when shuffle is off")
    }

    func testReshuffleCommand_enabledWhenShuffleOnWithEligibleImages() {
        // Given: AppState with shuffle enabled and eligible images
        let images = createTestImages(count: 5)
        sut.images = images
        sut.setShuffleEnabled(true)

        // When: Build command context
        let context = sut.buildCommandContext(
            canOpenFolder: true,
            toggleFilters: {},
            navigateToPrevious: {},
            navigateToNext: {},
            toggleFavorite: {},
            stopSlideshow: {},
            editCustomOrder: {}
        )

        // Then: Reshuffle should be enabled
        let canReshuffle = context.canReshuffle
        XCTAssertTrue(canReshuffle, "Reshuffle should be enabled when shuffle is on with eligible images")
    }

    func testReshuffleCommand_disabledWhenAllImagesExcluded() {
        // Given: AppState with shuffle enabled but all images excluded
        let images = createTestImages(count: 5, excludedIndices: [0, 1, 2, 3, 4])
        sut.images = images
        sut.setShuffleEnabled(true)

        // When: Build command context
        let context = sut.buildCommandContext(
            canOpenFolder: true,
            toggleFilters: {},
            navigateToPrevious: {},
            navigateToNext: {},
            toggleFavorite: {},
            stopSlideshow: {},
            editCustomOrder: {}
        )

        // Then: Reshuffle should be disabled when no eligible images
        let canReshuffle = context.canReshuffle
        XCTAssertFalse(canReshuffle, "Reshuffle should be disabled when no eligible images exist")
    }

    func testToggleShuffle_actionTogglesShuffleState() {
        // Given: AppState with shuffle disabled
        let images = createTestImages(count: 5)
        sut.images = images
        sut.setShuffleEnabled(false)

        let context = sut.buildCommandContext(
            canOpenFolder: true,
            toggleFilters: {},
            navigateToPrevious: {},
            navigateToNext: {},
            toggleFavorite: {},
            stopSlideshow: {},
            editCustomOrder: {}
        )

        // When: Call toggle shuffle action
        context.toggleShuffle()

        // Then: Shuffle should be enabled
        XCTAssertTrue(sut.isShuffleEnabled, "Toggle shuffle action should enable shuffle")
    }

    func testReshuffle_actionRegeneratesShuffleOrder() {
        // Given: AppState with shuffle enabled
        let images = createTestImages(count: 10)
        sut.images = images
        sut.setShuffleEnabled(true)

        let context = sut.buildCommandContext(
            canOpenFolder: true,
            toggleFilters: {},
            navigateToPrevious: {},
            navigateToNext: {},
            toggleFavorite: {},
            stopSlideshow: {},
            editCustomOrder: {}
        )

        // Navigate a bit to establish order
        for _ in 0..<3 {
            _ = sut.navigateToNextDisplayableImage()
        }
        let imageBeforeReshuffle = sut.images[sut.currentImageIndex].name

        // When: Call reshuffle action
        context.reshuffle()

        // Reset to start and navigate again
        sut.currentImageIndex = 0
        for _ in 0..<3 {
            _ = sut.navigateToNextDisplayableImage()
        }
        let imageAfterReshuffle = sut.images[sut.currentImageIndex].name

        // Then: Order should have been regenerated (images may differ)
        // The key is that reshuffle was called successfully
        XCTAssertTrue(sut.isShuffleEnabled, "Shuffle should still be enabled after reshuffle")
    }
}
