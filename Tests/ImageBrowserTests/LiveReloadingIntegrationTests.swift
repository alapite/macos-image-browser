import Foundation
import XCTest
@testable import ImageBrowser

@MainActor
final class LiveReloadingIntegrationTests: XCTestCase {

    var tempDirectory: URL!
    var appState: AppState!

    override func setUp() async throws {
        tempDirectory = makeTempDirectory()
        appState = makeAppState()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testNewImagesAreAddedToGalleryAutomatically() async throws {
        let expectation = XCTestExpectation(description: "New images should be added to gallery")
        expectation.expectedFulfillmentCount = 2

        copyFixture(resource: "photo1", ext: "jpg", to: tempDirectory)

        try await Task.sleep(nanoseconds: 100_000_000)

        appState.loadImages(from: tempDirectory)

        try await Task.sleep(nanoseconds: 500_000_000)

        let initialCount = appState.images.count
        XCTAssertEqual(initialCount, 1, "Should start with one image")

        let cancellable = appState.$images
            .dropFirst()
            .sink { images in
                if images.count > initialCount {
                    expectation.fulfill()
                }
            }

        try await Task.sleep(nanoseconds: 200_000_000)

        _ = copyFixture(resource: "photo2", ext: "png", to: tempDirectory)
        _ = copyFixture(resource: "photo3", ext: "heic", to: tempDirectory)

        await fulfillment(of: [expectation], timeout: 3.0)

        cancellable.cancel()

        XCTAssertEqual(appState.images.count, initialCount + 2, "Should have added 2 new images")
    }

    func testDeletedImagesAreRemovedFromGalleryAutomatically() async throws {
        let expectation = XCTestExpectation(description: "Deleted images should be removed")

        let file1 = copyFixture(resource: "photo1", ext: "jpg", to: tempDirectory)
        let file2 = copyFixture(resource: "photo2", ext: "png", to: tempDirectory)
        let file3 = copyFixture(resource: "photo3", ext: "heic", to: tempDirectory)

        try await Task.sleep(nanoseconds: 100_000_000)

        appState.loadImages(from: tempDirectory)

        try await Task.sleep(nanoseconds: 500_000_000)

        let initialCount = appState.images.count
        XCTAssertEqual(initialCount, 3, "Should start with 3 images")

        let cancellable = appState.$images
            .dropFirst()
            .sink { images in
                if images.count < initialCount {
                    expectation.fulfill()
                }
            }

        try await Task.sleep(nanoseconds: 200_000_000)

        try FileManager.default.removeItem(at: file1)
        try FileManager.default.removeItem(at: file3)

        await fulfillment(of: [expectation], timeout: 3.0)

        cancellable.cancel()

        XCTAssertEqual(appState.images.count, 1, "Should have removed 2 images")
    }

    func testCurrentImageIndexPreservedWhenPossible() async throws {
        let expectation = XCTestExpectation(description: "Current image should be preserved when new images added")

        let file1 = copyFixture(resource: "photo1", ext: "jpg", to: tempDirectory)
        _ = copyFixture(resource: "photo2", ext: "png", to: tempDirectory)
        _ = copyFixture(resource: "photo3", ext: "heic", to: tempDirectory)

        try await Task.sleep(nanoseconds: 100_000_000)

        appState.loadImages(from: tempDirectory)

        try await Task.sleep(nanoseconds: 500_000_000)

        appState.navigateToIndex(1)

        let currentImageBefore = appState.images[appState.currentImageIndex].url

        let cancellable = appState.$images
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }

        try await Task.sleep(nanoseconds: 200_000_000)

        _ = copyFixture(resource: "photo4", ext: "tiff", to: tempDirectory)

        await fulfillment(of: [expectation], timeout: 3.0)

        cancellable.cancel()

        let currentImageAfter = appState.images[appState.currentImageIndex].url

        XCTAssertEqual(currentImageBefore, currentImageAfter, "Current image should be preserved")
    }

