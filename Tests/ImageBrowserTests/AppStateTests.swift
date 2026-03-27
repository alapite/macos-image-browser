import XCTest
import Combine
@testable import ImageBrowser

@MainActor
final class AppStateTests: XCTestCase {
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

    private func createScanImage(name: String, in directory: URL) -> ImageFile {
        ImageFile(
            url: directory.appendingPathComponent(name),
            name: name,
            creationDate: Date()
        )
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

    func testNavigateToNext_skipsUnsupportedAdvancedFormats() {
        sut.images = createNamedImages(names: ["one.jpg", "two.cr3", "three.heic"])
        sut.currentImageIndex = 0
        sut.unsupportedImages = [sut.images[1].url]

        sut.navigateToNext()

        XCTAssertEqual(sut.currentImageIndex, 2)
        XCTAssertEqual(sut.images[sut.currentImageIndex].name, "three.heic")
    }

    func testNavigateToPrevious_skipsUnsupportedAdvancedFormats() {
        sut.images = createNamedImages(names: ["one.jpg", "two.cr3", "three.heic"])
        sut.currentImageIndex = 2
        sut.unsupportedImages = [sut.images[1].url]

        sut.navigateToPrevious()

        XCTAssertEqual(sut.currentImageIndex, 0)
        XCTAssertEqual(sut.images[sut.currentImageIndex].name, "one.jpg")
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

    func testSlideshowTick_skipsUnsupportedAdvancedFormats() {
        let scheduler = TestSlideshowScheduler()
        let appState = makeAppState(preferencesStore: preferencesStore, slideshowScheduler: scheduler)
        appState.images = createNamedImages(names: ["one.jpg", "two.cr3", "three.heic"])
        appState.currentImageIndex = 0
        appState.unsupportedImages = [appState.images[1].url]

        appState.startSlideshow()
        scheduler.fire()

        XCTAssertEqual(appState.currentImageIndex, 2)
        XCTAssertEqual(appState.images[appState.currentImageIndex].name, "three.heic")
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
        let newAppState = makeAppState(preferencesStore: preferencesStore)

        // Then: Values restored
        XCTAssertEqual(newAppState.slideshowInterval, 4.0, "Should restore slideshow interval")
        XCTAssertEqual(newAppState.sortOrder, .creationDate, "Should restore sort order")
        XCTAssertEqual(newAppState.customOrder, ["Z.jpg", "Y.jpg"], "Should restore custom order")
    }

    func testLoadPreferences_withNoData_usesDefaults() {
        // Given: No existing preferences

        // When: Create new AppState
        let newAppState = makeAppState(preferencesStore: InMemoryPreferencesStore())

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
                // Skip the initial empty array published by loadImages
                guard !images.isEmpty else { return }
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

    func testLoadImages_publishesFirstImageBeforeScanCompletes() async {
        let scanner = ControlledImageScanner()
        let appState = makeAppState(preferencesStore: preferencesStore, imageScanner: scanner)
        let folder = makeTempDirectory()
        let firstImage = createScanImage(name: "b.jpg", in: folder)
        let secondImage = createScanImage(name: "a.jpg", in: folder)

        let firstPublishExpectation = expectation(description: "first image published before completion")
        let completedExpectation = expectation(description: "load completed")
        var sawFirstPublishWhileLoading = false

        let imagesCancellable = appState.$images
            .dropFirst()
            .sink { images in
                if images.count == 1 {
                    sawFirstPublishWhileLoading = appState.isLoadingImages
                    firstPublishExpectation.fulfill()
                }
            }

        let loadingCancellable = appState.$isLoadingImages
            .dropFirst()
            .sink { isLoading in
                if !isLoading {
                    completedExpectation.fulfill()
                }
            }

        appState.loadImages(from: folder)
        await scanner.waitUntilStarted(for: folder)
        _ = await scanner.emitBatch(
            .init(images: [firstImage], failedImages: [], isFinal: false),
            for: folder
        )

        await fulfillment(of: [firstPublishExpectation], timeout: 1.0)
        XCTAssertTrue(sawFirstPublishWhileLoading, "First image should publish while loading is still active")

        _ = await scanner.emitBatch(
            .init(images: [secondImage], failedImages: [], isFinal: true),
            for: folder
        )

        await fulfillment(of: [completedExpectation], timeout: 1.0)
        XCTAssertEqual(
            appState.images.map(\.name),
            ["a.jpg", "b.jpg"],
            "Final completion should apply normal sort semantics after progressive append"
        )
        withExtendedLifetime((imagesCancellable, loadingCancellable)) {}
    }

    func testLoadImages_growsProgressivelyAcrossMultipleBatches() async {
        let scanner = ControlledImageScanner()
        let appState = makeAppState(preferencesStore: preferencesStore, imageScanner: scanner)
        let folder = makeTempDirectory()
        let imageA = createScanImage(name: "1.jpg", in: folder)
        let imageB = createScanImage(name: "2.jpg", in: folder)
        let imageC = createScanImage(name: "3.jpg", in: folder)

        let countOneExpectation = expectation(description: "first progressive step")
        let countTwoExpectation = expectation(description: "second progressive step")
        let completionExpectation = expectation(description: "final completion")

        let imagesCancellable = appState.$images
            .dropFirst()
            .sink { images in
                if images.count == 1 {
                    countOneExpectation.fulfill()
                } else if images.count == 2 {
                    countTwoExpectation.fulfill()
                }
            }

        let loadingCancellable = appState.$isLoadingImages
            .dropFirst()
            .sink { isLoading in
                if !isLoading {
                    completionExpectation.fulfill()
                }
            }

        appState.loadImages(from: folder)
        await scanner.waitUntilStarted(for: folder)

        _ = await scanner.emitBatch(
            .init(images: [imageA], failedImages: [], isFinal: false),
            for: folder
        )
        _ = await scanner.emitBatch(
            .init(images: [imageB], failedImages: [], isFinal: false),
            for: folder
        )

        await fulfillment(of: [countOneExpectation, countTwoExpectation], timeout: 1.0)

        _ = await scanner.emitBatch(
            .init(images: [imageC], failedImages: [], isFinal: true),
            for: folder
        )
        await fulfillment(of: [completionExpectation], timeout: 1.0)
        XCTAssertEqual(appState.images.count, 3, "Final image list should include all progressive batches")
        withExtendedLifetime((imagesCancellable, loadingCancellable)) {}
    }

    func testLoadImages_folderSwitchSuppressesStaleScanResults() async {
        let scanner = ControlledImageScanner()
        let appState = makeAppState(preferencesStore: preferencesStore, imageScanner: scanner)
        let folderA = makeTempDirectory()
        let folderB = makeTempDirectory()
        let staleImage = createScanImage(name: "stale.jpg", in: folderA)
        let currentImage = createScanImage(name: "current.jpg", in: folderB)

        let completedExpectation = expectation(description: "latest folder completed")
        let loadingCancellable = appState.$isLoadingImages
            .dropFirst()
            .sink { isLoading in
                if !isLoading {
                    completedExpectation.fulfill()
                }
            }

        appState.loadImages(from: folderA)
        await scanner.waitUntilStarted(for: folderA)

        appState.loadImages(from: folderB)
        await scanner.waitUntilStarted(for: folderB)

        _ = await scanner.emitBatch(
            .init(images: [staleImage], failedImages: [], isFinal: true),
            for: folderA
        )

        XCTAssertTrue(
            appState.images.isEmpty,
            "Stale folder completion should be ignored while latest folder is still loading"
        )
        XCTAssertTrue(appState.isLoadingImages, "Stale completion should not stop loading for active generation")

        _ = await scanner.emitBatch(
            .init(images: [currentImage], failedImages: [], isFinal: true),
            for: folderB
        )

        await fulfillment(of: [completedExpectation], timeout: 1.0)
        XCTAssertEqual(appState.images.map(\.name), ["current.jpg"], "Only latest folder scan should be published")
        XCTAssertEqual(
            appState.selectedFolder?.standardizedFileURL,
            folderB.standardizedFileURL,
            "Selected folder should remain on latest load request"
        )
        withExtendedLifetime(loadingCancellable) {}
    }

    func testLoadImages_loadingStateRemainsTrueUntilCurrentGenerationCompletes() async {
        let scanner = ControlledImageScanner()
        let appState = makeAppState(preferencesStore: preferencesStore, imageScanner: scanner)
        let folderA = makeTempDirectory()
        let folderB = makeTempDirectory()
        let imageA = createScanImage(name: "a.jpg", in: folderA)
        let imageB = createScanImage(name: "b.jpg", in: folderB)

        let completedExpectation = expectation(description: "active generation completes")
        let loadingCancellable = appState.$isLoadingImages
            .dropFirst()
            .sink { isLoading in
                if !isLoading {
                    completedExpectation.fulfill()
                }
            }

        appState.loadImages(from: folderA)
        await scanner.waitUntilStarted(for: folderA)
        XCTAssertTrue(appState.isLoadingImages, "Loading should begin immediately for first folder")

        appState.loadImages(from: folderB)
        await scanner.waitUntilStarted(for: folderB)
        XCTAssertTrue(appState.isLoadingImages, "Loading should remain true while newer generation is active")

        _ = await scanner.emitBatch(
            .init(images: [imageA], failedImages: [], isFinal: true),
            for: folderA
        )
        XCTAssertTrue(appState.isLoadingImages, "Stale generation completion must not end active generation loading")

        _ = await scanner.emitBatch(
            .init(images: [imageB], failedImages: [], isFinal: true),
            for: folderB
        )

        await fulfillment(of: [completedExpectation], timeout: 1.0)
        XCTAssertFalse(appState.isLoadingImages, "Loading should stop only when current generation reaches terminal state")
        withExtendedLifetime(loadingCancellable) {}
    }

    func testLoadImages_keepsTargetedAdvancedFormatsInImageListBeforeRenderAttempt() async {
        let scanner = ControlledImageScanner()
        let appState = makeAppState(preferencesStore: preferencesStore, imageScanner: scanner)
        let folder = makeTempDirectory()
        let rawImage = createScanImage(name: "camera.cr3", in: folder)
        let heicImage = createScanImage(name: "device.heic", in: folder)

        let completionExpectation = expectation(description: "scan completed")
        let cancellable = appState.$isLoadingImages
            .dropFirst()
            .sink { isLoading in
                if !isLoading {
                    completionExpectation.fulfill()
                }
            }

        appState.loadImages(from: folder)
        await scanner.waitUntilStarted(for: folder)

        _ = await scanner.emitBatch(
            .init(images: [rawImage, heicImage], failedImages: [], isFinal: true),
            for: folder
        )

        await fulfillment(of: [completionExpectation], timeout: 1.0)
        XCTAssertEqual(Set(appState.images.map(\.name)), ["camera.cr3", "device.heic"])
        XCTAssertTrue(appState.failedImages.isEmpty, "Render failures should not be inferred during scan-only enumeration")
        withExtendedLifetime(cancellable) {}
    }

    func testRecordLoadResult_tracksUnsupportedAdvancedFormatsSeparatelyFromFailedImages() {
        let imageFile = ImageFile(
            url: URL(fileURLWithPath: "/tmp/sample.cr3"),
            name: "sample.cr3",
            creationDate: Date()
        )

        sut.recordLoadResult(for: imageFile, image: nil)

        XCTAssertTrue(sut.unsupportedImages.contains(imageFile.url))
        XCTAssertFalse(sut.failedImages.contains(imageFile.url))
    }

    func testRecordLoadResult_tracksBrokenJpegInFailedImagesNotUnsupportedImages() {
        let imageFile = ImageFile(
            url: URL(fileURLWithPath: "/tmp/broken.jpg"),
            name: "broken.jpg",
            creationDate: Date()
        )

        sut.recordLoadResult(for: imageFile, image: nil)

        XCTAssertTrue(sut.failedImages.contains(imageFile.url))
        XCTAssertFalse(sut.unsupportedImages.contains(imageFile.url))
    }

    func testLoadDownsampledImage_reducesRequestedSizeForLargeRawFiles() async {
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 0)
        let appState = makeAppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
        let rawURL = URL(fileURLWithPath: "/tmp/large.nef")
        let rawImage = ImageFile(
            url: rawURL,
            name: "large.nef",
            creationDate: Date(),
            fileSizeBytes: 120_000_000
        )

        _ = await appState.loadDownsampledImage(for: rawImage, maxPixelSize: 6000, cache: .main)

        let requestedSize = await pipeline.recordedMaxPixelSize(for: rawURL, cache: .main)
        XCTAssertEqual(requestedSize, 3072)
    }

    func testMainImageRequestSize_isNormalizedForCacheReuse() async {
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 0)
        let appState = makeAppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
        let image = ImageFile(
            url: URL(fileURLWithPath: "/tmp/cache-reuse.jpg"),
            name: "cache-reuse.jpg",
            creationDate: Date(),
            fileSizeBytes: 5_000_000
        )

        _ = await appState.loadDownsampledImage(for: image, maxPixelSize: 3013, cache: .main)
        _ = await appState.loadDownsampledImage(for: image, maxPixelSize: 3070, cache: .main)

        let recordedSizes = await pipeline.recordedMaxPixelSizes(for: image.url, cache: .main)
        XCTAssertEqual(recordedSizes, [3072, 3072], "Nearby viewer request sizes should normalize to a shared cache size")
    }

    func testNormalizedMainImagePixelSize_capsAt8192() {
        let appState = makeAppState(preferencesStore: preferencesStore)

        let normalized = appState.normalizedMainImagePixelSize(12_000)

        XCTAssertEqual(normalized, 8192)
    }

    func testPrefetchMainImages_usesNormalizedMainImageRequestSize() async {
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 0)
        let appState = makeAppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
        appState.images = createNamedImages(names: ["0.jpg", "1.jpg", "2.jpg"])

        appState.prefetchMainImages(around: 1, maxPixelSize: 3013)

        let firstNeighborStarted = await pipeline.waitForAnyRequest(
            [appState.images[0].url, appState.images[2].url],
            cache: .main,
            timeoutNanoseconds: 1_000_000_000
        )
        XCTAssertNotNil(firstNeighborStarted, "Neighbor prefetch should start for adjacent images")

        let neighborSizes = await pipeline.recordedMaxPixelSizes(for: appState.images[0].url, cache: .main)
        XCTAssertEqual(neighborSizes, [3072], "Main-image prefetch should use the same normalized request sizing as direct viewing")
    }

