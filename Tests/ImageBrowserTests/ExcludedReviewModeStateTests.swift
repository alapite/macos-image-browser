import XCTest
import Combine
@testable import ImageBrowser

@MainActor
final class ExcludedReviewModeStateTests: XCTestCase {
    var sut: AppState!
    var preferencesStore: InMemoryPreferencesStore!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        await MainActor.run {
            preferencesStore = InMemoryPreferencesStore()
            sut = makeAppState(preferencesStore: preferencesStore)
            cancellables = Set<AnyCancellable>()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            sut = nil
            preferencesStore = nil
            cancellables = nil
        }
    }

    // MARK: - Enter/Exit Review Mode

    func testEnterExcludedReviewMode_setsFlagTrue() {
        // Given: AppState with no review mode active
        XCTAssertFalse(sut.isExcludedReviewMode, "Review mode should start inactive")

        // When: Enter excluded review mode
        sut.enterExcludedReviewMode()

        // Then: Review mode is active
        XCTAssertTrue(sut.isExcludedReviewMode, "Entering review mode should set flag to true")
    }

    func testExitExcludedReviewMode_setsFlagFalse() {
        // Given: AppState with review mode active
        sut.enterExcludedReviewMode()
        XCTAssertTrue(sut.isExcludedReviewMode, "Review mode should be active")

        // When: Exit excluded review mode
        sut.exitExcludedReviewMode()

        // Then: Review mode is inactive
        XCTAssertFalse(sut.isExcludedReviewMode, "Exiting review mode should set flag to false")
    }

    // MARK: - Folder Scope Behavior

    func testReviewMode_exitsOnFolderChange() {
        // Given: AppState with review mode active and a selected folder
        let folderA = URL(fileURLWithPath: "/tmp/folder-a")
        let folderB = URL(fileURLWithPath: "/tmp/folder-b")

        sut.selectedFolder = folderA
        sut.enterExcludedReviewMode()
        XCTAssertTrue(sut.isExcludedReviewMode, "Review mode should be active")

        // When: Folder changes to a different path
        sut.handleFolderChangeForReviewMode(previousFolder: folderA, newFolder: folderB)

        // Then: Review mode auto-exits
        XCTAssertFalse(sut.isExcludedReviewMode, "Review mode should exit when folder changes")
    }

    func testReviewMode_persistsWithinSameFolder() {
        // Given: AppState with review mode active and a selected folder
        let folder = URL(fileURLWithPath: "/tmp/folder")
        sut.selectedFolder = folder
        sut.enterExcludedReviewMode()
        XCTAssertTrue(sut.isExcludedReviewMode, "Review mode should be active")

        // When: Same folder is set again (no actual change)
        sut.handleFolderChangeForReviewMode(previousFolder: folder, newFolder: folder)

        // Then: Review mode persists
        XCTAssertTrue(sut.isExcludedReviewMode, "Review mode should persist when folder context is unchanged")
    }

    func testReviewMode_exitsWhenFolderPathDiffers() {
        // Given: AppState with review mode active
        let folderA = URL(fileURLWithPath: "/tmp/folder-a")
        let folderASubpath = URL(fileURLWithPath: "/tmp/folder-a/subfolder")

        sut.selectedFolder = folderA
        sut.enterExcludedReviewMode()
        XCTAssertTrue(sut.isExcludedReviewMode, "Review mode should be active")

        // When: Folder changes to a different path (even if related)
        sut.handleFolderChangeForReviewMode(previousFolder: folderA, newFolder: folderASubpath)

        // Then: Review mode auto-exits (different standardized paths)
        XCTAssertFalse(sut.isExcludedReviewMode, "Review mode should exit when standardized folder paths differ")
    }

    // MARK: - Review Mode State Independence

    func testEnterExcludedReviewMode_doesNotAffectImages() {
        // Given: AppState with images loaded
        let images = [
            ImageFile(
                url: URL(fileURLWithPath: "/tmp/image1.jpg"),
                name: "image1.jpg",
                creationDate: Date()
            ),
            ImageFile(
                url: URL(fileURLWithPath: "/tmp/image2.jpg"),
                name: "image2.jpg",
                creationDate: Date()
            )
        ]
        sut.images = images
        XCTAssertEqual(sut.images.count, 2, "Should have 2 images loaded")

        // When: Enter excluded review mode
        sut.enterExcludedReviewMode()

        // Then: Images are unchanged
        XCTAssertEqual(sut.images.count, 2, "Entering review mode should not modify images list")
        XCTAssertTrue(sut.isExcludedReviewMode, "Review mode should be active")
    }

    func testExitExcludedReviewMode_doesNotAffectImages() {
        // Given: AppState with images loaded and review mode active
        let images = [
            ImageFile(
                url: URL(fileURLWithPath: "/tmp/image1.jpg"),
                name: "image1.jpg",
                creationDate: Date()
            )
        ]
        sut.images = images
        sut.enterExcludedReviewMode()

        // When: Exit excluded review mode
        sut.exitExcludedReviewMode()

        // Then: Images are unchanged
        XCTAssertEqual(sut.images.count, 1, "Exiting review mode should not modify images list")
        XCTAssertFalse(sut.isExcludedReviewMode, "Review mode should be inactive")
    }

    // MARK: - Double Enter/Exit Safety

    func testEnterExcludedReviewMode_whenAlreadyActive_remainsTrue() {
        // Given: AppState with review mode already active
        sut.enterExcludedReviewMode()
        XCTAssertTrue(sut.isExcludedReviewMode)

        // When: Enter again
        sut.enterExcludedReviewMode()

        // Then: Still active (idempotent)
        XCTAssertTrue(sut.isExcludedReviewMode, "Double enter should remain active")
    }

    func testExitExcludedReviewMode_whenAlreadyInactive_remainsFalse() {
        // Given: AppState with review mode inactive
        XCTAssertFalse(sut.isExcludedReviewMode)

        // When: Exit (should be safe to call)
        sut.exitExcludedReviewMode()

        // Then: Still inactive (idempotent)
        XCTAssertFalse(sut.isExcludedReviewMode, "Double exit should remain inactive")
    }

    // MARK: - @Published Observable State

    func testReviewMode_stateChangesAreObservable() {
        // Given: AppState with review mode inactive
        XCTAssertFalse(sut.isExcludedReviewMode, "Review mode should start inactive")

        var receivedValues: [Bool] = []

        // When: Subscribing to @Published publisher
        sut.$isExcludedReviewMode
            .sink { value in
                receivedValues.append(value)
            }
            .store(in: &cancellables)

        // When: Entering review mode
        sut.enterExcludedReviewMode()

        // Then: Publisher emitted true
        XCTAssertTrue(receivedValues.contains(true), "Publisher should emit true when entering review mode")
        XCTAssertTrue(sut.isExcludedReviewMode, "Review mode should be active")

        // When: Exiting review mode
        sut.exitExcludedReviewMode()

        // Then: Publisher emitted false
        XCTAssertTrue(receivedValues.contains(false), "Publisher should emit false when exiting review mode")
        XCTAssertFalse(sut.isExcludedReviewMode, "Review mode should be inactive")
    }

    // MARK: - Excluded Count Updates

    func testExcludedCount_updatesWhenImagesExcluded() {
        // Given: AppState with 3 images, none excluded
        let image1 = ImageFile(
            url: URL(fileURLWithPath: "/tmp/image1.jpg"),
            name: "image1.jpg",
            creationDate: Date()
        )
        let image2 = ImageFile(
            url: URL(fileURLWithPath: "/tmp/image2.jpg"),
            name: "image2.jpg",
            creationDate: Date()
        )
        let image3 = ImageFile(
            url: URL(fileURLWithPath: "/tmp/image3.jpg"),
            name: "image3.jpg",
            creationDate: Date()
        )
        sut.images = [image1, image2, image3]

        let initialExcludedCount = sut.images.filter { $0.isExcluded }.count
        XCTAssertEqual(initialExcludedCount, 0, "Should start with 0 excluded images")

        var imageUpdateCount = 0
        sut.$images
            .dropFirst()
            .sink { _ in
                imageUpdateCount += 1
            }
            .store(in: &cancellables)

        // When: Excluding one image
        let imageKeys = [image1.url.standardizedFileURL.absoluteString]
        sut.applyExcludedState(for: imageKeys, isExcluded: true)

        // Then: Excluded count is now 1
        let updatedExcludedCount = sut.images.filter { $0.isExcluded }.count
        XCTAssertEqual(updatedExcludedCount, 1, "Should have 1 excluded image after exclusion")
        XCTAssertTrue(sut.images[0].isExcluded, "First image should be marked as excluded")
        XCTAssertEqual(imageUpdateCount, 1, "@Published images should emit change when excluded state is applied")
    }

    func testExcludedCount_decreasesWhenRestored() {
        // Given: AppState with 1 excluded image and 1 normal image
        let image1 = ImageFile(
            url: URL(fileURLWithPath: "/tmp/image1.jpg"),
            name: "image1.jpg",
            creationDate: Date()
        )
        let image2 = ImageFile(
            url: URL(fileURLWithPath: "/tmp/image2.jpg"),
            name: "image2.jpg",
            creationDate: Date()
        )
        sut.images = [image1, image2]

        let imageKeys = [image1.url.standardizedFileURL.absoluteString]
        sut.applyExcludedState(for: imageKeys, isExcluded: true)

        let excludedCount = sut.images.filter { $0.isExcluded }.count
        XCTAssertEqual(excludedCount, 1, "Should have 1 excluded image")

        var imageUpdateCount = 0
        sut.$images
            .dropFirst()
            .sink { _ in
                imageUpdateCount += 1
            }
            .store(in: &cancellables)

        // When: Restoring the excluded image
        sut.applyExcludedState(for: imageKeys, isExcluded: false)

        // Then: Excluded count is now 0
        let restoredExcludedCount = sut.images.filter { $0.isExcluded }.count
        XCTAssertEqual(restoredExcludedCount, 0, "Should have 0 excluded images after restoration")
        XCTAssertFalse(sut.images[0].isExcluded, "First image should not be marked as excluded")
        XCTAssertEqual(imageUpdateCount, 1, "@Published images should emit change when excluded state is cleared")
    }
}
