import XCTest
@testable import ImageBrowser

final class AppStateTests: XCTestCase {
    var sut: AppState!
    var preferencesStore: InMemoryPreferencesStore!

    override func setUp() {
        super.setUp()
        preferencesStore = InMemoryPreferencesStore()
        sut = AppState(preferencesStore: preferencesStore)
    }

    override func tearDown() {
        sut = nil
        preferencesStore = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createMockImages(count: Int) -> [ImageFile] {
        var images: [ImageFile] = []
        let calendar = Calendar.current
        let baseDate = Date()

        for i in 0..<count {
            let fileName = String(format: "Image%02d.jpg", i)
            let url = URL(fileURLWithPath: "/tmp/\(fileName)")

            // Create dates with 1-day increments
            var dateComponents = DateComponents()
            dateComponents.day = i
            let creationDate = calendar.date(byAdding: dateComponents, to: baseDate) ?? baseDate

            let imageFile = ImageFile(
                url: url,
                name: fileName,
                creationDate: creationDate
            )
            images.append(imageFile)
        }

        return images
    }

    private func createNamedImages(names: [String]) -> [ImageFile] {
        let calendar = Calendar.current
        let baseDate = Date()

        return names.enumerated().map { index, name in
            var dateComponents = DateComponents()
            dateComponents.day = index
            let creationDate = calendar.date(byAdding: dateComponents, to: baseDate) ?? baseDate

            return ImageFile(
                url: URL(fileURLWithPath: "/tmp/\(name)"),
                name: name,
                creationDate: creationDate
            )
        }
    }

    // MARK: - Navigation Tests

    func testNavigateToNext_movesToNextIndex() {
        // Given: 3 images, index 0
        sut.images = createMockImages(count: 3)
        sut.currentImageIndex = 0

        // When: Navigate to next
        sut.navigateToNext()

        // Then: Index becomes 1
        XCTAssertEqual(sut.currentImageIndex, 1, "Navigate to next should move to index 1")
    }

    func testNavigateToNext_wrapsToStart() {
        // Given: 3 images, index 2 (last)
        sut.images = createMockImages(count: 3)
        sut.currentImageIndex = 2

        // When: Navigate to next
        sut.navigateToNext()

        // Then: Index wraps to 0
        XCTAssertEqual(sut.currentImageIndex, 0, "Navigate to next from last should wrap to index 0")
    }

    func testNavigateToNext_doesNothingWhenNoImages() {
        // Given: No images
        sut.images = []
        sut.currentImageIndex = 0

        // When: Navigate to next
        sut.navigateToNext()

        // Then: Index unchanged
        XCTAssertEqual(sut.currentImageIndex, 0, "Navigate should do nothing when no images")
    }

    func testNavigateToPrevious_wrapsToEnd() {
        // Given: 3 images, index 0
        sut.images = createMockImages(count: 3)
        sut.currentImageIndex = 0

        // When: Navigate to previous
        sut.navigateToPrevious()

        // Then: Index wraps to 2
        XCTAssertEqual(sut.currentImageIndex, 2, "Navigate to previous from start should wrap to last index")
    }

    func testNavigateToPrevious_movesToPreviousIndex() {
        // Given: 3 images, index 2
        sut.images = createMockImages(count: 3)
        sut.currentImageIndex = 2

        // When: Navigate to previous
        sut.navigateToPrevious()

        // Then: Index becomes 1
        XCTAssertEqual(sut.currentImageIndex, 1, "Navigate to previous should move to index 1")
    }

    func testNavigateToIndex_validIndex_changesIndex() {
        // Given: 5 images, index 0
        sut.images = createMockImages(count: 5)
        sut.currentImageIndex = 0

        // When: Navigate to valid index
        sut.navigateToIndex(3)

        // Then: Index changes to 3
        XCTAssertEqual(sut.currentImageIndex, 3, "Navigate to valid index should change index")
    }

    func testNavigateToIndex_negativeIndex_doesNothing() {
        // Given: 3 images, index 1
        sut.images = createMockImages(count: 3)
        sut.currentImageIndex = 1

        // When: Navigate to negative index
        sut.navigateToIndex(-1)

        // Then: Index unchanged
        XCTAssertEqual(sut.currentImageIndex, 1, "Navigate to negative index should do nothing")
    }

    func testNavigateToIndex_outOfBounds_doesNothing() {
        // Given: 3 images, index 1
        sut.images = createMockImages(count: 3)
        sut.currentImageIndex = 1

        // When: Navigate to out of bounds index
        sut.navigateToIndex(10)

        // Then: Index unchanged
        XCTAssertEqual(sut.currentImageIndex, 1, "Navigate to out of bounds index should do nothing")
    }

    // MARK: - Sorting Tests

    func testSortByName_ordersAlphabetically() {
        // Given: Unsorted images [C, A, B]
        sut.images = createNamedImages(names: ["C.jpg", "A.jpg", "B.jpg"])

        // When: Sort by name
        sut.sortOrder = .name
        sut.resortImages()

        // Then: Images ordered [A, B, C]
        XCTAssertEqual(sut.images.map { $0.name }, ["A.jpg", "B.jpg", "C.jpg"], "Should sort alphabetically by name")
    }

    func testSortByCreationDate_oldestFirst() {
        // Given: Images with different dates
        sut.images = createMockImages(count: 3)
        // Reverse to make them out of order
        sut.images = sut.images.reversed()

        // When: Sort by creation date
        sut.sortOrder = .creationDate
        sut.resortImages()

        // Then: Images ordered oldest to newest
        let dates = sut.images.map { $0.creationDate }
        XCTAssertTrue(dates == dates.sorted(), "Should sort by creation date ascending")
    }

    func testSortByCustom_usesCustomOrder() {
        // Given: Custom order [B, A, C] and images [A, B, C]
        sut.customOrder = ["B.jpg", "A.jpg", "C.jpg"]
        sut.images = createNamedImages(names: ["A.jpg", "B.jpg", "C.jpg"])

        // When: Sort by custom order
        sut.sortOrder = .custom
        sut.resortImages()

        // Then: Images ordered [B, A, C]
        XCTAssertEqual(sut.images.map { $0.name }, ["B.jpg", "A.jpg", "C.jpg"], "Should use custom order")
    }

    func testSortByCustom_emptyCustomOrder_noChange() {
        // Given: Empty custom order and images
        sut.customOrder = []
        let originalImages = createNamedImages(names: ["B.jpg", "A.jpg", "C.jpg"])
        sut.images = originalImages

        // When: Sort by custom order with empty custom order
        sut.sortOrder = .custom
        sut.resortImages()

        // Then: No change to order
        XCTAssertEqual(sut.images.map { $0.name }, ["B.jpg", "A.jpg", "C.jpg"], "Should not change order with empty custom order")
    }

    func testResortImages_preservesCurrentImage() {
        // Given: Images and current image at index 2
        let images = createNamedImages(names: ["C.jpg", "B.jpg", "A.jpg", "D.jpg"])
        sut.images = images
        sut.currentImageIndex = 2 // Pointing to "A.jpg"

        // When: Resort by name
        sut.sortOrder = .name
        sut.resortImages()

        // Then: Current index points to same image (now at different index)
        let currentImageName = sut.images[sut.currentImageIndex].name
        XCTAssertEqual(currentImageName, "A.jpg", "Should preserve current image after resort")
    }

    // MARK: - Slideshow Tests

    func testStartSlideshow_setsRunningAndCreatesTimer() {
        // Given: Images and slideshow stopped
        sut.images = createMockImages(count: 3)
        sut.stopSlideshow()

        // When: Start slideshow
        sut.startSlideshow()

        // Then: isSlideshowRunning is true
        XCTAssertTrue(sut.isSlideshowRunning, "Slideshow should be running after start")
    }

    func testStartSlideshow_doesNothingWhenNoImages() {
        // Given: No images
        sut.images = []

        // When: Try to start slideshow
        sut.startSlideshow()

        // Then: Slideshow not running
        XCTAssertFalse(sut.isSlideshowRunning, "Slideshow should not start without images")
    }

    func testStopSlideshow_clearsRunningAndTimer() {
        // Given: Running slideshow
        sut.images = createMockImages(count: 3)
        sut.startSlideshow()

        // When: Stop slideshow
        sut.stopSlideshow()

        // Then: isSlideshowRunning is false
        XCTAssertFalse(sut.isSlideshowRunning, "Slideshow should not be running after stop")
    }

    func testToggleSlideshow_whenStopped_startsSlideshow() {
        // Given: Stopped slideshow
        sut.images = createMockImages(count: 3)
        sut.stopSlideshow()

        // When: Toggle slideshow
        sut.toggleSlideshow()

        // Then: Slideshow starts
        XCTAssertTrue(sut.isSlideshowRunning, "Toggle should start slideshow when stopped")
    }

    func testToggleSlideshow_whenRunning_stopsSlideshow() {
        // Given: Running slideshow
        sut.images = createMockImages(count: 3)
        sut.startSlideshow()

        // When: Toggle slideshow
        sut.toggleSlideshow()

        // Then: Slideshow stops
        XCTAssertFalse(sut.isSlideshowRunning, "Toggle should stop slideshow when running")
    }

    func testUpdateSlideshowInterval_whileRunning_restartsTimer() {
        // Given: Running slideshow
        sut.images = createMockImages(count: 3)
        sut.startSlideshow()
        XCTAssertTrue(sut.isSlideshowRunning, "Should start with running slideshow")

        // When: Update interval while running
        sut.updateSlideshowInterval(5.0)

        // Then: Slideshow still running with new interval
        XCTAssertTrue(sut.isSlideshowRunning, "Slideshow should still be running after interval update")
        XCTAssertEqual(sut.slideshowInterval, 5.0, "Interval should be updated")
    }

    func testUpdateSlideshowInterval_stopped_updatesInterval() {
        // Given: Stopped slideshow
        sut.images = createMockImages(count: 3)
        sut.stopSlideshow()

        // When: Update interval while stopped
        sut.updateSlideshowInterval(7.0)

        // Then: Interval updated, slideshow still stopped
        XCTAssertEqual(sut.slideshowInterval, 7.0, "Interval should be updated")
        XCTAssertFalse(sut.isSlideshowRunning, "Slideshow should remain stopped")
    }

    // MARK: - Preference Tests

    func testSavePreferences_writesToPreferencesStore() {
        // Given: Specific preference values
        sut.slideshowInterval = 5.0
        sut.sortOrder = .creationDate
        sut.customOrder = ["B.jpg", "A.jpg"]

        // When: Save preferences
        sut.savePreferences()

        // Then: Preferences store contains encoded data
        let data = preferencesStore.data(forKey: "ImageBrowserPreferences")
        XCTAssertNotNil(data, "Preferences store should contain encoded preferences")
    }

    func testLoadPreferences_restoresValues() {
        // Given: Saved preferences
        let originalPreferences = Preferences(
            slideshowInterval: 4.0,
            sortOrder: "Creation Date",
            customOrder: ["Z.jpg", "Y.jpg"],
            lastFolder: nil
        )

        if let encoded = try? JSONEncoder().encode(originalPreferences) {
            preferencesStore.set(encoded, forKey: "ImageBrowserPreferences")
        }

        // Create new AppState instance to test loading
        let newAppState = AppState(preferencesStore: preferencesStore)

        // Then: Values restored
        XCTAssertEqual(newAppState.slideshowInterval, 4.0, "Should restore slideshow interval")
        XCTAssertEqual(newAppState.sortOrder, .creationDate, "Should restore sort order")
        XCTAssertEqual(newAppState.customOrder, ["Z.jpg", "Y.jpg"], "Should restore custom order")
    }

    func testLoadPreferences_withNoData_usesDefaults() {
        // Given: No existing preferences

        // When: Create new AppState
        let newAppState = AppState(preferencesStore: InMemoryPreferencesStore())

        // Then: Default values used
        XCTAssertEqual(newAppState.slideshowInterval, 3.0, "Should use default interval 3.0")
        XCTAssertEqual(newAppState.sortOrder, .name, "Should use default order .name")
        XCTAssertTrue(newAppState.customOrder.isEmpty, "Should use empty custom order")
    }

    // MARK: - Image Loading and Caching Tests

    func testLoadImage_nonexistentFile_returnsNil() {
        // Given: Nonexistent file URL
        let nonexistentURL = URL(fileURLWithPath: "/tmp/nonexistent_image_12345.jpg")

        // When: Try to load image
        let image = sut.loadImage(from: nonexistentURL)

        // Then: Returns nil without crashing
        XCTAssertNil(image, "Should return nil for nonexistent file")
    }

    func testLoadImage_returnsSameInstance_onSecondCall() {
        // Given: Create a temporary test image file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_image_\(UUID().uuidString).png")

        // Create a simple 1x1 pixel image
        let imageSize = NSSize(width: 1, height: 1)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.white.drawSwatch(in: NSRect(origin: .zero, size: imageSize))
        image.unlockFocus()

        // Save image to temp file
        if let tiffData = image.tiffRepresentation {
            try? tiffData.write(to: tempURL)
        }

        defer {
            // Cleanup
            try? FileManager.default.removeItem(at: tempURL)
        }

        // When: Load same image twice
        let firstLoad = sut.loadImage(from: tempURL)
        let secondLoad = sut.loadImage(from: tempURL)

        // Then: Same instance returned (cached)
        XCTAssertNotNil(firstLoad, "First load should succeed")
        XCTAssertNotNil(secondLoad, "Second load should succeed")
        XCTAssertTrue(firstLoad === secondLoad, "Second load should return cached instance (same object)")
    }

    func testLoadImage_cachesMultipleImages() {
        // Given: Create multiple temporary test image files
        var tempURLs: [URL] = []

        for i in 0..<5 {
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_image_\(i)_\(UUID().uuidString).png")

            // Create a simple 1x1 pixel image
            let imageSize = NSSize(width: 1, height: 1)
            let image = NSImage(size: imageSize)
            image.lockFocus()
            NSColor.white.drawSwatch(in: NSRect(origin: .zero, size: imageSize))
            image.unlockFocus()

            // Save image to temp file
            if let tiffData = image.tiffRepresentation {
                try? tiffData.write(to: tempURL)
            }

            tempURLs.append(tempURL)
        }

        defer {
            // Cleanup
            tempURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        }

        // When: Load multiple images
        var loadedImages: [NSImage] = []
        for url in tempURLs {
            if let image = sut.loadImage(from: url) {
                loadedImages.append(image)
            }
        }

        // Then: All images cached and retrievable
        XCTAssertEqual(loadedImages.count, 5, "Should successfully load and cache all 5 images")

        // Verify cache works by loading again
        for (index, url) in tempURLs.enumerated() {
            let reload = sut.loadImage(from: url)
            XCTAssertNotNil(reload, "Reload of image \(index) should succeed")
            XCTAssertTrue(loadedImages[index] === reload, "Reload should return cached instance")
        }
    }

    func testLoadDownsampledImage_returnsImageForFixture() async {
        let fixtureURL = TestFixtures.url(resource: "one-pixel", extension: "png")
        let image = await sut.loadDownsampledImage(from: fixtureURL, maxPixelSize: 64, cache: .main)
        XCTAssertNotNil(image, "Downsampled image should load for valid fixture")
    }

    func testLoadDownsampledImage_cachesBySize() async {
        let fixtureURL = TestFixtures.url(resource: "two-pixel", extension: "png")
        let first = await sut.loadDownsampledImage(from: fixtureURL, maxPixelSize: 64, cache: .thumbnail)
        let second = await sut.loadDownsampledImage(from: fixtureURL, maxPixelSize: 64, cache: .thumbnail)
        XCTAssertNotNil(first, "First downsample should succeed")
        XCTAssertNotNil(second, "Second downsample should succeed")
        XCTAssertTrue(first === second, "Downsampled image should be cached by size")
    }

    func testLoadDownsampledImage_invalidFile_returnsNil() async {
        let tempDir = makeTempDirectory()
        let corruptedURL = copyFixture(resource: "corrupted", ext: "bin", to: tempDir)
        let image = await sut.loadDownsampledImage(from: corruptedURL, maxPixelSize: 64, cache: .main)
        XCTAssertNil(image, "Downsampled image should be nil for corrupted file")
    }
}