    func testPrefetchMainImages_whenIndexContextChanges_cancelsReplacedWork() async {
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 200_000_000)
        let appState = makeAppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
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

    func testPrefetchMainImages_whenAppStateIsReleased_cancelsOutstandingWork() async {
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 200_000_000)
        var appState: AppState? = makeAppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
        appState?.images = createNamedImages(names: ["0.jpg", "1.jpg", "2.jpg", "3.jpg", "4.jpg"])

        weak var weakAppState = appState
        let initialNeighborURL = appState!.images[1].url
        let staleNeighborURL = appState!.images[3].url

        appState?.prefetchMainImages(around: 2, maxPixelSize: 64)
        let initialNeighborStarted = await pipeline.waitForRequest(
            initialNeighborURL,
            cache: .main,
            timeoutNanoseconds: 1_000_000_000
        )
        XCTAssertTrue(initialNeighborStarted, "Initial prefetch should begin before release")

        appState = nil

        XCTAssertNil(weakAppState, "Prefetch task should not retain AppState after release")

        let staleNeighborRequested = await pipeline.waitForRequest(
            staleNeighborURL,
            cache: .main,
            timeoutNanoseconds: 500_000_000
        )
        XCTAssertFalse(
            staleNeighborRequested,
            "Outstanding prefetch work should be canceled when AppState is released"
        )
    }

    func testThumbnailPrefetch_whenFolderChanges_cancelsOldFolderWork() async {
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 220_000_000)
        let appState = makeAppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
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
        let appState = makeAppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
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

    func testLoadImages_folderSwitchPreservesSortOrderAndCurrentSelectionRules() async {
        let scanner = ControlledImageScanner()
        let appState = makeAppState(preferencesStore: preferencesStore, imageScanner: scanner)
        let folderB = makeTempDirectory()

        appState.images = createNamedImages(names: ["old-1.jpg", "old-2.jpg"])
        appState.currentImageIndex = 1
        appState.sortOrder = .creationDate

        let newerImage = ImageFile(
            url: folderB.appendingPathComponent("newer.jpg"),
            name: "newer.jpg",
            creationDate: Date(timeIntervalSince1970: 200),
            fileSizeBytes: 100
        )
        let olderImage = ImageFile(
            url: folderB.appendingPathComponent("older.jpg"),
            name: "older.jpg",
            creationDate: Date(timeIntervalSince1970: 100),
            fileSizeBytes: 100
        )

        appState.loadImages(from: folderB)
        await scanner.waitUntilStarted(for: folderB)

        let completionExpectation = expectation(description: "folder B loaded")
        let cancellable = appState.$isLoadingImages
            .dropFirst()
            .sink { isLoading in
                if !isLoading {
                    completionExpectation.fulfill()
                }
            }

        _ = await scanner.emitBatch(
            .init(images: [newerImage, olderImage], failedImages: [], isFinal: true),
            for: folderB
        )

        await fulfillment(of: [completionExpectation], timeout: 1.0)

        XCTAssertEqual(appState.images.map(\.name), ["older.jpg", "newer.jpg"])
        XCTAssertEqual(appState.currentImageIndex, 0, "Folder handoff should reset selection to the first valid image in the new folder")
        withExtendedLifetime(cancellable) {}
    }

    func testReportThumbnailVisibility_prefetchesOnlyBoundedWindowForLargeFolder() async {
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 20_000_000)
        let appState = makeAppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
        appState.images = createNamedImages(names: (0..<1_500).map { String(format: "Image%04d.jpg", $0) })

        appState.reportThumbnailVisibility(index: 12, maxPixelSize: 96)

        let nearbyObserved = await pipeline.waitForAnyRequest(
            [appState.images[12].url, appState.images[13].url],
            cache: .thumbnail,
            timeoutNanoseconds: 1_000_000_000
        )
        XCTAssertNotNil(nearbyObserved, "Visible-window prefetch should start around the current on-screen index")

        let farObserved = await pipeline.waitForRequest(
            appState.images[400].url,
            cache: .thumbnail,
            timeoutNanoseconds: 300_000_000
        )
        XCTAssertFalse(farObserved, "Visible-window prefetch should not warm far-away thumbnails in a large folder")
    }

    func testReportThumbnailVisibility_replacesStaleThumbnailWindowWhenUserScrolls() async {
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 20_000_000)
        let appState = makeAppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
        appState.images = createNamedImages(names: (0..<300).map { String(format: "Image%03d.jpg", $0) })

        appState.reportThumbnailVisibility(index: 10, maxPixelSize: 96)
        let firstWindowObserved = await pipeline.waitForAnyRequest(
            [appState.images[10].url, appState.images[11].url],
            cache: .thumbnail,
            timeoutNanoseconds: 1_000_000_000
        )
        XCTAssertNotNil(firstWindowObserved, "Initial thumbnail window should start prefetching nearby images")

        appState.reportThumbnailVisibility(index: 220, maxPixelSize: 96)

        let secondWindowObserved = await pipeline.waitForAnyRequest(
            [appState.images[220].url, appState.images[221].url],
            cache: .thumbnail,
            timeoutNanoseconds: 1_000_000_000
        )
        XCTAssertNotNil(secondWindowObserved, "Reporting a distant visible index should replace the thumbnail window")

        let staleObserved = await pipeline.waitForRequest(
            appState.images[40].url,
            cache: .thumbnail,
            timeoutNanoseconds: 300_000_000
        )
        XCTAssertFalse(staleObserved, "Old thumbnail window work should be abandoned after the user scrolls far away")
    }

    // MARK: - Responsiveness-First Navigation Tests

    func testAdjacentNavigation_keepsCurrentIndexAndImageInSync() async {
        // Given: Multiple images loaded
        let appState = makeAppState(preferencesStore: preferencesStore)
        appState.images = createNamedImages(names: ["A.jpg", "B.jpg", "C.jpg", "D.jpg"])
        appState.currentImageIndex = 1

        // When: Rapidly navigate through multiple images
        await MainActor.run {
            appState.navigateToNext()
            appState.navigateToNext()
            appState.navigateToPrevious()
        }

        // Then: Index stays in sync with navigation calls
        XCTAssertEqual(appState.currentImageIndex, 2, "Index should match final navigation position")
        XCTAssertEqual(appState.images[appState.currentImageIndex].name, "C.jpg", "Image should match final position")
    }

    func testRepeatedRapidNavigation_maintainsCorrectState() async {
        // Given: Large image set
        let appState = makeAppState(preferencesStore: preferencesStore)
        appState.images = createNamedImages(names: (0..<20).map { "Image\($0).jpg" })
        appState.currentImageIndex = 10

        // When: Execute rapid navigation sequence
        await MainActor.run {
            for _ in 0..<15 {
                appState.navigateToNext()
            }
            for _ in 0..<10 {
                appState.navigateToPrevious()
            }
        }

        // Then: Final index reflects net navigation (10 + 15 - 10 = 15)
        XCTAssertEqual(appState.currentImageIndex, 15, "Rapid navigation should maintain correct index")
        XCTAssertEqual(appState.images[appState.currentImageIndex].name, "Image15.jpg", "Current image should be correct")
    }

    func testFarIndexJump_cancelsPreviousPrefetchGeneration() async {
        // Given: Images and initial prefetch around index 0
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 50_000_000)
        let appState = makeAppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
        appState.images = createNamedImages(names: (0..<100).map { "Image\($0).jpg" })
        appState.currentImageIndex = 0

        appState.prefetchMainImages(around: 0, maxPixelSize: 128)
        let initialPrefetchStarted = await pipeline.waitForRequest(
            appState.images[1].url,
            cache: .main,
            timeoutNanoseconds: 500_000_000
        )
        XCTAssertTrue(initialPrefetchStarted, "Initial prefetch should start")

        // When: Jump to far index (90) and trigger new prefetch
        await MainActor.run {
            appState.navigateToIndex(90)
        }
        appState.prefetchMainImages(around: 90, maxPixelSize: 128)

        // Then: New prefetch around index 90 should start
        let newPrefetchStarted = await pipeline.waitForAnyRequest(
            [appState.images[89].url, appState.images[91].url],
            cache: .main,
            timeoutNanoseconds: 500_000_000
        )
        XCTAssertNotNil(newPrefetchStarted, "Far jump should trigger new neighborhood prefetch")

        // And: Old generation should not continue loading additional images
        let farOldIndexRequested = await pipeline.waitForRequest(
            appState.images[5].url,
            cache: .main,
            timeoutNanoseconds: 200_000_000
        )
        XCTAssertFalse(farOldIndexRequested, "Old generation prefetch should be canceled after far jump")
    }

    func testRapidFarJumps_onlyLatestGenerationCompletes() async {
        // Given: Large image set
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 30_000_000)
        let appState = makeAppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
        appState.images = createNamedImages(names: (0..<100).map { "Image\($0).jpg" })
        appState.currentImageIndex = 0

        // When: Execute multiple rapid far jumps with prefetch triggers
        await MainActor.run {
            appState.navigateToIndex(10)
        }
        appState.prefetchMainImages(around: 10, maxPixelSize: 128)

        try? await Task.sleep(nanoseconds: 20_000_000)

        await MainActor.run {
            appState.navigateToIndex(50)
        }
        appState.prefetchMainImages(around: 50, maxPixelSize: 128)

        try? await Task.sleep(nanoseconds: 20_000_000)

        await MainActor.run {
            appState.navigateToIndex(80)
        }
        appState.prefetchMainImages(around: 80, maxPixelSize: 128)

        // Wait a bit for prefetches to start
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then: The latest neighborhood (around 80) should be the one that completes
        let latestPrefetchObserved = await pipeline.waitForAnyCompletedRequest(
            [appState.images[79].url, appState.images[81].url],
            cache: .main,
            timeoutNanoseconds: 1_000_000_000
        )
        XCTAssertNotNil(latestPrefetchObserved, "Latest jump should complete prefetching around the active index")

        // Verify early generations do not complete after being replaced
        let earlyGenerationObserved = await pipeline.waitForCompletedRequest(
            appState.images[11].url,  // neighbor of first jump
            cache: .main,
            timeoutNanoseconds: 300_000_000
        )
        XCTAssertFalse(earlyGenerationObserved, "Early generation prefetch should not complete after later jumps replace it")
    }

    // MARK: - Memory Stability Tests

    func testSustainedNavigation_doesNotGrowUnbounded() async {
        // Given: Large image set for sustained navigation
        let appState = makeAppState(preferencesStore: preferencesStore)
        appState.images = createNamedImages(names: (0..<200).map { "Image\($0).jpg" })
        appState.currentImageIndex = 0

        // When: Execute sustained navigation loop (100 navigation steps)
        await MainActor.run {
            for _ in 0..<100 {
                appState.navigateToNext()
            }
        }

        // Then: State should remain bounded and consistent
        XCTAssertEqual(appState.images.count, 200, "Image count should remain constant")
        XCTAssertEqual(appState.currentImageIndex, 100, "Index should reflect net navigation")
        XCTAssertFalse(appState.isLoadingImages, "Loading state should not become corrupted")
    }

    func testFolderChange_cancelsAllPrefetchWork() async {
        // Given: Initial folder with prefetch
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 50_000_000)
        let appState = makeAppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)

        let folderA = makeTempDirectory()
        let folderB = makeTempDirectory()
        createImageFiles(in: folderA, names: ["A1.jpg", "A2.jpg"])
        createImageFiles(in: folderB, names: ["B1.jpg", "B2.jpg"])

        appState.updateThumbnailPrefetchSize(64)
        appState.loadImages(from: folderA)
        _ = await pipeline.waitForFirstRequest(in: folderA, timeoutNanoseconds: 1_000_000_000)

        // When: Switch to different folder
        appState.loadImages(from: folderB)
        let newFolderCompleted = await pipeline.waitForCompletedRequest(
            folderB.appendingPathComponent("B1.jpg"),
            cache: .thumbnail,
            timeoutNanoseconds: 1_000_000_000
        )
        XCTAssertTrue(newFolderCompleted, "New folder thumbnail prefetch should complete for the replacement context")

        // Then: Old folder prefetch should not complete after the folder switch
        let oldFolderRequest = await pipeline.waitForCompletedRequest(
            folderA.appendingPathComponent("A2.jpg"),
            cache: .thumbnail,
            timeoutNanoseconds: 300_000_000
        )
        XCTAssertFalse(oldFolderRequest, "Old folder prefetch should not complete after the folder changes")
    }

    func testLongRunningNavigationLoop_doesNotLeakTasks() async {
        // Given: Image set and prefetch pipeline
        let pipeline = RecordingDownsamplingPipeline(delayNanoseconds: 10_000_000)
        let appState = makeAppState(preferencesStore: preferencesStore, downsamplingPipeline: pipeline)
        appState.images = createNamedImages(names: (0..<50).map { "Image\($0).jpg" })
        appState.currentImageIndex = 0

        let initialRequestCount = await pipeline.recordedURLs().count

        // When: Execute long navigation loop with prefetch triggers
        for i in 0..<40 {
            await MainActor.run {
                appState.navigateToNext()
            }
            appState.prefetchMainImages(around: i + 1, maxPixelSize: 128)
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms between navigations
        }

        // Then: Request count should remain bounded (not scale with loop iterations)
        let finalRequestCount = await pipeline.recordedURLs().count
        let requestGrowth = finalRequestCount - initialRequestCount

        // Should request at most 2 images per prefetch (neighbors), not 40+
        XCTAssertLessThan(requestGrowth, 100, "Request count should remain bounded despite long navigation loop")
    }

    // MARK: - Performance Metrics Tests

    func testTimeToFirstImage_canBeMeasured() async {
        // Given: Folder with images
        let scanner = ControlledImageScanner()
        let appState = makeAppState(preferencesStore: preferencesStore, imageScanner: scanner)
        let folder = makeTempDirectory()
        let firstImage = createScanImage(name: "first.jpg", in: folder)

        let firstImageExpectation = expectation(description: "first image published")
        var timeToFirstImage: TimeInterval?

        let cancellable = appState.$images
            .dropFirst()
            .sink { images in
                if !images.isEmpty && timeToFirstImage == nil {
                    timeToFirstImage = Date().timeIntervalSince1970
                    firstImageExpectation.fulfill()
                }
            }

        let startTime = Date().timeIntervalSince1970

        // When: Load folder
        appState.loadImages(from: folder)
        await scanner.waitUntilStarted(for: folder)
        _ = await scanner.emitBatch(
            .init(images: [firstImage], failedImages: [], isFinal: false),
            for: folder
        )

        await fulfillment(of: [firstImageExpectation], timeout: 1.0)

        // Then: Time to first image can be measured
        XCTAssertNotNil(timeToFirstImage, "Should capture time to first image")
        if let measuredTime = timeToFirstImage {
            let elapsed = measuredTime - startTime
            XCTAssertGreaterThan(elapsed, 0, "Time to first image should be positive")
            XCTAssertLessThan(elapsed, 1.0, "Time to first image should be under 1 second")
        }
        withExtendedLifetime(cancellable) {}
    }

    func testAdjacentNavigationLatency_canBeMeasured() async {
        // Given: Images loaded
        let appState = makeAppState(preferencesStore: preferencesStore)
        appState.images = createNamedImages(names: ["A.jpg", "B.jpg", "C.jpg"])
        appState.currentImageIndex = 0

        var navigationTimes: [TimeInterval] = []
        let expectation1 = expectation(description: "nav 1")
        let expectation2 = expectation(description: "nav 2")

        // When: Navigate to adjacent images with timing
        let startTime1 = Date().timeIntervalSince1970
        await MainActor.run {
            appState.navigateToNext()
        }
        let endTime1 = Date().timeIntervalSince1970
        navigationTimes.append(endTime1 - startTime1)
        expectation1.fulfill()

        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        let startTime2 = Date().timeIntervalSince1970
        await MainActor.run {
            appState.navigateToNext()
        }
        let endTime2 = Date().timeIntervalSince1970
        navigationTimes.append(endTime2 - startTime2)
        expectation2.fulfill()

        await fulfillment(of: [expectation1, expectation2], timeout: 1.0)

        // Then: Navigation latency can be measured
        XCTAssertEqual(navigationTimes.count, 2, "Should capture 2 navigation latencies")
        XCTAssertTrue(navigationTimes.allSatisfy { $0 >= 0 }, "All latencies should be non-negative")
        XCTAssertTrue(navigationTimes.allSatisfy { $0 < 0.1 }, "All latencies should be under 100ms")
    }

    func testProgressiveLoadCompletion_canBeMeasured() async {
        // Given: Controlled scanner
        let scanner = ControlledImageScanner()
        let appState = makeAppState(preferencesStore: preferencesStore, imageScanner: scanner)
        let folder = makeTempDirectory()

        let images = (0..<5).map { i -> ImageFile in
            createScanImage(name: "img\(i).jpg", in: folder)
        }

        var completionTime: TimeInterval?
        let loadExpectation = expectation(description: "load completed")
        let startTime = Date().timeIntervalSince1970

        let cancellable = appState.$isLoadingImages
            .dropFirst()
            .sink { isLoading in
                if !isLoading && completionTime == nil {
                    completionTime = Date().timeIntervalSince1970
                    loadExpectation.fulfill()
                }
            }

        // When: Load with progressive batches
        appState.loadImages(from: folder)
        await scanner.waitUntilStarted(for: folder)

        for (index, image) in images.enumerated() {
            let isFinal = (index == images.count - 1)
            _ = await scanner.emitBatch(
                .init(images: [image], failedImages: [], isFinal: isFinal),
                for: folder
            )
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms between batches
        }

        await fulfillment(of: [loadExpectation], timeout: 2.0)

        // Then: Progressive load completion can be measured
        XCTAssertNotNil(completionTime, "Should capture completion time")
        if let measuredTime = completionTime {
            let elapsed = measuredTime - startTime
            XCTAssertGreaterThan(elapsed, 0, "Load time should be positive")
        }
        withExtendedLifetime(cancellable) {}
    }

    func testMemorySnapshot_doesNotAlterReleaseBehavior() async {
        // Given: AppState instance
        let appState = makeAppState(preferencesStore: preferencesStore)

        // When: Capture metrics snapshot
        let imageCountBefore = appState.images.count
        let loadingBefore = appState.isLoadingImages

        let metrics = appState.captureMetrics()

        let imageCountAfter = appState.images.count
        let loadingAfter = appState.isLoadingImages

        // Then: Snapshot should not modify state
        XCTAssertEqual(imageCountBefore, imageCountAfter, "Snapshot should not change image count")
        XCTAssertEqual(loadingBefore, loadingAfter, "Snapshot should not change loading state")
        XCTAssertEqual(metrics.imageCount, 0, "Metrics should reflect current state")
    }

    func testMetricsCapture_providesRepeatableMeasurements() async {
        // Given: AppState with loaded images
        let appState = makeAppState(preferencesStore: preferencesStore)
        appState.images = createNamedImages(names: ["A.jpg", "B.jpg", "C.jpg"])

        // When: Capture metrics multiple times
        let metrics1 = appState.captureMetrics()
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        let metrics2 = appState.captureMetrics()

        // Then: Measurements should be consistent
        XCTAssertEqual(metrics1.imageCount, metrics2.imageCount, "Image count should be stable")
        XCTAssertEqual(metrics1.imageCount, 3, "Should capture correct image count")
        XCTAssertNotEqual(metrics1.capturedAt, metrics2.capturedAt, "Timestamps should differ")
    }
}

