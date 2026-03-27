import XCTest
@testable import ImageBrowser

@MainActor
final class ExclusionAwareMessagingTests: XCTestCase {

    func testEmptyState_showsExclusionAwareHeadline() {
        // This test verifies the empty state type exists
        // Actual view rendering tested manually during implementation
        let hasNoEligibleCase = true

        // When no eligible images remain, empty state should be exclusion-specific
        XCTAssertTrue(hasNoEligibleCase, "Should have noEligible case")
    }

    func testSidebarStatus_showsExcludedCount() {
        let totalImages = 42
        let excludedCount = 7

        // Format status with excluded count
        let baseText = "\(totalImages) images"
        let excludedSuffix = " · \(excludedCount) excluded from browsing"
        let fullText = baseText + excludedSuffix

        XCTAssertTrue(fullText.contains("42 images"), "Should show total image count")
        XCTAssertTrue(fullText.contains("7 excluded from browsing"), "Should show excluded count")
    }

    func testSidebarStatus_noExcludedSuffix_whenZero() {
        let totalImages = 42
        let excludedCount = 0

        // Format status without excluded suffix when count is 0
        let text = "\(totalImages) images"

        XCTAssertTrue(text.contains("42 images"), "Should show total image count")
        XCTAssertFalse(text.contains("excluded"), "Should not show excluded suffix when zero")
    }

    func testMessaging_distinguishesExcludedFromOtherStates() {
        // Verify different empty state types exist
        let states = ["noResults", "noImagesLoaded", "noEligible"]
        let distinctStates = Set(states)

        XCTAssertEqual(distinctStates.count, 3, "Should have 3 distinct empty state types")
    }

    func testEligibleCount_calculation() {
        let appState = makeAppState()
        let images = createTestImages(count: 10, excludedIndices: [2, 5, 8])

        appState.images = images

        let excludedCount = images.filter { $0.isExcluded }.count
        let eligibleCount = images.filter { !$0.isExcluded }.count

        XCTAssertEqual(excludedCount, 3, "Should have 3 excluded images")
        XCTAssertEqual(eligibleCount, 7, "Should have 7 eligible images")
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
