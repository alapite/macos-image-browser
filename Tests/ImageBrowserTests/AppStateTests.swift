import XCTest
import Combine
@testable import ImageBrowser

@MainActor
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

    private func createImageFiles(in directory: URL, names: [String]) {
        for name in names {
            let fileURL = directory.appendingPathComponent(name)
            FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x00]))
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

    func testSortByCustom_withDuplicateFilenamesInDifferentFolders_usesURLKeys() {
        // Given: Duplicate filenames in separate folders
        let imageA = ImageFile(
            url: URL(fileURLWithPath: "/tmp/folder-a/duplicate.jpg"),
            name: "duplicate.jpg",
            creationDate: Date(timeIntervalSince1970: 100)
        )
        let imageB = ImageFile(
            url: URL(fileURLWithPath: "/tmp/folder-b/duplicate.jpg"),
            name: "duplicate.jpg",
            creationDate: Date(timeIntervalSince1970: 200)
        )
        let imageC = ImageFile(
            url: URL(fileURLWithPath: "/tmp/folder-c/unique.jpg"),
            name: "unique.jpg",
            creationDate: Date(timeIntervalSince1970: 300)
        )

        sut.images = [imageA, imageB, imageC]
        sut.customOrder = [imageB.url.standardizedFileURL.absoluteString, imageA.url.standardizedFileURL.absoluteString, imageC.url.standardizedFileURL.absoluteString]

        // When: Sort by custom order
        sut.sortOrder = .custom
        sut.resortImages()

        // Then: URLs follow explicit order even for duplicate names
        XCTAssertEqual(
            sut.images.map { $0.url.standardizedFileURL.absoluteString },
            [imageB.url.standardizedFileURL.absoluteString, imageA.url.standardizedFileURL.absoluteString, imageC.url.standardizedFileURL.absoluteString],
            "Custom sort should use URL-based keys to disambiguate duplicate filenames"
        )
    }

    func testSortByCustom_withLegacyFilenameOrder_remainsBackwardCompatible() {
        // Given: Legacy filename-only custom order and unique filenames
        sut.customOrder = ["B.jpg", "A.jpg", "C.jpg"]
        sut.images = [
            ImageFile(url: URL(fileURLWithPath: "/tmp/a/A.jpg"), name: "A.jpg", creationDate: Date(timeIntervalSince1970: 100)),
            ImageFile(url: URL(fileURLWithPath: "/tmp/b/B.jpg"), name: "B.jpg", creationDate: Date(timeIntervalSince1970: 200)),
            ImageFile(url: URL(fileURLWithPath: "/tmp/c/C.jpg"), name: "C.jpg", creationDate: Date(timeIntervalSince1970: 300))
        ]

        // When: Sort by custom order
        sut.sortOrder = .custom
        sut.resortImages()

        // Then: Legacy saved order still applies
        XCTAssertEqual(sut.images.map { $0.name }, ["B.jpg", "A.jpg", "C.jpg"], "Legacy filename-based custom order should keep working")
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

    func testImageFileID_isStableForSameURL() {
        // Given: Two ImageFile values representing the same URL
        let sharedURL = URL(fileURLWithPath: "/tmp/stable-id.jpg")
        let first = ImageFile(
            url: sharedURL,
            name: "stable-id.jpg",
            creationDate: Date(timeIntervalSince1970: 100)
        )
        let second = ImageFile(
            url: sharedURL,
            name: "stable-id.jpg",
            creationDate: Date(timeIntervalSince1970: 200)
        )

        // Then: Identity key is stable and URL-derived
        XCTAssertEqual(first.id, second.id, "Image identity should be stable for the same URL")
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

    func testSetSortOrder_resortsImagesAndPersistsPreference() {
        // Given: Images in non-alphabetical order
        sut.images = createNamedImages(names: ["C.jpg", "A.jpg", "B.jpg"])

        // When: Set sort order through intent method
        sut.setSortOrder(.name)

        // Then: Images are resorted and preference is persisted
        XCTAssertEqual(sut.images.map { $0.name }, ["A.jpg", "B.jpg", "C.jpg"], "setSortOrder should trigger resort behavior")

        let data = preferencesStore.data(forKey: "ImageBrowserPreferences")
        XCTAssertNotNil(data, "setSortOrder should persist preferences")

        let savedPreferences = data.flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
        XCTAssertEqual(savedPreferences?.sortOrder, AppState.SortOrder.name.rawValue, "Saved sort order should match selected value")
    }

    func testUpdateSlideshowInterval_persistsPreference() {
        // Given: Existing interval value
        XCTAssertEqual(sut.slideshowInterval, 3.0, "Default interval should start at 3.0")

        // When: Update interval through intent method
        sut.updateSlideshowInterval(6.5)

        // Then: Interval is updated and preference is persisted
        XCTAssertEqual(sut.slideshowInterval, 6.5, "updateSlideshowInterval should update interval")

        let data = preferencesStore.data(forKey: "ImageBrowserPreferences")
        XCTAssertNotNil(data, "updateSlideshowInterval should persist preferences")

        let savedPreferences = data.flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
        XCTAssertNotNil(savedPreferences, "Preferences should decode successfully")
        XCTAssertEqual(savedPreferences?.slideshowInterval ?? 0, 6.5, accuracy: 0.001, "Saved interval should match updated value")
    }

    // MARK: - Preference Tests

    func testSavePreferences_writesToPreferencesStore() {
        // Given: Specific preference values
        sut.updateSlideshowInterval(5.0)
        sut.setSortOrder(.creationDate)
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

    func testLoadImages_publishesLoadingBoundariesOnMainActor() async {
        let tempDir = makeTempDirectory()
        _ = copyFixture(resource: "one-pixel", ext: "png", to: tempDir)

        let loadingExpectation = expectation(description: "loading state updates")
        loadingExpectation.expectedFulfillmentCount = 2
        let completionExpectation = expectation(description: "images update")

        var loadingTransitions: [Bool] = []
        let loadingCancellable = sut.$isLoadingImages
            .dropFirst()
            .sink { isLoading in
                XCTAssertTrue(Thread.isMainThread, "isLoadingImages should publish on the main thread")
                loadingTransitions.append(isLoading)
                loadingExpectation.fulfill()
            }

        let imagesCancellable = sut.$images
            .dropFirst()
            .sink { images in
                XCTAssertTrue(Thread.isMainThread, "images should publish on the main thread")
                XCTAssertFalse(images.isEmpty, "Image scan should publish discovered images")
                completionExpectation.fulfill()
            }

        sut.loadImages(from: tempDir)
        await fulfillment(of: [loadingExpectation, completionExpectation], timeout: 2.0)

        XCTAssertEqual(loadingTransitions, [true, false], "loadImages should toggle loading state around async work")
        withExtendedLifetime((loadingCancellable, imagesCancellable)) {}
    }

    func testLoadImages_setsSelectedFolderAndPersistsLastFolder() async {
        let tempDir = makeTempDirectory()
        _ = copyFixture(resource: "one-pixel", ext: "png", to: tempDir)

        let imagesLoaded = expectation(description: "images loaded")
        let cancellable = sut.$images
            .dropFirst()
            .sink { images in
                if !images.isEmpty {
                    imagesLoaded.fulfill()
                }
            }

        sut.loadImages(from: tempDir)
        await fulfillment(of: [imagesLoaded], timeout: 2.0)

        XCTAssertEqual(
            sut.selectedFolder?.standardizedFileURL,
            tempDir.standardizedFileURL,
            "loadImages should track selected folder without requiring a separate folder-selection API"
        )

        let data = preferencesStore.data(forKey: "ImageBrowserPreferences")
        XCTAssertNotNil(data, "loadImages should persist preferences")

        let savedPreferences = data.flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
        XCTAssertEqual(savedPreferences?.lastFolder, tempDir.path, "loadImages should persist last loaded folder path")
        withExtendedLifetime(cancellable) {}
    }

    func testPrefetchMainImages_whenIndexContextChanges_cancelsReplacedWork() async {
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 200_000_000)
        let appState = AppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
        appState.images = createNamedImages(names: ["0.jpg", "1.jpg", "2.jpg", "3.jpg", "4.jpg"])

        appState.prefetchMainImages(around: 2, maxPixelSize: 64)
        let initialNeighborStarted = await pipeline.waitForRequest(
            appState.images[1].url,
            cache: .main,
            timeoutNanoseconds: 1_000_000_000
        )
        XCTAssertTrue(initialNeighborStarted, "Initial prefetch should begin before replacement")
        appState.prefetchMainImages(around: 1, maxPixelSize: 64)

        let replacementNeighbor = await pipeline.waitForAnyRequest(
            [appState.images[0].url, appState.images[2].url],
            cache: .main,
            timeoutNanoseconds: 1_000_000_000
        )
        XCTAssertNotNil(
            replacementNeighbor,
            "Replacement prefetch should load neighbors for the latest index context"
        )

        let outdatedNeighborRequested = await pipeline.waitForRequest(
            appState.images[3].url,
            cache: .main,
            timeoutNanoseconds: 500_000_000
        )
        XCTAssertFalse(
            outdatedNeighborRequested,
            "Old main-image prefetch should be canceled before loading the second outdated neighbor"
        )
    }

    func testThumbnailPrefetch_whenFolderChanges_cancelsOldFolderWork() async {
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 220_000_000)
        let appState = AppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
        appState.updateThumbnailPrefetchSize(64)

        let folderA = makeTempDirectory()
        let folderB = makeTempDirectory()
        createImageFiles(in: folderA, names: ["A1.jpg", "A2.jpg", "A3.jpg"])
        createImageFiles(in: folderB, names: ["B1.jpg", "B2.jpg"])

        appState.loadImages(from: folderA)
        _ = await pipeline.waitForFirstRequest(in: folderA, timeoutNanoseconds: 1_000_000_000)
        appState.loadImages(from: folderB)

        let replacementContextStarted = await pipeline.waitForFirstRequest(
            in: folderB,
            cache: .thumbnail,
            timeoutNanoseconds: 1_500_000_000
        )
        XCTAssertTrue(
            replacementContextStarted,
            "New folder context should trigger replacement thumbnail prefetch"
        )

        let outdatedRequestObserved = await pipeline.waitForRequest(
            folderA.appendingPathComponent("A2.jpg"),
            cache: .thumbnail,
            timeoutNanoseconds: 500_000_000
        )

        XCTAssertFalse(
            outdatedRequestObserved,
            "Old thumbnail prefetch should be canceled when switching folders"
        )
    }

    func testThumbnailPrefetch_whenNavigating_doesNotInvalidateThumbnailContext() async {
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 8_000_000)
        let appState = AppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
        appState.updateThumbnailPrefetchSize(64)

        let folder = makeTempDirectory()
        let imageNames = (0..<60).map { String(format: "N%02d.jpg", $0) }
        createImageFiles(in: folder, names: imageNames)

        appState.loadImages(from: folder)
        _ = await pipeline.waitForFirstRequest(in: folder, timeoutNanoseconds: 1_000_000_000)

        appState.navigateToNext()

        let farThumbnailObserved = await pipeline.waitForRequest(
            folder.appendingPathComponent("N55.jpg"),
            cache: .thumbnail,
            timeoutNanoseconds: 2_500_000_000
        )

        XCTAssertTrue(
            farThumbnailObserved,
            "Navigation should not invalidate thumbnail prefetch context"
        )
    }
}