actor RecordingDownsamplingPipeline: ImageDownsamplingProviding {
    private var requests: [(url: URL, maxPixelSize: Int, cache: DownsamplingCacheKind)] = []
    private var completedRequests: [(url: URL, cache: DownsamplingCacheKind)] = []
    private var cancelledRequests: [(url: URL, cache: DownsamplingCacheKind)] = []
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func loadImage(from url: URL, maxPixelSize: Int, cache: DownsamplingCacheKind) async -> CGImage? {
        requests.append((url: url, maxPixelSize: maxPixelSize, cache: cache))
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        if Task.isCancelled {
            cancelledRequests.append((url: url, cache: cache))
            return nil
        }
        completedRequests.append((url: url, cache: cache))
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

    func recordedMaxPixelSize(for url: URL, cache: DownsamplingCacheKind) -> Int? {
        requests.last(where: { request in
            request.url.standardizedFileURL == url.standardizedFileURL && request.cache == cache
        })?.maxPixelSize
    }

    func recordedMaxPixelSizes(for url: URL, cache: DownsamplingCacheKind) -> [Int] {
        requests
            .filter { request in
                request.url.standardizedFileURL == url.standardizedFileURL && request.cache == cache
            }
            .map(\.maxPixelSize)
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

    func waitForCompletedRequest(_ url: URL, cache: DownsamplingCacheKind, timeoutNanoseconds: UInt64) async -> Bool {
        let pollInterval: UInt64 = 20_000_000
        var waited: UInt64 = 0
        let requestPath = url.standardizedFileURL.path

        while waited < timeoutNanoseconds {
            if completedRequests.contains(where: { request in
                request.cache == cache && request.url.standardizedFileURL.path == requestPath
            }) {
                return true
            }
            try? await Task.sleep(nanoseconds: pollInterval)
            waited += pollInterval
        }
        return false
    }

    func waitForAnyCompletedRequest(_ urls: [URL], cache: DownsamplingCacheKind, timeoutNanoseconds: UInt64) async -> URL? {
        guard !urls.isEmpty else { return nil }
        let pollInterval: UInt64 = 20_000_000
        var waited: UInt64 = 0
        let candidatePaths = Set(urls.map { $0.standardizedFileURL.path })

        while waited < timeoutNanoseconds {
            if let request = completedRequests.first(where: { request in
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

actor ControlledImageScanner: ImageDirectoryScanning {
    private typealias BatchHandler = @Sendable (ProgressiveImageScanBatch) async -> Bool
    private final class ScanSession {
        var handler: BatchHandler
        var isCompleted: Bool = false
        var task: Task<Void, Never>?

        init(handler: @escaping @Sendable (ProgressiveImageScanBatch) async -> Bool) {
            self.handler = handler
        }
    }

    private var sessions: [String: ScanSession] = [:]
    private var startWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    private func isSessionCompleted(for key: String) -> Bool {
        sessions[key]?.isCompleted ?? false
    }

    func scanImagesProgressively(
        in url: URL,
        batchSize: Int,
        onBatch: @escaping @Sendable (ProgressiveImageScanBatch) async -> Bool
    ) async {
        _ = batchSize
        let key = Self.sessionKey(for: url)
        let session = ScanSession(handler: onBatch)
        sessions[key] = session

        if let waiters = startWaiters.removeValue(forKey: key) {
            for waiter in waiters {
                waiter.resume()
            }
        }

        // Create a task that will complete when the scan finishes
        let scanTask = Task<Void, Never> {
            await withCheckedContinuation { continuation in
                session.task = Task { [weak self] in
                    // Poll for completion
                    while !Task.isCancelled {
                        let isCompleted = await self?.isSessionCompleted(for: key) ?? false
                        if isCompleted {
                            continuation.resume()
                            return
                        }
                        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    }
                    continuation.resume()
                }
            }
        }

        // Wait for the scan to complete
        await scanTask.value

        // Cleanup
        session.task?.cancel()
        session.task = nil
        sessions.removeValue(forKey: key)
    }

    func waitUntilStarted(for url: URL) async {
        let key = Self.sessionKey(for: url)
        if sessions[key] != nil {
            return
        }

        await withCheckedContinuation { continuation in
            startWaiters[key, default: []].append(continuation)
        }
    }

    func emitBatch(_ batch: ProgressiveImageScanBatch, for url: URL) async -> Bool {
        let key = Self.sessionKey(for: url)
        guard let session = sessions[key] else { return false }

        let shouldContinue = await session.handler(batch)
        if batch.isFinal || !shouldContinue {
            session.isCompleted = true
        }
        return shouldContinue
    }

    private static func sessionKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}

@MainActor
private final class TestSlideshowScheduler: SlideshowScheduling {
    private var action: (@MainActor () -> Void)?

    func scheduleRepeating(
        every interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any SlideshowTimer {
        _ = interval
        self.action = action
        return TestSlideshowTimer()
    }

    func fire() {
        action?()
    }
}

private final class TestSlideshowTimer: SlideshowTimer {
    func invalidate() {}
}