    func testLiveReloadingDisabledWhenFolderChanges() async throws {
        let tempDirectory2 = makeTempDirectory()

        copyFixture(resource: "photo1", ext: "jpg", to: tempDirectory)

        try await Task.sleep(nanoseconds: 100_000_000)

        appState.loadImages(from: tempDirectory)

        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(appState.images.count, 1, "Should start with 1 image in first folder")

        _ = copyFixture(resource: "photo2", ext: "png", to: tempDirectory)

        try await Task.sleep(nanoseconds: 300_000_000)

        copyFixture(resource: "photo3", ext: "heic", to: tempDirectory2)

        appState.loadImages(from: tempDirectory2)

        try await Task.sleep(nanoseconds: 500_000_000)

        _ = copyFixture(resource: "photo4", ext: "tiff", to: tempDirectory2)

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(appState.images.count, 2, "Should have 2 images in second folder")
        XCTAssertTrue(appState.images.allSatisfy { $0.url.path.contains(tempDirectory2.path) }, "All images should be from second folder")

        try? FileManager.default.removeItem(at: tempDirectory2)
    }

    func testDeletingEarlierImagePreservesCurrentImageIdentity() async throws {
        let file1 = copyFixture(resource: "photo1", ext: "jpg", to: tempDirectory)
        _ = copyFixture(resource: "photo2", ext: "png", to: tempDirectory)
        _ = copyFixture(resource: "photo3", ext: "heic", to: tempDirectory)

        try await Task.sleep(nanoseconds: 100_000_000)

        appState.loadImages(from: tempDirectory)

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(appState.images.count, 3)

        appState.navigateToIndex(1)
        let currentImageBeforeDelete = appState.images[appState.currentImageIndex].url

        let deletionExpectation = XCTestExpectation(description: "Delete should update image list")
        let cancellable = appState.$images
            .dropFirst()
            .sink { images in
                if images.count == 2 {
                    deletionExpectation.fulfill()
                }
            }

        try FileManager.default.removeItem(at: file1)
        await fulfillment(of: [deletionExpectation], timeout: 3.0)
        cancellable.cancel()

        let currentImageAfterDelete = appState.images[appState.currentImageIndex].url
        XCTAssertEqual(
            currentImageAfterDelete,
            currentImageBeforeDelete,
            "Deleting an earlier item should preserve the same current image identity"
        )
    }

    func testShuffleOrderIncludesImagesAddedByLiveReload() async throws {
        _ = copyFixture(resource: "photo1", ext: "jpg", to: tempDirectory)
        _ = copyFixture(resource: "photo2", ext: "png", to: tempDirectory)

        try await Task.sleep(nanoseconds: 100_000_000)
        appState.loadImages(from: tempDirectory)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(appState.images.count, 2)

        appState.setShuffleEnabled(true)

        let addedExpectation = XCTestExpectation(description: "Third image should be added")
        let cancellable = appState.$images
            .dropFirst()
            .sink { images in
                if images.count == 3 {
                    addedExpectation.fulfill()
                }
            }

        _ = copyFixture(resource: "photo3", ext: "heic", to: tempDirectory)
        await fulfillment(of: [addedExpectation], timeout: 3.0)
        cancellable.cancel()

        var seenImageKeys: Set<String> = [appState.images[appState.currentImageIndex].id]
        for _ in 0..<10 {
            _ = appState.navigateToNextDisplayableImage()
            seenImageKeys.insert(appState.images[appState.currentImageIndex].id)
        }

        XCTAssertEqual(
            seenImageKeys.count,
            3,
            "Shuffle traversal should include newly added images"
        )
    }

    func testChangesFromPreviousFolderAreIgnoredAfterSwitch() async throws {
        let tempDirectory2 = makeTempDirectory()
        _ = copyFixture(resource: "photo1", ext: "jpg", to: tempDirectory)
        _ = copyFixture(resource: "photo2", ext: "png", to: tempDirectory2)

        try await Task.sleep(nanoseconds: 100_000_000)
        appState.loadImages(from: tempDirectory)
        try await Task.sleep(nanoseconds: 500_000_000)

        appState.loadImages(from: tempDirectory2)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(appState.images.allSatisfy { $0.url.path.contains(tempDirectory2.path) })

        let staleEventExpectation = XCTestExpectation(description: "Old folder changes should be ignored")
        staleEventExpectation.isInverted = true

        let cancellable = appState.$images
            .dropFirst()
            .sink { images in
                if images.contains(where: { $0.url.path.contains(self.tempDirectory.path) }) {
                    staleEventExpectation.fulfill()
                }
            }

        _ = copyFixture(resource: "photo3", ext: "heic", to: tempDirectory)
        await fulfillment(of: [staleEventExpectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertTrue(appState.images.allSatisfy { $0.url.path.contains(tempDirectory2.path) })

        try? FileManager.default.removeItem(at: tempDirectory2)
    }
}