actor RecordingDownsamplingPipeline: ImageDownsamplingProviding {
    private var requests: [(url: URL, cache: DownsamplingCacheKind)] = []
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func loadImage(from url: URL, maxPixelSize: Int, cache: DownsamplingCacheKind) async -> CGImage? {
        requests.append((url: url, cache: cache))
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return nil
    }

    func recordedURLs() -> [URL] {
        requests.map(\.url)
    }

    func recordedPaths(for cache: DownsamplingCacheKind) -> [String] {
        requests
            .filter { $0.cache == cache }
            .map { $0.url.standardizedFileURL.path }
    }

    func waitForFirstRequest(in directory: URL, timeoutNanoseconds: UInt64) async -> Bool {
        let pollInterval: UInt64 = 20_000_000
        var waited: UInt64 = 0
        let directoryPath = directory.standardizedFileURL.path
        while waited < timeoutNanoseconds {
            if requests.contains(where: { $0.url.standardizedFileURL.path.hasPrefix(directoryPath) }) {
                return true
            }
            try? await Task.sleep(nanoseconds: pollInterval)
            waited += pollInterval
        }
        return false
    }

    func waitForFirstRequest(in directory: URL, cache: DownsamplingCacheKind, timeoutNanoseconds: UInt64) async -> Bool {
        let pollInterval: UInt64 = 20_000_000
        var waited: UInt64 = 0
        let directoryPath = directory.standardizedFileURL.path
        while waited < timeoutNanoseconds {
            if requests.contains(where: { request in
                request.cache == cache && request.url.standardizedFileURL.path.hasPrefix(directoryPath)
            }) {
                return true
            }
            try? await Task.sleep(nanoseconds: pollInterval)
            waited += pollInterval
        }
        return false
    }

    func waitForRequest(_ url: URL, cache: DownsamplingCacheKind, timeoutNanoseconds: UInt64) async -> Bool {
        let pollInterval: UInt64 = 20_000_000
        var waited: UInt64 = 0
        let requestPath = url.standardizedFileURL.path

        while waited < timeoutNanoseconds {
            if requests.contains(where: { request in
                request.cache == cache && request.url.standardizedFileURL.path == requestPath
            }) {
                return true
            }
            try? await Task.sleep(nanoseconds: pollInterval)
            waited += pollInterval
        }
        return false
    }

    func waitForAnyRequest(_ urls: [URL], cache: DownsamplingCacheKind, timeoutNanoseconds: UInt64) async -> URL? {
        guard !urls.isEmpty else { return nil }
        let pollInterval: UInt64 = 20_000_000
        var waited: UInt64 = 0
        let candidatePaths = Set(urls.map { $0.standardizedFileURL.path })

        while waited < timeoutNanoseconds {
            if let request = requests.first(where: { request in
                request.cache == cache && candidatePaths.contains(request.url.standardizedFileURL.path)
            }) {
                return request.url
            }
            try? await Task.sleep(nanoseconds: pollInterval)
            waited += pollInterval
        }
        return nil
    }
}
